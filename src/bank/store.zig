const std = @import("std");
const json = @import("../json.zig");
const format = @import("../format.zig");
const fsutil = @import("../fsutil.zig");

const Allocator = std.mem.Allocator;
const cwd = std.fs.cwd;
const path = std.fs.path;

pub const TransactionStore = struct {
    arena: Allocator,
    fj_home: []const u8,

    const transactions_rel_path = "bank/transactions.json";
    const imports_rel_path = "bank/imports";
    const max_file_size = 50 * 1024 * 1024; // 50MB

    pub fn init(arena: Allocator, fj_home: []const u8) TransactionStore {
        return .{ .arena = arena, .fj_home = fj_home };
    }

    /// Load existing transactions (or empty if file doesn't exist)
    pub fn load(self: *TransactionStore) !json.TransactionsFile {
        const full_path = try path.join(self.arena, &.{ self.fj_home, transactions_rel_path });

        var file = cwd().openFile(full_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Return empty transactions file
                return .{
                    .last_updated = "",
                    .transactions = &.{},
                };
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.arena, max_file_size);

        return std.json.parseFromSliceLeaky(json.TransactionsFile, self.arena, content, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            std.log.err("Error parsing transactions.json: {}", .{err});
            return err;
        };
    }

    /// Save transactions to file
    pub fn save(self: *TransactionStore, data: json.TransactionsFile) !void {
        // Ensure bank/ directory exists
        const bank_dir = try path.join(self.arena, &.{ self.fj_home, "bank" });
        cwd().makePath(bank_dir) catch {};

        const full_path = try path.join(self.arena, &.{ self.fj_home, transactions_rel_path });

        const file = cwd().createFile(full_path, .{}) catch |err| {
            std.log.err("Error creating {s}: {}", .{ full_path, err });
            return err;
        };
        defer file.close();

        // Use buffered writer for performance
        var io_buffer: [4096]u8 = undefined;
        var writer = file.writer(&io_buffer);
        std.json.Stringify.value(data, .{ .whitespace = .indent_4 }, &writer.interface) catch |err| {
            std.log.err("Error writing transactions.json: {}", .{err});
            return err;
        };
        writer.interface.flush() catch |err| {
            std.log.err("Error flushing transactions.json: {}", .{err});
            return err;
        };
    }

    /// Check if transaction ID already exists
    pub fn exists(self: *const TransactionStore, txns: json.TransactionsFile, id: []const u8) bool {
        _ = self;
        for (txns.transactions) |t| {
            if (std.mem.eql(u8, t.id, id)) return true;
        }
        return false;
    }

    /// Archive imported CSV file to bank/imports/YYYY-MM-DD_filename.csv
    pub fn archiveImport(self: *TransactionStore, source_path: []const u8, today: []const u8) !void {
        // Ensure bank/imports/ directory exists
        const imports_dir = try path.join(self.arena, &.{ self.fj_home, imports_rel_path });
        cwd().makePath(imports_dir) catch {};

        // Get original filename
        const filename = path.basename(source_path);

        // Create archive filename: YYYY-MM-DD_original.csv
        const archive_name = try std.fmt.allocPrint(self.arena, "{s}_{s}", .{ today, filename });
        const archive_path = try path.join(self.arena, &.{ imports_dir, archive_name });

        // Copy file
        cwd().copyFile(source_path, cwd(), archive_path, .{}) catch |err| {
            std.log.warn("Could not archive CSV to {s}: {}", .{ archive_path, err });
            return err;
        };
    }

    /// Get all unique categories from transactions
    pub fn getCategories(self: *const TransactionStore, txns: json.TransactionsFile) ![]const []const u8 {
        var categories = std.StringHashMap(void).init(self.arena);
        defer categories.deinit();

        for (txns.transactions) |t| {
            if (t.category) |cat| {
                try categories.put(cat, {});
            }
        }

        var result = std.ArrayListUnmanaged([]const u8).empty;
        var it = categories.keyIterator();
        while (it.next()) |key| {
            try result.append(self.arena, key.*);
        }
        return result.toOwnedSlice(self.arena);
    }
};

/// Summary statistics for transactions
pub const TransactionSummary = struct {
    count: usize,
    total_incoming: i64,
    total_outgoing: i64,
    net: i64,
};

/// Calculate summary for a slice of transactions
pub fn calculateSummary(transactions: []const json.Transaction) TransactionSummary {
    var incoming: i64 = 0;
    var outgoing: i64 = 0;

    for (transactions) |t| {
        if (t.amount >= 0) {
            incoming += t.amount;
        } else {
            outgoing += t.amount;
        }
    }

    return .{
        .count = transactions.len,
        .total_incoming = incoming,
        .total_outgoing = outgoing,
        .net = incoming + outgoing,
    };
}

/// Filter transactions by date range and type
pub fn filterTransactions(
    arena: Allocator,
    transactions: []const json.Transaction,
    from: ?[]const u8,
    to: ?[]const u8,
    type_filter: ?[]const u8,
) ![]const json.Transaction {
    var filtered = std.ArrayListUnmanaged(json.Transaction).empty;

    for (transactions) |t| {
        // Date range filter
        if (from) |from_date| {
            if (std.mem.order(u8, t.date, from_date) == .lt) continue;
        }
        if (to) |to_date| {
            if (std.mem.order(u8, t.date, to_date) == .gt) continue;
        }
        // Type filter
        if (type_filter) |tf| {
            if (!std.mem.eql(u8, tf, "all") and !std.mem.eql(u8, t.@"type", tf)) continue;
        }
        try filtered.append(arena, t);
    }

    return filtered.toOwnedSlice(arena);
}

/// Monthly summary for group_by=month
pub const MonthlySummary = struct {
    month: []const u8,
    incoming: i64,
    outgoing: i64,
    net: i64,
    count: usize,
};

/// Group transactions by month
pub fn groupByMonth(arena: Allocator, transactions: []const json.Transaction) ![]const MonthlySummary {
    var months = std.StringHashMap(MonthlySummary).init(arena);

    for (transactions) |t| {
        // Extract YYYY-MM from date
        if (t.date.len >= 7) {
            const month_key = t.date[0..7];

            const entry = try months.getOrPut(month_key);
            if (!entry.found_existing) {
                entry.value_ptr.* = .{
                    .month = try arena.dupe(u8, month_key),
                    .incoming = 0,
                    .outgoing = 0,
                    .net = 0,
                    .count = 0,
                };
            }

            if (t.amount >= 0) {
                entry.value_ptr.incoming += t.amount;
            } else {
                entry.value_ptr.outgoing += t.amount;
            }
            entry.value_ptr.net += t.amount;
            entry.value_ptr.count += 1;
        }
    }

    // Convert to sorted slice
    var result = std.ArrayListUnmanaged(MonthlySummary).empty;
    var it = months.valueIterator();
    while (it.next()) |v| {
        try result.append(arena, v.*);
    }

    // Sort by month
    std.mem.sort(MonthlySummary, result.items, {}, struct {
        fn lessThan(_: void, a: MonthlySummary, b: MonthlySummary) bool {
            return std.mem.order(u8, a.month, b.month) == .lt;
        }
    }.lessThan);

    return result.toOwnedSlice(arena);
}

test "calculateSummary" {
    const txns = [_]json.Transaction{
        .{
            .id = "1",
            .ref_code = "VD/1",
            .date = "2025-01-01",
            .amount = 10000,
            .currency = "EUR",
            .description = "Income",
            .@"type" = "incoming",
            .source = .{ .file = "test.csv", .line = 1, .imported_at = "2025-01-01" },
        },
        .{
            .id = "2",
            .ref_code = "FE/1",
            .date = "2025-01-02",
            .amount = -5000,
            .currency = "EUR",
            .description = "Expense",
            .@"type" = "outgoing",
            .source = .{ .file = "test.csv", .line = 2, .imported_at = "2025-01-01" },
        },
    };

    const summary = calculateSummary(&txns);
    try std.testing.expectEqual(@as(usize, 2), summary.count);
    try std.testing.expectEqual(@as(i64, 10000), summary.total_incoming);
    try std.testing.expectEqual(@as(i64, -5000), summary.total_outgoing);
    try std.testing.expectEqual(@as(i64, 5000), summary.net);
}
