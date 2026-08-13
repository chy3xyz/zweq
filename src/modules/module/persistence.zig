//! Persistence over the zent Client — module registry + account bindings.

const std = @import("std");
const zent = @import("zent");
const crud = zent.crud_helpers;
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
    config: []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn free(self: ModuleBindingRow, allocator: std.mem.Allocator) void {
        allocator.free(self.module);
        allocator.free(self.status);
        allocator.free(self.config);
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
        const config = try self.allocator.dupe(u8, e.config);
        errdefer self.allocator.free(config);
        return .{
            .id = e.id,
            .tenant_id = e.tenant_id,
            .account_id = e.account_id,
            .module = module,
            .status = status,
            .config = config,
            .created_at = e.created_at orelse 0,
            .updated_at = e.updated_at orelse 0,
        };
    }

    // ── AppModule registry ───────────────────────────────────────

    pub fn getModuleByName(self: *ModuleStore, tenant_id: i64, name: []const u8) !?AppModuleRow {
        const preds = self.client.app_module.predicates;
        var entity = (try crud.first(self.client.app_module, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.nameEQ(.{ .string = name }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, AppModuleInfo, &entity, self.allocator);
        return try self.dupModule(entity);
    }

    /// Upsert a module by (tenant_id, name). Returns the module id.
    pub fn upsertModule(self: *ModuleStore, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8, status: []const u8, now: i64) !i64 {
        if (try self.getModuleByName(tenant_id, name)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.app_module.predicates;
            _ = try crud.update(self.client.app_module, .{
                .title = title,
                .version = version,
                .status = status,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.app_module, .{
            .tenant_id = tenant_id,
            .name = name,
            .title = title,
            .version = version,
            .status = status,
            .created_at = now,
            .updated_at = now,
        });
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
        const preds = self.client.module_binding.predicates;
        var entity = (try crud.first(self.client.module_binding, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.account_idEQ(.{ .int = account_id }), preds.moduleEQ(.{ .string = module }) })) orelse return null;
        defer zent.codegen.deinitEntity(infos, ModuleBindingInfo, &entity, self.allocator);
        return try self.dupBinding(entity);
    }

    /// Bind a module to an account (upsert). Returns the binding id.
    pub fn bind(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8, status: []const u8, now: i64) !i64 {
        if (try self.getBinding(tenant_id, account_id, module)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.module_binding.predicates;
            _ = try crud.update(self.client.module_binding, .{
                .status = status,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.module_binding, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .module = module,
            .status = status,
            .config = "",
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ModuleBindingInfo, &row, self.allocator);
        return row.id;
    }

    /// Update the per-account config blob for a bound module (upserts the
    /// binding when it does not exist yet). Returns the binding id.
    pub fn setBindingConfig(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8, config: []const u8, now: i64) !i64 {
        if (try self.getBinding(tenant_id, account_id, module)) |row| {
            defer row.free(self.allocator);
            const preds = self.client.module_binding.predicates;
            _ = try crud.update(self.client.module_binding, .{
                .config = config,
                .updated_at = now,
            }, .{preds.idEQ(.{ .int = row.id })});
            return row.id;
        }
        var row = try crud.create(self.client.module_binding, .{
            .tenant_id = tenant_id,
            .account_id = account_id,
            .module = module,
            .status = "active",
            .config = config,
            .created_at = now,
            .updated_at = now,
        });
        defer zent.codegen.deinitEntity(infos, ModuleBindingInfo, &row, self.allocator);
        return row.id;
    }

    pub fn unbind(self: *ModuleStore, tenant_id: i64, account_id: i64, module: []const u8) !void {
        const preds = self.client.module_binding.predicates;
        _ = try crud.delete(self.client.module_binding, .{ preds.tenant_idEQ(.{ .int = tenant_id }), preds.account_idEQ(.{ .int = account_id }), preds.moduleEQ(.{ .string = module }) });
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
