const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");

const Allocator = std.mem.Allocator;
const Logout = @This();
const log = std.log.scoped(.logout);

const auth_types = @import("auth_types.zig");
const Authenticator = auth_types.Authenticator;

// All Endpoints have these two:
path: []const u8 = "/logout",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

// endpoint specific data:
redirect_to: []const u8,

// GET handler
pub fn get(ep: *Logout, arena: Allocator, context: *Context, r: zap.Request) !void {
    log.info("GET {s}", .{r.path orelse ""});
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        if (std.mem.startsWith(u8, path, ep.path)) {
            context.authenticator.logout(&r);
            return r.redirectTo(ep.redirect_to, null);
        }
    }
    try ep_utils.show_404(arena, context, r);
}
