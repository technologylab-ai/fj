const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;

const Git = @import("../git.zig");

comptime path: []const u8 = "/git",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const log = std.log.scoped(.git_endpoint);
const html_git_command = @embedFile("templates/git_command.html");

const GitEndpoint = @This();

pub fn get(ep: *GitEndpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        // git commit
        if (std.mem.eql(u8, path, ep.path ++ "/commit")) {
            r.setStatus(.ok);
            return ep.git_commit(arena, context, r);
        }

        // git push
        if (std.mem.eql(u8, path, ep.path ++ "/push")) {
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

    var status_writer = std.io.Writer.Allocating.init(arena);
    _ = try git.push(&status_writer.writer);

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "push",
        .message = status_writer.written(),
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

fn git_commit(_: *GitEndpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };
    var fj = ep_utils.createFj(arena, context);
    var status_writer = std.io.Writer.Allocating.init(arena);
    if (try git.stage(.all, &status_writer.writer)) {
        _ = try git.commit("Committed via web", &status_writer.writer);
    }

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "commit",
        .message = status_writer.written(),
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}
