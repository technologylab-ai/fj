const std = @import("std");
const zeit = @import("zeit");

/// Get today's date as YYYY-MM-DD string
pub fn getTodayString(allocator: std.mem.Allocator) ![]const u8 {
    const ts = zeit.instant(.{}) catch return error.TimeError;
    const dt = ts.time();
    return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        dt.year, @intFromEnum(dt.month), dt.day,
    });
}
