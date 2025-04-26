const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const Fi = @import("../fi.zig");
const Endpoint = @import("endpoint.zig");
const Dir = std.fs.Dir;

const Context = @import("context.zig");
const Server = @This();

const log = std.log.scoped(.server);

pub const InitOpts = struct {
    host: []const u8,
    port: usize,
    username: []const u8,
    password: []const u8,
    work_dir: []const u8 = ".",
};

fn readLogo(allocator: Allocator, fi_home: []const u8) ![]const u8 {
    var fi_home_dir = try std.fs.cwd().openDir(fi_home, .{});
    defer fi_home_dir.close();

    var logo_file = try fi_home_dir.openFile("templates/logo.png", .{});
    defer logo_file.close();

    return try logo_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

pub fn start(fi_home: []const u8, opts: InitOpts) !void {
    //
    // Allocator
    //
    var gpa: std.heap.GeneralPurposeAllocator(.{
        // just to be explicit
        .thread_safe = true,
    }) = .{};
    defer std.debug.print("\n\nLeaks detected: {}\n\n", .{gpa.deinit() != .ok});
    const allocator = gpa.allocator();

    //
    // Endpoint
    //
    var endpoint: Endpoint = .{
        .path = "/",
        .error_strategy = .log_to_response,
    };

    //
    // Context
    //
    var context: Context = .{
        .auth_lookup = .empty,
        .fi_home = try allocator.dupe(u8, fi_home),
        .work_dir = opts.work_dir,
        .logo_imgdata = readLogo(allocator, fi_home) catch |err| {
            std.process.fatal("Unable to read logo from fi home: {}", .{err});
        },
    };
    defer allocator.free(context.fi_home);
    defer allocator.free(context.logo_imgdata);

    // cd into the working directory
    std.process.changeCurDir(context.work_dir) catch |err| {
        std.process.fatal(
            "Cannot change into working directory `{s}`: {}",
            .{ context.work_dir, err },
        );
    };
    // get it back
    context.work_dir = try std.process.getCwdAlloc(allocator);
    log.info("My working directory is: {s}", .{context.work_dir});
    defer allocator.free(context.work_dir);

    // fill the lookup table
    try context.auth_lookup.put(allocator, opts.username, opts.password);
    defer context.auth_lookup.deinit(allocator);

    // debug
    var it = context.auth_lookup.iterator();
    std.log.debug("Registered credentials:", .{});
    while (it.next()) |entry| {
        std.log.debug("    `{s}`: `{s}`", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    std.debug.print("\n", .{});

    //
    // App
    //
    const App = zap.App.Create(Context);
    var app = try App.init(allocator, &context, .{});
    defer app.deinit();

    //
    // Authentication
    //
    const Authenticator = zap.Auth.UserPassSession(@TypeOf(context.auth_lookup), false);
    var authenticator = try Authenticator.init(allocator, &context.auth_lookup, .{
        .usernameParam = "username",
        .passwordParam = "password",
        .loginPage = "/login",
        .cookieName = "FI_SESSION",
    });
    defer authenticator.deinit();

    const AuthEndpoint = App.Endpoint.Authenticating(Endpoint, Authenticator);
    var auth_endpoint = AuthEndpoint.init(&endpoint, &authenticator);

    try app.register(&auth_endpoint);

    //
    // zap
    //
    const interface = try std.fmt.allocPrintZ(allocator, "{s}", .{opts.host});
    defer allocator.free(interface);

    try app.listen(.{
        .interface = interface,
        .port = opts.port,
    });

    std.debug.print(
        "Serving: {s}\n\nVisit me at http://{s}:{d}\n\n",
        .{
            context.fi_home,
            opts.host,
            opts.port,
        },
    );

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
