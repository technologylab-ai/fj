const std = @import("std");
const Fatal = @import("fatal.zig");
const ErrorStack = Fatal.ErrorStack;
const CommandUtils = @import("commandutils.zig");
const showResultMessages = CommandUtils.showResultMessages;
const fsutil = @import("fsutil.zig");

arena: std.mem.Allocator,
io: std.Io,
errs: *ErrorStack,
work_dir: ?[]const u8 = null,

const PdfLatex = @This();

fn fatal(self: *const PdfLatex, comptime fmt: []const u8, args: anytype, err: anyerror) anyerror!noreturn {
    return self.errs.fail(fmt, args, err);
}

const log = std.log.scoped(.pdflatex);

const max_output_bytes: usize = 1 * 1024 * 1024;

fn cmd(self: *const PdfLatex, argv: []const []const u8) !bool {
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
        try self.fatal("Could not launch `pdflatex {s}`: {}", .{ arglist, err }, err);
    };
    switch (result.term) {
        .exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`pdflatex {s}` returned exit code {d}.", .{ arglist, exit_code });
                showResultMessages(self.io, result, null);
                return false;
            }
            log.info("{s} OK:", .{arglist});
            showResultMessages(self.io, result, null);
            return true;
        },
        .signal => |signal| {
            // show stdout, stderr
            log.err("`pdflatex {s}` received signal: {d}!", .{ arglist, @intFromEnum(signal) });
            showResultMessages(self.io, result, null);
            return false;
        },
        .stopped => |stopped| {
            // show stdout, stderr
            log.err("`pdflatex {s}` was stopped with code: {d}!", .{ arglist, @intFromEnum(stopped) });
            showResultMessages(self.io, result, null);
            return false;
        },
        .unknown => |unk| {
            // show stdout, stderr
            log.err("`pdflatex {s}` caused unknown code: {d}!", .{ arglist, unk });
            showResultMessages(self.io, result, null);
            return false;
        },
    }
}

pub fn run(self: *const PdfLatex, tex_filename: []const u8) !bool {
    // `-interaction=nonstopmode` guarantees pdflatex never blocks on the
    // interactive `?` prompt (e.g. inside the server, where stdin may not be
    // EOF). The exit code alone is not a trustworthy success signal — see
    // `logErrors` and `cmdCompileDocument` for the real detection.
    return self.cmd(&[_][]const u8{ "pdflatex", "-interaction=nonstopmode", tex_filename });
}

/// Returns concatenated LaTeX error lines from `{work_dir}/{basename}.log`
/// ("" if none / log unreadable). `basename` is derived from `tex_filename`
/// (`.tex` → `.log`). TeX reserves a leading `! ` for errors, so warnings
/// (`Overfull`, `LaTeX Warning:`, `Rerun to get …`) never match.
pub fn logErrors(self: *const PdfLatex, tex_filename: []const u8) []const u8 {
    const base = if (std.mem.endsWith(u8, tex_filename, ".tex"))
        tex_filename[0 .. tex_filename.len - ".tex".len]
    else
        tex_filename;
    const log_name = std.fmt.allocPrint(self.arena, "{s}.log", .{base}) catch return "";
    const log_path = if (self.work_dir) |wd|
        std.fs.path.join(self.arena, &.{ wd, log_name }) catch return ""
    else
        log_name;

    var log_file = std.Io.Dir.cwd().openFile(self.io, log_path, .{}) catch return "";
    defer log_file.close(self.io);
    const contents = fsutil.readToEndAlloc(self.io, log_file, self.arena, max_output_bytes) catch return "";

    const max_lines: usize = 30;
    var collected: std.ArrayListUnmanaged([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, contents, '\n');
    var prev_was_error = false;
    while (it.next()) |line| {
        if (collected.items.len >= max_lines) break;
        const is_error = std.mem.startsWith(u8, line, "! ") or
            std.mem.indexOf(u8, line, "Fatal error occurred") != null or
            std.mem.indexOf(u8, line, "no output PDF file produced") != null;
        if (is_error) {
            collected.append(self.arena, line) catch break;
            prev_was_error = true;
            continue;
        }
        // Include the `l.<n> …` context line that follows a TeX error.
        if (prev_was_error and std.mem.startsWith(u8, line, "l.")) {
            collected.append(self.arena, line) catch break;
        }
        prev_was_error = false;
    }
    if (collected.items.len == 0) return "";
    return std.mem.join(self.arena, "\n", collected.items) catch "";
}
