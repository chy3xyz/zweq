//! AI HTTP API — provider admin, chat sessions, approvals, runs, metrics.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const url_guard = @import("../../http/url_guard.zig");
const service = @import("service.zig");
const user_svc = @import("../user/service.zig");

const ProviderDto = struct {
    id: i64,
    name: []const u8,
    endpoint: []const u8,
    models: []const u8,
    fallback_providers: []const u8,
    enabled: bool,
    has_keys: bool,
    created_at: i64,
    updated_at: i64,
};

fn toProviderDto(row: service.ProviderRow) ProviderDto {
    return .{
        .id = row.id,
        .name = row.name,
        .endpoint = row.endpoint,
        .models = row.models,
        .fallback_providers = row.fallback_providers,
        .enabled = row.enabled,
        .has_keys = row.api_keys_encrypted.len > 0,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const SessionDto = struct {
    id: i64,
    title: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toSessionDto(row: service.SessionRow) SessionDto {
    return .{ .id = row.id, .title = row.title, .created_at = row.created_at, .updated_at = row.updated_at };
}

const MessageDto = struct {
    id: i64,
    role: []const u8,
    content: []const u8,
    reasoning_content: []const u8,
    created_at: i64,
};

fn toMessageDto(row: service.MessageRow) MessageDto {
    return .{ .id = row.id, .role = row.role, .content = row.content, .reasoning_content = row.reasoning_content, .created_at = row.created_at };
}

const ApprovalDto = struct {
    id: i64,
    session_id: i64,
    requested_by: i64,
    skill_name: []const u8,
    args: []const u8,
    status: []const u8,
    created_at: i64,
};

fn toApprovalDto(row: service.ApprovalRow) ApprovalDto {
    return .{
        .id = row.id,
        .session_id = row.session_id,
        .requested_by = row.requested_by,
        .skill_name = row.skill_name,
        .args = row.args,
        .status = row.status,
        .created_at = row.created_at,
    };
}

const RunDto = struct {
    id: i64,
    session_id: i64,
    user_id: i64,
    kind: []const u8,
    prompt: []const u8,
    model: []const u8,
    tokens_in: i64,
    tokens_out: i64,
    steps: i64,
    tool_calls: i64,
    tool_errors: i64,
    status: []const u8,
    err: []const u8,
    created_at: i64,
};

fn toRunDto(row: service.RunRow) RunDto {
    return .{
        .id = row.id,
        .session_id = row.session_id,
        .user_id = row.user_id,
        .kind = row.kind,
        .prompt = row.prompt,
        .model = row.model,
        .tokens_in = row.tokens_in,
        .tokens_out = row.tokens_out,
        .steps = row.steps,
        .tool_calls = row.tool_calls,
        .tool_errors = row.tool_errors,
        .status = row.status,
        .err = row.err,
        .created_at = row.created_at,
    };
}

const SaveProviderReq = struct {
    name: []const u8,
    endpoint: []const u8,
    api_keys: ?[]const []const u8 = null,
    models: ?[]const u8 = null,
    fallback_providers: ?[]const u8 = null,
    enabled: ?bool = null,
};

const CreateSessionReq = struct {
    title: []const u8 = "",
};

const ChatReq = struct {
    content: []const u8,
};

pub fn AiApi(comptime AiSvcT: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *AiSvcT,
        user_svc: *UserService,

        pub const module_name = "ai";
        pub const nest: []const []const u8 = &.{};
        pub const State = Self;

        pub const routes: []const http.RouteSpec(Self) = &.{
            .{ .method = .GET, .path = "ai/sessions", .handler = http.wrapHandler(Self, listSessions), .meta = .{ .auth = .jwt } },
            .{ .method = .POST, .path = "ai/sessions", .handler = http.wrapHandler(Self, createSession), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "ai/sessions/{id}/messages", .handler = http.wrapHandler(Self, listMessages), .meta = .{ .auth = .jwt } },
            .{ .method = .POST, .path = "ai/sessions/{id}/chat", .handler = http.wrapHandler(Self, chat), .meta = .{ .auth = .jwt } },
            .{ .method = .DELETE, .path = "ai/sessions/{id}", .handler = http.wrapHandler(Self, deleteSession), .meta = .{ .auth = .jwt } },
            .{ .method = .GET, .path = "ai/providers", .handler = http.wrapHandler(Self, listProviders), .meta = .{ .permission = "ai:read" } },
            .{ .method = .POST, .path = "ai/providers", .handler = http.wrapHandler(Self, createProvider), .meta = .{ .permission = "ai:write" } },
            .{ .method = .PUT, .path = "ai/providers/{id}", .handler = http.wrapHandler(Self, updateProvider), .meta = .{ .permission = "ai:write" } },
            .{ .method = .DELETE, .path = "ai/providers/{id}", .handler = http.wrapHandler(Self, deleteProvider), .meta = .{ .permission = "ai:write" } },
            .{ .method = .POST, .path = "ai/providers/{id}/check", .handler = http.wrapHandler(Self, checkProvider), .meta = .{ .permission = "ai:write" } },
            .{ .method = .GET, .path = "ai/approvals", .handler = http.wrapHandler(Self, listApprovals), .meta = .{ .permission = "ai:read" } },
            .{ .method = .POST, .path = "ai/approvals/{id}/approve", .handler = http.wrapHandler(Self, approveApproval), .meta = .{ .permission = "ai:write" } },
            .{ .method = .POST, .path = "ai/approvals/{id}/reject", .handler = http.wrapHandler(Self, rejectApproval), .meta = .{ .permission = "ai:write" } },
            .{ .method = .GET, .path = "ai/runs", .handler = http.wrapHandler(Self, listRuns), .meta = .{ .permission = "ai:read" } },
            .{ .method = .POST, .path = "ai/workflow/run", .handler = http.wrapHandler(Self, runWorkflow), .meta = .{ .permission = "ai:write" } },
            .{ .method = .GET, .path = "ai/metrics", .handler = http.wrapHandler(Self, metrics), .meta = .{ .permission = "ai:read" } },
            .{ .method = .GET, .path = "ai/skills", .handler = http.wrapHandler(Self, skills), .meta = .{ .permission = "ai:read" } },
        };

        pub fn init(svc: *AiSvcT, users: *UserService) Self {
            return .{ .svc = svc, .user_svc = users };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/ai/sessions", listSessions, @ptrCast(@alignCast(self)));
            try g.post("/ai/sessions", createSession, @ptrCast(@alignCast(self)));
            try g.get("/ai/sessions/{id}/messages", listMessages, @ptrCast(@alignCast(self)));
            try g.post("/ai/sessions/{id}/chat", chat, @ptrCast(@alignCast(self)));
            try g.delete("/ai/sessions/{id}", deleteSession, @ptrCast(@alignCast(self)));

            var a = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            try a.get("/ai/providers", listProviders, @ptrCast(@alignCast(self)));
            try a.post("/ai/providers", createProvider, @ptrCast(@alignCast(self)));
            try a.put("/ai/providers/{id}", updateProvider, @ptrCast(@alignCast(self)));
            try a.delete("/ai/providers/{id}", deleteProvider, @ptrCast(@alignCast(self)));
            try a.post("/ai/providers/{id}/check", checkProvider, @ptrCast(@alignCast(self)));
            try a.get("/ai/approvals", listApprovals, @ptrCast(@alignCast(self)));
            try a.post("/ai/approvals/{id}/approve", approveApproval, @ptrCast(@alignCast(self)));
            try a.post("/ai/approvals/{id}/reject", rejectApproval, @ptrCast(@alignCast(self)));
            try a.get("/ai/runs", listRuns, @ptrCast(@alignCast(self)));
            try a.post("/ai/workflow/run", runWorkflow, @ptrCast(@alignCast(self)));
            try a.get("/ai/metrics", metrics, @ptrCast(@alignCast(self)));
            try a.get("/ai/skills", skills, @ptrCast(@alignCast(self)));
        }

        fn authUid(ctx: *http.Context) ?i64 {
            return ctx.userIdInt(i64);
        }

        fn setAuditActor(ctx: *http.Context, self: *Self) !void {
            const uid = authUid(ctx) orelse return;
            const row_opt = self.user_svc.getUserById(uid) catch return;
            const row = row_opt orelse return;
            defer row.free(self.user_svc.store.allocator);
            try ctx.setAttr("audit_actor", row.name);
        }

        // ── Provider CRUD ──

        fn listProviders(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.store.listProviders(params.page, params.page_size) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            // 行与数组由 `AiStore.dupProvider`/`listProviders` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer result.free(self.svc.store.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ProviderDto, toProviderDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createProvider(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const req = ctx.bindJson(SaveProviderReq) catch {
                try ctx.sendErrorResponse(400, 400, "无效的请求 JSON");
                return;
            };
            if (req.name.len == 0 or req.endpoint.len == 0) {
                try ctx.sendErrorResponse(400, 400, "Provider 名称与端点不能为空");
                return;
            }
            // SSRF 基线：endpoint 会被服务端主动请求，只允许 http(s) 且非字面内网地址。
            if (!url_guard.isAcceptableOutboundUrl(req.endpoint)) {
                try ctx.sendErrorResponse(400, 400, "endpoint 不允许（需 http(s) 且非内网地址）");
                return;
            }

            var enc_keys: []const u8 = "";
            var enc_buf: ?[]u8 = null;
            defer if (enc_buf) |b| ctx.allocator.free(b);

            if (req.api_keys) |keys| {
                if (keys.len > 0) {
                    const plain_json = std.json.Stringify.valueAlloc(ctx.allocator, keys, .{}) catch |err| {
                        std.log.err("internal error: {s}", .{@errorName(err)});
                        try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                        return;
                    };
                    defer ctx.allocator.free(plain_json);
                    enc_buf = self.svc.encryptKeys(ctx.allocator, plain_json) catch |err| switch (err) {
                        error.MissingKeySecret => {
                            try ctx.sendErrorResponse(400, 400, "站点未配置 AI 密钥主控密钥 (ZWEQ_AI_KEY_SECRET),无法加密保存");
                            return;
                        },
                        else => {
                            std.log.err("internal error: {s}", .{@errorName(err)});
                            try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                            return;
                        },
                    };
                    enc_keys = enc_buf.?;
                }
            }

            const now = zigmodu.time.wallClockSeconds(self.svc.io);
            const id = self.svc.store.createProvider(
                req.name,
                req.endpoint,
                enc_keys,
                req.models orelse "",
                req.fallback_providers orelse "",
                req.enabled orelse true,
                now,
            ) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };

            try ctx.okValue(.{ .id = id });
        }

        fn updateProvider(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Provider ID");
                return;
            };
            const cur_opt = self.svc.store.getProvider(id) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "Provider 不存在");
                return;
            };
            // 行由 `AiStore.dupProvider` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer cur.free(self.svc.store.allocator);

            const req = ctx.bindJson(SaveProviderReq) catch {
                try ctx.sendErrorResponse(400, 400, "无效的请求 JSON");
                return;
            };

            // SSRF 基线：与创建入口同款校验（endpoint 为必填字段，空值同样会被拒绝）。
            if (!url_guard.isAcceptableOutboundUrl(req.endpoint)) {
                try ctx.sendErrorResponse(400, 400, "endpoint 不允许（需 http(s) 且非内网地址）");
                return;
            }

            var enc_keys = cur.api_keys_encrypted;
            var enc_buf: ?[]u8 = null;
            defer if (enc_buf) |b| ctx.allocator.free(b);

            if (req.api_keys) |keys| {
                if (keys.len > 0) {
                    const plain_json = std.json.Stringify.valueAlloc(ctx.allocator, keys, .{}) catch |err| {
                        std.log.err("internal error: {s}", .{@errorName(err)});
                        try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                        return;
                    };
                    defer ctx.allocator.free(plain_json);
                    enc_buf = self.svc.encryptKeys(ctx.allocator, plain_json) catch |err| switch (err) {
                        error.MissingKeySecret => {
                            try ctx.sendErrorResponse(400, 400, "未配置 ZWEQ_AI_KEY_SECRET");
                            return;
                        },
                        else => {
                            std.log.err("internal error: {s}", .{@errorName(err)});
                            try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                            return;
                        },
                    };
                    enc_keys = enc_buf.?;
                }
            }

            const now = zigmodu.time.wallClockSeconds(self.svc.io);
            _ = self.svc.store.updateProvider(
                id,
                req.name,
                req.endpoint,
                enc_keys,
                req.models orelse cur.models,
                req.fallback_providers orelse cur.fallback_providers,
                req.enabled orelse cur.enabled,
                now,
            ) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };

            try ctx.ok("null");
        }

        fn deleteProvider(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Provider ID");
                return;
            };
            self.svc.store.deleteProvider(id) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            try ctx.ok("null");
        }

        fn checkProvider(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Provider ID");
                return;
            };
            const result = self.svc.checkProvider(ctx.allocator, id) catch |err| switch (err) {
                error.ProviderNotFound => {
                    try ctx.sendErrorResponse(404, 404, "Provider 不存在");
                    return;
                },
                error.ProviderDisabled => {
                    try ctx.sendErrorResponse(400, 400, "Provider 已停用");
                    return;
                },
                error.EmptyApiKeys => {
                    try ctx.sendErrorResponse(400, 400, "Provider 未配置密钥");
                    return;
                },
                error.EmptyModel => {
                    try ctx.sendErrorResponse(400, 400, "Provider 未配置模型");
                    return;
                },
                else => {
                    // 连接失败的内部错误类型只记录到服务端日志（见下方 std.log.err），
                    // 不再透传给客户端，避免泄漏内部错误名。
                    std.log.err("provider connect test failed: {s}", .{@errorName(err)});
                    try ctx.sendErrorResponse(502, 502, "连接测试失败，请检查网络或 Provider 配置");
                    return;
                },
            };
            try ctx.okValue(.{ .status = result });
        }

        // ── Sessions & Chat ──

        fn listSessions(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUid(ctx) orelse return;
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.store.listSessions(uid, params.page, params.page_size) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            // 行与数组由 `AiStore.dupSession`/`listSessions` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer result.free(self.svc.store.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, SessionDto, toSessionDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createSession(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUid(ctx) orelse return;
            const tenant_id = mw.authTenantId(ctx) orelse 1;
            const req = ctx.bindJson(CreateSessionReq) catch CreateSessionReq{};
            const now = zigmodu.time.wallClockSeconds(self.svc.io);
            const title = if (req.title.len > 0) req.title else "新对话";
            const id = self.svc.store.createSession(uid, tenant_id, title, now) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            try ctx.okValue(.{ .id = id });
        }

        fn listMessages(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUid(ctx) orelse return;
            const sid = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Session ID");
                return;
            };
            const sess_opt = self.svc.store.getSession(sid, uid) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            const sess = sess_opt orelse {
                try ctx.sendErrorResponse(404, 404, "Session 不存在");
                return;
            };
            // 行由 `AiStore.dupSession` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer sess.free(self.svc.store.allocator);

            var result = self.svc.store.listMessages(sid) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            // 行与数组由 `AiStore.dupMessage`/`listMessages` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer result.free(self.svc.store.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, MessageDto, toMessageDto);
            try ctx.okValue(.{ .list = dtos, .total = result.total });
        }

        fn chat(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUid(ctx) orelse return;
            const sid = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Session ID");
                return;
            };
            const session_opt = self.svc.store.getSession(sid, uid) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            const session = session_opt orelse {
                try ctx.sendErrorResponse(404, 404, "Session 不存在");
                return;
            };
            // 行由 `AiStore.dupSession` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer session.free(self.svc.store.allocator);

            const req = ctx.bindJson(ChatReq) catch {
                try ctx.sendErrorResponse(400, 400, "无效的请求 JSON");
                return;
            };
            const content = std.mem.trim(u8, req.content, " \t\r\n");
            if (content.len == 0) {
                try ctx.sendErrorResponse(400, 400, "消息内容不能为空");
                return;
            }

            const now = zigmodu.time.wallClockSeconds(self.svc.io);
            _ = self.svc.store.addMessage(sid, "user", content, "", now) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };

            var outcome = self.svc.chat(ctx.allocator, sid, uid, session.tenant_id, content) catch |err| switch (err) {
                error.NoAiProvider => {
                    try ctx.sendErrorResponse(503, 503, "未配置可用的 AI Provider");
                    return;
                },
                error.QuotaExceeded => {
                    try ctx.sendErrorResponse(429, 429, "今日 AI 调用次数已达上限");
                    return;
                },
                error.AiCircuitOpen => {
                    try ctx.sendErrorResponse(503, 503, "AI 服务暂不可用(熔断保护中)");
                    return;
                },
                else => {
                    std.log.err("internal error: {s}", .{@errorName(err)});
                    try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                    return;
                },
            };
            defer outcome.free(ctx.allocator);

            // 应答已生成，不能因落库失败丢弃它；但历史缺失/会话时间不同步必须留痕。
            _ = self.svc.store.addMessage(sid, "assistant", outcome.answer, outcome.reasoning, now) catch |err| {
                std.log.err("[ai] 助手回复写入失败 session={d}: {s}", .{ sid, @errorName(err) });
            };
            _ = self.svc.store.touchSession(sid, now) catch |err| {
                std.log.err("[ai] 会话时间更新失败 session={d}: {s}", .{ sid, @errorName(err) });
            };
            try ctx.okValue(.{
                .answer = outcome.answer,
                .reasoning_content = outcome.reasoning,
                .budget_exhausted = outcome.budget_exhausted,
            });
        }

        fn deleteSession(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const uid = authUid(ctx) orelse return;
            const sid = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Session ID");
                return;
            };
            _ = self.svc.store.deleteSession(sid, uid) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            try ctx.ok("null");
        }

        // ── Approvals / runs / metrics ──

        fn listApprovals(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const status = ctx.queryParam("status");
            var result = self.svc.store.listApprovals(status, params.page, params.page_size) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            // 行与数组由 `AiStore.dupApproval`/`listApprovals` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer result.free(self.svc.store.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, ApprovalDto, toApprovalDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn resolveApproval(ctx: *http.Context, approve: bool) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = authUid(ctx) orelse return;
            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的 Approval ID");
                return;
            };
            const done = self.svc.approve(ctx.allocator, id, admin_id, approve) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            if (!done) {
                try ctx.sendErrorResponse(400, 400, "该审批已处理或不存在");
                return;
            }
            try ctx.ok("null");
        }

        fn approveApproval(ctx: *http.Context) !void {
            return resolveApproval(ctx, true);
        }

        fn rejectApproval(ctx: *http.Context) !void {
            return resolveApproval(ctx, false);
        }

        fn listRuns(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            const uid = ctx.queryInt(i64, "user_id", 0);
            var result = self.svc.store.listRuns(if (uid > 0) uid else null, params.page, params.page_size) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            // 行与数组由 `AiStore.dupRun`/`listRuns` 用 store 分配器（进程 gpa）分配，`ctx.allocator` 是连接 arena（free 是 no-op）→ 用拥有者释放。
            defer result.free(self.svc.store.allocator);
            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RunDto, toRunDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn runWorkflow(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const admin_id = authUid(ctx) orelse return;
            const tenant_id = mw.authTenantId(ctx) orelse 1;

            var result = self.svc.runHealthWorkflow(ctx.allocator, admin_id, tenant_id) catch |err| {
                std.log.err("internal error: {s}", .{@errorName(err)});
                try ctx.sendErrorResponse(500, 500, "服务器内部错误");
                return;
            };
            defer result.deinit();

            const WorkflowStepOut = struct {
                name: []const u8,
                status: []const u8,
                output: []const u8,
            };
            var outs = try ctx.allocator.alloc(WorkflowStepOut, result.steps.items.len);
            defer ctx.allocator.free(outs);
            for (result.steps.items, 0..) |rec, i| {
                outs[i] = .{
                    .name = rec.name,
                    .status = @tagName(rec.status),
                    .output = rec.output,
                };
            }

            try ctx.okValue(.{
                .status = @tagName(result.status),
                .steps = outs,
            });
        }

        fn metrics(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            var snapshot = self.svc.currentAgentMetrics();
            var ai_metrics = zigmodu.ai.observability.AiMetrics{ .agent = &snapshot };
            const body = try ai_metrics.toPrometheusFormat(ctx.allocator);
            defer ctx.allocator.free(body);
            try ctx.text(200, body);
        }

        fn skills(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            try setAuditActor(ctx, self);
            const names = [_][]const u8{ "zweq.user.search", "zweq.task.stats", "zweq.audit.search", "zweq.tenant.list", "zweq.notify.send" };
            try ctx.okValue(.{ .skills = names[0..] });
        }
    };
}
