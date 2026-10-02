//! Admin audit-log API — query the audit trail (write side is the service).

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const service = @import("service.zig");

const AuditDto = struct {
    id: i64,
    actor_user_id: i64,
    actor_name: []const u8,
    action: []const u8,
    target_type: []const u8,
    target_id: i64,
    detail: []const u8,
    ip: []const u8,
    success: bool,
    created_at: i64,
};

fn toDto(row: service.AuditRow) AuditDto {
    return .{
        .id = row.id,
        .actor_user_id = row.actor_user_id,
        .actor_name = row.actor_name,
        .action = row.action,
        .target_type = row.target_type,
        .target_id = row.target_id,
        .detail = row.detail,
        .ip = row.ip,
        .success = row.success,
        .created_at = row.created_at,
    };
}

/// 把一行审计记录追加为 CSV 行。每个数值列各用独立的栈缓冲（保持零分配）：
/// 共用一个 `buf` 时所有切片都指向同一内存，writeRow 时四列全部变成
/// 最后格式化的 created_at。
fn appendAuditRow(csv: *zigmodu.csv.Writer, r: service.AuditRow) !void {
    var id_buf: [64]u8 = undefined;
    var aid_buf: [64]u8 = undefined;
    var tid_buf: [64]u8 = undefined;
    var ts_buf: [64]u8 = undefined;
    const id_s = try std.fmt.bufPrint(&id_buf, "{d}", .{r.id});
    const aid_s = try std.fmt.bufPrint(&aid_buf, "{d}", .{r.actor_user_id});
    const tid_s = try std.fmt.bufPrint(&tid_buf, "{d}", .{r.target_id});
    const ts_s = try std.fmt.bufPrint(&ts_buf, "{d}", .{r.created_at});
    const ok_s = if (r.success) "true" else "false";
    try csv.writeRow(&.{ id_s, r.action, aid_s, r.actor_name, r.target_type, tid_s, r.detail, r.ip, ok_s, ts_s });
}

test "audit CSV export row uses each column's own value" {
    var csv = zigmodu.csv.Writer.init(std.testing.allocator);
    defer csv.deinit();
    try appendAuditRow(&csv, .{
        .id = 101,
        .actor_user_id = 202,
        .actor_name = "alice",
        .action = "user.update",
        .target_type = "user",
        .target_id = 303,
        .detail = "改邮箱",
        .ip = "127.0.0.1",
        .success = true,
        .tenant_id = 1,
        .created_at = 946684800,
        .updated_at = 946684800,
    });
    try std.testing.expectEqualStrings(
        "101,user.update,202,alice,user,303,改邮箱,127.0.0.1,true,946684800",
        csv.buf.items,
    );
}

pub fn AuditApi(comptime AuditServiceT: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *AuditServiceT,
        user_svc: *UserService,

        pub const module_name = "audit";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "audit-logs", .handler = http.wrapHandler(Self, listLogs), .meta = .{ .permission = "audit:read" } },
            .{ .method = .GET, .path = "audit-logs/export", .handler = http.wrapHandler(Self, exportLogs), .meta = .{ .permission = "audit:read" } },
        };

        pub fn init(svc: *AuditServiceT, users: *UserService) Self {
            return .{ .svc = svc, .user_svc = users };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            g = try g.use(mw.adminGuard(self.user_svc.store));
            try g.get("/audit-logs", listLogs, @ptrCast(@alignCast(self)));
            try g.get("/audit-logs/export", exportLogs, @ptrCast(@alignCast(self)));
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        /// CSV 导出分页参数：每页 500 行边查边拼，上限 10000 行与旧实现一致。
        const export_page_size: usize = 500;
        const export_row_limit: usize = 10000;

        fn exportLogs(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            var csv = zigmodu.csv.Writer.init(ctx.allocator);
            defer csv.deinit();
            try csv.writeHeader(&.{ "id", "action", "actor_user_id", "actor_name", "target_type", "target_id", "detail", "ip", "success", "created_at" });
            // 分页边查边拼（每页 500、上限 10000 不变）：行由 `AuditStore.dup`
            // 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free
            // 是 no-op）→ 必须用拥有者释放；每页拼完立即释放，峰值内存从「万行
            // 同时存活」降为「一页 + 已拼字符串」。
            var page: usize = 1;
            var exported: usize = 0;
            while (exported < export_row_limit) {
                var result = self.svc.list(page, export_page_size, .{}) catch |err| {
                    std.log.err("internal error: {s}", .{@errorName(err)});
                    try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                    return;
                };
                defer result.free(self.svc.store.allocator);
                if (result.items.len == 0) break;
                for (result.items) |r| try appendAuditRow(&csv, r);
                exported += result.items.len;
                if (result.items.len < export_page_size) break;
                page += 1;
            }
            try ctx.setHeader("Content-Type", "text/csv; charset=utf-8");
            try ctx.setHeader("Content-Disposition", "attachment; filename=audit-logs.csv");
            try ctx.text(200, csv.buf.items);
        }

        fn listLogs(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = ctx.userIdInt(i64) orelse return;
            _ = admin_id;

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 200 });
            const actor = ctx.queryInt(i64, "actor", 0);
            const action_raw = ctx.queryParam("action");
            const keyword_raw = ctx.queryParam("keyword");

            const filters: service.AuditFilters = .{
                .actor_user_id = if (actor > 0) actor else null,
                .action = action_raw,
                .keyword = keyword_raw,
            };
            var result = self.svc.list(params.page, params.page_size, filters) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, AuditDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }
    };
}
