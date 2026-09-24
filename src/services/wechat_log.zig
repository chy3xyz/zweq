//! 微信接口失败的诊断落点。
//!
//! 背景：zwechat 的公开方法在 `errcode != 0` 时只返回粗粒度的
//! `WechatError.ApiError` —— `errcode`（40001 token 失效 / 45009 超频 / 40003 openid
//! 非法 / 48001 未授权 …）在 API 边界就被丢掉了，我们此前只能看到"微信接口调用失败"，
//! 线上排障无从下手。
//!
//! v0.4.5 起 `lastErrorDetail()` 把 `errcode`/`errmsg`/`api_name` 记在线程局部零分配
//! 缓冲里，供 catch 分支读取。**必须在失败点立刻读**：缓冲只保留"本线程最近一次失败"，
//! 且成功的调用不会自动清空（这是刻意的——token 失效重试成功后仍能查到首次 40001 的原因）。
//!
//! 用法（服务层，紧跟失败的 zwechat 调用）：
//!
//!     const resp = client.get(uri) catch |err| {
//!         wechat_log.logApiError("menu.fetchMenu");
//!         return err;
//!     };

const std = @import("std");
const zwechat = @import("zwechat");

const util_error = zwechat.util.error_mod;

/// 在**调用微信接口之前**调用：清掉本线程上一次失败的详情槽。
///
/// 为什么必须有这一步：`lastErrorDetail()` 只告诉你"本线程最近一次失败"，而成功的
/// 调用**不会**清空槽位（上游刻意如此，便于 token 强刷重试后仍能查到首次 40001）。
/// 于是不加这一步就直接在 catch 里读，可能把**上一次调用的 errcode 挂到当前 label 上**
/// ——错误比没有日志更糟。上游文档给出的这个用法就是为这种场景准备的。
pub fn beginCall() void {
    util_error.clearErrorDetail();
}

/// 记录一次微信接口失败：有详情就打 errcode/errmsg/api_name，没有就说明"无详情"
/// （网络失败、解码失败这类本来就没有 errcode）。级别用 warn——外部依赖出错不该
/// 按 err 处理（仓库里 `log.err` 的语义是"服务端自身故障"）。
///
/// 调用点要求：本次调用前已 `beginCall()`，否则可能打印上一次失败的陈旧详情。
pub fn logApiError(label: []const u8) void {
    const detail = util_error.lastErrorDetail() orelse {
        std.log.warn("[wechat] {s} 失败（无 errcode 详情：传输/解码类错误，或该接口未写详情通道）", .{label});
        return;
    };
    std.log.warn("[wechat] {s} 失败 api={s} errcode={d} errmsg={s}", .{
        label,
        detail.api_name,
        detail.errcode,
        detail.errmsg,
    });
}

/// 记录我们自己解析出来的 errcode（不走 zwechat 详情通道的那些路径）。
///
/// 适用场景：调用方自己 `parseFromSlice` 后判 `errcode != 0`——此时 errcode/errmsg
/// **就在手边**，无需（也不该）去读线程局部槽位（那些路径上游压根不写槽）。
pub fn logErrcode(label: []const u8, errcode: i64, errmsg: []const u8) void {
    std.log.warn("[wechat] {s} 失败 errcode={d} errmsg={s}", .{ label, errcode, errmsg });
}

/// 取最近一次失败的 errcode（无详情返回 null）。给需要按错误码分支的调用方用。
pub fn lastErrcode() ?i64 {
    const detail = util_error.lastErrorDetail() orelse return null;
    return detail.errcode;
}
