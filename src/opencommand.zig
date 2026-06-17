const std = @import("std");
const Fatal = @import("fatal.zig");
const ErrorStack = Fatal.ErrorStack;
const CommandUtils = @import("commandutils.zig");
const showResultMessages = CommandUtils.showResultMessages;

arena: std.mem.Allocator,
io: std.Io,
errs: *ErrorStack,
work_dir: ?[]const u8 = null,

const OpenCommand = @This();

fn fatal(self: *const OpenCommand, comptime fmt: []const u8, args: anytype, err: anyerror) anyerror!noreturn {
    return self.errs.fail(fmt, args, err);
}

const log = std.log.scoped(.OpenCommand);

const max_output_bytes: usize = 1 * 1024 * 1024;

fn cmd(self: *const OpenCommand, argv: []const []const u8) !bool {
    if (argv.len == 0) return false;
    const arglist = std.mem.join(self.arena, " ", argv) catch {
        return false;
    };

    var io_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(self.io, &io_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch unreachable;

    stderr.writeAll("\n" ++ "-" ** 80 ++ "\n") catch unreachable;
    defer stderr.writeAll("-" ** 80 ++ "\n") catch unreachable;

    const result = std.process.run(self.arena, self.io, .{
        .argv = argv,
        .cwd = if (self.work_dir) |wd| .{ .path = wd } else .inherit,
        .stdout_limit = .limited(max_output_bytes),
        .stderr_limit = .limited(max_output_bytes),
        .expand_arg0 = .expand,
    }) catch |err| {
        try self.fatal("Could not launch `{s}`: {}", .{ arglist, err }, err);
    };
    switch (result.term) {
        .exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`{s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(self.io, result, null);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(self.io, result, null);
            return true;
        },
        .signal => |signal| {
            // show stdout, stderr
            log.err("`{s}` received signal: {d}!", .{ arglist, @intFromEnum(signal) });
            showResultMessages(self.io, result, null);
            return false;
        },
        .stopped => |stopped| {
            // show stdout, stderr
            log.err("`{s}` was stopped with code: {d}!", .{ arglist, @intFromEnum(stopped) });
            showResultMessages(self.io, result, null);
            return false;
        },
        .unknown => |unk| {
            // show stdout, stderr
            log.err("`{s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(self.io, result, null);
            return false;
        },
    }
}

pub fn openDocument(self: *const OpenCommand, document_filename: []const u8) !bool {
    const command = switch (@import("builtin").os.tag) {
        .linux => "xdg-open",
        .macos => "open",
        .windows => "start",
        else => unreachable,
    };
    return self.cmd(&[_][]const u8{ command, document_filename });
}
