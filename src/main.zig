const std = @import("std");
const Cli = @import("cli.zig");
const zli = @import("zli");
const Fi = @import("fi.zig");
const Server = @import("web/server.zig");
const Fatal = @import("fatal.zig");

const assert = std.debug.assert;
const log = std.log.scoped(.fi);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    var cmd_arena = std.heap.ArenaAllocator.init(allocator);
    defer cmd_arena.deinit();

    const arena = cmd_arena.allocator();

    var pargs = try std.process.argsWithAllocator(allocator);
    defer pargs.deinit();

    const result = zli.parse(&pargs, Cli.Cli);

    var fi: Fi = .{ .arena = arena };
    defer fi.deinit();

    switch (result) {
        .init => |args| {
            try fi.setup(args.fi_home);
            try fi.cmd_init(args);
        },
        .git => |args| {
            try fi.setup(args.fi_home);
            try fi.cmd_git(args);
        },
        .client => |args| {
            try fi.setup(args.fi_home);
            _ = try fi.cmdClient(args);
        },
        .rate => |args| {
            try fi.setup(args.fi_home);
            _ = try fi.cmdRate(args);
        },
        .letter => |args| {
            try fi.setup(args.fi_home);
            _ = try fi.cmdLetter(args);
        },
        .offer => |args| {
            try fi.setup(args.fi_home);
            _ = try fi.cmdOffer(args);
        },
        .invoice => |args| {
            try fi.setup(args.fi_home);
            _ = try fi.cmdInvoice(args);
        },
        .serve => |args| {
            Fatal.mode = .server;
            try fi.setup(args.fi_home);
            try Server.start(
                fi.fi_home.?,
                .{
                    .host = args.host,
                    .port = args.port,
                    .username = args.username,
                    .password = args.password,
                    .work_dir = args.work_dir,
                },
            );
        },
    }
}
