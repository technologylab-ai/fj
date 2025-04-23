const std = @import("std");
const zap = @import("zap");
const Fi = @import("../fi.zig");
const FiEndpoint = @import("endpoint.zig");
const Dir = std.fs.Dir;

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

auth_lookup: *std.StringHashMapUnmanaged([]const u8),
start_opts: InitOpts,
fi: *const Fi,
endpoint: *FiEndpoint,

pub const InitOpts = struct {
    host: []const u8,
    port: usize,
    username: []const u8,
    password: []const u8,
    work_dir: []const u8 = ".",
};

// we need a REAL allocator in the server orelse we'll OOM at some stage
pub fn init(fi: *const Fi, gpa: std.mem.Allocator, opts: InitOpts) !Server {
    const lookup = try fi.arena.create(std.StringHashMapUnmanaged([]const u8));
    lookup.* = .empty;
    try lookup.put(fi.arena, opts.username, opts.password);

    const endpoint = try fi.arena.create(FiEndpoint);
    endpoint.* = FiEndpoint.init(gpa, "/");

    // consider using zap.Fi!!!
    // we need a REAL allocator in the server!!!
    return .{
        .fi = fi,
        .start_opts = opts,
        .auth_lookup = lookup,
        .endpoint = endpoint,
    };
}

pub fn start(fi: *const Fi, opts: InitOpts) !void {
    const interface = try std.fmt.allocPrintZ(fi.arena, "{s}", .{opts.host});

    var listener = zap.HttpListener.init(.{
        .interface = interface,
        .port = opts.port,
        .on_request = on_request,
        .log = true,
        // .public_folder = fi.fi_home.?,
    });
    try listener.listen();

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

fn on_request(r: zap.Request) !void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }
    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}
