//! Admin-facing auto-reply rules API — manage keyword rules per account.

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const RuleDto = struct {
    id: i64,
    account_id: i64,
    name: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
};

fn toRuleDto(row: service.RuleRow) RuleDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .name = row.name,
        .status = row.status,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
    };
}

const KeywordDto = struct {
    id: i64,
    rule_id: i64,
    keyword: []const u8,
    match_type: []const u8,
};

const ReplyDto = struct {
    id: i64,
    rule_id: i64,
    reply_type: []const u8,
    content: []const u8,
    news_title: []const u8,
    news_description: []const u8,
    news_pic_url: []const u8,
    news_url: []const u8,
};

const CreateRuleReq = struct {
    account_id: i64,
    name: []const u8,
};

const UpdateRuleReq = struct {
    name: ?[]const u8 = null,
    status: ?[]const u8 = null,
};

const AddKeywordReq = struct {
    keyword: []const u8,
    match_type: []const u8,
};

const AddReplyReq = struct {
    reply_type: []const u8,
    content: ?[]const u8 = null,
    news_title: ?[]const u8 = null,
    news_description: ?[]const u8 = null,
    news_pic_url: ?[]const u8 = null,
    news_url: ?[]const u8 = null,
};

pub fn RuleApi(comptime Service: type, comptime UserService: type) type {
    return struct {
        const Self = @This();
        svc: *Service,
        user_svc: *UserService,
        audit: *audit_svc.AuditService,
        default_tenant_id: i64,

        pub fn init(svc: *Service, users: *UserService, audit: *audit_svc.AuditService, default_tenant_id: i64) Self {
            return .{ .svc = svc, .user_svc = users, .audit = audit, .default_tenant_id = default_tenant_id };
        }

        pub fn registerRoutes(self: *Self, group: *http.RouteGroup) !void {
            var g = try group.use(zigmodu.http.http_middleware.jwtAuthWithSecurity(&self.user_svc.sec.module));
            g = try g.use(mw.tokenVersionGuard(self.user_svc.sec, self.user_svc.store));
            try g.get("/rules", listRules, @ptrCast(@alignCast(self)));
            try g.post("/rules", createRule, @ptrCast(@alignCast(self)));
            try g.get("/rules/{id}", getRule, @ptrCast(@alignCast(self)));
            try g.put("/rules/{id}", updateRule, @ptrCast(@alignCast(self)));
            try g.delete("/rules/{id}", deleteRule, @ptrCast(@alignCast(self)));
            try g.get("/rules/{id}/keywords", listKeywords, @ptrCast(@alignCast(self)));
            try g.post("/rules/{id}/keywords", addKeyword, @ptrCast(@alignCast(self)));
            try g.delete("/rules/{id}/keywords/{kid}", removeKeyword, @ptrCast(@alignCast(self)));
            try g.get("/rules/{id}/replies", listReplies, @ptrCast(@alignCast(self)));
            try g.post("/rules/{id}/replies", addReply, @ptrCast(@alignCast(self)));
            try g.delete("/rules/{id}/replies/{rid}", removeReply, @ptrCast(@alignCast(self)));
        }

        fn requireAdmin(ctx: *http.Context, self: *Self) !?i64 {
            const uid = mw.authUserId(ctx) orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            const row_opt = self.user_svc.getUserById(uid) catch {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(401, 401, "未登录或登录已过期");
                return null;
            };
            defer row.free(self.svc.allocator);
            if (!row.admin) {
                try ctx.sendErrorResponse(403, 403, "需要管理员权限");
                return null;
            }
            try ctx.setAttr("audit_actor", row.name);
            return uid;
        }

        fn tenantScope(ctx: *http.Context, self: *Self) i64 {
            return mw.authTenantId(ctx) orelse self.default_tenant_id;
        }

        fn listRules(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const account_raw = ctx.queryParam("account_id") orelse {
                try ctx.sendErrorResponse(400, 400, "缺少 account_id");
                return;
            };
            const account_id = std.fmt.parseInt(i64, account_raw, 10) catch {
                try ctx.sendErrorResponse(400, 400, "无效的 account_id");
                return;
            };
            const params = zigmodu.http.PageParams.parse(ctx, .{ .max_page_size = 100 });
            var result = self.svc.listRules(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RuleDto, toRuleDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn createRule(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateRuleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.name);
            const id = self.svc.createRule(tid, req.account_id, req.name) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "规则名称不能为空",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建自动回复规则 {s} @ account {d}", .{ req.name, req.account_id });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.create", "rule", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "规则已创建", .data = .{ .id = id } });
        }

        fn getRule(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const row_opt = self.svc.getRule(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const row = row_opt orelse {
                try ctx.sendErrorResponse(404, 404, "规则不存在");
                return;
            };
            defer row.free(self.svc.allocator);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = toRuleDto(row) });
        }

        fn updateRule(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const req = ctx.bindJson(UpdateRuleReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                if (req.name) |n| ctx.allocator.free(n);
                if (req.status) |s| ctx.allocator.free(s);
            }
            const cur_opt = self.svc.getRule(id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const cur = cur_opt orelse {
                try ctx.sendErrorResponse(404, 404, "规则不存在");
                return;
            };
            defer cur.free(self.svc.allocator);
            const name = req.name orelse cur.name;
            const status = req.status orelse cur.status;
            self.svc.updateRule(id, name, status) catch |err| {
                const msg = switch (err) {
                    error.InvalidName => "规则名称不能为空",
                    error.InvalidStatus => "状态仅支持 active/disabled",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d2: [128]u8 = undefined;
            const det2 = try std.fmt.bufPrint(&d2, "更新规则 #{d} → {s}", .{ id, status });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.update", "rule", id, det2, zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn deleteRule(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            self.svc.deleteRule(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.delete", "rule", id, "删除规则", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn listKeywords(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const rule_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const rows = self.svc.store.listKeywordsForRule(rule_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            const dtos = try ctx.allocator.alloc(KeywordDto, rows.len);
            for (rows, 0..) |r, i| {
                dtos[i] = .{
                    .id = r.id,
                    .rule_id = r.rule_id,
                    .keyword = r.keyword,
                    .match_type = r.match_type,
                };
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = dtos } });
        }

        fn addKeyword(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const rule_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const req = ctx.bindJson(AddKeywordReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.keyword);
                ctx.allocator.free(req.match_type);
            }
            const rule_opt = self.svc.getRule(rule_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const rule = rule_opt orelse {
                try ctx.sendErrorResponse(404, 404, "规则不存在");
                return;
            };
            defer rule.free(self.svc.allocator);
            const kid = self.svc.addKeyword(tid, rule.account_id, rule_id, req.keyword, req.match_type) catch |err| {
                const msg = switch (err) {
                    error.InvalidKeyword => "关键词不能为空",
                    error.InvalidMatchType => "匹配方式仅支持 full/contain",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "规则 #{d} 加关键词 {s}", .{ rule_id, req.keyword });
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.keyword", "rule", rule_id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "关键词已添加", .data = .{ .id = kid } });
        }

        fn removeKeyword(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const kid = ctx.paramInt(i64, "kid") catch {
                try ctx.sendErrorResponse(400, 400, "无效的关键词 ID");
                return;
            };
            self.svc.removeKeyword(kid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.keyword.delete", "rule", kid, "删除关键词", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }

        fn listReplies(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            _ = (try requireAdmin(ctx, self)) orelse return;

            const rule_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const rows = self.svc.store.listRepliesForRule(rule_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer {
                for (rows) |r| r.free(ctx.allocator);
                ctx.allocator.free(rows);
            }
            const dtos = try ctx.allocator.alloc(ReplyDto, rows.len);
            for (rows, 0..) |r, i| {
                dtos[i] = .{
                    .id = r.id,
                    .rule_id = r.rule_id,
                    .reply_type = r.reply_type,
                    .content = r.content,
                    .news_title = r.news_title,
                    .news_description = r.news_description,
                    .news_pic_url = r.news_pic_url,
                    .news_url = r.news_url,
                };
            }
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = .{ .items = dtos } });
        }

        fn addReply(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const rule_id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的规则 ID");
                return;
            };
            const req = ctx.bindJson(AddReplyReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer {
                ctx.allocator.free(req.reply_type);
                if (req.content) |s| ctx.allocator.free(s);
                if (req.news_title) |s| ctx.allocator.free(s);
                if (req.news_description) |s| ctx.allocator.free(s);
                if (req.news_pic_url) |s| ctx.allocator.free(s);
                if (req.news_url) |s| ctx.allocator.free(s);
            }
            const rule_opt = self.svc.getRule(rule_id) catch {
                try ctx.sendErrorResponse(500, 500, "服务器错误");
                return;
            };
            const rule = rule_opt orelse {
                try ctx.sendErrorResponse(404, 404, "规则不存在");
                return;
            };
            defer rule.free(self.svc.allocator);
            const rid = self.svc.addReply(
                tid,
                rule.account_id,
                rule_id,
                req.reply_type,
                req.content orelse "",
                req.news_title orelse "",
                req.news_description orelse "",
                req.news_pic_url orelse "",
                req.news_url orelse "",
            ) catch |err| {
                const msg = switch (err) {
                    error.InvalidReplyType => "回复类型仅支持 text/news，text 时内容不能为空",
                    else => @errorName(err),
                };
                try ctx.sendErrorResponse(400, 400, msg);
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.reply", "rule", rule_id, "添加回复", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "回复已添加", .data = .{ .id = rid } });
        }

        fn removeReply(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;

            const rid = ctx.paramInt(i64, "rid") catch {
                try ctx.sendErrorResponse(400, 400, "无效的回复 ID");
                return;
            };
            self.svc.removeReply(rid) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "rule.reply.delete", "rule", rid, "删除回复", zigmodu.http.RequestUtil.getRealIp(ctx), true, tenantScope(ctx, self));
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const DefaultRuleApi = RuleApi(service.RuleService, user_svc.UserService);
