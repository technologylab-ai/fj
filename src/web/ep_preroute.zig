const std = @import("std");
const zap = @import("zap");
const Context = @import("context.zig");
const fsutil = @import("../fsutil.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.pre_router);

init_route: []const u8,
App: type,

const PreRouter = @This();

pub fn Create(pr: *const PreRouter, Endpoint: type) type {
    return struct {
        path: []const u8,
        error_strategy: zap.Endpoint.ErrorStrategy,
        ep: *Endpoint,
        init_route: []const u8,

        pub fn init(endpoint_ptr: anytype) @This() {
            return .{
                .ep = endpoint_ptr,
                .path = endpoint_ptr.path,
                .error_strategy = endpoint_ptr.error_strategy,
                .init_route = pr.init_route,
            };
        }

        fn redirect(self: *@This(), r: zap.Request) !void {
            log.info("REDIRECT TO {s}", .{self.init_route});
            try r.redirectTo(self.init_route, null);
        }

        pub fn get(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("GET {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("get", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn post(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("POST {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("post", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn put(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("PUT {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("put", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn delete(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("DELETE {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("delete", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn patch(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("PATCH {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("patch", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn options(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("OPTIONS {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("options", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
        pub fn head(self: *@This(), arena: Allocator, context: *Context, r: zap.Request) !void {
            log.info("HEAD {s}", .{r.path orelse ""});
            if (fsutil.isDirPresent(context.fj_home)) {
                return pr.App.callHandlerIfExist("head", self.ep, arena, context, r);
            }
            try self.redirect(r);
        }
    };
}
