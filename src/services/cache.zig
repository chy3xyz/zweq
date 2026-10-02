//! Cache service — thread-safe wrapper over zigmodu's LRU CacheManager.
//!
//! Values are arbitrary bytes (JSON strings work well). Keys are
//! namespaced by the caller, e.g. `user:42`, `kv:<key>`. The underlying
//! CacheManager is single-threaded (see zigmodu src/cache/CacheManager.zig),
//! while the HTTP server runs many handler fibers concurrently — every
//! manager access is serialized through `mutex`, and `getOrSet` runs its
//! loader callback outside the lock.

const std = @import("std");
const zigmodu = @import("zigmodu");

pub const CacheService = struct {
    allocator: std.mem.Allocator,
    manager: zigmodu.data.CacheManager,
    mutex: std.Io.Mutex,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, max_entries: usize, ttl_seconds: u64) CacheService {
        return .{
            .allocator = allocator,
            .manager = zigmodu.data.CacheManager.init(allocator, max_entries, ttl_seconds, .LRU),
            .mutex = std.Io.Mutex.init,
            .io = io,
        };
    }

    pub fn deinit(self: *CacheService) void {
        // 与框架 cache/Lru.zig 的 deinit 同策略：析构必须跑完，等锁期间
        // 临界区都是 O(1) map 操作，等待有界。注意 unlock 必须在
        // self.* = undefined 之前显式调用（defer 会在 undefined 之后才执行）。
        self.mutex.lockUncancelable(self.io);
        self.manager.deinit();
        self.mutex.unlock(self.io);
        self.* = undefined;
    }

    pub fn set(self: *CacheService, key: []const u8, value: []const u8) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.manager.set(key, value);
    }

    /// Returns a cache-owned slice (do not free, do not keep across writes).
    pub fn get(self: *CacheService, key: []const u8) ?[]const u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.manager.get(key);
    }

    /// Read-through: return the cached value or run `loader`, store the
    /// result and return it. The loader is an I/O callback, so it runs
    /// outside the lock; the lock only serializes map reads/writes.
    pub fn getOrSet(self: *CacheService, key: []const u8, loader: *const fn (allocator: std.mem.Allocator) anyerror![]const u8) ![]const u8 {
        if (self.get(key)) |v| return v;
        const fresh = try loader(self.allocator);
        // best-effort 缓存写入：`set` 只可能因淘汰/分配失败而报错,失败只是这次
        // 没缓存住,本次返回值仍然正确(调用方拿到的是 loader 的结果)。
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.manager.set(key, fresh) catch {};
        return fresh;
    }

    /// 锁内先查后写，check-then-act 原子化：返回 true 表示本调用完成了
    /// 首次写入，false 表示键已存在（nonce 去重等重放防线用它防并发穿透）。
    pub fn setIfAbsent(self: *CacheService, key: []const u8, value: []const u8) !bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.manager.get(key) != null) return false;
        try self.manager.set(key, value);
        return true;
    }

    pub fn remove(self: *CacheService, key: []const u8) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.manager.remove(key);
    }

    pub fn count(self: *CacheService) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.manager.count();
    }
};
