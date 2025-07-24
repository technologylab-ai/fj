const std = @import("std");
const Fj = @import("../fj.zig");
const zap = @import("zap");

const log = std.log.scoped(.context);
const fsutil = @import("../fsutil.zig");

const webmanifest_tuples = &[_][2][]const u8{
    .{ "/android-chrome-192x192.png", @embedFile("assets/android-chrome-192x192.png") },
    .{ "/android-chrome-512x512.png", @embedFile("assets/android-chrome-512x512.png") },
    .{ "/apple-touch-icon.png", @embedFile("assets/apple-touch-icon.png") },
    .{ "/favicon-16x16.png", @embedFile("assets/favicon-16x16.png") },
    .{ "/favicon-32x32.png", @embedFile("assets/favicon-32x32.png") },
    .{ "/favicon.ico", @embedFile("assets/favicon.ico") },
    .{ "/site.webmanifest", @embedFile("assets/site.webmanifest") },
};

gpa: std.mem.Allocator,
auth_lookup: std.StringHashMapUnmanaged([]const u8),
fj_home: []const u8,
work_dir: []const u8,
logo_imgdata: []const u8,

// we redirect to dashboard or init unless it's favico stuff
pub fn unhandledRequest(self: *@This(), _: std.mem.Allocator, r: zap.Request) anyerror!void {
    if (r.path) |path| {
        for (webmanifest_tuples) |*tuple| {
            if (std.mem.eql(u8, path, tuple[0])) {
                log.info("GET {s}", .{path});
                return r.sendBody(tuple[1]);
            }
        }
    }

    log.info("UNHANDLED: {s}", .{r.path orelse ""});
    if (fsutil.isDirPresent(self.fj_home)) {
        try r.redirectTo("/dashboard", null);
    } else {
        try r.redirectTo("/init", null);
    }
}
