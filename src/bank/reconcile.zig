const std = @import("std");
const fj_json = @import("../json.zig");
const Allocator = std.mem.Allocator;

pub const ReconcileResult = struct {
    matched_count: usize,
    matched_invoices: []const MatchedInvoice,
};

pub const MatchedInvoice = struct {
    invoice_id: []const u8,
    transaction_id: []const u8,
    transaction_date: []const u8, // YYYY-MM-DD from bank statement
    amount_euros: i64,
};

/// Reconcile incoming transactions with unpaid invoices
/// Supports multi-invoice payments: if transaction mentions multiple invoice IDs
/// and their totals sum to the transaction amount, all are marked as paid.
pub fn reconcile(
    arena: Allocator,
    transactions: []fj_json.Transaction,
    unpaid_invoices: []const fj_json.Invoice,
    now: []const u8,
) !ReconcileResult {
    var matched = std.ArrayListUnmanaged(MatchedInvoice).empty;

    for (transactions) |*txn| {
        // Skip if already reconciled or outgoing
        if (txn.reconciliation.invoice_id != null) continue;
        if (txn.amount <= 0) continue;

        // Combine reference and description for searching
        const search_text = try std.fmt.allocPrint(arena, "{s} {s}", .{
            txn.reference orelse "",
            txn.description,
        });

        // Find all invoice IDs mentioned in the transaction
        var mentioned_invoices = std.ArrayListUnmanaged(fj_json.Invoice).empty;
        for (unpaid_invoices) |inv| {
            if (inv.total == null) continue;
            if (containsInvoiceId(search_text, inv.id)) {
                try mentioned_invoices.append(arena, inv);
            }
        }

        if (mentioned_invoices.items.len == 0) continue;

        // Calculate sum of mentioned invoices
        var total_cents: i64 = 0;
        for (mentioned_invoices.items) |inv| {
            total_cents += inv.total.? * 100;
        }

        // Check if sum matches transaction amount
        if (total_cents != txn.amount) continue;

        // Match found! Build comma-separated invoice ID list
        var id_parts = std.ArrayListUnmanaged([]const u8).empty;
        for (mentioned_invoices.items) |inv| {
            try id_parts.append(arena, inv.id);
        }
        const combined_ids = try std.mem.join(arena, ",", id_parts.items);

        // Update transaction with all matched invoice IDs
        txn.reconciliation = .{
            .invoice_id = combined_ids,
            .matched_at = now,
            .confidence = if (mentioned_invoices.items.len == 1) "high" else "multi",
        };

        // Add each invoice to the matched list
        for (mentioned_invoices.items) |inv| {
            try matched.append(arena, .{
                .invoice_id = inv.id,
                .transaction_id = txn.id,
                .transaction_date = txn.date,
                .amount_euros = inv.total.?,
            });
        }
    }

    return .{
        .matched_count = matched.items.len,
        .matched_invoices = try matched.toOwnedSlice(arena),
    };
}

/// Check if text contains invoice ID pattern (e.g., "2025-042")
/// Also handles line-wrap artifacts where spaces appear in the ID (e.g., "202 5-042")
fn containsInvoiceId(text: ?[]const u8, invoice_id: []const u8) bool {
    const t = text orelse return false;
    // Direct match first
    if (std.mem.indexOf(u8, t, invoice_id) != null) return true;
    // Try matching with single spaces removed (handles line-wrap artifacts)
    return containsWithSpacesRemoved(t, invoice_id);
}

/// Check if text contains pattern after removing single spaces from text
fn containsWithSpacesRemoved(text: []const u8, pattern: []const u8) bool {
    // Sliding window: try to match pattern allowing single spaces in text
    var ti: usize = 0;
    outer: while (ti <= text.len) {
        var pi: usize = 0;
        var tii = ti;
        while (pi < pattern.len and tii < text.len) {
            if (text[tii] == pattern[pi]) {
                tii += 1;
                pi += 1;
            } else if (text[tii] == ' ') {
                // Skip single space in text
                tii += 1;
            } else {
                ti += 1;
                continue :outer;
            }
        }
        if (pi == pattern.len) return true;
        ti += 1;
    }
    return false;
}

test "containsInvoiceId" {
    try std.testing.expect(containsInvoiceId("Payment for invoice 2025-042", "2025-042"));
    try std.testing.expect(containsInvoiceId("RE 2025-042 Beratung", "2025-042"));
    try std.testing.expect(!containsInvoiceId("Random payment", "2025-042"));
    try std.testing.expect(!containsInvoiceId(null, "2025-042"));
}

test "multi-invoice detection" {
    try std.testing.expect(containsInvoiceId("RNr. 2025-002 RNr. 2025-003", "2025-002"));
    try std.testing.expect(containsInvoiceId("RNr. 2025-002 RNr. 2025-003", "2025-003"));
    try std.testing.expect(!containsInvoiceId("RNr. 2025-002 RNr. 2025-003", "2025-004"));
}

test "line-wrap space handling" {
    // "202 5-004" should match "2025-004"
    try std.testing.expect(containsInvoiceId("RNr. 202 5-004 something", "2025-004"));
    try std.testing.expect(containsInvoiceId("20 25-004", "2025-004"));
    try std.testing.expect(containsInvoiceId("2025 -004", "2025-004"));
    // Multiple spaces should not be collapsed
    try std.testing.expect(!containsInvoiceId("20  25-004", "2025-004"));
}
