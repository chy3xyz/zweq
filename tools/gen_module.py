#!/usr/bin/env python3
"""zweq 模块脚手架生成器。

从一个模块名生成一个「标准 CRUD 应用」的六件套骨架，并自动接线
schema.zig / main.zig / tests.zig（以 checkin 模块为锚点追加）。

用法：
    python3 tools/gen_module.py vote --title 投票
    python3 tools/gen_module.py vote --title 投票 --dry-run

生成结果：
    src/modules/<name>/{model,persistence,service,api,module,root}.zig
    + schema.zig / main.zig / tests.zig 的接线（锚点追加，幂等）

生成的骨架是一个可编译、可运行的「记录型」应用（tenant_id + account_id
+ title 单表），可作为真实业务（投票/抽奖/表单/报名…）的起点：先跑通
CRUD，再按 dev.md §10 增删字段、加 Receiver 钩子接微信消息。
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES_DIR = os.path.join(ROOT, "src", "modules")

NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def pascal_case(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


# ---------------------------------------------------------------------------
# 六个文件的模板（占位符：@NAME@=snake_case 模块名，@Name@=PascalCase，
# @title@=中文标题）。Zig 代码里不会出现 @NAME@ 这种左右带 @ 的串，故用
# 纯字符串替换，避免与 Zig 的 `{}` 字面量冲突。
# ---------------------------------------------------------------------------

MODEL_TPL = '''//! zent schema-as-code — @title@（@NAME@）模块。
//!
//! 由 `tools/gen_module.py` 生成的记录型应用骨架：单表 @Name@Record
//! （tenant_id + account_id + title）。按需增删字段后重写业务，并可参照
//! `src/modules/checkin` 增加 message 模块 Receiver 钩子接入公众号消息。

const zent = @import("zent");
const field = zent.core.field;
const Schema = zent.core.schema.Schema;

pub const @Name@Record = Schema("@Name@Record", .{
    .fields = &.{
        field.Int("tenant_id").Default(1),
        field.Int("account_id"),
        field.String("title").Default(""),
    },
    .mixins = &.{zent.core.mixin.TimeMixin},
});
'''

PERSISTENCE_TPL = '''//! Persistence over the zent Client — @title@（@NAME@）记录。

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.@Name@Record });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const @Name@RecordInfo = infos[0];

pub const @Name@RecordRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    title: []const u8,
    created_at: i64,

    pub fn free(self: @Name@RecordRow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};

pub const @Name@ListResult = struct {
    items: []@Name@RecordRow,
    total: i64,

    pub fn free(self: *@Name@ListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const @Name@Store = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) @Name@Store {
        return .{ .allocator = allocator, .client = client };
    }

    fn dup(self: *@Name@Store, e: anytype) !@Name@RecordRow {
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .title = title,
            .created_at = e.created_at orelse 0,
        };
    }

    pub fn create(self: *@Name@Store, tenant_id: i64, account_id: i64, title: []const u8, now: i64) !i64 {
        var row = try crud.create(self.client.@name@_record, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .title = title,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, @Name@RecordInfo, &row, self.allocator);
        return row.id;
    }

    pub fn getById(self: *@Name@Store, id: i64) !?@Name@RecordRow {
        const preds = self.client.@name@_record.predicates;
        var entity = (try crud.first(self.client.@name@_record, .{preds.idEQ(.{ .int = id })})) orelse return null;
        defer zent.codegen.deinitEntity(infos, @Name@RecordInfo, &entity, self.allocator);
        return try self.dup(entity);
    }

    pub fn list(self: *@Name@Store, page: usize, page_size: usize, tenant_id: i64, account_id: i64) !@Name@ListResult {
        var q = self.client.@name@_record.Query();
        defer q.deinit();
        const preds = self.client.@name@_record.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderDesc("created_at")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(@Name@RecordRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dup(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    pub fn delete(self: *@Name@Store, id: i64) !void {
        const preds = self.client.@name@_record.predicates;
        _ = try crud.delete(self.client.@name@_record, .{preds.idEQ(.{ .int = id })});
    }
};
'''

SERVICE_TPL = '''//! @Name@ service — @title@ 业务。No HTTP/SQL leakage。

const std = @import("std");
const zigmodu = @import("zigmodu");
const persist = @import("persistence.zig");

pub const @Name@RecordRow = persist.@Name@RecordRow;
pub const @Name@ListResult = persist.@Name@ListResult;

pub const @Name@Error = error{
    InvalidTitle,
    NotFound,
    Unexpected,
};

pub const @Name@Service = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.@Name@Store,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.@Name@Store) @Name@Service {
        return .{ .allocator = allocator, .io = io, .store = store };
    }

    fn now(self: *@Name@Service) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    pub fn create(self: *@Name@Service, tenant_id: i64, account_id: i64, title: []const u8) @Name@Error!i64 {
        if (std.mem.trim(u8, title, " \\t").len == 0) return error.InvalidTitle;
        return self.store.create(tenant_id, account_id, title, self.now()) catch error.Unexpected;
    }

    pub fn get(self: *@Name@Service, id: i64) @Name@Error!?@Name@RecordRow {
        return self.store.getById(id) catch error.Unexpected;
    }

    pub fn list(self: *@Name@Service, page: usize, page_size: usize, tenant_id: i64, account_id: i64) @Name@Error!@Name@ListResult {
        return self.store.list(page, page_size, tenant_id, account_id) catch error.Unexpected;
    }

    pub fn delete(self: *@Name@Service, id: i64) @Name@Error!void {
        self.store.delete(id) catch return error.Unexpected;
    }
};
'''

API_TPL = '''//! Admin-facing @title@（@NAME@）API。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;
const mw = @import("../../middleware/auth.zig");
const user_svc = @import("../user/service.zig");
const audit_svc = @import("../audit/service.zig");

const service = @import("service.zig");

const RecordDto = struct {
    id: i64,
    account_id: i64,
    title: []const u8,
    created_at: i64,
};

fn toDto(row: service.@Name@RecordRow) RecordDto {
    return .{
        .id = row.id,
        .account_id = row.account_id,
        .title = row.title,
        .created_at = row.created_at,
    };
}

const CreateReq = struct {
    account_id: i64,
    title: []const u8,
};

pub fn @Name@Api(comptime Service: type, comptime UserService: type) type {
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
            try g.get("/@name@/records", list, @ptrCast(@alignCast(self)));
            try g.post("/@name@/records", create, @ptrCast(@alignCast(self)));
            try g.delete("/@name@/records/{id}", delete, @ptrCast(@alignCast(self)));
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

        fn list(ctx: *http.Context) !void {
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
            var result = self.svc.list(params.page, params.page_size, tid, account_id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            defer result.free(self.svc.allocator);

            const dtos = try zigmodu.http.Extract.toDtoList(ctx.allocator, result.items, RecordDto, toDto);
            try zigmodu.http.sendPaged(ctx, dtos, @intCast(result.total), params, .ruoyi);
        }

        fn create(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const req = ctx.bindJson(CreateReq) catch {
                try ctx.sendErrorResponse(400, 400, "请求体格式错误");
                return;
            };
            defer ctx.allocator.free(req.title);
            const id = self.svc.create(tid, req.account_id, req.title) catch |err| {
                try ctx.sendErrorResponse(400, 400, @errorName(err));
                return;
            };
            var d1: [128]u8 = undefined;
            const det1 = try std.fmt.bufPrint(&d1, "创建 @title@ 记录 {s}", .{req.title});
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "@name@.create", "@name@", id, det1, zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(201, .{ .code = 0, .msg = "已创建", .data = .{ .id = id } });
        }

        fn delete(ctx: *http.Context) !void {
            const self: *Self = @ptrCast(@alignCast(ctx.user_data orelse return error.UnexpectedError));
            const admin_id = (try requireAdmin(ctx, self)) orelse return;
            const tid = tenantScope(ctx, self);

            const id = ctx.paramInt(i64, "id") catch {
                try ctx.sendErrorResponse(400, 400, "无效的记录 ID");
                return;
            };
            self.svc.delete(id) catch |err| {
                try ctx.sendErrorResponse(500, 500, @errorName(err));
                return;
            };
            self.audit.log(admin_id, ctx.getAttr("audit_actor") orelse "", "@name@.delete", "@name@", id, "删除 @title@ 记录", zigmodu.http.RequestUtil.getRealIp(ctx), true, tid);
            try ctx.jsonStruct(200, .{ .code = 0, .msg = "ok", .data = null });
        }
    };
}

pub const Default@Name@Api = @Name@Api(service.@Name@Service, user_svc.UserService);
'''

MODULE_TPL = '''//! ZigModu module `@name@` — @title@。
const zigmodu = @import("zigmodu");

pub const info = zigmodu.api.Module{
    .name = "@name@",
    .description = "@title@",
    .dependencies = &.{},
    .is_internal = false,
};

pub fn init() !void {}
pub fn deinit() void {}
'''

ROOT_TPL = '''//! Barrel re-exports for module `@name@`.
pub const model = @import("model.zig");
pub const persistence = @import("persistence.zig");
pub const service = @import("service.zig");
pub const api = @import("api.zig");
pub const module = @import("module.zig");
'''

TEMPLATES = {
    "model.zig": MODEL_TPL,
    "persistence.zig": PERSISTENCE_TPL,
    "service.zig": SERVICE_TPL,
    "api.zig": API_TPL,
    "module.zig": MODULE_TPL,
    "root.zig": ROOT_TPL,
}


def render(tpl: str, name: str, Name: str, title: str) -> str:
    return (tpl.replace("@NAME@", name).replace("@Name@", Name).replace("@name@", name).replace("@title@", title))


# ---------------------------------------------------------------------------
# 接线 patch（以 checkin 为锚点追加，幂等：已存在则跳过）
# ---------------------------------------------------------------------------

def patch_once(path: str, anchor: str, addition: str):
    """在 anchor 行后追加 addition；若 addition 已存在或 anchor 缺失则跳过/报错。"""
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()
    if addition.strip() in src:
        return False  # 已存在，幂等跳过
    if src.count(anchor) != 1:
        raise SystemExit(f"锚点不唯一或缺失：{path} 中的 {anchor!r}（出现 {src.count(anchor)} 次）")
    src = src.replace(anchor, anchor + addition, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    return True


def patch_replace(path: str, old: str, new: str):
    """把锚点本身替换为新文本（用于改写末尾分号/运算符的场景），幂等。"""
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()
    if new in src:
        return False  # 已替换，幂等跳过
    if src.count(old) != 1:
        raise SystemExit(f"锚点不唯一或缺失：{path} 中的 {old!r}（出现 {src.count(old)} 次）")
    src = src.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    return True


def wire_schema(name: str, Name: str):
    p = os.path.join(ROOT, "src", "schema.zig")
    patch_once(p,
               'const checkin_model = @import("modules/checkin/model.zig");',
               f'\nconst {name}_model = @import("modules/{name}/model.zig");')
    patch_once(p,
               'const checkin_graph = zent.codegen.graph.buildGraph(&.{checkin_model.CheckinRecord});',
               f'\nconst {name}_graph = zent.codegen.graph.buildGraph(&.{{{name}_model.{Name}Record}});')
    # infos 链：points 为当前末尾项（带分号），改为 `++` 并追加新项。
    patch_replace(p,
                  '    points_graph.types;',
                  f'    points_graph.types ++\n    {name}_graph.types;')


def wire_main(name: str, Name: str):
    p = os.path.join(ROOT, "src", "main.zig")
    patch_once(p,
               'const checkin = @import("modules/checkin/root.zig");',
               f'\nconst {name} = @import("modules/{name}/root.zig");')
    patch_once(p,
               '        checkin.persistence.infos,',
               f'\n        {name}.persistence.infos,')
    # service 初始化：追加在 checkin 的 receiver 注册块之后
    patch_once(p,
               '        .handle = checkin.service.receiverHandle,\n    });',
               f'\n    var {name}_store = {name}.persistence.{Name}Store.init(allocator, store_env.client);\n'
               f'    var {name}_svc = {name}.service.{Name}Service.init(allocator, io, &{name}_store);')
    patch_once(p,
               '        checkin.module,',
               f'\n        {name}.module,')
    patch_once(p,
               '    var checkin_api = checkin.api.CheckinApi(@TypeOf(checkin_svc), @TypeOf(user_svc)).init(&checkin_svc, &user_svc, &audit_svc, default_tenant_id);',
               f'\n    var {name}_api = {name}.api.{Name}Api(@TypeOf({name}_svc), @TypeOf(user_svc)).init(&{name}_svc, &user_svc, &audit_svc, default_tenant_id);')
    patch_once(p,
               '    try checkin_api.registerRoutes(&v1);',
               f'\n    try {name}_api.registerRoutes(&v1);')


def wire_tests(name: str):
    p = os.path.join(ROOT, "src", "tests.zig")
    patch_once(p,
               'const checkin = @import("modules/checkin/root.zig");',
               f'\nconst {name} = @import("modules/{name}/root.zig");')
    # openMemory 有两处 infos 列表：返回类型声明（4 空格缩进）与函数体（8 空格缩进）。
    patch_once(p,
               '    checkin.persistence.infos,',
               f'\n    {name}.persistence.infos,')
    patch_once(p,
               '        checkin.persistence.infos,',
               f'\n        {name}.persistence.infos,')


def main():
    ap = argparse.ArgumentParser(description="生成 zweq 模块六件套骨架并接线")
    ap.add_argument("name", help="模块名（snake_case，如 vote）")
    ap.add_argument("--title", help="模块中文标题（默认取模块名）")
    ap.add_argument("--dry-run", action="store_true", help="只打印将写入/改动的文件，不落盘")
    args = ap.parse_args()

    name = args.name
    if not NAME_RE.match(name):
        sys.exit(f"非法模块名：{name!r}（须匹配 [a-z][a-z0-9_]*）")
    Name = pascal_case(name)
    title = args.title or name

    mod_dir = os.path.join(MODULES_DIR, name)
    if os.path.exists(mod_dir):
        sys.exit(f"模块目录已存在：{mod_dir}")

    files = {fn: render(tpl, name, Name, title) for fn, tpl in TEMPLATES.items()}

    print(f"== 生成模块 {name}（{Name}）— {title} ==")
    for fn in sorted(files):
        target = os.path.join(mod_dir, fn)
        if args.dry_run:
            print(f"  [dry-run] {os.path.relpath(target, ROOT)}")
        else:
            os.makedirs(mod_dir, exist_ok=True)
            with open(target, "w", encoding="utf-8") as f:
                f.write(files[fn])
            print(f"  写入 {os.path.relpath(target, ROOT)}")

    if not args.dry_run:
        print("== 接线 ==")
        wire_schema(name, Name)
        wire_main(name, Name)
        wire_tests(name)
        print("  已接线 schema.zig / main.zig / tests.zig")

    print("== 下一步 ==")
    print(f"  zig build && zig build test")
    print(f"  # 需接公众号消息时，参照 src/modules/checkin 在 service 加 receiverHandle，")
    print(f"  # 并在 main.zig 的 checkin receiver 注册块后加 wechat_svc.registerReceiver(...)。")


if __name__ == "__main__":
    main()
