const std = @import("std");
const Fi = @import("../fi.zig");

auth_lookup: std.StringHashMapUnmanaged([]const u8),
fi: *const Fi,
work_dir: []const u8 = ".",
