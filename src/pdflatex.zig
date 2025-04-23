const std = @import("std");
const Fatal = @import("fatal.zig");
const fatal = Fatal.fatal;

arena: std.mem.Allocator,
work_dir: ?[]const u8 = null,

const PdfLatex = @This();

const log = std.log.scoped(.pdflatex);

const max_output_bytes: usize = 1 * 1024 * 1024;

fn showResultMessages(result: std.process.Child.RunResult) void {
    var stdout = std.io.getStdOut();
    var stderr = std.io.getStdErr();
    stdout.writeAll(result.stdout) catch unreachable;
    // stderr.writeAll("\n") catch unreachable;
    stderr.writeAll(result.stderr) catch unreachable;
}

fn cmd(self: *const PdfLatex, argv: []const []const u8) !bool {
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
        try fatal("Could not launch `pdflatex {s}`: {}", .{ arglist, err }, err);
    };
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`pdflatex {s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(result);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(result);
            return true;
        },
        .Signal => |signal| {
            // show stdout, stderr
            log.err("`pdflatex {s}` received signal: {d}!", .{ arglist, signal });
            showResultMessages(result);
            return false;
        },
        .Stopped => |stopped| {
            // show stdout, stderr
            log.err("`pdflatex {s}` was stopped with code: {d}!", .{ arglist, stopped });
            showResultMessages(result);
            return false;
        },
        .Unknown => |unk| {
            // show stdout, stderr
            log.err("`pdflatex {s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(result);
            return false;
        },
    }
}

pub fn run(self: *const PdfLatex, tex_filename: []const u8) !bool {
    return self.cmd(&[_][]const u8{ "pdflatex", tex_filename });
}
