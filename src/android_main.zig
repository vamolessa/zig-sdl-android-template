const std = @import("std");

const main = @import("main.zig");

const c = @cImport({
    @cInclude("android/log.h");
});

export fn SDL_main() void {
    main.main() catch |err| std.log.err("catch error from main: {}", .{err});
}

// make the std.log.<logger> functions write to the android log
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const priority = switch(message_level) {
        .emerg => c.ANDROID_LOG_FATAL,
        .alert => c.ANDROID_LOG_FATAL,
        .crit => c.ANDROID_LOG_FATAL,
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .notice => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";

    var buf = std.io.FixedBufferStream([4 * 1024]u8) {
        .buffer = undefined,
        .pos = 0,
    };
    var writer = buf.writer();
    writer.print(prefix ++ format, args) catch {};

    if (buf.pos >= buf.buffer.len) {
        buf.pos = buf.buffer.len - 1;
    }
    buf.buffer[buf.pos] = 0;

    _ = c.__android_log_write(priority, "ZIG", &buf.buffer);
}

