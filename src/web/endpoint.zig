const std = @import("std");
const zap = @import("zap");
const Fj = @import("../fj.zig");
const Cli = @import("../cli.zig");
const Git = @import("../git.zig");
const fj_json = @import("../json.zig");
const Context = @import("context.zig");
const Format = @import("../format.zig");
const fsutil = @import("../fsutil.zig");
const util = @import("util.zig");
const Fatal = @import("../fatal.zig");
const Version = @import("../version.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @This();

const log = std.log.scoped(.endpoint);

// Login:
// ------
// GET     /                            Login form
// GET     /logo.png                    Logo

// Dashboard:
// ----------
// GET     /                            Dashboard
// POST    /                            Dashboard right after login
//

// Resources:
// ----------
//
// type: client | rate
//
// GET     /<type>                      <type> Overview page
// GET     /<type>/view/:shortname      <type> viewer
// GET     /<type>/edit/:shortname      <type> editor
// POST    /<type>/commit/:shortname    -> Back to dashboard
// POST    /<type>/new/:shortname       <type> editor
//

// Documents:
// ----------
//
// type: letter | offer | invoice
//
// GET     /<type>                      <type> Overview HTML page
// POST    /<type>/new                  Show editor for compilation: -> redirect to /<type>/compile/:new-id (if redirect uses /get)
// GET     /<type>/edit/:id             Show editor editable=true, compile=true

// GET     /<type>/view/:id             Show editor editable=false, compile=false
// POST    /<type>/commit/:id           Show editor editable=true, compile=false
// POST    /<type>/compile/:id          Show editor editable=true, compile=true
// GET     /<type>/new/:id              Show editor editable=true, compile=true
//
// GET     /<type>/pdf/:id              Show PDF from fj_home
// GET     /<type>/draftpdf/:id         Show PDF from workdir
//

// Git:
// ----
//
// GET     /git/commit                  Show git command result page
// GET     /git/push                    Show git command result page

const Client = fj_json.Client;
const Rate = fj_json.Rate;
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const ClientCommand = Cli.ClientCommand;
const RateCommand = Cli.RateCommand;
const LetterCommand = Cli.LetterCommand;
const OfferCommand = Cli.OfferCommand;
const InvoiceCommand = Cli.InvoiceCommand;
const GitCommand = Cli.GitCommand;

const html_login = @embedFile("templates/login.html");
const html_dashboard = @embedFile("templates/dashboard.html");
const html_404_not_found = "<html><body><h1>404 - Not found!</h1></body></html";
const html_git_command = @embedFile("templates/git_command.html");
const html_resource_editor = @embedFile("templates/resource_editor.html");
const html_resource_list = @embedFile("templates/resource_list.html");
const html_document_list = @embedFile("templates/document_list.html");
const html_document_editor = @embedFile("templates/document_editor.html");
const html_error = @embedFile("templates/error.html");

// the slug
path: []const u8,
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

//
// helpers

fn createFj(arena: Allocator, context: *Context) Fj {
    const fj: Fj = .{
        .arena = arena,
        .fj_home = context.fj_home,
    };
    return fj;
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
            return ep.resource_list(arena, context, r, Client);
        }
        if (std.mem.startsWith(u8, path, "/client/view/") and
            path.len > "/client/view/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                Client,
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
                Client,
                path["/client/edit/".len..],
                true,
            );
        }

        // rates
        if (std.mem.eql(u8, path, "/rate")) {
            r.setStatus(.ok);
            return ep.resource_list(arena, context, r, Rate);
        }
        if (std.mem.startsWith(u8, path, "/rate/view/") and
            path.len > "/rate/view/".len)
        {
            r.setStatus(.ok);
            return ep.resource_view(
                arena,
                context,
                r,
                Rate,
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
                Rate,
                path["/rate/edit/".len..],
                true,
            );
        }

        // invoices
        if (std.mem.eql(u8, path, "/invoice")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, Invoice);
        }

        if (std.mem.startsWith(u8, path, "/invoice/view/") and
            path.len > "/invoice/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                Invoice,
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
                Invoice,
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
                Invoice,
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
                Invoice,
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
                Invoice,
                path["/invoice/draftpdf/".len..],
            );
        }

        // offers
        if (std.mem.eql(u8, path, "/offer")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, Offer);
        }

        if (std.mem.startsWith(u8, path, "/offer/view/") and
            path.len > "/offer/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                Offer,
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
                Offer,
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
                Offer,
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
                Offer,
                path["/offer/draftpdf/".len..],
            );
        }

        // letters
        if (std.mem.eql(u8, path, "/letter")) {
            r.setStatus(.ok);
            return ep.document_list(arena, context, r, Letter);
        }
        if (std.mem.startsWith(u8, path, "/letter/view/") and
            path.len > "/letter/view/".len)
        {
            r.setStatus(.ok);
            return ep.document_view(
                arena,
                context,
                r,
                Letter,
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
                Letter,
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
                Letter,
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
                Letter,
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

fn allDocsAndStats(_: *Endpoint, arena: Allocator, context: *Context, DocumentTypes: []const type) !struct { documents: []Document, stats: Stats } {
    var doc_list = std.ArrayListUnmanaged(Document).empty;
    var stats: Stats = .{};

    var fj = createFj(arena, context);

    inline for (DocumentTypes) |DocumentType| {
        const Command = switch (DocumentType) {
            Invoice => InvoiceCommand,
            Offer => OfferCommand,
            Letter => LetterCommand,
            else => unreachable,
        };

        const listCommand: Command = .{
            .positional = .{ .subcommand = .list },
        };
        const names = try fj.cmdListDocuments(listCommand);

        for (names.list) |name| {
            const id = try documentIdFromName(name);
            const show_cli: Command = .{
                .positional = .{ .subcommand = .show, .arg = id },
            };
            const files = try fj.cmdShowDocument(show_cli);
            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                files.show.json,
                .{},
            );

            const status: []const u8 = blk: {
                switch (DocumentType) {
                    Invoice => {
                        stats.num_invoices_total = @intCast(names.list.len);
                        stats.invoiced_total_amount += obj.total orelse 0;
                        if (obj.paid_date == null) {
                            stats.num_invoices_open += 1;
                            break :blk "open";
                        } else {
                            break :blk "paid";
                        }
                    },
                    Offer => {
                        stats.num_offers_total = @intCast(names.list.len);
                        if (obj.accepted_date == null) {

                            // check if it's pending or declined
                            if (obj.declined_date != null) {
                                break :blk "declined";
                            }

                            stats.num_offers_open += 1;
                            stats.offers_pending_amount += obj.total orelse 0;
                            break :blk "open";
                        } else {
                            stats.offers_accepted_amount += obj.total orelse 0;
                            break :blk "accepted";
                        }
                    },
                    Letter => break :blk "",
                    else => unreachable,
                }
            };

            const amount = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                } else {
                    break :blk try Format.floatThousandsAlloc(
                        arena,
                        @as(f32, @floatFromInt(obj.total orelse 0)),
                        .{ .comma = ',', .sep = '.' },
                    );
                }
            };

            const doc_type = Fj.documentTypeHumanName(DocumentType);

            const document: Document = .{
                .type = try arena.dupe(u8, doc_type),
                .id = try arena.dupe(u8, id),
                .client = try arena.dupe(u8, obj.client_shortname),
                .date = try arena.dupe(u8, obj.date),
                .sort_date = try arena.dupe(u8, obj.updated),
                .status = try arena.dupe(u8, status),
                .amount = try arena.dupe(u8, amount),
            };

            try doc_list.append(arena, document);
        }
    }

    return .{ .documents = try doc_list.toOwnedSlice(arena), .stats = stats };
}

fn show_dashboard(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = createFj(arena, context);
    const year = try fj.year();
    const fj_config = try fj.loadConfigJson();

    const docs_and_stats = try ep.allDocsAndStats(arena, context, &.{ Invoice, Offer, Letter });
    const stats = docs_and_stats.stats;

    std.mem.sort(Document, docs_and_stats.documents, {}, Document.greaterThan);
    const recent_documents = docs_and_stats.documents[0..@min(docs_and_stats.documents.len, 5)]; // cap at 5

    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };

    var git_status_alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.status(git_status_alist.writer(arena).any());

    const params = .{
        .recent_docs = recent_documents,
        .currency_symbol = fj_config.CurrencySymbol,
        .invoices_total = stats.num_invoices_total,
        .invoices_open = stats.num_invoices_open,
        .offers_total = stats.num_offers_total,
        .offers_open = stats.num_offers_open,
        .git_status = git_status_alist.items,
        .invoiced_total = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.invoiced_total_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .offers_accepted_amount = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.offers_accepted_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .offers_pending_amount = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.offers_pending_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .year = year,
        .company = fj_config.CompanyName,
        .version = Version.version(),
        .fj_home = fj.fj_home.?,
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

    var fj = createFj(arena, context);
    log.debug("fj_home: {s}", .{fj.fj_home.?});

    const type_string, const CliCommand = switch (ResourceType) {
        Client => .{ "client", ClientCommand },
        Rate => .{ "rate", RateCommand },
        else => unreachable,
    };

    const resources = blk: {
        var list = std.ArrayListUnmanaged(ListItem).empty;

        // 1. get all the clients / rates
        const list_cli: CliCommand = .{
            .positional = .{ .subcommand = .list },
        };

        const names = try fj.handleRecordCommand(list_cli);
        for (names.list) |shortname| {
            log.debug("trying to load {} {s} {s}", .{ ResourceType, type_string, shortname });
            const obj = try fj.loadRecord(ResourceType, try arena.dupe(u8, shortname), .{ .custom_path = null });
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

    const fj_config = try fj.loadConfigJson();
    const params = .{
        .type = type_string,
        .resources = resources,
        .company = fj_config.CompanyName,
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
    var fj = createFj(arena, context);
    log.debug("fj_home: {s}", .{fj.fj_home.?});

    const type_string = switch (ResourceType) {
        Client => "client",
        Rate => "rate",
        else => unreachable,
    };

    const obj = try fj.loadRecord(
        ResourceType,
        try arena.dupe(u8, id),
        .{ .custom_path = null },
    );

    var alist: std.ArrayListUnmanaged(u8) = .empty;
    const writer = alist.writer(arena);
    try std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer);

    const fj_config = try fj.loadConfigJson();
    const params = .{
        .type = type_string,
        .shortname = id,
        .json = alist.items,
        .editable = editable,
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_resource_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_list(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type) !void {
    var fj = createFj(arena, context);
    const year = try fj.year();
    const fj_config = try fj.loadConfigJson();

    const doc_type = Fj.documentTypeHumanName(DocumentType);
    const docs_and_stats = try ep.allDocsAndStats(arena, context, &.{DocumentType});
    std.mem.sort(Document, docs_and_stats.documents, {}, Document.greaterThan);

    const params = .{
        .type = doc_type,
        .documents = docs_and_stats.documents,
        .currency_symbol = fj_config.CurrencySymbol,
        .year = year,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_document_list);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn toDocument(_: *Endpoint, arena: Allocator, obj: anytype, files: Fj.DocumentFileContents) !Document {
    const DocumentType = @TypeOf(obj);
    const doc_type = Fj.documentTypeHumanName(DocumentType);
    const status: []const u8 = blk: {
        switch (DocumentType) {
            Invoice => {
                if (obj.paid_date == null) {
                    break :blk "open";
                } else {
                    break :blk "paid";
                }
            },
            Offer => {
                if (obj.accepted_date == null) {
                    break :blk "open";
                } else {
                    break :blk "accepted";
                }
            },
            Letter => break :blk "",
            else => unreachable,
        }
    };

    const amount = blk: {
        if (DocumentType == Letter) {
            break :blk "";
        } else {
            break :blk try Format.floatThousandsAlloc(
                arena,
                @as(f32, @floatFromInt(obj.total orelse 0)),
                .{ .comma = ',', .sep = '.' },
            );
        }
    };

    return .{
        .type = doc_type,
        .id = obj.id,
        .client = obj.client_shortname,
        .date = obj.date,
        .sort_date = obj.updated,
        .status = status,
        .amount = amount,
        .json = files.json,
        .billables = files.billables,
        .tex = files.tex,
    };
}
fn document_view(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    const doc_type = Fj.documentTypeHumanName(DocumentType);
    const Command = switch (DocumentType) {
        Invoice => InvoiceCommand,
        Offer => OfferCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const command: Command = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };

    const files = try fj.cmdShowDocument(command);

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.show.json,
        .{},
    );

    const document = try ep.toDocument(arena, obj, files.show);

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fj_config.CurrencySymbol,
        .editable = false,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = false,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
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

    sort_date: []const u8,

    json: []const u8 = "",
    billables: []const u8 = "",
    tex: []const u8 = "",

    pub fn lessThan(ctx: void, a: @This(), b: @This()) bool {
        _ = ctx;
        return std.mem.order(u8, a.sort_date, b.sort_date) == .lt;
    }

    pub fn greaterThan(ctx: void, a: @This(), b: @This()) bool {
        _ = ctx;
        return std.mem.order(u8, a.sort_date, b.sort_date) == .gt;
    }
};

const Stats = struct {
    num_invoices_open: isize = 0,
    num_invoices_total: isize = 0,
    num_offers_open: isize = 0,
    num_offers_total: isize = 0,
    invoiced_total_amount: usize = 0,
    offers_pending_amount: usize = 0,
    offers_accepted_amount: usize = 0,
};

fn document_edit(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, DocumentType: type, id: []const u8) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    const document_subdir_name = try fj.findDocumentById(DocumentType, id);
    const document_dir_path = try std.fs.path.join(arena, &.{ context.work_dir, document_subdir_name });
    // we are in workdir
    if (fsutil.isDirPresent(document_dir_path)) {
        // delete it!
        try std.fs.cwd().deleteTree(document_dir_path);
    }

    const doc_type = Fj.documentTypeHumanName(DocumentType);

    const Command = switch (DocumentType) {
        Invoice => InvoiceCommand,
        Offer => OfferCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const command: Command = .{
        .positional = .{ .subcommand = .checkout, .arg = id },
    };

    const files = try fj.cmdCheckoutDocument(command);

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.checkout.json,
        .{},
    );

    const document = try ep.toDocument(arena, obj, files.checkout);

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fj_config.CurrencySymbol,
        .editable = true,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_new(
    ep: *Endpoint,
    arena: Allocator,
    context: *Context,
    r: zap.Request,
    DocumentType: type,
) !void {
    var fj = createFj(arena, context);

    // get the files passed in from the browser
    try r.parseBody();

    const client = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("client", "client".len);
        const fio_client = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_client, 0);
        const client = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk client;
    };

    const rates = blk: {
        if (DocumentType == Letter) {
            break :blk "";
        }
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("rates", "rates".len);
        const fio_rates = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_rates, 0);
        const rates = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk rates;
    };

    const project = blk: {
        if (DocumentType == Letter) {
            break :blk "";
        }
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("project", "project".len);
        const fio_project = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_project, 0);
        const project = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk project;
    };

    const doc_type = Fj.documentTypeHumanName(DocumentType);

    const expected_path = try std.fmt.allocPrint(
        arena,
        "{s}--{d}-XXX--{s}",
        .{ doc_type, try fj.year(), client },
    );
    if (fsutil.isDirPresent(expected_path)) {
        // delete it
        try std.fs.cwd().deleteTree(expected_path);
    }

    const Command = switch (DocumentType) {
        Invoice => InvoiceCommand,
        Offer => OfferCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const command: Command = blk: {
        if (DocumentType == Letter) {
            break :blk .{
                // .positional = .{ .subcommand = .new, .arg = client },
                .positional = .{ .subcommand = .new, .arg = client },
            };
        } else {
            break :blk .{
                .positional = .{ .subcommand = .new, .arg = client },
                .rates = rates,
                .project = project,
            };
        }
    };

    const result = fj.cmdCreateNewDocument(command) catch |err| {
        const message = try std.fmt.allocPrint(
            arena,
            "{}:\n{s}",
            .{ err, Fatal.errormsg },
        );
        var mustache = try zap.Mustache.fromData(html_error);
        defer mustache.deinit();
        const fj_config = try fj.loadConfigJson();
        const result = mustache.build(
            .{ .message = message, .company = fj_config.CompanyName },
        );
        defer result.deinit();

        if (result.str()) |rendered| {
            return try r.sendBody(rendered);
        } else {
            return;
        }
        return;
    };

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        result.new.files.json,
        .{},
    );

    const document = try ep.toDocument(arena, obj, result.new.files);
    const fj_config = try fj.loadConfigJson();

    // const document_name_instead_of_id = try std.fmt.allocPrint(
    //     arena,
    //     "{s}--{s}--{s}",
    //     .{ doc_type, document.id, document.client },
    // );
    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fj_config.CurrencySymbol,
        .editable = true,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_document_editor);
    defer mustache.deinit();
    const mustache_result = mustache.build(params);
    defer mustache_result.deinit();

    if (mustache_result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn document_compile(
    ep: *Endpoint,
    arena: Allocator,
    context: *Context,
    r: zap.Request,
    DocumentType: type,
    id: []const u8,
) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();
    const doc_type = Fj.documentTypeHumanName(DocumentType);
    const document_subdir_name = try fj.findDocumentById(DocumentType, id);

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
        if (DocumentType == Letter) {
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

    // now save them
    var cwd = std.fs.cwd();
    const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
    const billables_filename = "billables.csv";
    const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

    var json_file = try cwd.createFile(json_filename, .{});
    defer json_file.close();
    try json_file.writeAll(json);

    if (DocumentType != Letter) {
        var billables_file = try cwd.createFile(billables_filename, .{});
        defer billables_file.close();
        try billables_file.writeAll(billables);
    }

    var tex_file = try cwd.createFile(tex_filename, .{});
    defer tex_file.close();
    try tex_file.writeAll(tex);

    const CompileCommand = switch (DocumentType) {
        Invoice => InvoiceCommand,
        Offer => OfferCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const compileCommand: CompileCommand = .{
        .positional = .{ .subcommand = .compile },
    };

    const files = fj.cmdCompileDocument(compileCommand) catch |err| {
        // show error
        const message = try std.fmt.allocPrint(
            arena,
            "Error: {}\n\n{s}",
            .{ err, Fatal.errormsg },
        );

        var mustache = try zap.Mustache.fromData(html_error);
        defer mustache.deinit();
        const result = mustache.build(.{
            .message = message,
            .company = fj_config.CompanyName,
        });
        defer result.deinit();

        if (result.str()) |rendered| {
            return try r.sendBody(rendered);
        } else {
            return;
        }
    };

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.compile.json,
        .{},
    );

    const document = try ep.toDocument(arena, obj, files.compile);

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fj_config.CurrencySymbol,
        .editable = true,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
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
    ep: *Endpoint,
    arena: Allocator,
    context: *Context,
    r: zap.Request,
    DocumentType: type,
    id: []const u8,
) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();
    const document_subdir_name = try fj.findDocumentById(DocumentType, id);

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
        if (DocumentType == Letter) {
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

    const doc_type = Fj.documentTypeHumanName(DocumentType);

    // now save them
    var cwd = std.fs.cwd();
    const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
    const billables_filename = "billables.csv";
    const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

    var json_file = try cwd.createFile(json_filename, .{});
    defer json_file.close();
    try json_file.writeAll(json);

    if (DocumentType != Letter) {
        var billables_file = try cwd.createFile(billables_filename, .{});
        defer billables_file.close();
        try billables_file.writeAll(billables);
    }

    var tex_file = try cwd.createFile(tex_filename, .{});
    defer tex_file.close();
    try tex_file.writeAll(tex);

    const CommitCommand = switch (DocumentType) {
        Invoice => InvoiceCommand,
        Offer => OfferCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const commitCommand: CommitCommand = .{
        .force = true,
        .positional = .{ .subcommand = .commit },
    };

    const files = try fj.cmdCommitDocument(commitCommand);

    const obj = try std.json.parseFromSliceLeaky(
        DocumentType,
        arena,
        files.commit.json,
        .{},
    );

    const document = try ep.toDocument(arena, obj, files.commit);

    const params = .{
        .type = doc_type,
        .document = document,
        .currency_symbol = fj_config.CurrencySymbol,
        .editable = false,
        .json = document.json,
        .billables = document.billables,
        .tex = document.tex,
        .id = document.id,
        .compile = true,
        .is_letter = DocumentType == Letter,
        .company = fj_config.CompanyName,
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
    var fj = createFj(arena, context);

    const document_base = try fj.documentBaseDir(DocumentType);

    const human_doctype = Fj.documentTypeHumanName(DocumentType);

    const document_dir_name = blk: {
        if (Fj.startsWithIC(id, human_doctype)) {
            break :blk id;
        } else {
            break :blk try fj.findDocumentById(DocumentType, id);
        }
    };

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
    var fj = createFj(arena, context);

    log.debug("document_draft_pdf called with id {s}", .{id});

    const document_subdir_name = try fj.findDocumentById(DocumentType, id);

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
    if (fsutil.fileExists(pdf_path)) {
        try r.sendFile(pdf_path);
    } else {
        try r.sendBody(try std.fmt.allocPrint(arena, "{s} not found", .{pdf_path}));
    }
}

fn git_push(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };
    var fj = createFj(arena, context);
    var alist = std.ArrayListUnmanaged(u8).empty;
    _ = try git.push(alist.writer(arena).any());

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "push",
        .message = alist.items,
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn git_commit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };
    var fj = createFj(arena, context);
    var alist = std.ArrayListUnmanaged(u8).empty;
    const writer = alist.writer(arena).any();
    if (try git.stage(.all, writer)) {
        _ = try git.commit("Committed via web", writer);
    }

    const fj_config = try fj.loadConfigJson();

    const params = .{
        .command = "commit",
        .message = alist.items,
        .company = fj_config.CompanyName,
    };
    var mustache = try zap.Mustache.fromData(html_git_command);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

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

        // /client/new
        if (std.mem.eql(u8, path, "/client/new")) {
            return ep.resource_new(
                arena,
                context,
                r,
                Client,
            );
        }

        // /client/commit/:shortname
        if (std.mem.startsWith(u8, path, "/client/commit/") and
            path.len > "/client/commit/".len)
        {
            return ep.resource_commit(
                arena,
                context,
                r,
                Client,
                path["/client/commit/".len..],
            );
        }

        // /rate/new
        if (std.mem.eql(u8, path, "/rate/new")) {
            return ep.resource_new(
                arena,
                context,
                r,
                Rate,
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
                Rate,
                path["/rate/commit/".len..],
            );
        }

        // /invoice/new/:shortname
        if (std.mem.eql(u8, path, "/invoice/new")) {
            return ep.document_new(
                arena,
                context,
                r,
                Invoice,
            );
        }

        // /offer/new/:shortname
        if (std.mem.eql(u8, path, "/offer/new")) {
            return ep.document_new(
                arena,
                context,
                r,
                Offer,
            );
        }

        // /letter/new/:shortname
        if (std.mem.eql(u8, path, "/letter/new")) {
            return ep.document_new(
                arena,
                context,
                r,
                Letter,
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
                Invoice,
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
                Offer,
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
                Letter,
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
                Invoice,
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
                Offer,
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
                Letter,
                path["/letter/commit/".len..],
            );
        }
    }

    r.setStatus(.not_found);
    try r.sendBody(html_404_not_found);
}

fn resource_new(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, ResourceType: type) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();
    log.debug("fj_home: {s}", .{fj.fj_home.?});

    const type_string = switch (ResourceType) {
        Client => "client",
        Rate => "rate",
        else => unreachable,
    };

    try r.parseBody();

    const shortname = blk: {
        const fio_params = r.h.*.params;
        const key = zap.fio.fiobj_str_new("shortname", "shortname".len);
        const fio_shortname = zap.fio.fiobj_hash_get(fio_params, key);

        const elem = zap.fio.fiobj_ary_index(fio_shortname, 0);
        const shortname = zap.util.fio2str(elem) orelse return error.NoString;
        break :blk shortname;
    };

    const expected_filename = try std.fmt.allocPrint(arena, "{s}.json", .{shortname});
    if (fsutil.fileExists(expected_filename)) {
        const message = try std.fmt.allocPrint(
            arena,
            "Error: {s} {s} already exists!",
            .{ type_string, shortname },
        );

        var mustache = try zap.Mustache.fromData(html_error);
        defer mustache.deinit();
        const result = mustache.build(.{
            .message = message,
            .company = fj_config.CompanyName,
        });
        defer result.deinit();

        if (result.str()) |rendered| {
            return try r.sendBody(rendered);
        } else {
            return;
        }
    }

    const Command = switch (ResourceType) {
        Client => ClientCommand,
        Rate => RateCommand,
        Letter => LetterCommand,
        else => unreachable,
    };

    const command: Command = .{
        .positional = .{ .subcommand = .new, .arg = shortname },
    };

    _ = try fj.handleRecordCommand(command);

    const obj = try fj.loadRecord(
        ResourceType,
        try arena.dupe(u8, shortname),
        .{ .custom_path = "." },
    );

    var alist: std.ArrayListUnmanaged(u8) = .empty;
    const writer = alist.writer(arena);
    try std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer);

    const params = .{
        .type = type_string,
        .shortname = shortname,
        .json = alist.items,
        .editable = true,
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_resource_editor);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        try r.sendBody(rendered);
    }
}

fn resource_commit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, ResourceType: type, shortname: []const u8) !void {
    var fj = createFj(arena, context);

    try r.parseBody();
    if (r.body) |body| {
        log.debug("BODY: `{s}`", .{body});
    }

    const json = blk: {
        const fio_params = r.h.*.params;
        log.debug("type of params = {s}", .{util.fiobj_type(r.h.*.params)});

        const param_count = zap.fio.fiobj_hash_count(fio_params);
        log.debug("param_count = {d}", .{param_count});

        const key = zap.fio.fiobj_str_new("json", "json".len);
        const fio_json = zap.fio.fiobj_hash_get(fio_params, key);
        log.debug("fio_json = {s}", .{util.fiobj_type(fio_json)});

        const elem = zap.fio.fiobj_ary_index(fio_json, 0);
        log.debug("elem = {s}", .{util.fiobj_type(elem)});
        const json = zap.util.fio2str(elem) orelse return error.NoString;
        log.debug("json = {s}", .{json});
        break :blk json;
    };

    var path_buf: [Fj.max_path_bytes]u8 = undefined;
    const new_revision = blk: {
        const json_path = try fj.recordPath(ResourceType, shortname, null, &path_buf);
        if (fsutil.fileExists(json_path)) {
            const existing = try fj.loadRecord(ResourceType, shortname, .{});
            break :blk existing.revision + 1;
        } else {
            break :blk 0;
        }
    };

    // now parse the specified one
    var obj = try std.json.parseFromSliceLeaky(ResourceType, arena, json, .{});
    obj.revision = new_revision;
    obj.updated = try fj.isoTime();

    // and write it into fj_home
    _ = try fj.writeRecord(shortname, obj, .{ .allow_overwrite = true });
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
