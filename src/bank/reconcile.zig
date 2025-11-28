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
/// Matches by: exact amount (euros*100 = cents) AND invoice ID found in text
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

        // Try to match against unpaid invoices
        for (unpaid_invoices) |inv| {
            if (inv.total == null) continue;

            // Amount match: invoice euros * 100 == transaction cents
            const invoice_cents = inv.total.? * 100;
            if (invoice_cents != txn.amount) continue;

            // Invoice ID must appear in reference or description
            if (!containsInvoiceId(txn.reference, inv.id) and
                !containsInvoiceId(txn.description, inv.id))
            {
                continue;
            }

            // High confidence match - update transaction
            txn.reconciliation = .{
                .invoice_id = inv.id,
                .matched_at = now,
                .confidence = "high",
            };

            try matched.append(arena, .{
                .invoice_id = inv.id,
                .transaction_id = txn.id,
                .transaction_date = txn.date,
                .amount_euros = inv.total.?,
            });
            break;
        }
    }

    return .{
        .matched_count = matched.items.len,
        .matched_invoices = try matched.toOwnedSlice(arena),
    };
}

/// Check if text contains invoice ID pattern (e.g., "2025-042")
fn containsInvoiceId(text: ?[]const u8, invoice_id: []const u8) bool {
    const t = text orelse return false;
    return std.mem.indexOf(u8, t, invoice_id) != null;
}

test "containsInvoiceId" {
    try std.testing.expect(containsInvoiceId("Payment for invoice 2025-042", "2025-042"));
    try std.testing.expect(containsInvoiceId("RE 2025-042 Beratung", "2025-042"));
    try std.testing.expect(!containsInvoiceId("Random payment", "2025-042"));
    try std.testing.expect(!containsInvoiceId(null, "2025-042"));
}
