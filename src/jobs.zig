//! Background task handlers registered with the task Dispatcher.

const std = @import("std");
const mail = @import("services/mail.zig");
const task_svc = @import("modules/task/service.zig");

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

/// The handler registry for this application. `mailer` must outlive the
/// dispatcher.
pub fn handlers(mailer: *const mail.Mailer) [1]task_svc.Handler {
    return .{
        .{
            .name = "mail.send",
            .ctx = @ptrCast(@alignCast(@constCast(mailer))),
            .run = mailSend,
        },
    };
}
