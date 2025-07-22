const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");

const html_login = @embedFile("templates/login.html");

const Allocator = std.mem.Allocator;
const Login = @This();
const log = std.log.scoped(.login);

path: []const u8 = "/login",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

main_page: []const u8,

/// Show the login form
pub fn get(ep: *Login, arena: Allocator, context: *Context, r: zap.Request) !void {
    // dispatch inside the /login page
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        // login
        if (std.mem.eql(u8, path, "/login/logo.png")) {
            r.setStatus(.ok);
            return r.sendBody(context.logo_imgdata);
        }
        if (std.mem.startsWith(u8, path, "/login")) {
            const params = .{
                .login_page = "/login",
                .main_page = ep.main_page,
            };

            var mustache = try zap.Mustache.fromData(html_login);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return r.sendBody(rendered);
            }
            return error.Mustache;
        }
    }
    try ep_utils.show_404(arena, context, r);
}

// unauthorized login attempts go to login page: this happens inside the
// zap.Endpoint.Authenticating !!!
// Note: this function is "unreachable" by the /login mechanics: everything starting with /login is passed-through orelse we wouldn't be able to serve the logo etc
pub fn unauthorized(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}

pub fn post(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn put(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn delete(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn patch(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn options(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn head(_: *Login, _: Allocator, _: *Context, _: zap.Request) !void {}
