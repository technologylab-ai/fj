const std = @import("std");
const log = std.log.scoped(.zip);

pub const ZipArgs = struct {
    zip_name: []const u8,
    filenames: []const []const u8,
    work_dir: ?[]const u8 = null,
};

pub fn zip(arena: std.mem.Allocator, args: ZipArgs) !bool {
    if (args.filenames.len == 0) return false;
    var arg_list = std.ArrayListUnmanaged([]const u8).empty;
    try arg_list.appendSlice(arena, &.{
        "zip",
        args.zip_name,
    });
    try arg_list.appendSlice(arena, args.filenames);

    const args_str = std.mem.join(arena, " ", arg_list.items) catch {
        return false;
    };

    var stderr = std.io.getStdErr();
    stderr.writeAll("\n" ++ "-" ** 80 ++ "\n") catch unreachable;
    defer stderr.writeAll("-" ** 80 ++ "\n") catch unreachable;

    const result = std.process.Child.run(.{
        .allocator = arena,
        .argv = arg_list.items,
        .cwd = args.work_dir,
        // .max_output_bytes = max_output_bytes,
        .expand_arg0 = .expand,
    }) catch |err| {
        log.err("Could not launch `{s}`: {}", .{ args_str, err });
        return err;
    };
    switch (result.term) {
        .Exited => |exit_code| {
            if (exit_code != 0) {
                log.err("`{s}` returned exit code {d}.", .{ args_str, exit_code });
                showResultMessages(result);
                return false;
            }
            log.info("{s} OK:", .{args_str});
            showResultMessages(result);
            return true;
        },
        .Signal => |signal| {
            // show stdout, stderr
            log.err("`{s}` received signal: {d}!", .{ args_str, signal });
            showResultMessages(result);
            return false;
        },
        .Stopped => |stopped| {
            // show stdout, stderr
            log.err("`{s}` was stopped with code: {d}!", .{ args_str, stopped });
            showResultMessages(result);
            return false;
        },
        .Unknown => |unk| {
            // show stdout, stderr
            log.err("`{s}` caused unknown code: {d}!", .{ args_str, unk });
            showResultMessages(result);
            return false;
        },
    }
}

fn showResultMessages(result: std.process.Child.RunResult) void {
    var stdout = std.io.getStdOut();
    var stderr = std.io.getStdErr();
    stdout.writeAll(result.stdout) catch {};
    // stderr.writeAll("\n") catch unreachable;
    stderr.writeAll(result.stderr) catch {};
}
