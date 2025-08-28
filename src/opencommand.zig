const std = @import("std");
const Fatal = @import("fatal.zig");
const fatal = Fatal.fatal;
const CommandUtils = @import("commandutils.zig");
const showResultMessages = CommandUtils.showResultMessages;

arena: std.mem.Allocator,
work_dir: ?[]const u8 = null,

const OpenCommand = @This();

const log = std.log.scoped(.OpenCommand);

const max_output_bytes: usize = 1 * 1024 * 1024;

fn cmd(self: *const OpenCommand, argv: []const []const u8) !bool {
    if (argv.len == 0) return false;
    const arglist = std.mem.join(self.arena, " ", argv) catch {
        return false;
    };

    var io_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&io_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch unreachable;

    stderr.writeAll("\n" ++ "-" ** 80 ++ "\n") catch unreachable;
    defer stderr.writeAll("-" ** 80 ++ "\n") catch unreachable;

    const result = std.process.Child.run(.{
        .allocator = self.arena,
        .argv = argv,
        .cwd = self.work_dir,
        .max_output_bytes = max_output_bytes,
        .expand_arg0 = .expand,
    }) catch |err| {
        try fatal("Could not launch `{s}`: {}", .{ arglist, err }, err);
    };
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`{s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(result, null);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(result, null);
            return true;
        },
        .Signal => |signal| {
            // show stdout, stderr
            log.err("`{s}` received signal: {d}!", .{ arglist, signal });
            showResultMessages(result, null);
            return false;
        },
        .Stopped => |stopped| {
            // show stdout, stderr
            log.err("`{s}` was stopped with code: {d}!", .{ arglist, stopped });
            showResultMessages(result, null);
            return false;
        },
        .Unknown => |unk| {
            // show stdout, stderr
            log.err("`{s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(result, null);
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
