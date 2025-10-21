const std = @import("std");

pub const Mode = enum { cli, server };
pub var mode: Mode = .cli;
pub var errormsg: []const u8 = "";
pub var errormsg_buffer: [2048]u8 = undefined;

pub fn fatal(comptime fmt: []const u8, args: anytype, err: anyerror) !noreturn {
    switch (mode) {
        .cli => std.process.fatal(fmt, args),
        .server => {
            errormsg = std.fmt.bufPrint(
                &errormsg_buffer,
                fmt,
                args,
            ) catch |bp_err| {
                switch (bp_err) {
                    error.NoSpaceLeft => {
                        // as much as possible WAS written to the buffer
                        // so the entire buffer must be full
                        errormsg = errormsg_buffer[0..];
                        std.log.err("{s}", .{errormsg});
                        return err;
                    },
                }
            };
            std.log.err("{s}", .{errormsg});
            return err; // so that server can catch it
        },
    }
}
