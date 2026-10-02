//! Background task handlers registered with the task Dispatcher.

const std = @import("std");
const mail = @import("services/mail.zig");
const task_svc = @import("modules/task/service.zig");
const wt = @import("http/webhook_transport.zig");

/// `mail.send` — payload is JSON: {"to": "...", "subject": "...", "text": "..."}.
/// 返回 error 时 Dispatcher 会走 markFailedOrRetry 重试链路,不再静默丢信。
pub fn mailSend(ctx: ?*anyopaque, allocator: std.mem.Allocator, io: std.Io, payload: []const u8) anyerror!void {
    _ = io;
    const mailer: *mail.Mailer = @ptrCast(@alignCast(ctx orelse {
        std.log.err("[jobs] mail.send 缺少 handler 上下文(ctx=null),无法投递", .{});
        return error.NoHandlerCtx;
    }));
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch |err| {
        std.log.err("[jobs] mail.send payload 解析失败: {s}; payload 前 128 字节=\"{s}\"", .{ @errorName(err), payload[0..@min(payload.len, 128)] });
        return error.BadPayload;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        std.log.err("[jobs] mail.send payload 不是 JSON 对象(type={s}); 前 128 字节=\"{s}\"", .{ @tagName(std.meta.activeTag(parsed.value)), payload[0..@min(payload.len, 128)] });
        return error.BadPayload;
    }
    const obj = parsed.value.object;
    const to = obj.get("to") orelse {
        std.log.err("[jobs] mail.send payload 缺少 \"to\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    const subject = obj.get("subject") orelse {
        std.log.err("[jobs] mail.send payload 缺少 \"subject\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    const text = obj.get("text") orelse {
        std.log.err("[jobs] mail.send payload 缺少 \"text\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    // 三个字段必须是字符串:直接访问 .string 遇到数字/对象会 panic,
    // 把整个 dispatcher 线程打死(单 worker,等于队列停摆)。
    if (to != .string or subject != .string or text != .string) {
        std.log.err("[jobs] mail.send 字段类型错误(to={s}, subject={s}, text={s}),要求均为字符串", .{
            @tagName(std.meta.activeTag(to)),
            @tagName(std.meta.activeTag(subject)),
            @tagName(std.meta.activeTag(text)),
        });
        return error.BadFieldType;
    }
    // send 保持 void 签名(测试/console 调用方依赖),投递失败通过
    // send_failed 标志上报;先清残留再发送,失败后抛错触发任务重试。
    _ = mailer.takeSendFailed();
    mailer.send(.{
        .to = to.string,
        .subject = subject.string,
        .text = text.string,
    });
    if (mailer.takeSendFailed()) {
        std.log.err("[jobs] mail.send SMTP 投递失败(to={s} subject=\"{s}\"),上报任务失败以触发重试", .{ to.string, subject.string });
        return error.SmtpDeliveryFailed;
    }
}

/// `webhook.deliver` — payload is JSON: {"endpoint": "...", "event": "...", "payload": "..."}.
/// 重试语义（队列 markFailedOrRetry 对任何 error 都会重试，故按状态码分流）：
/// 2xx → 成功收尾；5xx/网络错误 → 返回 error 触发退避重试；
/// 4xx → 对端明确拒绝（地址/验签/报文错误），重试必然同样失败，
/// 记日志后按成功收尾，任务终态不再重试。
/// 失败路径一律 warn 而非 err：经 Dispatcher 跑的 5xx/网络错误会由
/// runTask 再以 err 记一次（双 err 刷屏）；且单测直接调 handler 时
/// err 级日志会让 zig test runner 把用例判败。
pub fn webhookDeliver(ctx: ?*anyopaque, allocator: std.mem.Allocator, io: std.Io, payload: []const u8) anyerror!void {
    _ = io;
    const transport: *wt.WebhookTransport = @ptrCast(@alignCast(ctx orelse {
        std.log.err("[jobs] webhook.deliver 缺少 handler 上下文(ctx=null),无法投递", .{});
        return error.NoHandlerCtx;
    }));
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch |err| {
        std.log.warn("[jobs] webhook.deliver payload 解析失败: {s}; payload 前 128 字节=\"{s}\"", .{ @errorName(err), payload[0..@min(payload.len, 128)] });
        return error.BadPayload;
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        std.log.warn("[jobs] webhook.deliver payload 不是 JSON 对象(type={s}); 前 128 字节=\"{s}\"", .{ @tagName(std.meta.activeTag(parsed.value)), payload[0..@min(payload.len, 128)] });
        return error.BadPayload;
    }
    const obj = parsed.value.object;
    const endpoint = obj.get("endpoint") orelse {
        std.log.warn("[jobs] webhook.deliver payload 缺少 \"endpoint\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    const event = obj.get("event") orelse {
        std.log.warn("[jobs] webhook.deliver payload 缺少 \"event\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    const body = obj.get("payload") orelse {
        std.log.warn("[jobs] webhook.deliver payload 缺少 \"payload\" 字段; 前 128 字节=\"{s}\"", .{payload[0..@min(payload.len, 128)]});
        return error.MissingField;
    };
    // 三个字段必须是字符串:直接访问 .string 遇到数字/对象会 panic,
    // 把整个 dispatcher 线程打死(单 worker,等于队列停摆)。
    if (endpoint != .string or event != .string or body != .string) {
        std.log.warn("[jobs] webhook.deliver 字段类型错误(endpoint={s}, event={s}, payload={s}),要求均为字符串", .{
            @tagName(std.meta.activeTag(endpoint)),
            @tagName(std.meta.activeTag(event)),
            @tagName(std.meta.activeTag(body)),
        });
        return error.BadFieldType;
    }
    const status = transport.post(endpoint.string, body.string) catch |err| {
        // 网络错误（DNS/连接拒绝/超时）：对端不可达通常是暂时的，返回
        // error 走 markFailedOrRetry 退避重试（err 级日志由 runTask 记）。
        std.log.warn("[jobs] webhook.deliver 传输失败 endpoint={s} event={s}: {s},上报任务失败以触发重试", .{ endpoint.string, event.string, @errorName(err) });
        return error.WebhookTransportFailed;
    };
    if (status >= 200 and status < 300) return;
    if (status >= 500) {
        std.log.warn("[jobs] webhook.deliver 对端 5xx(status={d}) endpoint={s} event={s},上报任务失败以触发重试", .{ status, endpoint.string, event.string });
        return error.WebhookServerError;
    }
    // 4xx：见函数头注释——队列无法按错误类型区分重试与否，记日志
    // 后吞掉返回 success，避免无意义重试占满 max_attempts。
    std.log.warn("[jobs] webhook.deliver 对端拒绝(status={d}) endpoint={s} event={s},视为终态失败不再重试", .{ status, endpoint.string, event.string });
}

/// The handler registry for this application. `mailer` and
/// `webhook_transport` must outlive the dispatcher.
pub fn handlers(mailer: *const mail.Mailer, webhook_transport: *wt.WebhookTransport) [2]task_svc.Handler {
    return .{
        .{
            .name = "mail.send",
            .ctx = @ptrCast(@alignCast(@constCast(mailer))),
            .run = mailSend,
        },
        .{
            .name = "webhook.deliver",
            .ctx = @ptrCast(@alignCast(webhook_transport)),
            .run = webhookDeliver,
        },
    };
}
