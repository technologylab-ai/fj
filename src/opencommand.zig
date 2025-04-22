const std = @import("std");
const fatal = std.process.fatal;

arena: std.mem.Allocator,
work_dir: ?[]const u8 = null,

const OpenCommand = @This();

const log = std.log.scoped(.OpenCommand);

const max_output_bytes: usize = 1 * 1024 * 1024;

fn showResultMessages(result: std.process.Child.RunResult) void {
    var stdout = std.io.getStdOut();
    var stderr = std.io.getStdErr();
    stdout.writeAll(result.stdout) catch unreachable;
    // stderr.writeAll("\n") catch unreachable;
    stderr.writeAll(result.stderr) catch unreachable;
}

fn cmd(self: *const OpenCommand, argv: []const []const u8) bool {
    if (argv.len == 0) return false;
    const arglist = std.mem.join(self.arena, " ", argv) catch {
        return false;
    };

    var stderr = std.io.getStdErr();
    stderr.writeAll("\n" ++ "-" ** 80 ++ "\n") catch unreachable;
    defer stderr.writeAll("-" ** 80 ++ "\n") catch unreachable;

    const result = std.process.Child.run(.{
        .allocator = self.arena,
        .argv = argv,
        .cwd = self.work_dir,
        .max_output_bytes = max_output_bytes,
        .expand_arg0 = .expand,
    }) catch |err| {
        fatal("Could not launch `{s}`: {}", .{ arglist, err });
    };
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`{s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(result);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(result);
            return true;
        },
        .Signal => |signal| {
            // show stdout, stderr
            log.err("`{s}` received signal: {d}!", .{ arglist, signal });
            showResultMessages(result);
            return false;
        },
        .Stopped => |stopped| {
            // show stdout, stderr
            log.err("`{s}` was stopped with code: {d}!", .{ arglist, stopped });
            showResultMessages(result);
            return false;
        },
        .Unknown => |unk| {
            // show stdout, stderr
            log.err("`{s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(result);
            return false;
        },
    }
}

pub fn openDocument(self: *const OpenCommand, document_filename: []const u8) bool {
    const command = switch (@import("builtin").os.tag) {
        .linux => "xdg-open",
        .macos => "open",
        .windows => "start",
        else => unreachable,
    };
    return self.cmd(&[_][]const u8{ command, document_filename });
}
