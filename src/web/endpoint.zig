const std = @import("std");
const zap = @import("zap");
const Fi = @import("../fi.zig");
const Cli = @import("../cli.zig");
const Git = @import("../git.zig");
const fi_json = @import("../json.zig");
const Context = @import("context.zig");
const Format = @import("../format.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @This();

const log = std.log.scoped(.endpoint);

// Login:
// ------
// GET     /                           HTML: Login HTML
// GET     /logo.png                    PNG: The logo.png

// Dashboard:
// ----------
// GET     /                           HTML: Dashboard HMTL
//
// API:
//
// GET     /git/push                   JSON: push archive

// Resources:
// ----------
// GET     /client                      HTML: Client Overview HTML page
// GET     /rate                        HTML: Client Overview HTML page
// GET     /client/view/:id             HTML: Client viewer
// GET     /rate/view/:id               HTML: Rate viewer
// GET     /client/edit/:id             HTML: Client editor
// GET     /rate/edit/:id               HTML: Rate editor
// GET     /rate/new                    HTML: New Rate editor
// GET     /client/new                  HTML: New Client editor
// POST    /client/:shortname/commit    HTML: Replace client JSON
// POST    /rate/:shortname/commit      HTML: Replace client JSON
//

// Documents:
// ----------
//
// GET     /letter                     HTML: Offer Overview HTML page
// GET     /offer                      HTML: Offer Overview HTML page
// GET     /invoice                    HTML: Offer Overview HTML page
// GET     /offer/edit/:id             HTML: Show editor
// GET     /offer/view/:id             HTML: Show editor READONLY
//
// API:
//
// GET     /offer/list                 JSON: List all offers
// GET     /offer/new                  JSON: Create new offer
// GET     /offer/:id/offer.json       JSON: Return raw offer JSON
// POST    /offer/:id/offer.json       JSON: Replace offer JSON
// GET     /offer/:id/billables.csv     CSV: Return raw CSV
// POST    /offer/:id/billables.csv    JSON: Replace CSV
// POST    /offer/:id/compile          JSON: Compile offer
// POST    /offer/:id/commit           JSON: Finalize + commit
// GET     /offer/:id/pdf               PDF: Return compiled PDF

const html_login = @embedFile("templates/login.html");
const html_dashboard = @embedFile("templates/dashboard.html");
const html_404_not_found = "<html><body><h1>404 - Not found!</h1></body></html";
const html_git_push = @embedFile("templates/git_push.html");
const html_resource_editor = @embedFile("templates/resource_editor.html");
const html_resource_list = @embedFile("templates/resource_list.html");

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
            return ep.show_dashboard(arena, context, r);
        }

        // git push
        if (std.mem.eql(u8, path, "/git/push")) {
            r.setStatus(.ok);
            return ep.git_push(arena, context, r);
        }

        // clients
        if (std.mem.eql(u8, path, "/client")) {
            r.setStatus(.ok);
            return ep.resource_list(arena, context, r, fi_json.Client);
        }

        // rates
        if (std.mem.eql(u8, path, "/rate")) {
            r.setStatus(.ok);
            return ep.resource_list(arena, context, r, fi_json.Rate);
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

fn documentIdFromName(docname: []const u8) ![]const u8 {
    var it = std.mem.splitSequence(u8, docname, "--");
    if (it.next() == null) return error.InvalidName;
    if (it.next()) |id| {
        return id;
    }
    return error.InvalidName;
}

fn show_dashboard(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const RecentDocument = struct {
        type: []const u8,
        id: []const u8,
        client: []const u8,
        date: []const u8,
        status: []const u8,
        amount: []const u8,

        pub fn lessThan(ctx: void, a: @This(), b: @This()) bool {
            _ = ctx;
            return std.mem.order(u8, a.date, b.date) == .lt;
        }

        pub fn greaterThan(ctx: void, a: @This(), b: @This()) bool {
            _ = ctx;
            return std.mem.order(u8, a.date, b.date) == .gt;
        }
    };

    var fi = createFi(arena, context);
    const year = try fi.year();
    const fi_config = try fi.loadConfigJson();

    var num_invoices_open: isize = 0;
    var num_invoices_total: isize = 0;
    var num_offers_open: isize = 0;
    var num_offers_total: isize = 0;

    var invoiced_total_amount: usize = 0;

    const recent_documents = blk: {
        var recent_document_list = std.ArrayListUnmanaged(RecentDocument).empty;

        // 1. get all the invoices
        const invoices_cli: Cli.InvoiceCommand = .{
            .positional = .{ .subcommand = .list },
        };
        const invoice_names = try fi.cmdListDocuments(invoices_cli);
        num_invoices_total = @intCast(invoice_names.list.len);
        for (invoice_names.list) |invoice_name| {
            const id = try documentIdFromName(invoice_name);
            const show_cli: Cli.InvoiceCommand = .{
                .positional = .{ .subcommand = .show, .arg = id },
            };
            const invoice_files = try fi.cmdShowDocument(show_cli);
            const obj = try std.json.parseFromSliceLeaky(
                fi_json.Invoice,
                arena,
                invoice_files.show.json,
                .{},
            );

            invoiced_total_amount += obj.total orelse 0;

            const status = status_blk: {
                if (obj.paid_date == null) {
                    num_invoices_open += 1;
                    break :status_blk "open";
                } else {
                    break :status_blk "paid";
                }
            };
            try recent_document_list.append(arena, .{
                // we don't dup() them because of the arena
                .type = "invoice",
                .id = obj.id,
                .client = obj.client_shortname,
                .date = obj.updated[0..10],
                .status = status,
                .amount = try Format.floatThousandsAlloc(
                    arena,
                    @as(f32, @floatFromInt(obj.total orelse 0)),
                    .{ .comma = ',', .sep = '.' },
                ),
            });
        }

        // 2. get all the offers
        const offers_cli: Cli.OfferCommand = .{
            .positional = .{ .subcommand = .list },
        };
        const offer_names = try fi.cmdListDocuments(offers_cli);
        num_offers_total = @intCast(offer_names.list.len);
        for (offer_names.list) |offer_name| {
            const id = try documentIdFromName(offer_name);
            const show_cli: Cli.OfferCommand = .{
                .positional = .{ .subcommand = .show, .arg = id },
            };
            const offer_files = try fi.cmdShowDocument(show_cli);
            const obj = try std.json.parseFromSliceLeaky(
                fi_json.Offer,
                arena,
                offer_files.show.json,
                .{},
            );

            const status = status_blk: {
                if (obj.accepted_date == null) {
                    num_offers_open += 1;
                    break :status_blk "open";
                } else {
                    break :status_blk "accepted";
                }
            };
            try recent_document_list.append(arena, .{
                // we don't dup() them because of the arena
                .type = "offer",
                .id = obj.id,
                .client = obj.client_shortname,
                .date = obj.updated[0..10],
                .status = status,
                .amount = try Format.floatThousandsAlloc(
                    arena,
                    @as(f32, @floatFromInt(obj.total orelse 0)),
                    .{ .comma = ',', .sep = '.' },
                ),
            });
        }

        // 3. get all the letters
        const letters_cli: Cli.LetterCommand = .{
            .positional = .{ .subcommand = .list },
        };
        const letter_names = try fi.cmdListDocuments(letters_cli);
        for (letter_names.list) |letter_name| {
            const id = try documentIdFromName(letter_name);
            const show_cli: Cli.LetterCommand = .{
                .positional = .{ .subcommand = .show, .arg = id },
            };
            const letter_files = try fi.cmdShowDocument(show_cli);
            const obj = try std.json.parseFromSliceLeaky(
                fi_json.Letter,
                arena,
                letter_files.show.json,
                .{},
            );

            try recent_document_list.append(arena, .{
                // we don't dup() them because of the arena
                .type = "letter",
                .id = obj.id,
                .client = obj.client_shortname,
                .date = obj.updated[0..10],
                .status = "",
                .amount = "",
            });
        }

        // 5. sort them descendingly by date

        const unsorted = try recent_document_list.toOwnedSlice(arena);
        std.mem.sort(RecentDocument, unsorted, {}, RecentDocument.greaterThan);

        // 6. cap them at 5
        break :blk unsorted[0..@min(unsorted.len, 5)];
    };

    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fi_home,
    };

    var git_status_alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.status(git_status_alist.writer(arena).any());

    const params = .{
        .recent_docs = recent_documents,
        .currency_symbol = fi_config.CurrencySymbol,
        .invoices_total = num_invoices_total,
        .invoices_open = num_invoices_open,
        .offers_total = num_offers_total,
        .offers_open = num_offers_open,
        .git_status = git_status_alist.items,
        .invoiced_total = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(invoiced_total_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .year = year,
    };

    var mustache = try zap.Mustache.fromData(html_dashboard);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn resource_list(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, ResourceType: type) !void {
    const ListItem = struct {
        shortname: []const u8,
        remarks: []const u8,

        pub fn lessThan(ctx: void, a: @This(), b: @This()) bool {
            _ = ctx;
            return std.mem.order(u8, a.shortname, b.shortname) == .lt;
        }

        pub fn greaterThan(ctx: void, a: @This(), b: @This()) bool {
            _ = ctx;
            return std.mem.order(u8, a.shortname, b.shortname) == .gt;
        }
    };

    var fi = createFi(arena, context);
    log.debug("fi_home: {s}", .{fi.fi_home.?});

    const type_string, const CliCommand = switch (ResourceType) {
        fi_json.Client => .{ "client", Cli.ClientCommand },
        fi_json.Rate => .{ "rate", Cli.RateCommand },
        else => unreachable,
    };

    const resources = blk: {
        var list = std.ArrayListUnmanaged(ListItem).empty;

        // 1. get all the clients / rates
        const list_cli: CliCommand = .{
            .positional = .{ .subcommand = .list },
        };

        const names = try fi.handleRecordCommand(list_cli);
        for (names.list) |shortname| {
            log.debug("trying to load {} {s} {s}", .{ ResourceType, type_string, shortname });
            const obj = try fi.loadRecord(ResourceType, try arena.dupe(u8, shortname), .{ .custom_path = null });
            try list.append(arena, .{
                // we don't dup() them because of the arena
                .shortname = obj.shortname,
                .remarks = obj.remarks orelse "",
            });
        }

        // 2. sort them descendingly by date
        const sorted = try list.toOwnedSlice(arena);
        std.mem.sort(ListItem, sorted, {}, ListItem.lessThan);

        break :blk sorted;
    };

    const params = .{
        .type = type_string,
        .resources = resources,
    };
    var mustache = try zap.Mustache.fromData(html_resource_list);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn git_push(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fi_home,
    };

    var alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.push(alist.writer(arena).any());

    const params = .{
        .message = alist.items,
    };
    var mustache = try zap.Mustache.fromData(html_git_push);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

pub fn post(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {

    // dispatch routes
    if (r.path) |path| {
        if (std.mem.eql(u8, path, "/")) {
            r.setStatus(.ok);
            return ep.show_dashboard(arena, context, r);
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
