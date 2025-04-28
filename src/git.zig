const std = @import("std");
const Fatal = @import("fatal.zig");
const fatal = Fatal.fatal;

arena: std.mem.Allocator,
repo_dir: []const u8,

const Git = @This();

const log = std.log.scoped(.git);

const max_output_bytes: usize = 200 * 1024;

fn showResultMessages(result: std.process.Child.RunResult, writer: ?std.io.AnyWriter) void {
    var stdout = writer orelse std.io.getStdOut().writer().any();
    var stderr = writer orelse std.io.getStdErr().writer().any();
    stdout.writeAll(result.stdout) catch unreachable;
    // stderr.writeAll("\n") catch unreachable;
    stderr.writeAll(result.stderr) catch unreachable;
}

fn cmd(self: *const Git, argv: []const []const u8, writer: ?std.io.AnyWriter) !bool {
    const arglist = std.mem.join(self.arena, " ", argv) catch {
        return false;
    };

    var stderr = std.io.getStdErr();
    stderr.writeAll("\n" ++ "-" ** 80 ++ "\n") catch unreachable;
    defer stderr.writeAll("-" ** 80 ++ "\n") catch unreachable;

    const result = std.process.Child.run(.{
        .allocator = self.arena,
        .argv = argv,
        .cwd = self.repo_dir,
        .max_output_bytes = max_output_bytes,
        .expand_arg0 = .expand,
    }) catch |err| {
        try fatal("Could not launch `git {s}`: {}", .{ arglist, err }, err);
    };
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`git {s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(result, writer);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(result, writer);
            return true;
        },
        .Signal => |signal| {
            // show stdout, stderr
            log.err("`git {s}` received signal: {d}!", .{ arglist, signal });
            showResultMessages(result, writer);
            return false;
        },
        .Stopped => |stopped| {
            // show stdout, stderr
            log.err("`git {s}` was stopped with code: {d}!", .{ arglist, stopped });
            showResultMessages(result, writer);
            return false;
        },
        .Unknown => |unk| {
            // show stdout, stderr
            log.err("`git {s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(result, writer);
            return false;
        },
    }
}

pub fn init(self: *const Git) !bool {
    return self.cmd(&[_][]const u8{ "git", "init" }, null);
}

pub fn status(self: *const Git, writer: ?std.io.AnyWriter) !bool {
    return self.cmd(&[_][]const u8{ "git", "status" }, writer);
}

pub fn stage(
    self: *const Git,
    opts: union(enum) { file: []const u8, files: []const []const u8, all },
    writer: ?std.io.AnyWriter,
) !bool {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    args.append(self.arena, "git") catch try fatal("OOM!", .{}, error.OutOfMemory);
    args.append(self.arena, "add") catch try fatal("OOM!", .{}, error.OutOfMemory);

    switch (opts) {
        .all => args.append(self.arena, ".") catch try fatal("OOM!", .{}, error.OutOfMemory),
        .files => |files| {
            for (files) |file| args.append(self.arena, file) catch try fatal("OOM!", .{}, error.OutOfMemory);
        },
        .file => |file| args.append(self.arena, file) catch try fatal("OOM!", .{}, error.OutOfMemory),
    }

    return self.cmd(args.items, writer);
}

pub fn commit(self: *const Git, commit_message: []const u8, writer: ?std.io.AnyWriter) !bool {
    return self.cmd(&[_][]const u8{ "git", "commit", "-m", commit_message }, writer);
}

pub fn push(self: *const Git, writer: ?std.io.AnyWriter) !bool {
    return self.cmd(&[_][]const u8{ "git", "push", "-u", "origin", "master" }, writer);
}

pub fn pull(self: *const Git, writer: ?std.io.AnyWriter) !bool {
    return self.cmd(&[_][]const u8{ "git", "pull" }, writer);
}

pub const RemoteSubCommand = enum { add, show, delete, list };
pub fn remote(self: *const Git, opts: struct {
    subcommand: RemoteSubCommand,
    remote: ?[]const u8 = null,
    url: ?[]const u8 = null,
}) !bool {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    switch (opts.subcommand) {
        .list => return self.cmd(&[_][]const u8{ "git", "remote", "-v" }, null),
        .show => {
            if (opts.remote) |remote_name| {
                args.appendSlice(
                    self.arena,
                    &[_][]const u8{ "git", "remote", "show", remote_name },
                ) catch try fatal("OOM!", .{}, error.OutOfMemory);
                return self.cmd(args.items, null);
            } else {
                try fatal("fj git remote requires a --remote= !", .{}, error.Cli);
            }
        },
        .add => {
            if (opts.remote == null) {
                try fatal("fj git remote add requires a --remote= !", .{}, error.Cli);
            }
            if (opts.url == null) {
                try fatal("fj git remote add requires a --url= !", .{}, error.Cli);
            }
            args.appendSlice(
                self.arena,
                &[_][]const u8{ "git", "remote", "add", opts.remote.?, opts.url.? },
            ) catch try fatal("OOM!", .{}, error.OutOfMemory);
            return self.cmd(args.items, null);
        },
        .delete => {
            if (opts.remote == null) {
                try fatal("fj git remote delete requires a --remote= !", .{}, error.Cli);
            }
            args.appendSlice(
                self.arena,
                &[_][]const u8{ "git", "remote", "remove", opts.remote.? },
            ) catch try fatal("OOM!", .{}, error.OutOfMemory);
            return self.cmd(args.items, null);
        },
    }
}
