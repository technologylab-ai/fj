const std = @import("std");

pub const Opts = struct {
    comma: u8,
    sep: u8,

    pub const german: Opts = .{ .comma = ',', .sep = '.' };
    pub const english: Opts = .{ .comma = '.', .sep = ',' };
};

pub fn intThousandsAlloc(alloc: std.mem.Allocator, value: anytype, opts: Opts) ![]const u8 {
    const buf = try alloc.alloc(u8, 32);
    return intThousands(value, opts, buf);
}

pub fn floatThousandsAlloc(alloc: std.mem.Allocator, value: anytype, opts: Opts) ![]const u8 {
    const buf = try alloc.alloc(u8, 32);
    return floatThousands(value, opts, buf);
}

pub fn intThousands(
    value: anytype,
    opts: Opts,
    out: []u8,
) ![]const u8 {
    if (@typeInfo(@TypeOf(value)) != .int) {
        @compileError("intThousands called with type != int!");
    }
    var buf: [32]u8 = undefined;
    var i: usize = buf.len;

    var n = value;
    var digits: usize = 0;

    if (n == 0) {
        i -= 1;
        buf[i] = '0';
    } else {
        while (n != 0) {
            if (digits != 0 and digits % 3 == 0) {
                i -= 1;
                buf[i] = opts.sep;
            }
            i -= 1;
            buf[i] = '0' + @as(u8, @intCast(n % 10));
            n /= 10;
            digits += 1;
        }
    }

    const result = buf[i..];
    if (result.len > out.len)
        return error.BufferTooSmall;

    @memcpy(out[0..result.len], result);
    return out[0..result.len];
}

pub fn float(value: anytype, opts: Opts, out: []u8) ![]const u8 {
    if (@typeInfo(@TypeOf(value)) != .float) {
        @compileError("float called with type != float!");
    }
    const float_str = try std.fmt.bufPrint(out, "{d:0.2}", value);
    if (opts.comma != '.') {
        std.mem.replaceScalar(u8, float_str, '.', opts.comma);
    }
    return float_str;
}

pub fn floatThousands(
    value: anytype,
    opts: Opts,
    out: []u8,
) ![]const u8 {
    if (@typeInfo(@TypeOf(value)) != .float) {
        @compileError("floatThousands called with type != float!");
    }
    var buf: [32]u8 = undefined;
    var buf_remainder: [2]u8 = undefined;
    var i: usize = buf.len;

    var n: usize = @intFromFloat(@trunc(value));
    const epsilon: @TypeOf(value) = 0.0005;
    const remainder_2digits: u8 = @intFromFloat(@round((value + epsilon - @as(@TypeOf(value), @floatFromInt(n))) * 100.0));
    var digits: usize = 0;

    if (n == 0.0) {
        i -= 1;
        buf[i] = '0';
    } else {
        while (n > 0) {
            if (digits != 0 and digits % 3 == 0) {
                i -= 1;
                buf[i] = opts.sep;
            }
            i -= 1;
            buf[i] = '0' + @as(u8, @intCast(n % 10));
            n /= 10;
            digits += 1;
        }
    }

    const result = buf[i..];

    const remainder_str = std.fmt.bufPrint(&buf_remainder, "{d:02}", .{remainder_2digits}) catch unreachable;

    if (result.len + remainder_str.len + 1 > out.len)
        return error.BufferTooSmall;

    @memcpy(out[0..result.len], result);
    out[result.len] = opts.comma;
    @memcpy(out[result.len + 1 .. result.len + 1 + remainder_str.len], remainder_str);
    return out[0 .. result.len + 1 + remainder_str.len];
}

test floatThousands {
    var out: [32]u8 = undefined;

    var value: f32 = undefined;
    var result_str: []const u8 = undefined;

    value = 2.5;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2,50", result_str);

    value = 2500;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,00", result_str);

    value = 2500.5051;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,51", result_str);

    value = 2500.5050;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,51", result_str);

    value = 2500.5049;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,51", result_str);

    value = 2500.5044;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,50", result_str);

    value = 2500.5054;
    result_str = try floatThousands(value, .german, &out);
    try std.testing.expectEqualStrings("2.500,51", result_str);
}

pub fn strip(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n");
}
