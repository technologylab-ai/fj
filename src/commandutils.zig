const std = @import("std");

pub fn showResultMessages(result: std.process.Child.RunResult, writer: ?*std.io.Writer) void {
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;

    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);

    const stdout = writer orelse &stdout_writer.interface;
    const stderr = writer orelse &stderr_writer.interface;
    stdout.writeAll(result.stdout) catch unreachable;
    stderr.writeAll(result.stderr) catch unreachable;

    stdout.flush() catch unreachable;
    stderr.flush() catch unreachable;
}
