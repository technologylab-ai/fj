const std = @import("std");
const Fi = @import("../fi.zig");

auth_lookup: std.StringHashMapUnmanaged([]const u8),
fi_home: []const u8,
work_dir: []const u8,
logo_imgdata: []const u8,
