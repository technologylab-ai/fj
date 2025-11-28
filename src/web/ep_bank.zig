const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const bank = @import("../bank.zig");
const fj_json = @import("../json.zig");
const Fj = @import("../fj.zig");
const format = @import("../format.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.bank_endpoint);

path: []const u8 = "/bank",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const EpBank = @This();
const html_bank = @embedFile("templates/bank.html");

const page_size: usize = 25;

pub fn get(ep: *EpBank, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET bank {s}", .{path});

        if (std.mem.eql(u8, path, ep.path)) {
            return ep.listTransactions(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

pub fn post(ep: *EpBank, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("POST bank {s}", .{path});

        if (std.mem.eql(u8, path, "/bank/upload")) {
            return ep.uploadCsv(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

fn listTransactions(ep: *EpBank, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    var fj = ep_utils.createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    // Load transactions
    var store = bank.TransactionStore.init(arena, context.fj_home);
    const txn_file = store.load() catch fj_json.TransactionsFile{
        .last_updated = "",
        .transactions = &.{},
    };

    // Parse query params
    const page_str = r.getParamSlice("page");
    const page: usize = if (page_str) |ps| std.fmt.parseInt(usize, ps, 10) catch 1 else 1;
    const search_query = r.getParamSlice("q");

    // Import result params (from redirect after upload)
    const imported_str = r.getParamSlice("imported");
    const reconciled_str = r.getParamSlice("reconciled");
    const error_param = r.getParamSlice("error");

    // Filter transactions by search query (case-insensitive)
    var filtered_txns = std.ArrayListUnmanaged(fj_json.Transaction).empty;
    for (txn_file.transactions) |txn| {
        if (search_query) |query| {
            if (query.len > 0 and !matchesSearch(txn, query)) {
                continue;
            }
        }
        try filtered_txns.append(arena, txn);
    }
    const all_txns = filtered_txns.items;
    var sorted_txns = try arena.alloc(fj_json.Transaction, all_txns.len);
    @memcpy(sorted_txns, all_txns);
    std.mem.sort(fj_json.Transaction, sorted_txns, {}, struct {
        fn lessThan(_: void, a: fj_json.Transaction, b: fj_json.Transaction) bool {
            // Sort descending (newest first)
            return std.mem.order(u8, a.date, b.date) == .gt;
        }
    }.lessThan);

    // Pagination
    const total_count = sorted_txns.len;
    const total_pages = if (total_count == 0) 1 else (total_count + page_size - 1) / page_size;
    const current_page = @min(page, total_pages);
    const start_idx = (current_page - 1) * page_size;
    const end_idx = @min(start_idx + page_size, total_count);

    const page_txns = if (start_idx < total_count) sorted_txns[start_idx..end_idx] else &[_]fj_json.Transaction{};

    // Build transaction views
    var txn_views = std.ArrayListUnmanaged(TransactionView).empty;
    for (page_txns) |txn| {
        const amount_display = try formatAmount(arena, txn.amount);
        const is_positive = txn.amount >= 0;

        try txn_views.append(arena, .{
            .date = txn.date,
            .description = txn.description,
            .amount_display = amount_display,
            .is_positive = is_positive,
            .reconciled_invoice = txn.reconciliation.invoice_id,
            .is_reconciled = txn.reconciliation.invoice_id != null,
        });
    }

    // Convert usize to strings for Mustache (avoids isize type issues)
    const total_count_str = try std.fmt.allocPrint(arena, "{d}", .{total_count});
    const page_str_fmt = try std.fmt.allocPrint(arena, "{d}", .{current_page});
    const total_pages_str = try std.fmt.allocPrint(arena, "{d}", .{total_pages});

    // Build pagination URLs (include search query if present)
    const query_suffix = if (search_query) |q|
        (if (q.len > 0) try std.fmt.allocPrint(arena, "&q={s}", .{q}) else "")
    else "";
    const prev_page_url = try std.fmt.allocPrint(arena, "/bank?page={d}{s}", .{
        if (current_page > 1) current_page - 1 else 1,
        query_suffix,
    });
    const next_page_url = try std.fmt.allocPrint(arena, "/bank?page={d}{s}", .{
        if (current_page < total_pages) current_page + 1 else total_pages,
        query_suffix,
    });

    const params = .{
        .transactions = txn_views.items,
        .total_count = total_count_str,
        .page = page_str_fmt,
        .total_pages = total_pages_str,
        .has_pages = total_pages > 1,
        .has_prev = current_page > 1,
        .has_next = current_page < total_pages,
        .prev_page = prev_page_url,
        .next_page = next_page_url,
        .search_query = search_query orelse "",
        .has_search = if (search_query) |q| q.len > 0 else false,
        .imported = imported_str orelse "",
        .has_import_result = imported_str != null,
        .reconciled = reconciled_str orelse "",
        .has_reconciled = reconciled_str != null,
        .error_message = error_param orelse "",
        .has_error = error_param != null,
    };

    var mustache = try zap.Mustache.fromData(html_bank);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

fn uploadCsv(ep: *EpBank, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    try r.parseBody();

    // Get the uploaded file
    const file_param = ep_utils.getBodyParam(r, "csv_file") catch |err| {
        log.err("Failed to get csv_file param: {}", .{err});
        return r.redirectTo("/bank?error=no_file", null);
    };

    var param = zap.Request.fiobj2HttpParam(arena, file_param) catch |err| {
        log.err("fiobj2HttpParam failed: {}", .{err});
        return r.redirectTo("/bank?error=parse_error", null);
    } orelse {
        log.err("fiobj2HttpParam returned null", .{});
        return r.redirectTo("/bank?error=no_file", null);
    };

    const file_data = switch (param) {
        zap.Request.HttpParam.Hash_Binfile => |*file| blk: {
            log.info("Got Hash_Binfile: filename={s}, len={d}", .{
                file.filename orelse "(none)",
                if (file.data) |d| d.len else 0,
            });
            break :blk file.data orelse "";
        },
        zap.Request.HttpParam.Array_Binfile => |*files| blk: {
            log.info("Got Array_Binfile with {d} files", .{files.items.len});
            if (files.items.len > 0) {
                const first = files.items[0];
                break :blk first.data orelse "";
            }
            break :blk "";
        },
        else => |other| {
            log.err("Unexpected param type: {}", .{other});
            return r.redirectTo("/bank?error=invalid_file", null);
        },
    };

    if (file_data.len == 0) {
        return r.redirectTo("/bank?error=empty_file", null);
    }

    // Import the CSV data
    const import_result = importBankCsv(arena, context.fj_home, file_data) catch |err| {
        log.err("Import error: {}", .{err});
        return r.redirectTo("/bank?error=import_failed", null);
    };

    // Redirect with results
    const redirect_url = try std.fmt.allocPrint(
        arena,
        "/bank?imported={d}&reconciled={d}",
        .{ import_result.new_count, import_result.reconciled_count },
    );
    return r.redirectTo(redirect_url, null);
}

const ImportResult = struct {
    new_count: usize,
    reconciled_count: usize,
    matched_invoices: []const bank.MatchedInvoice,
};

fn importBankCsv(arena: Allocator, fj_home: []const u8, content: []const u8) !ImportResult {
    // Convert ISO-8859-1 to UTF-8
    const utf8_content = try bank.latin1ToUtf8(arena, content);

    // Parse with BAWAG parser
    var bawag_parser: bank.BawagParser = .{};
    const p = bawag_parser.parser();
    const result = try p.parse(utf8_content, arena);

    // Load existing transactions
    var store = bank.TransactionStore.init(arena, fj_home);
    const txn_file = try store.load();

    // Deduplicate and add new transactions
    var new_count: usize = 0;
    var new_txns = std.ArrayListUnmanaged(fj_json.Transaction).empty;
    try new_txns.appendSlice(arena, txn_file.transactions);

    // Get current timestamp
    const timestamp: i64 = std.time.timestamp();
    const epoch_secs: u64 = @intCast(timestamp);
    const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const now_str = try std.fmt.allocPrint(arena, "{d}-{d:0>2}-{d:0>2}T00:00:00", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
    });

    for (result.transactions) |parsed| {
        const id = try bank.generateId(arena, parsed.ref_code);

        // Check for duplicates
        var is_dup = false;
        for (txn_file.transactions) |existing| {
            if (std.mem.eql(u8, existing.id, id)) {
                is_dup = true;
                break;
            }
        }
        if (is_dup) continue;

        const txn_type: []const u8 = if (parsed.amount >= 0) "incoming" else "outgoing";

        try new_txns.append(arena, .{
            .id = id,
            .ref_code = parsed.ref_code,
            .date = parsed.date,
            .amount = parsed.amount,
            .currency = parsed.currency,
            .description = parsed.description,
            .counterparty = parsed.counterparty,
            .reference = parsed.reference,
            .@"type" = txn_type,
            .source = .{
                .file = "web-upload",
                .line = parsed.line,
                .imported_at = now_str,
            },
        });
        new_count += 1;
    }

    // Reconciliation
    var reconciled_count: usize = 0;
    var matched_invoices: []const bank.MatchedInvoice = &.{};

    if (new_count > 0) {
        // Load unpaid invoices for reconciliation
        var fj_inst: Fj = .{
            .arena = arena,
            .fj_home = fj_home,
        };
        const unpaid = fj_inst.loadUnpaidInvoices() catch &[_]fj_json.Invoice{};
        if (unpaid.len > 0) {
            const new_txn_slice = new_txns.items[txn_file.transactions.len..];
            const reconcile_result = try bank.reconcileInvoices(
                arena,
                @constCast(new_txn_slice),
                unpaid,
                now_str,
            );
            reconciled_count = reconcile_result.matched_count;
            matched_invoices = reconcile_result.matched_invoices;

            // Mark matched invoices as paid
            for (matched_invoices) |match| {
                fj_inst.markInvoicePaidById(match.invoice_id, match.transaction_date) catch {};
            }
        }

        // Save transactions
        const updated_txns = try new_txns.toOwnedSlice(arena);
        const updated_file: fj_json.TransactionsFile = .{
            .version = 1,
            .last_updated = now_str,
            .account_iban = result.account_iban orelse txn_file.account_iban,
            .transactions = updated_txns,
        };
        try store.save(updated_file);
    }

    return .{
        .new_count = new_count,
        .reconciled_count = reconciled_count,
        .matched_invoices = matched_invoices,
    };
}

fn formatAmount(arena: Allocator, cents: i64) ![]const u8 {
    const euros: f64 = @as(f64, @floatFromInt(cents)) / 100.0;
    var buf: [32]u8 = undefined;
    const formatted = try format.floatThousands(euros, format.Opts.german, &buf);
    const sign: []const u8 = if (cents >= 0) "+" else "";
    return std.fmt.allocPrint(arena, "{s}€{s}", .{ sign, formatted });
}

const TransactionView = struct {
    date: []const u8,
    description: []const u8,
    amount_display: []const u8,
    is_positive: bool,
    reconciled_invoice: ?[]const u8,
    is_reconciled: bool,
};

/// Case-insensitive search across transaction fields
fn matchesSearch(txn: fj_json.Transaction, query: []const u8) bool {
    // Search in description
    if (containsIgnoreCase(txn.description, query)) return true;

    // Search in reference
    if (txn.reference) |ref| {
        if (containsIgnoreCase(ref, query)) return true;
    }

    // Search in counterparty name
    if (txn.counterparty.name) |name| {
        if (containsIgnoreCase(name, query)) return true;
    }

    // Search in counterparty IBAN
    if (txn.counterparty.iban) |iban| {
        if (containsIgnoreCase(iban, query)) return true;
    }

    // Search in date
    if (containsIgnoreCase(txn.date, query)) return true;

    // Search in reconciled invoice ID
    if (txn.reconciliation.invoice_id) |inv_id| {
        if (containsIgnoreCase(inv_id, query)) return true;
    }

    return false;
}

/// Case-insensitive substring search
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = haystack[i + j];
            if (std.ascii.toLower(hc) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}
