const std = @import("std");
const zap = @import("zap");
const Fi = @import("../fi.zig");
const Endpoint = @import("endpoint.zig");
const Dir = std.fs.Dir;

const Context = @import("context.zig");
const Server = @This();

// Dashboard:
// ----------
//
// GET     /                           Dashboard HMTL
// GET     /stats.json                 optional: computed stats, recent docs, etc.
// GET     /git/push                   push archive

// Resources:
// ----------
//
// GET     /client/list                List all clients
// GET     /client/new                 Create new client, return raw JSON
// GET     /client/:shortname          Return raw client JSON
// POST    /client/:shortname/commit   Replace client JSON

// Documents:
// ----------
//
// GET     /offer/list                 List all offers
// GET     /offer/new                  Create new offer
// GET     /offer/:id/offer.json       Return raw offer JSON
// POST    /offer/:id/offer.json       Replace offer JSON
// GET     /offer/:id/billables.csv    Return raw CSV
// POST    /offer/:id/billables.csv    Replace CSV
// POST    /offer/:id/compile          Compile offer
// POST    /offer/:id/commit           Finalize + commit
// GET     /offer/:id/pdf              Return compiled PDF

pub const InitOpts = struct {
    host: []const u8,
    port: usize,
    username: []const u8,
    password: []const u8,
    work_dir: []const u8 = ".",
};

pub fn start(fi: *const Fi, opts: InitOpts) !void {
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
        .fi = fi,
        .work_dir = opts.work_dir,
    };
    // fill the lookup table
    try context.auth_lookup.put(fi.arena, opts.username, opts.password);

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
        .cookieName = "FI_SESSION_XXXXXXXX",
    });
    defer authenticator.deinit();

    const AuthEndpoint = App.Endpoint.Authenticating(Endpoint, Authenticator);
    var auth_endpoint = AuthEndpoint.init(&endpoint, &authenticator);

    try app.register(&auth_endpoint);

    //
    // zap
    //
    const interface = try std.fmt.allocPrintZ(fi.arena, "{s}", .{opts.host});

    try app.listen(.{
        .interface = interface,
        .port = opts.port,
    });

    std.debug.print(
        "Serving: {s}\n\nVisit me at http://{s}:{d}\n\n",
        .{
            fi.fi_home.?,
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
