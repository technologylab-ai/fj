// Bank module - Bank statement import and transaction management
// Phase 3 of Strategic AI Advisor roadmap

pub const parser = @import("bank/parser.zig");
pub const store = @import("bank/store.zig");
pub const reconcile = @import("bank/reconcile.zig");

// Re-export commonly used types
pub const BawagParser = parser.BawagParser;
pub const ParserType = parser.ParserType;
pub const ParseResult = parser.ParseResult;
pub const ParsedTransaction = parser.ParsedTransaction;

pub const TransactionStore = store.TransactionStore;
pub const TransactionSummary = store.TransactionSummary;
pub const MonthlySummary = store.MonthlySummary;

// Re-export utility functions
pub const latin1ToUtf8 = parser.latin1ToUtf8;
pub const detectParser = parser.detectParser;
pub const generateId = parser.generateId;
pub const parseGermanAmount = parser.parseGermanAmount;

pub const calculateSummary = store.calculateSummary;
pub const filterTransactions = store.filterTransactions;
pub const groupByMonth = store.groupByMonth;

// Reconciliation (Phase 4)
pub const ReconcileResult = reconcile.ReconcileResult;
pub const MatchedInvoice = reconcile.MatchedInvoice;
pub const reconcileInvoices = reconcile.reconcile;
