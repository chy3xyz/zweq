//! Admin diagnostics API — real runtime state, no hardcoded counters.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const user_persist = @import("../user/persistence.zig");
const task_persist = @import("../task/persistence.zig");
const file_persist = @import("../file/persistence.zig");
const notify_persist = @import("../notify/persistence.zig");
const tenant_persist = @import("../tenant/persistence.zig");

pub fn SystemApi(comptime CacheT: type, comptime TaskSvcT: type) type {
    return struct {
        const Self = @This();
        cache: *CacheT,
        tasks: *TaskSvcT,
        users_svc: *user_svc.UserService,
        user_store: *user_persist.UserStore,
        file_store: *file_persist.FileStore,
        notify_store: *notify_persist.NotificationStore,
        tenant_store: *tenant_persist.TenantStore,
        io: std.Io,
        started_at: i64,
        db_kind: []const u8,
        smtp_enabled: bool,
        mail_console: bool,
        module_count: usize,

        pub const module_name = "system";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "system/info", .handler = http.wrapHandler(Self, info), .meta = .{ .permission = "system:read" } },
            .{ .method = .GET, .path = "system/dashboard", .handler = http.wrapHandler(Self, dashboard), .meta = .{ .permission = "system:read" } },
        };

        pub fn init(
            cache: *CacheT,
            tasks: *TaskSvcT,
            users_svc: *user_svc.UserService,
            user_store: *user_persist.UserStore,
            file_store: *file_persist.FileStore,
            notify_store: *notify_persist.NotificationStore,
            tenant_store: *tenant_persist.TenantStore,
            io: std.Io,
            started_at: i64,
            db_kind: []const u8,
            smtp_enabled: bool,
            mail_console: bool,
            module_count: usize,
        ) Self {
            return .{
                .cache = cache,
                .tasks = tasks,
                .users_svc = users_svc,
                .user_store = user_store,
                .file_store = file_store,
                .notify_store = notify_store,
                .tenant_store = tenant_store,
                .io = io,
                .started_at = started_at,
                .db_kind = db_kind,
                .smtp_enabled = smtp_enabled,
                .mail_console = mail_console,
                .module_count = module_count,
            };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.users_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.users_svc.sec, self.users_svc.store));
            try g.get("/system/info", info, @ptrCast(@alignCast(self)));
            try g.get("/system/dashboard", dashboard, @ptrCast(@alignCast(self)));
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = ctx.userIdInt(i64) orelse return;
            const row_opt = self.users_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.users_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        fn info(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            const now = zigmodu.time.wallClockSeconds(self.io);
            const task_counts = self.tasks.counts() catch task_persist.StatusCounts{};
            try ctx.okValue(.{
                    .app = "zweq",
                    .version = "0.2.0",
                    .uptime_seconds = now - self.started_at,
                    .db = self.db_kind,
                    .mail = .{ .smtp = self.smtp_enabled, .console = self.mail_console },
                    .cache_entries = self.cache.count(),
                    .modules = self.module_count,
                    .tasks = task_counts,
                });
        }

        fn dashboard(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);

            const now = zigmodu.time.wallClockSeconds(self.io);
            const day: i64 = 24 * 3600;

            // Last 7 days of registrations, oldest day first.
            var trend: [7]i64 = undefined;
            var i: usize = 0;
            while (i < 7) : (i += 1) {
                const start = now - @as(i64, @intCast(7 - @as(usize, i))) * day;
                const end = start + day;
                trend[i] = self.user_store.countRegisteredBetween(start, end) catch 0;
            }

            const total_users = self.user_store.countAll() catch 0;
            const total_files = self.file_store.countAll() catch 0;
            const total_notifications = self.notify_store.countAll() catch 0;
            const total_tenants = self.tenant_store.countAll() catch 0;
            const task_counts = self.tasks.counts() catch task_persist.StatusCounts{};

            try ctx.okValue(.{
                    .users = .{ .total = total_users, .registered_last_7d = trend },
                    .tasks = task_counts,
                    .files = total_files,
                    .notifications = total_notifications,
                    .tenants = total_tenants,
                    .cache_entries = self.cache.count(),
                });
        }
    };
}
