const std = @import("std");
const zap = @import("zap");

const FiEndpoint = @This();

alloc: std.mem.Allocator = undefined,

path: []const u8,
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

pub fn init(
    a: std.mem.Allocator,
    user_path: []const u8,
) FiEndpoint {
    return .{
        .alloc = a,
        .path = user_path,
    };
}

pub fn deinit(self: *FiEndpoint) void {
    self._users.deinit();
}

pub fn get(self: *FiEndpoint, r: zap.Request) !void {
    _ = self;
    _ = r;
}

pub fn post(self: *FiEndpoint, r: zap.Request) !void {
    _ = self;
    _ = r;
}

pub fn options(_: *FiEndpoint, r: zap.Request) !void {
    try r.setHeader("Access-Control-Allow-Origin", "*");
    try r.setHeader("Access-Control-Allow-Methods", "GET, POST, HEAD");
    r.setStatus(zap.http.StatusCode.no_content);
    r.markAsFinished(true);
}

pub fn head(_: *FiEndpoint, r: zap.Request) !void {
    r.setStatus(zap.http.StatusCode.no_content);
    r.markAsFinished(true);
}

pub fn put(_: *FiEndpoint, _: zap.Request) !void {}
pub fn patch(_: *FiEndpoint, _: zap.Request) !void {}
pub fn delete(_: *FiEndpoint, _: zap.Request) !void {}
