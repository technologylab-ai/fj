const std = @import("std");
const Cli = @import("cli.zig");
const zli = @import("zli");
const Fj = @import("fj.zig");
const Server = @import("web/server.zig");
const Fatal = @import("fatal.zig");
const Version = @import("version.zig");

const assert = std.debug.assert;
const log = std.log.scoped(.fj);

const zeitlog = @import("zeitlog.zig");
pub const std_options: std.Options = .{
    .log_level = .debug,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .zap, .level = .debug },
    },
    .logFn = zeitlog.log,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    var cmd_arena = std.heap.ArenaAllocator.init(allocator);
    defer cmd_arena.deinit();

    // init logging with correct timezone
    try zeitlog.init(allocator);
    defer zeitlog.deinit();

    const arena = cmd_arena.allocator();

    var pargs = try std.process.argsWithAllocator(allocator);
    defer pargs.deinit();

    const result = zli.parse(&pargs, Cli.Cli);

    var fj: Fj = .{ .arena = arena };
    defer fj.deinit();

    switch (result) {
        .init => |args| {
            try fj.setup(args.fj_home);
            try fj.cmd_init(args);
        },
        .git => |args| {
            try fj.setup(args.fj_home);
            try fj.cmd_git(args);
        },
        .client => |args| {
            try fj.setup(args.fj_home);
            _ = try fj.cmdClient(args);
        },
        .rate => |args| {
            try fj.setup(args.fj_home);
            _ = try fj.cmdRate(args);
        },
        .letter => |args| {
            try fj.setup(args.fj_home);
            _ = try fj.cmdLetter(args);
        },
        .offer => |args| {
            try fj.setup(args.fj_home);
            _ = try fj.cmdOffer(args);
        },
        .invoice => |args| {
            try fj.setup(args.fj_home);
            _ = try fj.cmdInvoice(args);
        },
        .keys => |args| {
            try fj.setup(args.fj_home);
            try fj.cmdKeys(args);
        },
        .serve => |args| {
            Fatal.mode = .server;
            try fj.setup(args.fj_home);
            try Server.start(
                fj.fj_home.?,
                .{
                    .host = args.host,
                    .port = args.port,
                    .username = args.username,
                    .password = args.password,
                    .work_dir = args.work_dir,
                },
            );
        },
        .version => {
            var stdout_buffer: [128]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("fj version {s}\n", .{Version.version() orelse "(unknown version)"});
        },
    }
}
