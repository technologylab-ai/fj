const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;

const Git = @import("../git.zig");

path: []const u8 = "/git",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const log = std.log.scoped(.git_endpoint);
const html_git_command = @embedFile("templates/git_command.html");

const GitEndpoint = @This();

pub fn get(ep: *GitEndpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        // git commit
        if (std.mem.eql(u8, path, "/git/commit")) {
            r.setStatus(.ok);
            return ep.git_commit(arena, context, r);
        }

        // git push
        if (std.mem.eql(u8, path, "/git/push")) {
            r.setStatus(.ok);
            return ep.git_push(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

fn git_push(_: *GitEndpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };
    var fj = ep_utils.createFj(arena, context);
    var alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.push(alist.writer(arena).any());

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "push",
        .message = alist.items,
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return r.sendBody(rendered);
    }
    return error.Mustache;
}

fn git_commit(_: *GitEndpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };
    var fj = ep_utils.createFj(arena, context);
    var alist = std.ArrayListUnmanaged(u8).empty;
    const writer = alist.writer(arena).any();
    if (try git.stage(.all, writer)) {
        _ = try git.commit("Committed via web", writer);
    }

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "commit",
        .message = alist.items,
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return r.sendBody(rendered);
    }
    return error.Mustache;
}
