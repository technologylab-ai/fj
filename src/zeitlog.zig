const std = @import("std");
const zeit = @import("zeit");

var timezone: ?zeit.TimeZone = null;

pub fn init(gpa: std.mem.Allocator) !void {
    timezone = try zeit.local(gpa, null);
}

pub fn deinit() void {
    if (timezone) |*tz| {
        tz.deinit();
        timezone = null;
    }
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    // this might make it thread-safe
    _ = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();
    const io = std.Io.Threaded.global_single_threaded.io();
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var now = zeit.instant(.{}) catch {
        std.log.defaultLog(level, scope, "!" ++ format, args);
        return;
    };

    if (timezone) |*tz| {
        now = now.in(tz);
    }

    const time = now.time();

    nosuspend stderr.print("{d}-{d:02}-{d:02} {d:02}:{d:02}:{d:02}.{d:03} | ", .{
        time.year,
        @intFromEnum(time.month),
        time.day,
        time.hour,
        time.minute,
        time.second,
        time.millisecond,
    }) catch unreachable;

    std.log.defaultLog(level, scope, format, args);
}
