const std = @import("std");
const zap = @import("zap");
const Fi = @import("../fi.zig");
const Cli = @import("../cli.zig");
const Git = @import("../git.zig");
const fi_json = @import("../json.zig");
const Context = @import("context.zig");
const Format = @import("../format.zig");
const fsutil = @import("../fsutil.zig");

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
// GET     /offer/new                  HTML: Show editor
// GET     /offer/edit/:id             HTML: Show editor
// GET     /offer/view/:id             HTML: Show editor READONLY
// GET     /offer/pdf/:id              Show PDF
//

const html_login = @embedFile("templates/login.html");
const html_dashboard = @embedFile("templates/dashboard.html");
const html_404_not_found = "<html><body><h1>404 - Not found!</h1></body></html";
const html_git_command = @embedFile("templates/git_command.html");
const html_resource_editor = @embedFile("templates/resource_editor.html");
const html_resource_list = @embedFile("templates/resource_list.html");
const html_document_list = @embedFile("templates/document_list.html");
const html_document_editor = @embedFile("templates/document_editor.html");

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

        // git commit
        if (std.mem.eql(u8, path, "/git/commit")) {
            r.setStatus(.ok);
            return ep.git_commit(arena, context, r);
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
        if (std.mem.startsWith(u8, path, "/client/view/") and
            path.len > "/client/view/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                fi_json.Client,
                path["/client/view/".len..],
                false,
            );
        }
        if (std.mem.startsWith(u8, path, "/client/edit/") and
            path.len > "/client/edit/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                fi_json.Client,
                path["/client/edit/".len..],
                true,
            );
        }

        // rates
        if (std.mem.eql(u8, path, "/rate")) {
            r.setStatus(.ok);
            return ep.resource_list(arena, context, r, fi_json.Rate);
        }
        if (std.mem.startsWith(u8, path, "/rate/view/") and
            path.len > "/rate/view/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                fi_json.Rate,
                path["/rate/view/".len..],
                false,
            );
        }
        if (std.mem.startsWith(u8, path, "/rate/edit/") and
            path.len > "/rate/edit/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                fi_json.Rate,
                path["/rate/edit/".len..],
                true,
            );
        }

        // invoices
        if (std.mem.eql(u8, path, "/invoice")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, fi_json.Invoice);
        }

        if (std.mem.startsWith(u8, path, "/invoice/view/") and
            path.len > "/invoice/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/view/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/invoice/edit/") and
            path.len > "/invoice/edit/".len)
        {
            r.setStatus(.ok);
            return ep.document_edit(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/edit/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/invoice/edit/") and
            path.len > "/invoice/edit/".len)
        {
            r.setStatus(.ok);
            return ep.document_edit(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/edit/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/invoice/pdf/") and
            path.len > "/invoice/pdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_pdf(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/pdf/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/invoice/draftpdf/") and
            path.len > "/invoice/draftpdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_draft_pdf(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/draftpdf/".len..],
            );
        }

        // offers
        if (std.mem.eql(u8, path, "/offer")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, fi_json.Offer);
        }

        if (std.mem.startsWith(u8, path, "/offer/view/") and
            path.len > "/offer/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/view/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/offer/edit/") and
            path.len > "/offer/edit/".len)
        {
            r.setStatus(.ok);
            return ep.document_edit(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/edit/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/offer/pdf/") and
            path.len > "/offer/pdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_pdf(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/pdf/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/offer/draftpdf/") and
            path.len > "/offer/draftpdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_draft_pdf(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/draftpdf/".len..],
            );
        }

        // letters
        if (std.mem.eql(u8, path, "/letter")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, fi_json.Letter);
        }
        if (std.mem.startsWith(u8, path, "/letter/view/") and
            path.len > "/letter/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/view/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/letter/edit/") and
            path.len > "/letter/edit/".len)
        {
            r.setStatus(.ok);
            return ep.document_edit(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/edit/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/letter/pdf/") and
            path.len > "/letter/pdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_pdf(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/pdf/".len..],
            );
        }
        if (std.mem.startsWith(u8, path, "/letter/draftpdf/") and
            path.len > "/letter/draftpdf/".len)
        {
            r.setStatus(.ok);
            return ep.document_draft_pdf(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/draftpdf/".len..],
            );
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

fn documentIdFromName(docname: []const u8) ![]const u8 {
    log.debug("trying to get id from {s}", .{docname});
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

    var recent_document_list = std.ArrayListUnmanaged(RecentDocument).empty;
    const recent_documents = blk: {

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

fn resource_view(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, ResourceType: type, id: []const u8, editable: bool) !void {
    var fi = createFi(arena, context);
    log.debug("fi_home: {s}", .{fi.fi_home.?});

    const type_string = switch (ResourceType) {
        fi_json.Client => "client",
        fi_json.Rate => "rate",
        else => unreachable,
    };

    const obj = try fi.loadRecord(
        ResourceType,
        try arena.dupe(u8, id),
        .{ .custom_path = null },
    );

    var alist: std.ArrayListUnmanaged(u8) = .empty;
    const writer = alist.writer(arena);
    try std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer);

    const params = .{
        .type = type_string,
        .shortname = id,
        .json = alist.items,
        .editable = editable,
    };

    var mustache = try zap.Mustache.fromData(html_resource_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_list(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type) !void {
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

    var doc_type: []const u8 = undefined; // hack
    const documents = blk: {
        var recent_document_list = std.ArrayListUnmanaged(RecentDocument).empty;

        switch (DocumentType) {
            fi_json.Invoice => {
                doc_type = "invoice";
                const invoices_cli: Cli.InvoiceCommand = .{
                    .positional = .{ .subcommand = .list },
                };
                const invoice_names = try fi.cmdListDocuments(invoices_cli);
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

                    const status = status_blk: {
                        if (obj.paid_date == null) {
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
            },

            fi_json.Offer => {
                doc_type = "offer";
                const offers_cli: Cli.OfferCommand = .{
                    .positional = .{ .subcommand = .list },
                };
                const offer_names = try fi.cmdListDocuments(offers_cli);
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
            },

            fi_json.Letter => {
                doc_type = "letter";
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
            },
            else => unreachable,
        }

        const sorted = try recent_document_list.toOwnedSlice(arena);
        std.mem.sort(RecentDocument, sorted, {}, RecentDocument.greaterThan);
        break :blk sorted;
    };

    const params = .{
        .type = doc_type,
        .documents = documents,
        .currency_symbol = fi_config.CurrencySymbol,
        .year = year,
    };

    var mustache = try zap.Mustache.fromData(html_document_list);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_view(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fi = createFi(arena, context);
    const fi_config = try fi.loadConfigJson();

    var doc_type: []const u8 = undefined; // hack

    const document: Document = blk: {
        switch (DocumentType) {
            fi_json.Invoice => {
                doc_type = "invoice";
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

                const status = status_blk: {
                    if (obj.paid_date == null) {
                        break :status_blk "open";
                    } else {
                        break :status_blk "paid";
                    }
                };
                break :blk .{
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
                    .json = invoice_files.show.json,
                    .billables = invoice_files.show.billables,
                    .tex = invoice_files.show.tex,
                };
            },

            fi_json.Offer => {
                doc_type = "offer";
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
                        break :status_blk "open";
                    } else {
                        break :status_blk "accepted";
                    }
                };
                break :blk .{
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
                    .json = offer_files.show.json,
                    .billables = offer_files.show.billables,
                    .tex = offer_files.show.tex,
                };
            },

            fi_json.Letter => {
                doc_type = "letter";
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

                break :blk .{
                    // we don't dup() them because of the arena
                    .type = "letter",
                    .id = obj.id,
                    .client = obj.client_shortname,
                    .date = obj.updated[0..10],
                    .status = "",
                    .amount = "",
                    .json = letter_files.show.json,
                    .billables = letter_files.show.billables,
                    .tex = letter_files.show.tex,
                };
            },
            else => unreachable,
        }
    };

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fi_config.CurrencySymbol,
        .editable = false,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = false,
        .is_letter = DocumentType == fi_json.Letter,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

const Document = struct {
    type: []const u8,
    id: []const u8,
    client: []const u8,
    date: []const u8,
    status: []const u8,
    amount: []const u8,

    json: []const u8,
    billables: []const u8,
    tex: []const u8,
};

fn document_edit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fi = createFi(arena, context);
    const fi_config = try fi.loadConfigJson();

    const document_subdir_name = try fi.findDocumentById(DocumentType, id);
    const document_dir_path = try std.fs.path.join(arena, &.{ context.work_dir, document_subdir_name });
    // we are in workdir
    if (fsutil.isDirPresent(document_dir_path)) {
        // delete it!
        try std.fs.cwd().deleteTree(document_dir_path);
    }

    const document: Document = blk: {
        switch (DocumentType) {
            fi_json.Invoice => {
                const checkout_cli: Cli.InvoiceCommand = .{
                    .positional = .{ .subcommand = .checkout, .arg = id },
                };
                const invoice_files = try fi.cmdCheckoutDocument(checkout_cli);
                const obj = try std.json.parseFromSliceLeaky(
                    fi_json.Invoice,
                    arena,
                    invoice_files.checkout.json,
                    .{},
                );

                const status = status_blk: {
                    if (obj.paid_date == null) {
                        break :status_blk "open";
                    } else {
                        break :status_blk "paid";
                    }
                };
                break :blk .{
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
                    .json = invoice_files.checkout.json,
                    .billables = invoice_files.checkout.billables,
                    .tex = invoice_files.checkout.tex,
                };
            },

            fi_json.Offer => {
                const checkout_cli: Cli.OfferCommand = .{
                    .positional = .{ .subcommand = .checkout, .arg = id },
                };
                const offer_files = try fi.cmdCheckoutDocument(checkout_cli);
                const obj = try std.json.parseFromSliceLeaky(
                    fi_json.Offer,
                    arena,
                    offer_files.checkout.json,
                    .{},
                );

                const status = status_blk: {
                    if (obj.accepted_date == null) {
                        break :status_blk "open";
                    } else {
                        break :status_blk "accepted";
                    }
                };
                break :blk .{
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
                    .json = offer_files.checkout.json,
                    .billables = offer_files.checkout.billables,
                    .tex = offer_files.checkout.tex,
                };
            },

            fi_json.Letter => {
                const checkout_cli: Cli.LetterCommand = .{
                    .positional = .{ .subcommand = .checkout, .arg = id },
                };
                const letter_files = try fi.cmdCheckoutDocument(checkout_cli);
                const obj = try std.json.parseFromSliceLeaky(
                    fi_json.Letter,
                    arena,
                    letter_files.checkout.json,
                    .{},
                );

                break :blk .{
                    // we don't dup() them because of the arena
                    .type = "letter",
                    .id = obj.id,
                    .client = obj.client_shortname,
                    .date = obj.updated[0..10],
                    .status = "",
                    .amount = "",
                    .json = letter_files.checkout.json,
                    .billables = letter_files.checkout.billables,
                    .tex = letter_files.checkout.tex,
                };
            },
            else => unreachable,
        }
    };

    const doc_type = Fi.documentTypeHumanName(DocumentType);

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fi_config.CurrencySymbol,
        .editable = true,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == fi_json.Letter,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_compile(
    _: *Endpoint,
    arena: Allocator,
    context: *Context,
    r: zap.Request,
    DocumentType: type,
    id: []const u8,
) !void {
    var fi = createFi(arena, context);
    const fi_config = try fi.loadConfigJson();
    const document_subdir_name = try fi.findDocumentById(DocumentType, id);

    // cd into the subdir
    log.debug("Current dir is {s}", .{try std.process.getCwdAlloc(arena)});
    log.debug("Trying to change into {s}", .{document_subdir_name});
    try std.process.changeCurDir(document_subdir_name);
    defer {
        std.process.changeCurDir(context.work_dir) catch |err| std.process.fatal("Cannot change to work_dir {s}: {}!!!", .{ context.work_dir, err });
    }

    // get the files passed in from the browser
    try r.parseBody();

    const json = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("json", "json".len);
        const fio_json = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_json, 0);
        const json = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk json;
    };

    const billables = blk: {
        if (DocumentType == fi_json.Letter) {
            break :blk "";
        }
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("billables", "billables".len);
        const fio_billables = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_billables, 0);
        const billables = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk billables;
    };

    const tex = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("tex", "tex".len);
        const fio_tex = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_tex, 0);
        const tex = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk tex;
    };

    const doc_type = Fi.documentTypeHumanName(DocumentType);

    // now save them
    var cwd = std.fs.cwd();
    const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
    const billables_filename = "billables.csv";
    const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

    var json_file = try cwd.createFile(json_filename, .{});
    defer json_file.close();
    try json_file.writeAll(json);

    if (DocumentType != fi_json.Letter) {
        var billables_file = try cwd.createFile(billables_filename, .{});
        defer billables_file.close();
        try billables_file.writeAll(billables);
    }

    var tex_file = try cwd.createFile(tex_filename, .{});
    defer tex_file.close();
    try tex_file.writeAll(tex);

    const CompileCommand = switch (DocumentType) {
        fi_json.Invoice => Cli.InvoiceCommand,
        fi_json.Offer => Cli.OfferCommand,
        fi_json.Letter => Cli.LetterCommand,
        else => unreachable,
    };

    const compileCommand: CompileCommand = .{
        .positional = .{ .subcommand = .compile },
    };

    const files = try fi.cmdCompileDocument(compileCommand);

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.compile.json,
        .{},
    );

    const status: []const u8 = blk: {
        switch (DocumentType) {
            fi_json.Invoice => {
                if (obj.paid_date == null) {
                    break :blk "open";
                } else {
                    break :blk "paid";
                }
            },
            fi_json.Offer => {
                if (obj.accepted_date == null) {
                    break :blk "open";
                } else {
                    break :blk "accepted";
                }
            },
            fi_json.Letter => break :blk "",
            else => unreachable,
        }
    };

    const amount = blk: {
        if (DocumentType == fi_json.Letter) {
            break :blk "";
        } else {
            break :blk try Format.floatThousandsAlloc(
                arena,
                @as(f32, @floatFromInt(obj.total orelse 0)),
                .{ .comma = ',', .sep = '.' },
            );
        }
    };

    const document: Document = .{
        .type = doc_type,
        .id = id,
        .client = obj.client_shortname,
        .date = obj.updated[0..10],
        .status = status,
        .amount = amount,
        .json = files.compile.json,
        .billables = files.compile.billables,
        .tex = files.compile.tex,
    };

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fi_config.CurrencySymbol,
        .editable = true,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == fi_json.Letter,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_commit(
    _: *Endpoint,
    arena: Allocator,
    context: *Context,
    r: zap.Request,
    DocumentType: type,
    id: []const u8,
) !void {
    var fi = createFi(arena, context);
    const fi_config = try fi.loadConfigJson();
    const document_subdir_name = try fi.findDocumentById(DocumentType, id);

    // cd into the subdir
    log.debug("Current dir is {s}", .{try std.process.getCwdAlloc(arena)});
    log.debug("Trying to change into {s}", .{document_subdir_name});
    try std.process.changeCurDir(document_subdir_name);
    defer {
        std.process.changeCurDir(context.work_dir) catch |err| std.process.fatal("Cannot change to work_dir {s}: {}!!!", .{ context.work_dir, err });
    }

    // get the files passed in from the browser
    try r.parseBody();

    const json = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("json", "json".len);
        const fio_json = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_json, 0);
        const json = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk json;
    };

    const billables = blk: {
        if (DocumentType == fi_json.Letter) {
            break :blk "";
        }
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("billables", "billables".len);
        const fio_billables = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_billables, 0);
        const billables = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk billables;
    };

    const tex = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("tex", "tex".len);
        const fio_tex = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_tex, 0);
        const tex = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk tex;
    };

    const doc_type = Fi.documentTypeHumanName(DocumentType);

    // now save them
    var cwd = std.fs.cwd();
    const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
    const billables_filename = "billables.csv";
    const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

    var json_file = try cwd.createFile(json_filename, .{});
    defer json_file.close();
    try json_file.writeAll(json);

    if (DocumentType != fi_json.Letter) {
        var billables_file = try cwd.createFile(billables_filename, .{});
        defer billables_file.close();
        try billables_file.writeAll(billables);
    }

    var tex_file = try cwd.createFile(tex_filename, .{});
    defer tex_file.close();
    try tex_file.writeAll(tex);

    const CommitCommand = switch (DocumentType) {
        fi_json.Invoice => Cli.InvoiceCommand,
        fi_json.Offer => Cli.OfferCommand,
        fi_json.Letter => Cli.LetterCommand,
        else => unreachable,
    };

    const commitCommand: CommitCommand = .{
        .force = true,
        .positional = .{ .subcommand = .commit },
    };

    const files = try fi.cmdCommitDocument(commitCommand);

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.commit.json,
        .{},
    );

    const status: []const u8 = blk: {
        switch (DocumentType) {
            fi_json.Invoice => {
                if (obj.paid_date == null) {
                    break :blk "open";
                } else {
                    break :blk "paid";
                }
            },
            fi_json.Offer => {
                if (obj.accepted_date == null) {
                    break :blk "open";
                } else {
                    break :blk "accepted";
                }
            },
            fi_json.Letter => break :blk "",
            else => unreachable,
        }
    };

    const amount = blk: {
        if (DocumentType == fi_json.Letter) {
            break :blk "";
        } else {
            break :blk try Format.floatThousandsAlloc(
                arena,
                @as(f32, @floatFromInt(obj.total orelse 0)),
                .{ .comma = ',', .sep = '.' },
            );
        }
    };

    const document: Document = .{
        .type = doc_type,
        .id = id,
        .client = obj.client_shortname,
        .date = obj.updated[0..10],
        .status = status,
        .amount = amount,
        .json = files.commit.json,
        .billables = files.commit.billables,
        .tex = files.commit.tex,
    };

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fi_config.CurrencySymbol,
        .editable = false,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == fi_json.Letter,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_pdf(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fi = createFi(arena, context);

    const document_base = try fi.documentBaseDir(DocumentType);

    const human_doctype = Fi.documentTypeHumanName(DocumentType);

    const document_dir_name = blk: {
        if (Fi.startsWithIC(id, human_doctype)) {
            break :blk id;
        } else {
            break :blk try fi.findDocumentById(DocumentType, id);
        }
    };

    // Linux XDG_OPEN || macos open || windows: explorer.exe?
    const pdf_filename = try std.fmt.allocPrint(
        arena,
        "{s}.pdf",
        .{document_dir_name},
    );
    const pdf_path = try std.fs.path.join(
        arena,
        &[_][]const u8{ document_base, document_dir_name, pdf_filename },
    );
    log.info("Opening {s}", .{pdf_path});

    try r.setHeader("Cache-Control", "no-store");
    try r.sendFile(pdf_path);
}

fn document_draft_pdf(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fi = createFi(arena, context);
    const document_subdir_name = try fi.findDocumentById(DocumentType, id);

    // Linux XDG_OPEN || macos open || windows: explorer.exe?
    const pdf_filename = try std.fmt.allocPrint(
        arena,
        "{s}.pdf",
        .{document_subdir_name},
    );
    const pdf_path = try std.fs.path.join(
        arena,
        &[_][]const u8{ document_subdir_name, pdf_filename },
    );
    log.info("Opening {s}", .{pdf_path});

    try r.setHeader("Cache-Control", "no-store");
    try r.sendFile(pdf_path);
}

fn git_push(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fi_home,
    };

    var alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.push(alist.writer(arena).any());

    const params = .{
        .command = "push",
        .message = alist.items,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
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

fn git_commit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fi_home,
    };

    var alist = std.ArrayListUnmanaged(u8).empty;
    const writer = alist.writer(arena).any();
    if (try git.stage(.all, writer)) {
        _ = try git.commit("Committed via web", writer);
    }

    const params = .{
        .command = "commit",
        .message = alist.items,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
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

        // /client/commit/:shortname
        if (std.mem.startsWith(u8, path, "/client/commit/") and
            path.len > "/client/commit/".len)
        {
            return ep.resource_commit(
                arena,
                context,
                r,
                fi_json.Client,
                path["/client/commit/".len..],
            );
        }

        // /rate/commit/:shortname
        if (std.mem.startsWith(u8, path, "/rate/commit/") and
            path.len > "/rate/commit/".len)
        {
            return ep.resource_commit(
                arena,
                context,
                r,
                fi_json.Rate,
                path["/rate/commit/".len..],
            );
        }

        // /invoice/compile/:shortname
        if (std.mem.startsWith(u8, path, "/invoice/compile/") and
            path.len > "/invoice/compile/".len)
        {
            return ep.document_compile(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/compile/".len..],
            );
        }

        // /offer/compile/:shortname
        if (std.mem.startsWith(u8, path, "/offer/compile/") and
            path.len > "/offer/compile/".len)
        {
            return ep.document_compile(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/compile/".len..],
            );
        }

        // /letter/compile/:shortname
        if (std.mem.startsWith(u8, path, "/letter/compile/") and
            path.len > "/letter/compile/".len)
        {
            return ep.document_compile(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/compile/".len..],
            );
        }

        // /invoice/commit/:shortname
        if (std.mem.startsWith(u8, path, "/invoice/commit/") and
            path.len > "/invoice/commit/".len)
        {
            return ep.document_commit(
                arena,
                context,
                r,
                fi_json.Invoice,
                path["/invoice/commit/".len..],
            );
        }

        // /offer/commit/:shortname
        if (std.mem.startsWith(u8, path, "/offer/commit/") and
            path.len > "/offer/commit/".len)
        {
            return ep.document_commit(
                arena,
                context,
                r,
                fi_json.Offer,
                path["/offer/commit/".len..],
            );
        }

        // /letter/commit/:shortname
        if (std.mem.startsWith(u8, path, "/letter/commit/") and
            path.len > "/letter/commit/".len)
        {
            return ep.document_commit(
                arena,
                context,
                r,
                fi_json.Letter,
                path["/letter/commit/".len..],
            );
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

fn fiobj_type(o: zap.fio.FIOBJ) []const u8 {
    const value_type = switch (zap.fio.fiobj_type(o)) {
        zap.fio.FIOBJ_T_NULL => "null",
        zap.fio.FIOBJ_T_TRUE => "true",
        zap.fio.FIOBJ_T_FALSE => "false",
        zap.fio.FIOBJ_T_NUMBER => "number",
        zap.fio.FIOBJ_T_FLOAT => "float",
        zap.fio.FIOBJ_T_STRING => "string",
        zap.fio.FIOBJ_T_ARRAY => "array",
        zap.fio.FIOBJ_T_HASH => "hash",
        zap.fio.FIOBJ_T_DATA => "data",
        zap.fio.FIOBJ_T_UNKNOWN => "unknown",
        else => "shit",
    };
    return value_type;
}
const CallbackContext_KV = struct {
    allocator: Allocator,
    params: *std.ArrayList(zap.Request.HttpParamKV),
    last_error: ?anyerror = null,

    pub fn callback(fiobj_value: zap.fio.FIOBJ, context_: ?*anyopaque) callconv(.C) c_int {
        const ctx: *@This() = @as(*@This(), @ptrCast(@alignCast(context_)));
        // this is thread-safe, guaranteed by fio
        const fiobj_key: zap.fio.FIOBJ = zap.fio.fiobj_hash_key_in_loop();
        log.debug("value_type = {s}", .{fiobj_type(fiobj_value)});
        ctx.params.append(.{
            .key = zap.util.fio2strAlloc(ctx.allocator, fiobj_key) catch |err| {
                ctx.last_error = err;
                return -1;
            },
            .value = zap.Request.fiobj2HttpParam(ctx.allocator, fiobj_value) catch |err| {
                ctx.last_error = err;
                return -1;
            },
        }) catch |err| {
            // what to do?
            // signal the caller that an error occured by returning -1
            // also, set the error
            ctx.last_error = err;
            return -1;
        };
        return 0;
    }
};

fn resource_commit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, ResourceType: type, shortname: []const u8) !void {
    var fi = createFi(arena, context);

    try r.parseBody();
    if (r.body) |body| {
        log.debug("BODY: `{s}`", .{body});
    }

    const json = blk: {
        const fio_params = r.h.*.params;
        log.debug("type of params = {s}", .{fiobj_type(r.h.*.params)});

        const param_count = zap.fio.fiobj_hash_count(fio_params);
        log.debug("param_count = {d}", .{param_count});

        const key = zap.fio.fiobj_str_new("json", "json".len);
        const fio_json = zap.fio.fiobj_hash_get(fio_params, key);
        log.debug("fio_json = {s}", .{fiobj_type(fio_json)});

        const elem = zap.fio.fiobj_ary_index(fio_json, 0);
        log.debug("elem = {s}", .{fiobj_type(elem)});
        const json = zap.util.fio2str(elem) orelse return error.NoString;
        log.debug("json = {s}", .{json});
        break :blk json;
    };

    var path_buf: [Fi.max_path_bytes]u8 = undefined;
    const new_revision = blk: {
        const json_path = try fi.recordPath(ResourceType, shortname, null, &path_buf);
        if (fsutil.fileExists(json_path)) {
            const existing = try fi.loadRecord(ResourceType, shortname, .{});
            break :blk existing.revision + 1;
        } else {
            break :blk 0;
        }
    };

    // now parse the specified one
    var obj = try std.json.parseFromSliceLeaky(ResourceType, arena, json, .{});
    obj.revision = new_revision;
    obj.updated = try fi.isoTime();

    // and write it into fi_home
    _ = try fi.writeRecord(shortname, obj, .{ .allow_overwrite = true });
    try r.redirectTo("/", null);
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
