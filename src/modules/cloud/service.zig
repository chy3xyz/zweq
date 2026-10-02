//! Cloud service — site licenses (授权码) + marketplace (应用市场).
//! No HTTP/SQL leakage. `installPackage` feeds the module registry + binding.

const std = @import("std");
const zigmodu = @import("zigmodu");
const zwechat = @import("zwechat");
const zent = @import("zent");
const persist = @import("persistence.zig");
const module_svc_mod = @import("../module/service.zig");
const url_guard = @import("../../http/url_guard.zig");

pub const LicenseRow = persist.LicenseRow;
pub const LicenseListResult = persist.LicenseListResult;
pub const MarketPackageRow = persist.MarketPackageRow;
pub const MarketListResult = persist.MarketListResult;

pub const CloudError = error{
    InvalidName,
    InvalidUrl,
    InvalidDays,
    InvalidLicense,
    LicenseExpired,
    ChecksumMismatch,
    DownloadFailed,
    NotFound,
    RemoteUnavailable,
    /// 安装投递后台 worker 后等待结果超时（前端要求的同步语义下的独立超时）。
    RemoteTimeout,
    Unexpected,
};

pub const CloudService = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *persist.CloudStore,
    module_svc: *module_svc_mod.ModuleService,
    /// 远端 zweq-cloud 服务 base url（`http://host:port/api/v1`）。
    /// 空 = 本地模式（授权码/市场走本地 DB）。
    remote_base_url: []const u8,
    /// 可选 transport 注入（测试用）；null 时用真实 std.http.Client。
    http_transport: ?zwechat.util.http.HttpClient.Transport = null,
    http_transport_ctx: ?*anyopaque = null,
    /// 站点授权码（站点设置 `cloud_license_key`；由 main 启动时注入）。
    site_license_key: []const u8 = "",
    /// 授权状态（原子）。本地模式恒 true；远端模式由后台 monitor 校验后
    /// 更新，失败/过期/未配置授权码 → false（fail-closed 锁功能）。
    license_valid: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    /// 最近一次云端授权校验时间戳（0 = 尚未校验）。
    license_checked_at: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    /// 最后一次「成功」校验时间戳（0 = 从未成功）。宽限期据此计算。
    last_success_at: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    /// 宽限天数：校验失败/云端抖动时，若曾成功授权且在宽限期内，仍放行。
    /// 0 = 无宽限（严格 fail-closed）。
    grace_days: i64 = 7,
    /// 原始 SQL 执行器（执行市场包 manifest 里的迁移 SQL）。null = 不可执行迁移。
    driver: ?zent.sql_driver.Driver = null,
    /// 动态表元数据存储（manifest tables 注册 + 通用查询）。null = 不可用。
    dyn_table_store: ?*persist.DynamicTableStore = null,
    /// 远端云服务后台 worker：zwechat client 是同步阻塞实现，远端下载/同步
    /// 统一投递到这里在专用线程执行，不占 io 线程。懒启动（首次投递时
    /// spawn），deinit 时 join。
    worker: RemoteWorker = .{},

    pub fn init(allocator: std.mem.Allocator, io: std.Io, store: *persist.CloudStore, module_svc: *module_svc_mod.ModuleService, remote_base_url: []const u8) CloudService {
        return .{ .allocator = allocator, .io = io, .store = store, .module_svc = module_svc, .remote_base_url = remote_base_url };
    }

    /// 注入 SQL 执行器（main 装配时从 store_env 取 asDriver()）。
    pub fn setDriver(self: *CloudService, d: zent.sql_driver.Driver) void {
        self.driver = d;
    }

    /// 注入动态表元数据存储。
    pub fn setDynamicTableStore(self: *CloudService, s: *persist.DynamicTableStore) void {
        self.dyn_table_store = s;
    }

    /// 释放内部持有的字符串（site_license_key）并停止远端 worker。测试/
    /// 短生命周期用；main 中进程级存活可不调用。
    pub fn deinit(self: *CloudService) void {
        if (self.site_license_key.len > 0) self.allocator.free(self.site_license_key);
        self.stopRemoteWorker();
    }

    /// 是否启用远端云服务（zweq-cloud）模式。
    pub fn isRemote(self: *const CloudService) bool {
        return self.remote_base_url.len > 0;
    }

    /// 当前站点是否已授权（licenseGuard 中间件据此锁功能）。
    /// 宽限期：曾成功授权、当前校验失败但仍在宽限天数内 → 放行。
    pub fn isLicensed(self: *const CloudService) bool {
        if (self.license_valid.load(.acquire)) return true;
        const last_ok = self.last_success_at.load(.acquire);
        if (last_ok > 0 and self.grace_days > 0) {
            const now_secs = zigmodu.time.wallClockSeconds(self.io);
            if (now_secs - last_ok < self.grace_days * 86400) return true;
        }
        return false;
    }

    /// 设置宽限天数（启动时从站点设置 `cloud_license_grace_days` 读入）。
    pub fn setGraceDays(self: *CloudService, days: i64) void {
        self.grace_days = @max(0, days);
    }

    /// 设置站点授权码（启动时从站点设置 `cloud_license_key` 读入）。
    /// dupe 一份，避免引用被释放的查询结果。
    pub fn setSiteLicenseKey(self: *CloudService, key: []const u8) !void {
        if (self.site_license_key.len > 0) self.allocator.free(self.site_license_key);
        self.site_license_key = try self.allocator.dupe(u8, key);
    }

    /// 向远端 zweq-cloud 校验站点授权码并更新 license_valid。
    /// - 本地模式：恒 licensed（本地不锁）。
    /// - 远端模式：无授权码或校验失败/过期/无效 → licensed=false（fail-closed）。
    ///   校验成功记录 last_success_at（宽限期基准）；失败不覆盖该基准。
    pub fn checkSiteLicense(self: *CloudService) void {
        if (!self.isRemote()) {
            self.license_valid.store(true, .release);
            self.license_checked_at.store(self.now(), .release);
            return;
        }
        if (self.site_license_key.len == 0) {
            self.license_valid.store(false, .release);
            self.license_checked_at.store(self.now(), .release);
            return;
        }
        const ok = self.verifyLicenseRemote(self.allocator, self.site_license_key) catch false;
        self.license_valid.store(ok, .release);
        if (ok) self.last_success_at.store(self.now(), .release);
        self.license_checked_at.store(self.now(), .release);
    }

    fn now(self: *CloudService) i64 {
        return zigmodu.time.wallClockSeconds(self.io);
    }

    /// Generate a license key `WEQ-XXXXXXXX-XXXXXXXX-XXXXXXXX`.
    fn genLicenseKey(self: *CloudService, allocator: std.mem.Allocator) ![]const u8 {
        var r: [12]u8 = undefined;
        {
            var file = try std.Io.Dir.cwd().openFile(self.io, "/dev/urandom", .{});
            errdefer file.close(self.io);
            const read = try file.readPositionalAll(self.io, &r, 0);
            if (read != r.len) return error.Unexpected;
        }
        return std.fmt.allocPrint(allocator, "WEQ-{x:0>8}-{x:0>8}-{x:0>8}", .{
            std.mem.readInt(u32, r[0..4], .little),
            std.mem.readInt(u32, r[4..8], .little),
            std.mem.readInt(u32, r[8..12], .little),
        });
    }

    /// Issue a new license valid for `days`. Returns the row (caller frees).
    pub fn generateLicense(self: *CloudService, allocator: std.mem.Allocator, tenant_id: i64, days: i64) CloudError!LicenseRow {
        if (days <= 0) return error.InvalidDays;
        const key = self.genLicenseKey(allocator) catch return error.Unexpected;
        defer allocator.free(key);
        const expires_at = self.now() + days * 86400;
        _ = self.store.createLicense(tenant_id, key, expires_at, self.now()) catch return error.Unexpected;
        const row_opt = self.store.getLicenseByKey(tenant_id, key) catch return error.Unexpected;
        return row_opt orelse error.NotFound;
    }

    /// Verify a license is active and unexpired.
    pub fn verifyLicense(self: *CloudService, tenant_id: i64, license_key: []const u8) CloudError!bool {
        const row_opt = self.store.getLicenseByKey(tenant_id, license_key) catch return error.Unexpected;
        const row = row_opt orelse return error.InvalidLicense;
        defer row.free(self.allocator);
        if (std.mem.eql(u8, row.status, "revoked")) return error.InvalidLicense;
        if (row.expires_at > 0 and self.now() > row.expires_at) {
            // 过期状态回写失败不影响本次判定（下面仍返回 LicenseExpired），
            // 状态会在下次校验时重试写入。
            self.store.setLicenseStatus(row.id, "expired", self.now()) catch {};
            return error.LicenseExpired;
        }
        if (!std.mem.eql(u8, row.status, "active")) return error.InvalidLicense;
        return true;
    }

    pub fn listLicenses(self: *CloudService, page: usize, page_size: usize, tenant_id: i64) CloudError!LicenseListResult {
        return self.store.listLicenses(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn revokeLicense(self: *CloudService, id: i64) CloudError!void {
        self.store.setLicenseStatus(id, "revoked", self.now()) catch return error.Unexpected;
    }

    pub fn listMarket(self: *CloudService, page: usize, page_size: usize, tenant_id: i64) CloudError!MarketListResult {
        return self.store.listMarket(page, page_size, tenant_id) catch error.Unexpected;
    }

    pub fn publishPackage(self: *CloudService, tenant_id: i64, name: []const u8, title: []const u8, version: []const u8, description: []const u8, download_url: []const u8, checksum: []const u8) CloudError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        // SSRF 基线：download_url 非空时会被 installPackage 服务端拉取，写入前校验。
        if (download_url.len > 0 and !url_guard.isAcceptableOutboundUrl(download_url)) return error.InvalidUrl;
        return self.store.upsertPackage(tenant_id, name, title, version, description, download_url, checksum, self.now()) catch error.Unexpected;
    }

    /// 校验内容 sha256 是否与期望 hex 匹配（防止市场产物被篡改）。
    /// 期望为空时跳过校验。
    pub fn verifyChecksum(content: []const u8, expected_hex: []const u8) bool {
        if (expected_hex.len == 0) return true;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(content, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        return std.mem.eql(u8, &hex, expected_hex);
    }

    /// 产物文件名组件安全校验（[a-zA-Z0-9_.-]，长度 1-64，防路径逃逸；允许
    /// `.` 以支持版本号，`.` 不会形成路径段逃逸）。
    pub fn safeArtifactComponent(s: []const u8) bool {
        if (s.len == 0 or s.len > 64) return false;
        for (s) |c| {
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
            if (!ok) return false;
        }
        return true;
    }

    /// "Install" a marketplace package: register it in the module registry and
    /// optionally bind it to an account. Returns the module registry id.
    ///
    /// 产物两种形态：
    /// 1. **manifest（模块描述 + 迁移 SQL 包）**：JSON `{name,title,version,
    ///    description,entry,migrations:[SQL...]}` —— 安装时执行迁移 SQL 建表，
    ///    再按 manifest 元数据注册模块。
    /// 2. **旧数据/配置包**：非法 JSON 时回退为按 pkg 元数据注册（无迁移）。
    pub fn installPackage(self: *CloudService, tenant_id: i64, name: []const u8, account_id: i64) CloudError!i64 {
        if (std.mem.trim(u8, name, " \t").len == 0) return error.InvalidName;
        const pkg_opt = self.store.getPackageByName(tenant_id, name) catch return error.Unexpected;
        const pkg = pkg_opt orelse return error.NotFound;
        defer pkg.free(self.allocator);

        // 默认按 pkg 元数据注册（无产物 / 非 manifest 产物时）。
        var mod_name: []const u8 = pkg.name;
        var mod_title: []const u8 = pkg.title;
        var mod_version: []const u8 = pkg.version;
        var migrations: []const []const u8 = &.{};
        // manifest 所有权提升到函数级，确保 applyMigrations 时字符串仍存活
        // （if 块内的 defer 会在块尾过早释放）。
        var mf_owned: ?Manifest = null;
        defer if (mf_owned) |*m| m.free(self.allocator);

        if (pkg.download_url.len > 0) {
            // SSRF 基线：存量数据可能早于写入口校验，服务端拉取前再拦一次。
            if (!url_guard.isAcceptableOutboundUrl(pkg.download_url)) return error.InvalidUrl;
            const content = try self.downloadAndVerify(pkg.name, pkg.version, pkg.download_url, pkg.checksum);
            defer self.allocator.free(content);

            if (try parseManifest(self.allocator, content)) |mf| {
                mf_owned = mf;
                const m = &mf_owned.?;
                mod_name = m.name;
                mod_title = m.title;
                mod_version = m.version;
                migrations = m.migrations;
                // manifest 落盘为 .manifest.json。
                try self.storeArtifact(m.name, m.version, content);
            } else {
                // 旧数据包：落盘 .bin。
                try self.storeArtifact(pkg.name, pkg.version, content);
            }
        }

        // 执行迁移 SQL（建表等，幂等 IF NOT EXISTS）。
        if (migrations.len > 0) {
            try self.applyMigrations(migrations);
        }

        // 注册 manifest 声明的动态表元数据（运行时通用查询网关用）。
        if (mf_owned) |*m| {
            if (self.dyn_table_store) |dts| {
                for (m.tables) |*t| {
                    _ = dts.register(tenant_id, m.name, t.name, t.title, t.columns_json, self.now()) catch return error.Unexpected;
                }
            }
        }

        const module_id = self.module_svc.register(tenant_id, mod_name, mod_title, mod_version) catch return error.Unexpected;
        if (account_id > 0) {
            _ = self.module_svc.bind(tenant_id, account_id, mod_name, "active") catch return error.Unexpected;
        }
        return module_id;
    }

    /// 市场包 manifest（模块描述 + 迁移 SQL 包）。caller-owned 字符串。
    pub const Manifest = struct {
        name: []const u8,
        title: []const u8,
        version: []const u8,
        description: []const u8,
        entry: []const u8,
        migrations: []const []const u8,
        /// 声明的动态表（迁移建表后注册，运行时经通用查询网关访问）。
        tables: []const ManifestTable,

        pub fn free(self: *const Manifest, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.title.len > 0) allocator.free(self.title);
            if (self.version.len > 0) allocator.free(self.version);
            if (self.description.len > 0) allocator.free(self.description);
            if (self.entry.len > 0) allocator.free(self.entry);
            for (self.migrations) |m| allocator.free(m);
            if (self.migrations.len > 0) allocator.free(self.migrations);
            for (self.tables) |*t| t.free(allocator);
            if (self.tables.len > 0) allocator.free(self.tables);
        }
    };

    /// manifest 声明的动态表（columns_json = `[{name,title,type}]`）。
    pub const ManifestTable = struct {
        name: []const u8,
        title: []const u8,
        columns_json: []const u8,

        pub fn free(self: *const ManifestTable, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.title.len > 0) allocator.free(self.title);
            allocator.free(self.columns_json);
        }
    };

    /// 解析 manifest JSON。非法 JSON 或缺 name 时返回 null（调用方回退旧行为）。
    fn parseManifest(allocator: std.mem.Allocator, content: []const u8) CloudError!?Manifest {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
        defer parsed.deinit();
        const name = objString(parsed.value, "name") orelse return null;
        if (name.len == 0) return null;
        const title = objString(parsed.value, "title") orelse "";
        const version = objString(parsed.value, "version") orelse "1.0.0";
        const description = objString(parsed.value, "description") orelse "";
        const entry = objString(parsed.value, "entry") orelse name;

        var migrations = std.ArrayList([]const u8).empty;
        defer migrations.deinit(allocator);
        if (parsed.value.object.get("migrations")) |mig_v| {
            switch (mig_v) {
                .array => |arr| {
                    for (arr.items) |item| {
                        const sql = switch (item) {
                            .string => |s| s,
                            else => continue,
                        };
                        const dup = allocator.dupe(u8, sql) catch return error.Unexpected;
                        migrations.append(allocator, dup) catch {
                            allocator.free(dup);
                            return error.Unexpected;
                        };
                    }
                },
                else => {},
            }
        }

        // tables 声明：[{name,title,columns:[{name,title,type}]}]。
        var tables = std.ArrayList(ManifestTable).empty;
        defer {
            for (tables.items) |*t| t.free(allocator);
            tables.deinit(allocator);
        }
        if (parsed.value.object.get("tables")) |tbl_v| {
            switch (tbl_v) {
                .array => |arr| {
                    for (arr.items) |item| {
                        const t_name = objString(item, "name") orelse continue;
                        const t_title = objString(item, "title") orelse "";
                        // columns 序列化为 JSON（无 columns → "[]"）。
                        const cols_json = if (item.object.get("columns")) |cv|
                            std.json.Stringify.valueAlloc(allocator, cv, .{}) catch "[]"
                        else
                            allocator.dupe(u8, "[]") catch return error.Unexpected;
                        const name_c = allocator.dupe(u8, t_name) catch return error.Unexpected;
                        errdefer allocator.free(name_c);
                        const title_c = if (t_title.len > 0) allocator.dupe(u8, t_title) catch return error.Unexpected else "";
                        errdefer if (title_c.len > 0) allocator.free(title_c);
                        tables.append(allocator, .{ .name = name_c, .title = title_c, .columns_json = cols_json }) catch return error.Unexpected;
                    }
                },
                else => {},
            }
        }

        const name_dup = allocator.dupe(u8, name) catch return error.Unexpected;
        errdefer allocator.free(name_dup);
        const title_dup = if (title.len > 0) allocator.dupe(u8, title) catch return error.Unexpected else "";
        errdefer if (title_dup.len > 0) allocator.free(title_dup);
        const version_dup = allocator.dupe(u8, version) catch return error.Unexpected;
        errdefer allocator.free(version_dup);
        const desc_dup = if (description.len > 0) allocator.dupe(u8, description) catch return error.Unexpected else "";
        errdefer if (desc_dup.len > 0) allocator.free(desc_dup);
        const entry_dup = if (entry.len > 0) allocator.dupe(u8, entry) catch return error.Unexpected else "";
        errdefer if (entry_dup.len > 0) allocator.free(entry_dup);

        const mig_slice = if (migrations.items.len > 0) (migrations.toOwnedSlice(allocator) catch return error.Unexpected) else &.{};
        errdefer if (mig_slice.len > 0) {
            for (mig_slice) |m| allocator.free(m);
            allocator.free(mig_slice);
        };

        const tables_slice = if (tables.items.len > 0) (tables.toOwnedSlice(allocator) catch return error.Unexpected) else &.{};
        errdefer if (tables_slice.len > 0) {
            for (tables_slice) |*t| t.free(allocator);
            allocator.free(tables_slice);
        };

        return .{
            .name = name_dup,
            .title = title_dup,
            .version = version_dup,
            .description = desc_dup,
            .entry = entry_dup,
            .migrations = mig_slice,
            .tables = tables_slice,
        };
    }

    /// 执行迁移 SQL（顺序执行；失败即中止并返回 Unexpected）。
    /// 每条 SQL 先过沙箱白名单校验，非法语句拒绝执行。
    fn applyMigrations(self: *CloudService, migrations: []const []const u8) CloudError!void {
        const d = self.driver orelse return error.Unexpected;
        for (migrations) |sql| {
            if (!validateMigrationSql(sql)) return error.InvalidName;
            _ = d.exec(sql, &.{}) catch return error.Unexpected;
        }
    }

    /// 列出已注册的动态表元数据（caller free）。
    pub fn listDynamicTables(self: *CloudService, tenant_id: i64) CloudError![]persist.DynamicTableStore.DynamicTableRow {
        const dts = self.dyn_table_store orelse return error.Unexpected;
        return dts.list(tenant_id) catch error.Unexpected;
    }

    /// 通用查询网关结果：动态表查询的行数据（列名 + 每行字符串值）。
    pub const DynamicRows = struct {
        columns: []const []const u8,
        cells: []const []const u8, // 行优先：rows[row][col]
        column_count: usize,
        row_count: usize,

        pub fn free(self: *const DynamicRows, allocator: std.mem.Allocator) void {
            for (self.columns) |c| allocator.free(c);
            if (self.columns.len > 0) allocator.free(self.columns);
            for (self.cells) |c| allocator.free(c);
            if (self.cells.len > 0) allocator.free(self.cells);
        }
    };

    /// 通用查询网关：查询动态表（白名单表名 + 分页）。表名必须已注册且仅
    /// [a-zA-Z0-9_.-]（防注入）；分页参数为整数（无注入面）。
    pub fn queryDynamicTable(self: *CloudService, allocator: std.mem.Allocator, tenant_id: i64, table_name: []const u8, page: usize, page_size: usize) CloudError!DynamicRows {
        const dts = self.dyn_table_store orelse return error.Unexpected;
        if (!safeArtifactComponent(table_name)) return error.InvalidName;
        const meta = (dts.getByTable(tenant_id, table_name) catch return error.Unexpected) orelse return error.NotFound;
        defer meta.free(self.allocator);
        const d = self.driver orelse return error.Unexpected;

        const offset = (page - 1) * page_size;

        // 列名主来源：表元数据 columns_json（空表也能拿到列 + 与值对齐）。
        var col_list = std.ArrayList([]const u8).empty;
        defer {
            for (col_list.items) |c| allocator.free(c);
            col_list.deinit(allocator);
        }
        if (std.json.parseFromSlice(std.json.Value, allocator, meta.columns_json, .{})) |parsed| {
            defer parsed.deinit();
            switch (parsed.value) {
                .array => |arr| {
                    for (arr.items) |col| {
                        if (objString(col, "name")) |n| {
                            const cname = allocator.dupe(u8, n) catch return error.Unexpected;
                            col_list.append(allocator, cname) catch return error.Unexpected;
                        }
                    }
                },
                else => {},
            }
        } else |_| {}

        // 按声明列投影（列名白名单，防注入 + 值与列名对齐）；无声明列回退 SELECT *。
        const sql = if (col_list.items.len > 0) blk: {
            var proj = std.ArrayList(u8).empty;
            defer proj.deinit(allocator);
            for (col_list.items, 0..) |c, i| {
                if (i > 0) proj.appendSlice(allocator, ",") catch return error.Unexpected;
                proj.appendSlice(allocator, "\"") catch return error.Unexpected;
                proj.appendSlice(allocator, c) catch return error.Unexpected;
                proj.appendSlice(allocator, "\"") catch return error.Unexpected;
            }
            break :blk std.fmt.allocPrint(allocator, "SELECT {s} FROM \"{s}\" LIMIT {d} OFFSET {d}", .{ proj.items, table_name, page_size, offset }) catch return error.Unexpected;
        } else std.fmt.allocPrint(allocator, "SELECT * FROM \"{s}\" LIMIT {d} OFFSET {d}", .{ table_name, page_size, offset }) catch return error.Unexpected;
        defer allocator.free(sql);

        var rows = d.query(sql, &.{}) catch return error.Unexpected;
        defer rows.deinit();

        var cell_list = std.ArrayList([]const u8).empty;
        defer {
            for (cell_list.items) |c| allocator.free(c);
            cell_list.deinit(allocator);
        }

        var ncols: usize = col_list.items.len;
        var row_count: usize = 0;
        while (rows.next()) |row| {
            row_count += 1;
            // 无元数据列名时回退到 row 的列名。
            if (ncols == 0) {
                ncols = row.columnCount();
                var i: usize = 0;
                while (i < ncols) : (i += 1) {
                    const cname = allocator.dupe(u8, row.columnName(i)) catch return error.Unexpected;
                    col_list.append(allocator, cname) catch return error.Unexpected;
                }
            }
            var i: usize = 0;
            while (i < ncols) : (i += 1) {
                const val = cellString(allocator, row, i) catch return error.Unexpected;
                cell_list.append(allocator, val) catch {
                    allocator.free(val);
                    return error.Unexpected;
                };
            }
        }

        const cols_slice = if (col_list.items.len > 0) (col_list.toOwnedSlice(allocator) catch return error.Unexpected) else &.{};
        errdefer if (cols_slice.len > 0) {
            for (cols_slice) |c| allocator.free(c);
            allocator.free(cols_slice);
        };
        const cells_slice = if (cell_list.items.len > 0) (cell_list.toOwnedSlice(allocator) catch return error.Unexpected) else &.{};
        errdefer if (cells_slice.len > 0) {
            for (cells_slice) |c| allocator.free(c);
            allocator.free(cells_slice);
        };

        return .{ .columns = cols_slice, .cells = cells_slice, .column_count = ncols, .row_count = row_count };
    }

    /// 迁移 SQL 沙箱：仅允许白名单 DDL（建表/建索引/改表），拒绝多语句、
    /// 危险关键字（DROP/DELETE/INSERT/UPDATE/PRAGMA/ATTACH/GRANT 等）、超长。
    /// 纯函数（可单测）。
    pub fn validateMigrationSql(sql: []const u8) bool {
        const trimmed = std.mem.trim(u8, sql, " \t\r\n");
        if (trimmed.len == 0 or trimmed.len > 4096) return false;
        // 单语句：只允许至多一个语句（分号只能在末尾）。
        if (std.mem.indexOfScalar(u8, trimmed, ';')) |semi| {
            const rest = std.mem.trim(u8, trimmed[semi + 1 ..], " \t\r\n");
            if (rest.len != 0) return false; // 分号后还有内容 → 多语句
        }
        var upper_buf: [4096]u8 = undefined;
        const upper = std.ascii.upperString(&upper_buf, trimmed);
        // 白名单前缀。
        const allowed = std.mem.startsWith(u8, upper, "CREATE TABLE") or
            std.mem.startsWith(u8, upper, "CREATE INDEX") or
            std.mem.startsWith(u8, upper, "CREATE UNIQUE INDEX") or
            std.mem.startsWith(u8, upper, "ALTER TABLE");
        if (!allowed) return false;
        // 危险关键字拒绝（大小写不敏感子串匹配）。
        const dangerous = [_][]const u8{
            "DROP",   "DELETE", "INSERT", "UPDATE", "GRANT",    "REVOKE",
            "PRAGMA", "ATTACH", "DETACH", "VACUUM", "TRUNCATE", "SELECT",
        };
        for (dangerous) |kw| {
            if (std.mem.indexOf(u8, upper, kw) != null) return false;
        }
        return true;
    }

    /// 下载产物并校验 sha256。返回 caller-owned 内容。
    /// 注意：这是 zwechat 同步 client 的阻塞调用，handler 路径必须走
    /// `installPackageRemote`（投递远端 worker 执行），不要直接调本函数。
    fn downloadAndVerify(self: *CloudService, name: []const u8, version: []const u8, url: []const u8, expected_hex: []const u8) CloudError![]u8 {
        _ = name;
        _ = version;
        var client = self.newRemoteClient();
        defer client.deinit();
        const body = client.get(url) catch return error.DownloadFailed;
        defer self.allocator.free(body);
        if (!verifyChecksum(body, expected_hex)) return error.ChecksumMismatch;
        return self.allocator.dupe(u8, body) catch error.Unexpected;
    }

    /// 把产物落盘到 `uploads/market/{name}-{version}.bin`。
    /// name/version 仅允许 [a-zA-Z0-9_-]（防路径逃逸）。
    fn storeArtifact(self: *CloudService, name: []const u8, version: []const u8, content: []const u8) CloudError!void {
        if (!safeArtifactComponent(name) or !safeArtifactComponent(version)) return error.InvalidName;
        var dir = std.Io.Dir.cwd();
        dir.createDir(self.io, "uploads/market", .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return error.Unexpected,
        };
        const path = std.fmt.allocPrint(self.allocator, "uploads/market/{s}-{s}.bin", .{ name, version }) catch return error.Unexpected;
        defer self.allocator.free(path);
        var file = std.Io.Dir.cwd().createFile(self.io, path, .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => return, // 幂等：产物已存在视为已安装过
            else => return error.Unexpected,
        };
        defer file.close(self.io);
        file.writePositionalAll(self.io, content, 0) catch return error.Unexpected;
    }

    // ── 远端云服务（zweq-cloud）对接 ──────────────────────────────────────

    fn newRemoteClient(self: *CloudService) zwechat.util.http.HttpClient {
        var c = zwechat.util.http.HttpClient.init(self.allocator);
        if (self.http_transport) |t| c.setTransport(t, self.http_transport_ctx);
        return c;
    }

    /// 用远端 zweq-cloud 校验授权码（POST `{base}/cloud/licenses/verify`）。
    /// 返回 true = 有效；无效/过期映射为 InvalidLicense / LicenseExpired。
    /// 低频管理面可保持同步：后台手动校验是低频操作；zwechat client 同步
    /// 阻塞且不支持 per-request 超时配置。周期校验 checkSiteLicense 跑在
    /// 主循环线程，不占 io 线程。
    pub fn verifyLicenseRemote(self: *CloudService, allocator: std.mem.Allocator, license_key: []const u8) CloudError!bool {
        const url = std.fmt.allocPrint(allocator, "{s}/cloud/licenses/verify", .{self.remote_base_url}) catch return error.Unexpected;
        defer allocator.free(url);
        const body = std.fmt.allocPrint(allocator, "{{\"key\":\"{s}\"}}", .{license_key}) catch return error.Unexpected;
        defer allocator.free(body);

        var client = self.newRemoteClient();
        defer client.deinit();
        const resp = client.postJSON(url, body) catch return error.RemoteUnavailable;
        defer allocator.free(resp);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, resp, .{}) catch return error.RemoteUnavailable;
        defer parsed.deinit();
        const data = objField(parsed.value, "data") orelse return error.RemoteUnavailable;
        const valid = objBool(data, "valid") orelse false;
        if (!valid) {
            const reason = objString(data, "reason") orelse "";
            if (std.mem.eql(u8, reason, "expired")) return error.LicenseExpired;
            return error.InvalidLicense;
        }
        return true;
    }

    /// 从远端 zweq-cloud 同步市场包列表到本地（GET `{base}/cloud/market`）。
    /// 每个包的 download_url 指向云端产物下载接口，checksum 沿用云端值。
    /// 返回同步的包数量。
    pub fn syncMarketRemote(self: *CloudService, allocator: std.mem.Allocator, tenant_id: i64) CloudError!usize {
        const url = std.fmt.allocPrint(allocator, "{s}/cloud/market", .{self.remote_base_url}) catch return error.Unexpected;
        defer allocator.free(url);

        var client = self.newRemoteClient();
        defer client.deinit();
        const resp = client.get(url) catch return error.RemoteUnavailable;
        defer allocator.free(resp);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, resp, .{}) catch return error.RemoteUnavailable;
        defer parsed.deinit();
        const data = objField(parsed.value, "data") orelse return error.RemoteUnavailable;
        const list = objField(data, "list") orelse return error.RemoteUnavailable;
        const items = list.array.items;

        var count: usize = 0;
        for (items) |item| {
            const name = objString(item, "name") orelse continue;
            const title = objString(item, "title") orelse "";
            const version = objString(item, "version") orelse "";
            const description = objString(item, "description") orelse "";
            const checksum = objString(item, "checksum") orelse "";
            if (!safeArtifactComponent(name) or !safeArtifactComponent(version)) continue;

            const dl = std.fmt.allocPrint(allocator, "{s}/cloud/market/{s}/download", .{ self.remote_base_url, name }) catch continue;
            defer allocator.free(dl);
            _ = self.store.upsertPackage(tenant_id, name, title, version, description, dl, checksum, self.now()) catch continue;
            count += 1;
        }
        return count;
    }

    /// installPackageRemote 的等待上限（毫秒）。前端安装流程要求同步拿到
    /// module_id，这是该同步语义下的独立超时——zwechat client 自身无任何
    /// 超时配置，超时只能靠等待侧限出来。
    pub const install_remote_wait_ms: i64 = 60_000;

    /// 市场同步投递后台 worker 异步执行（202 语义）：立即返回，结果经
    /// 市场列表可见。失败只记日志（同步入口由 admin 重试）。
    pub fn syncMarketRemoteAsync(self: *CloudService, tenant_id: i64) CloudError!void {
        const job = try self.newRemoteJob(.sync_market, tenant_id, "", 0);
        self.enqueueRemote(job) catch {
            self.freeRemoteJob(job);
            return error.Unexpected;
        };
    }

    /// 安装（含远端产物下载）投递 worker 执行，handler 限时等待结果。
    /// 前端安装流程要求同步返回 module_id，不能纯异步；阻塞下载在 worker
    /// 线程上跑（不占 io 线程），handler 只 park 在条件变量上。
    /// 取舍：等待超时返回 error.RemoteTimeout 后，worker 里的安装仍会在
    /// 后台跑完（模块可能随后注册成功），调用方应提示用户稍后在市场列表确认。
    pub fn installPackageRemote(self: *CloudService, tenant_id: i64, name: []const u8, account_id: i64, wait_ms: i64) CloudError!i64 {
        const job = try self.newRemoteJob(.install, tenant_id, name, account_id);
        self.enqueueRemote(job) catch {
            self.freeRemoteJob(job);
            return error.Unexpected;
        };
        const io = self.io;
        self.worker.mutex.lock(io) catch {
            // fiber 被取消：job 标记为无主，由 worker 收尾释放。
            self.abandonRemoteJob(job);
            return error.Unexpected;
        };
        while (!job.done) {
            self.worker.cond.waitTimeout(io, &self.worker.mutex, awakeTimeoutMs(wait_ms)) catch |err| switch (err) {
                error.Timeout => {
                    self.worker.mutex.unlock(io);
                    self.abandonRemoteJob(job);
                    return error.RemoteTimeout;
                },
                error.Canceled => {
                    self.worker.mutex.unlock(io);
                    self.abandonRemoteJob(job);
                    return error.Unexpected;
                },
            };
        }
        // done 由 worker 在持锁下置位：结果读尽后即可释放等待权与 job。
        job.has_waiter = false;
        self.worker.mutex.unlock(io);
        if (job.err) |e| {
            self.freeRemoteJob(job);
            return e;
        }
        const module_id = job.module_id;
        self.freeRemoteJob(job);
        return module_id;
    }

    fn newRemoteJob(self: *CloudService, kind: RemoteJobKind, tenant_id: i64, name: []const u8, account_id: i64) CloudError!*RemoteJob {
        const job = self.allocator.create(RemoteJob) catch return error.Unexpected;
        errdefer self.allocator.destroy(job);
        job.* = .{
            .kind = kind,
            .tenant_id = tenant_id,
            .account_id = account_id,
            .has_waiter = kind == .install,
        };
        if (name.len > 0) {
            job.name = self.allocator.dupe(u8, name) catch return error.Unexpected;
        }
        return job;
    }

    fn freeRemoteJob(self: *CloudService, job: *RemoteJob) void {
        if (job.name.len > 0) self.allocator.free(job.name);
        self.allocator.destroy(job);
    }

    /// 等待方（限时等待的 handler fiber）放弃 job：锁内清掉 has_waiter，
    /// worker 看到 false 时负责释放；若 worker 已先完成，则由等待方释放。
    fn abandonRemoteJob(self: *CloudService, job: *RemoteJob) void {
        const io = self.io;
        self.worker.mutex.lockUncancelable(io);
        job.has_waiter = false;
        const done = job.done;
        self.worker.mutex.unlock(io);
        if (done) self.freeRemoteJob(job);
    }

    fn enqueueRemote(self: *CloudService, job: *RemoteJob) CloudError!void {
        if (!self.ensureRemoteWorker()) return error.Unexpected;
        const io = self.io;
        self.worker.mutex.lockUncancelable(io);
        defer self.worker.mutex.unlock(io);
        self.worker.queue.append(self.allocator, job) catch return error.Unexpected;
        self.worker.cond.signal(io);
    }

    /// 懒启动远端 worker（首次投递时 spawn）；失败返回 false。
    fn ensureRemoteWorker(self: *CloudService) bool {
        const io = self.io;
        self.worker.mutex.lockUncancelable(io);
        defer self.worker.mutex.unlock(io);
        if (self.worker.started) return true;
        const t = std.Thread.spawn(.{}, remoteWorkerMain, .{self}) catch {
            std.log.err("[cloud] 远端任务 worker 启动失败，远端调用无法异步化", .{});
            return false;
        };
        self.worker.thread = t;
        self.worker.started = true;
        return true;
    }

    /// 停止远端 worker 并释放队列残留。仅测试/短生命周期调用；main 中
    /// 进程级存活依赖进程退出回收。
    fn stopRemoteWorker(self: *CloudService) void {
        if (!self.worker.started) return;
        const io = self.io;
        self.worker.mutex.lockUncancelable(io);
        self.worker.stopping = true;
        self.worker.cond.signal(io);
        self.worker.mutex.unlock(io);
        if (self.worker.thread) |t| t.join();
        self.worker.thread = null;
        for (self.worker.queue.items) |job| self.freeRemoteJob(job);
        self.worker.queue.deinit(self.allocator);
        self.worker.queue = .empty;
        self.worker.started = false;
    }

    /// 远端 worker 主循环（专用线程）：从队列取任务执行。zwechat client
    /// 同步阻塞，在这里跑不占 io 线程。
    fn remoteWorkerMain(self: *CloudService) void {
        const io = self.io;
        std.log.info("[cloud] remote worker started", .{});
        while (true) {
            self.worker.mutex.lockUncancelable(io);
            while (self.worker.queue.items.len == 0 and !self.worker.stopping) {
                // 500ms 兜底唤醒保证 stop 及时性；push/stop 都会 signal。
                self.worker.cond.waitTimeout(io, &self.worker.mutex, awakeTimeoutMs(500)) catch {};
            }
            if (self.worker.stopping and self.worker.queue.items.len == 0) {
                self.worker.mutex.unlock(io);
                std.log.info("[cloud] remote worker stopped", .{});
                return;
            }
            const job = self.worker.queue.orderedRemove(0);
            self.worker.mutex.unlock(io);

            switch (job.kind) {
                .sync_market => {
                    if (self.syncMarketRemote(self.allocator, job.tenant_id)) |count| {
                        std.log.info("[cloud] 后台市场同步完成 tenant={d} 共 {d} 个包", .{ job.tenant_id, count });
                    } else |err| {
                        std.log.err("[cloud] 后台市场同步失败 tenant={d}: {s}", .{ job.tenant_id, @errorName(err) });
                    }
                    self.freeRemoteJob(job);
                },
                .install => {
                    const res = self.installPackage(job.tenant_id, job.name, job.account_id);
                    if (res) |id| {
                        self.worker.mutex.lockUncancelable(io);
                        job.module_id = id;
                    } else |e| {
                        // 等待方可能已超时离开，错误不会有人看见——必须留痕。
                        std.log.err("[cloud] 后台安装失败 tenant={d} pkg={s}: {s}", .{ job.tenant_id, job.name, @errorName(e) });
                        self.worker.mutex.lockUncancelable(io);
                        job.err = e;
                    }
                    job.done = true;
                    if (job.has_waiter) {
                        self.worker.cond.signal(io);
                        self.worker.mutex.unlock(io);
                    } else {
                        // 等待方已超时/取消离开：由 worker 释放 job。
                        self.worker.mutex.unlock(io);
                        self.freeRemoteJob(job);
                    }
                },
            }
        }
    }
};

/// 把毫秒数包成 `std.Io.Timeout`（awake 时钟，与 zigmodu runtime 一致）。
fn awakeTimeoutMs(ms: i64) std.Io.Timeout {
    return .{ .duration = .{ .raw = std.Io.Duration.fromMilliseconds(ms), .clock = .awake } };
}

/// 远端任务种类。
const RemoteJobKind = enum { sync_market, install };

/// 投递到远端 worker 的一个任务。输入字符串归本 job 所有（service 分配器）。
/// 释放责任：has_waiter=true（install 限时等待）由等待方释放；否则由 worker
/// 释放。超时/取消的等待方在锁内清掉 has_waiter 后离开。
const RemoteJob = struct {
    kind: RemoteJobKind,
    tenant_id: i64,
    account_id: i64 = 0,
    /// install：包名（service 分配器持有）。
    name: []u8 = &.{},
    /// 是否仍有等待方（install 同步等待）。
    has_waiter: bool = false,
    done: bool = false,
    module_id: i64 = 0,
    err: ?CloudError = null,
};

/// 远端云服务后台 worker（单线程内存任务队列）。
const RemoteWorker = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    queue: std.ArrayList(*RemoteJob) = .empty,
    started: bool = false,
    stopping: bool = false,
    thread: ?std.Thread = null,
};

fn objField(v: std.json.Value, key: []const u8) ?std.json.Value {
    return v.object.get(key);
}

fn objString(v: std.json.Value, key: []const u8) ?[]const u8 {
    const field = v.object.get(key) orelse return null;
    return switch (field) {
        .string => |s| s,
        else => null,
    };
}

fn objBool(v: std.json.Value, key: []const u8) ?bool {
    const field = v.object.get(key) orelse return null;
    return switch (field) {
        .bool => |b| b,
        else => null,
    };
}

/// 把数据库行的一列转成字符串（统一 dupe，caller free）。空值 → 空串。
fn cellString(allocator: std.mem.Allocator, row: zent.sql_driver.Row, idx: usize) ![]const u8 {
    if (row.isNull(idx)) return allocator.dupe(u8, "");
    if (row.getText(idx)) |t| return allocator.dupe(u8, t);
    if (row.getInt(idx)) |v| return std.fmt.allocPrint(allocator, "{d}", .{v});
    if (row.getFloat(idx)) |f| return std.fmt.allocPrint(allocator, "{d}", .{f});
    if (row.getBool(idx)) |b| return allocator.dupe(u8, if (b) "true" else "false");
    return allocator.dupe(u8, "");
}
