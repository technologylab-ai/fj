const std = @import("std");
const zeit = @import("zeit");

var timezone: ?zeit.TimeZone = null;

// Captured at init so logFn — whose signature is fixed by std.Options.logFn and
// therefore can't take an io parameter — has a real io to write/timestamp with.
// The global is only ever used as a pre-init fallback, not in steady state.
var g_io: ?std.Io = null;

pub fn init(io: std.Io, gpa: std.mem.Allocator) !void {
    g_io = io;
    timezone = try zeit.local(gpa, io, null);
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
    const io = g_io orelse std.Io.Threaded.global_single_threaded.io();

    var now = zeit.instant(io, .{}) catch {
        std.log.defaultLog(level, scope, "!" ++ format, args);
        return;
    };

    if (timezone) |*tz| {
        now = now.in(tz);
    }

    const time = now.time();

    // Lock stderr ONCE and write both the timestamp prefix and the message
    // through the same locked terminal writer. Mixing a private File writer
    // with defaultLog's own lockStderr writer raced on the shared stderr state
    // and silently dropped the leading bytes of every message. unlockStderr()
    // flushes the buffer on release, so no explicit flush is needed here.
    var buffer: [1024]u8 = undefined;
    const locked = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();
    const term = locked.terminal();

    nosuspend term.writer.print("{d}-{d:02}-{d:02} {d:02}:{d:02}:{d:02}.{d:03} | ", .{
        time.year,
        @intFromEnum(time.month),
        time.day,
        time.hour,
        time.minute,
        time.second,
        time.millisecond,
    }) catch {};

    std.log.defaultLogFileTerminal(level, scope, format, args, term) catch {};
}
