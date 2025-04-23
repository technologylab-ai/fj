const std = @import("std");
const zap = @import("zap");
const Context = @import("context.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @This();

// WIP this is just copied from the App example

const HTTP_RESPONSE_TEMPLATE = "X";

// the slug
path: []const u8,
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

// authenticated GET requests go here
// we use the endpoint, the context, the arena, and try
pub fn get(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;
    _ = context;
    r.setStatus(.ok);
    try r.sendBody(HTTP_RESPONSE_TEMPLATE);
}

// we also catch the unauthorized callback
// we use the endpoint, the context, the arena, and try
pub fn unauthorized(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;
    _ = context;
    r.setStatus(.unauthorized);
    try r.sendBody(HTTP_RESPONSE_TEMPLATE);
}

// not implemented, don't care
pub fn post(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn put(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn delete(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn patch(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn options(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn head(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
