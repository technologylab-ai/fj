const std = @import("std");
const zeit = @import("zeit");

var timezone: ?zeit.TimeZone = null;

pub fn init(gpa: std.mem.Allocator) !void {
    timezone = try zeit.local(gpa, null);
}

pub fn deinit() void {
    if (timezone) |*tz| {
        tz.deinit();
    }
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // this might make it thread-safe
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();

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
