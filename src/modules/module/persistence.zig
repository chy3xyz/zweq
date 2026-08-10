//! Persistence over the zent Client — module registry + account bindings.

const std = @import("std");
const zent = @import("zent");
const model = @import("model.zig");
const schema = @import("../../schema.zig");

const graph = zent.codegen.graph.buildGraph(&.{ model.AppModule, model.ModuleBinding });
pub const infos = graph.types;
/// Shared, application-wide typed client (all schemas registered in schema.zig).
pub const Client = schema.Client;
pub const AppModuleInfo = infos[0];
pub const ModuleBindingInfo = infos[1];

pub const AppModuleRow = struct {
    id: i64,
    tenant_id: i64,
    name: []const u8,
    title: []const u8,
    version: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: AppModuleRow, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.version);
        allocator.free(self.status);
    }
};

pub const ModuleListResult = struct {
    items: []AppModuleRow,
    total: i64,

    pub fn free(self: *ModuleListResult, allocator: std.mem.Allocator) void {
        for (self.items) |r| r.free(allocator);
        allocator.free(self.items);
    }
};

pub const ModuleBindingRow = struct {
    id: i64,
    tenant_id: i64,
    account_id: i64,
    module: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: ModuleBindingRow, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.status);
    }
};

pub const ModuleStore = struct {
    allocator: std.mem.Allocator,
    client: Client,

    pub fn init(allocator: std.mem.Allocator, client: Client) ModuleStore {
        return .{ .allocator = allocator, .client = client };
    }

    fn dupModule(self: *ModuleStore, e: anytype) !AppModuleRow {
        const name = try self.allocator.dupe(u8, e.name);
        errdefer self.allocator.free(name);
        const title = try self.allocator.dupe(u8, e.title);
        errdefer self.allocator.free(title);
        const version = try self.allocator.dupe(u8, e.version);
        errdefer self.allocator.free(version);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .name = name,
            .title = title,
            .version = version,
            .status = status,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    fn dupBinding(self: *ModuleStore, e: anytype) !ModuleBindingRow {
        const module = try self.allocator.dupe(u8, e.module);
        errdefer self.allocator.free(module);
        const status = try self.allocator.dupe(u8, e.status);
        errdefer self.allocator.free(status);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .module = module,
            .status = status,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    // ── AppModule registry ───────────────────────────────────────

    pub fn getModuleByName(self: *ModuleStore, tenant_id: i64, name: []const u8) !?AppModuleRow {
        var q = self.client.app_module.Query();
        defer q.deinit();
        const preds = self.client.app_module.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.nameEQ(.{ .string = name })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, AppModuleInfo, &entity, self.allocator);
        return try self.dupModule(entity);
    }

    /// Upsert a module by (tenant_id, name). Returns the module id.
    pub fn upsertModule(self: *ModuleStore, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8, status: []const u8, now: i64) !i64 {
        if (try self.getModuleByName(tenant_id, name)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.app_module.predicates;
            var upd = self.client.app_module.Update();
            defer upd.deinit();
            _ = try upd.set("title", .{ .string = title });
            _ = try upd.set("version", .{ .string = version });
            _ = try upd.set("status", .{ .string = status });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.app_module.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("name", name);
        _ = try b.setFieldValue("title", title);
        _ = try b.setFieldValue("version", version);
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, AppModuleInfo, &row, self.allocator);
        return row.id;
    }

    pub fn listModules(self: *ModuleStore, page: usize, page_size: usize, tenant_id: i64) !ModuleListResult {
        var q = self.client.app_module.Query();
        defer q.deinit();
        const preds = self.client.app_module.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("name")});

        var paged = try q.paged(page, page_size);
        defer paged.deinit();

        var out = try self.allocator.alloc(AppModuleRow, paged.items.items.len);
        var n: usize = 0;
        errdefer {
            for (out[0..n]) |r| r.free(self.allocator);
            self.allocator.free(out);
        }
        for (paged.items.items) |e| {
            out[n] = try self.dupModule(e);
            n += 1;
        }
        return .{ .items = out, .total = paged.total };
    }

    // ── ModuleBinding ─────────────────────────────────────────────

    pub fn getBinding(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8) !?ModuleBindingRow {
        var q = self.client.module_binding.Query();
        defer q.deinit();
        const preds = self.client.module_binding.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.Where(.{preds.moduleEQ(.{ .string = module })});
        _ = q.Limit(1);
        const entity_opt = try q.First();
        var entity = entity_opt orelse return null;
        defer zent.codegen.deinitEntity(infos, ModuleBindingInfo, &entity, self.allocator);
        return try self.dupBinding(entity);
    }

    /// Bind a module to an account (upsert). Returns the binding id.
    pub fn bind(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8, status: []const u8, now: i64) !i64 {
        if (try self.getBinding(tenant_id, account_id, module)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.module_binding.predicates;
            var upd = self.client.module_binding.Update();
            defer upd.deinit();
            _ = try upd.set("status", .{ .string = status });
            _ = try upd.setFieldValue("updated_at", now);
            _ = try upd.Where(.{preds.idEQ(.{ .int = row.id })});
            _ = try upd.Save();
            return row.id;
        }
        var b = try self.client.module_binding.Create();
        defer b.deinit();
        _ = try b.setFieldValue("tenant_id", tenant_id);
        _ = try b.setFieldValue("account_id", account_id);
        _ = try b.setFieldValue("module", module);
        _ = try b.setFieldValue("status", status);
        _ = try b.setFieldValue("created_at", now);
        _ = try b.setFieldValue("updated_at", now);
        var row = try b.Save();
        defer zent.codegen.deinitEntity(infos, ModuleBindingInfo, &row, self.allocator);
        return row.id;
    }

    pub fn unbind(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8) !void {
        const preds = self.client.module_binding.predicates;
        var d = self.client.module_binding.Delete();
        defer d.deinit();
        _ = try d.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try d.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try d.Where(.{preds.moduleEQ(.{ .string = module })});
        _ = try d.Exec();
    }

    pub fn listBindings(self: *ModuleStore, tenant_id: i64, account_id: i64) ![]ModuleBindingRow {
        var q = self.client.module_binding.Query();
        defer q.deinit();
        const preds = self.client.module_binding.predicates;
        _ = try q.Where(.{preds.tenant_idEQ(.{ .int = tenant_id })});
        _ = try q.Where(.{preds.account_idEQ(.{ .int = account_id })});
        _ = try q.OrderBy(&[_]zent.sql.Order{zent.sql.OrderAsc("module")});
        var rows = try q.All();
        defer {
            for (rows.items) |*e| zent.codegen.deinitEntity(infos, ModuleBindingInfo, e, self.allocator);
            rows.deinit();
        }
        var out = try self.allocator.alloc(ModuleBindingRow, rows.items.len);
        errdefer self.allocator.free(out);
        var n: usize = 0;
        errdefer for (out[0..n]) |r| r.free(self.allocator);
        for (rows.items) |e| {
            out[n] = try self.dupBinding(e);
            n += 1;
        }
        return out;
    }
};
