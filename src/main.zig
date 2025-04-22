const std = @import("std");
const Cli = @import("cli.zig");
const zli = @import("zli");
const App = @import("app.zig");
const Server = @import("web/server.zig");

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

    var app: App = .{ .arena = arena };

    defer app.deinit();

    switch (result) {
        .init => |args| {
            app.setup(args.fi_home);
            try app.cmd_init(args);
        },
        .git => |args| {
            app.setup(args.fi_home);
            try app.cmd_git(args);
        },
        .client => |args| {
            app.setup(args.fi_home);
            try app.cmd_client(args);
        },
        .rate => |args| {
            app.setup(args.fi_home);
            try app.cmd_rate(args);
        },
        .letter => |args| {
            app.setup(args.fi_home);
            try app.cmd_letter(args);
        },
        .offer => |args| {
            app.setup(args.fi_home);
            try app.cmd_offer(args);
        },
        .invoice => |args| {
            app.setup(args.fi_home);
            try app.cmd_invoice(args);
        },
        .serve => |args| {
            app.setup(args.fi_home);
            try Server.start(&app, args.host, args.port);
        },
    }
}
