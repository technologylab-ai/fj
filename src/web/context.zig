const std = @import("std");
const Fj = @import("../fj.zig");
const zap = @import("zap");

const log = std.log.scoped(.context);
const fsutil = @import("../fsutil.zig");

gpa: std.mem.Allocator,
auth_lookup: std.StringHashMapUnmanaged([]const u8),
fj_home: []const u8,
work_dir: []const u8,
logo_imgdata: []const u8,

pub fn unhandledRequest(self: *@This(), _: std.mem.Allocator, r: zap.Request) anyerror!void {
    log.info("UNHANDLED: {s}", .{r.path orelse ""});
    if (fsutil.isDirPresent(self.fj_home)) {
        try r.redirectTo("/dashboard", null);
    } else {
        try r.redirectTo("/init", null);
    }
}
