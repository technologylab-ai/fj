const std = @import("std");
const zap = @import("zap");
const Fi = @import("../fi.zig");
const Context = @import("context.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @This();

// Login:
// ------
//
// GET     /                           Login HTML
// GET     /logo.png                   Login page

// Dashboard:
// ----------
//
// GET     /                           Dashboard HMTL
// GET     /stats.json                 optional: computed stats, recent docs, etc.
// GET     /git/push                   push archive

// Resources:
// ----------
//
// GET     /client                     Client HTML page
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

const html_login = @embedFile("templates/login.html");
const html_dashboard = @embedFile("templates/dashboard.html");
const html_404_not_found = "<html><body><h1>404 - Not found!</h1></body></html";

// the slug
path: []const u8,
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

//
// helpers

fn createFi(arena: Allocator, context: *Context) Fi {
    const fi: Fi = .{
        .arena = arena,
        .fi_home = context.fi_home,
    };
    return fi;
}

//
// requests

// authenticated GET requests go here
// we use the endpoint, the context, the arena, and try
pub fn get(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;

    // dispatch routes
    if (r.path) |path| {

        // login
        if (std.mem.eql(u8, path, "/login/logo.png")) {
            r.setStatus(.ok);
            return r.sendBody(context.logo_imgdata);
        }
        if (std.mem.startsWith(u8, path, "/login")) {
            r.setStatus(.ok);
            return r.sendBody(html_login);
        }

        // dashboard
        if (std.mem.eql(u8, path, "/")) {
            r.setStatus(.ok);
            return r.sendBody(html_dashboard);
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

pub fn post(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;
    _ = context;

    // dispatch routes
    if (r.path) |path| {
        if (std.mem.eql(u8, path, "/")) {
            r.setStatus(.ok);
            return r.sendBody(html_dashboard);
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

// unauthorized goes to login page
pub fn unauthorized(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;
    _ = context;
    try r.redirectTo("/login", .unauthorized);
}

pub fn put(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn delete(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn patch(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn options(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
pub fn head(_: *Endpoint, _: Allocator, _: *Context, _: zap.Request) !void {}
