//! Admin email-template API — list and upsert customizable templates.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const service = @import("service.zig");

const TemplateDto = struct {
    code: []const u8,
    subject: []const u8,
    body: []const u8,
    updated_at: i64,
};

fn toDto(row: service.TemplateRow) TemplateDto {
    return .{
        .code = row.code,
        .subject = row.subject,
        .body = row.body,
        .updated_at = row.updated_at,
    };
}

const UpsertTemplateReq = struct {
    subject: []const u8,
    body: []const u8,
};

pub fn MailTemplateApi(comptime TemplateServiceT: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *TemplateServiceT,
        user_svc: *UserService,

        pub const module_name = "mail_template";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "email-templates", .handler = http.wrapHandler(Self, listTemplates), .meta = .{ .permission = "mail_template:read" } },
            .{ .method = .PUT, .path = "email-templates/{code}", .handler = http.wrapHandler(Self, upsertTemplate), .meta = .{ .permission = "mail_template:write" } },
        };

        pub fn init(svc: *TemplateServiceT, users: *UserService) Self {
            return .{ .svc = svc, .user_svc = users };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            g = try g.use(mw.adminGuard(self.user_svc.store));
            try g.get("/email-templates", listTemplates, @ptrCast(@alignCast(self)));
            try g.put("/email-templates/{code}", upsertTemplate, @ptrCast(@alignCast(self)));
        }

        fn listTemplates(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));

            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.list(params.page, params.page_size) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, TemplateDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn upsertTemplate(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));

            const code = ctx.param("code") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少模板 code");
                return;
            };
            const req = ctx.bindJson(UpsertTemplateReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.subject);
                ctx.allocator.free(req.body);
            }
            if (std.mem.trim(u8, req.subject, " \t").len == 0 or std.mem.trim(u8, req.body, " \t").len == 0) {
                try ctx.sendErrorResponse(400, 400, "主题和正文不能为空");
                return;
            }
            self.svc.upsert(code, req.subject, req.body) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            try ctx.ok("null");
        }
    };
}

pub const DefaultMailTemplateApi = MailTemplateApi(service.MailTemplateService, @import("../user/service.zig").UserService);
