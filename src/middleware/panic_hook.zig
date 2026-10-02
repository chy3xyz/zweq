//! 请求上下文感知的 panic 钩子 —— 复刻 zigmodu `api/PanicHook.zig` 的语义
//! （见该文件头注释：panic 前把当事请求 METHOD /path 打到 stderr，再交回
//! `std.debug.defaultPanic` 打出正常消息与栈；进程级恢复仍靠 supervisor）。
//!
//! 不直接用 `pub const panic = zmodu.panicHook;` 的原因：上游 PanicHook.zig
//! 的 writeStderr 调了 `std.posix.write`，而 0.17.0-dev 标准库（1567 /
//! 1970 / 2151 均实测）已无该 API；lazy analysis 使其在上游自己的构建里
//! 从未被实例化，应用根一接线即编译错。这里用本文件私有 threadlocal 槽 +
//! `std.posix.system.write` 复刻同一行为，并附记录请求的 middleware
//! （zigmodu Server 私有自己的槽且不暴露读取口，故自行记录一份）。

const std = @import("std");
const zigmodu = @import("zigmodu");
const http = zigmodu.http;

const BUF_SIZE = 512;

threadlocal var request_buf: [BUF_SIZE]u8 = undefined;
threadlocal var request_len: usize = 0;

/// 记录当前线程正在派发的请求。panic 时据此归因；请求结束必须
/// `clearRequestContext`，复用线程不能把后来的崩溃算到早先请求头上。
pub fn setRequestContext(method: []const u8, path: []const u8) void {
    var len: usize = 0;
    const m = method[0..@min(method.len, 16)];
    @memcpy(request_buf[len..][0..m.len], m);
    len += m.len;
    request_buf[len] = ' ';
    len += 1;
    const room = BUF_SIZE - len;
    const p = path[0..@min(path.len, room)];
    @memcpy(request_buf[len..][0..p.len], p);
    len += p.len;
    request_len = len;
}

pub fn clearRequestContext() void {
    request_len = 0;
}

fn panicWithRequestContext(msg: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);
    if (request_len > 0) {
        const prefix = "panic while handling request: ";
        var out: [prefix.len + BUF_SIZE + 1]u8 = undefined;
        @memcpy(out[0..prefix.len], prefix);
        @memcpy(out[prefix.len..][0..request_len], request_buf[0..request_len]);
        out[prefix.len + request_len] = '\n';
        writeStderr(out[0 .. prefix.len + request_len + 1]);
    }
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn writeStderr(bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const n = std.posix.system.write(std.posix.STDERR_FILENO, rest.ptr, rest.len);
        if (n <= 0) return;
        rest = rest[@intCast(n)..];
    }
}

/// 应用根接线：`pub const panic = panic_hook.hook;`
pub const hook = std.debug.FullPanic(panicWithRequestContext);

/// 把 METHOD /path 记入本文件 threadlocal 的 middleware，挂在全局链最前。
pub fn recordRequestContext() http.Middleware {
    return .{
        .func = struct {
            fn handle(ctx: *http.Context, next: http.HandlerFn, _: ?*anyopaque) anyerror!void {
                setRequestContext(ctx.method.toString(), ctx.path);
                defer clearRequestContext();
                try next(ctx);
            }
        }.handle,
    };
}
