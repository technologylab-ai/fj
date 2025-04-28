const std = @import("std");
const Fj = @import("../fj.zig");

auth_lookup: std.StringHashMapUnmanaged([]const u8),
fj_home: []const u8,
work_dir: []const u8,
logo_imgdata: []const u8,
