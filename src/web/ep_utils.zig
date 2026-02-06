const std = @import("std");
const zap = @import("zap");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;
const Fj = @import("../fj.zig");
const Format = @import("../format.zig");

const fj_json = @import("../json.zig");
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const Cli = @import("../cli.zig");
const LetterCommand = Cli.LetterCommand;
const OfferCommand = Cli.OfferCommand;
const InvoiceCommand = Cli.InvoiceCommand;
const GitCommand = Cli.GitCommand;

const html_404_not_found = @embedFile("templates/404.html");
const html_head = @embedFile("templates/html_head.html");
const html_nav = @embedFile("templates/html_nav.html");

pub fn sendBody(arena: Allocator, s: []const u8, company: []const u8, r: zap.Request) !void {
    const params = .{
        .head_block = html_head,
        .html_nav = try std.mem.replaceOwned(u8, arena, html_nav, "{{company}}", company),
    };

    const new_body_1 = try std.mem.replaceOwned(u8, arena, s, "<<<", "{{{");
    const new_body_2 = try std.mem.replaceOwned(u8, arena, new_body_1, ">>>", "}}}");

    var mustache = try zap.Mustache.fromData(new_body_2);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return r.sendBody(rendered);
    }
    return error.Mustache;
}

pub const Document = struct {
    type: []const u8,
    id: []const u8,
    client: []const u8,
    project: []const u8,
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

pub const Stats = struct {
    num_invoices_open: isize = 0,
    num_invoices_total: isize = 0,
    num_offers_open: isize = 0,
    num_offers_total: isize = 0,
    invoiced_total_amount: i64 = 0,
    invoices_open_amount: i64 = 0,
    offers_pending_amount: i64 = 0,
    offers_accepted_amount: i64 = 0,
};

pub const YearOption = struct {
    value: []const u8,
    label: []const u8,
    is_current: bool,
};

pub fn show_404(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = createFj(arena, context);
    const fj_config = try fj.loadConfigJson();
    var mustache = try zap.Mustache.fromData(html_404_not_found);
    defer mustache.deinit();
    const result = mustache.build(.{
        .company = fj_config.CompanyName,
        .message = r.path orelse "<unknown>",
    });
    defer result.deinit();

    r.setStatus(.not_found);
    if (result.str()) |rendered| {
        return sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

pub fn createFj(arena: Allocator, context: *Context) Fj {
    const fj: Fj = .{
        .arena = arena,
        .fj_home = context.fj_home,
    };
    return fj;
}

pub fn getBodyStrParam(alloc: Allocator, r: zap.Request, param_name: []const u8) ![]const u8 {
    const fio_params = r.h.*.params;
    const key = zap.fio.fiobj_str_new(param_name.ptr, param_name.len);
    const fio_value = zap.fio.fiobj_hash_get(fio_params, key);

    // this prevents further fiobj_ary_index calls from crashing the server
    // if the param is not present
    if (fio_value == 0) return error.NotFound;

    const elem = zap.fio.fiobj_ary_index(fio_value, 0);
    const string = zap.util.fio2str(elem) orelse return error.NoString;
    return alloc.dupe(u8, string);
}

pub fn getBodyParam(r: zap.Request, param_name: []const u8) !zap.fio.FIOBJ {
    const fio_params = r.h.*.params;
    const key = zap.fio.fiobj_str_new(param_name.ptr, param_name.len);
    const fio_value = zap.fio.fiobj_hash_get(fio_params, key);

    // this prevents further fiobj_ary_index calls from crashing the server
    // if the param is not present
    if (fio_value == 0) return error.NotFound;

    return fio_value;
}

pub fn documentIdFromName(docname: []const u8) ![]const u8 {
    // log.debug("trying to get id from {s}", .{docname});
    var it = std.mem.splitSequence(u8, docname, "--");
    if (it.next() == null) return error.InvalidName;
    if (it.next()) |id| {
        return id;
    }
    return error.InvalidName;
}

pub fn readCurrentYear(arena: Allocator, fj_home: []const u8) ?i32 {
    const file_path = std.fs.path.join(arena, &.{ fj_home, ".current_year" }) catch return null;
    const file = std.fs.cwd().openFile(file_path, .{}) catch return null;
    defer file.close();
    var buf: [16]u8 = undefined;
    const n = file.readAll(&buf) catch return null;
    const content = std.mem.trim(u8, buf[0..n], &.{ ' ', '\n', '\r', '\t' });
    return std.fmt.parseInt(i32, content, 10) catch null;
}

fn collectYearsFromDir(arena: Allocator, base_dir_path: []const u8, human: []const u8, year_set: *std.AutoHashMapUnmanaged(i32, void)) !void {
    var dir = std.fs.cwd().openDir(base_dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.ascii.startsWithIgnoreCase(entry.name, human)) {
            const id = documentIdFromName(entry.name) catch continue;
            if (id.len >= 4) {
                const yr = std.fmt.parseInt(i32, id[0..4], 10) catch continue;
                try year_set.put(arena, yr, {});
            }
        }
    }
}

pub fn collectAvailableYears(arena: Allocator, context: *Context) ![]i32 {
    var fj = createFj(arena, context);
    var year_set = std.AutoHashMapUnmanaged(i32, void).empty;

    inline for (&[_]type{ Invoice, Offer, Letter }) |DocType| {
        const human = Fj.documentTypeHumanName(DocType);
        if (fj.documentBaseDir(DocType)) |base_dir_path| {
            try collectYearsFromDir(arena, base_dir_path, human, &year_set);
        } else |_| {}
    }

    var year_list = std.ArrayListUnmanaged(i32).empty;
    var kit = year_set.keyIterator();
    while (kit.next()) |key| {
        try year_list.append(arena, key.*);
    }
    const years = try year_list.toOwnedSlice(arena);
    std.mem.sort(i32, years, {}, std.sort.desc(i32));
    return years;
}

pub fn buildYearOptions(arena: Allocator, available_years: []const i32, selected_year: ?i32) ![]YearOption {
    var options = std.ArrayListUnmanaged(YearOption).empty;

    for (available_years) |yr| {
        const value = try std.fmt.allocPrint(arena, "{d}", .{yr});
        try options.append(arena, .{
            .value = value,
            .label = value,
            .is_current = if (selected_year) |sy| sy == yr else false,
        });
    }

    // Add "All Years" option
    try options.append(arena, .{
        .value = "all",
        .label = "All Years",
        .is_current = selected_year == null,
    });

    return options.toOwnedSlice(arena);
}

pub fn allDocsAndStats(arena: Allocator, context: *Context, DocumentTypes: []const type, filter_year: ?i32) !struct { documents: []Document, stats: Stats } {
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

        // Filter by year if specified
        const filtered_list = blk: {
            if (filter_year) |yr| {
                var filtered = std.ArrayListUnmanaged([]const u8).empty;
                const year_prefix = try std.fmt.allocPrint(arena, "{d}-", .{yr});
                for (names.list) |name| {
                    const id = documentIdFromName(name) catch continue;
                    if (std.mem.startsWith(u8, id, year_prefix)) {
                        try filtered.append(arena, name);
                    }
                }
                break :blk try filtered.toOwnedSlice(arena);
            }
            break :blk names.list;
        };

        for (filtered_list) |name| {
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
                        stats.num_invoices_total = @intCast(filtered_list.len);
                        stats.invoiced_total_amount += obj.total orelse 0;
                        if (obj.paid_date == null) {
                            stats.num_invoices_open += 1;
                            stats.invoices_open_amount += obj.total orelse 0;
                            break :blk "open";
                        } else {
                            break :blk "paid";
                        }
                    },
                    Offer => {
                        stats.num_offers_total = @intCast(filtered_list.len);
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
                .project = try arena.dupe(u8, obj.project_name),
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
