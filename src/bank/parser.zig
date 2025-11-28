const std = @import("std");
const json = @import("../json.zig");
const format = @import("../format.zig");

const Allocator = std.mem.Allocator;

pub const ParsedTransaction = struct {
    ref_code: []const u8,
    date: []const u8,
    amount: i64,
    currency: []const u8,
    description: []const u8,
    counterparty: json.Counterparty,
    reference: ?[]const u8,
    line: usize,
};

pub const ParseResult = struct {
    transactions: []const ParsedTransaction,
    account_iban: ?[]const u8,
    errors: []const ParseError,
};

pub const ParseError = struct {
    line: usize,
    message: []const u8,
};

pub const ParserType = enum {
    bawag,
    // Future: sparkasse, generic, etc.
};

/// Parser interface for bank CSV formats
pub const Parser = struct {
    ptr: *anyopaque,
    parseFn: *const fn (ptr: *anyopaque, content: []const u8, arena: Allocator) anyerror!ParseResult,

    pub fn parse(self: Parser, content: []const u8, arena: Allocator) !ParseResult {
        return self.parseFn(self.ptr, content, arena);
    }
};

/// Auto-detect parser based on file content/name
pub fn detectParser(filename: []const u8, content: []const u8) ?ParserType {
    _ = content;
    // For now, default to BAWAG if filename contains "BAWAG" or "Umsatzliste"
    if (std.mem.indexOf(u8, filename, "BAWAG") != null or
        std.mem.indexOf(u8, filename, "Umsatzliste") != null)
    {
        return .bawag;
    }
    return .bawag; // Default to BAWAG for Phase 3
}

/// Convert ISO-8859-1 (Latin-1) bytes to UTF-8
pub fn latin1ToUtf8(arena: Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8).empty;
    for (input) |byte| {
        if (byte < 128) {
            try result.append(arena, byte);
        } else {
            // ISO-8859-1 byte -> UTF-8 (2 bytes for 128-255)
            try result.append(arena, 0xC0 | (byte >> 6));
            try result.append(arena, 0x80 | (byte & 0x3F));
        }
    }
    return result.toOwnedSlice(arena);
}

/// BAWAG CSV parser implementation
pub const BawagParser = struct {
    pub fn parser(self: *BawagParser) Parser {
        return .{
            .ptr = self,
            .parseFn = parseImpl,
        };
    }

    fn parseImpl(ptr: *anyopaque, content: []const u8, arena: Allocator) !ParseResult {
        _ = ptr;

        var transactions = std.ArrayListUnmanaged(ParsedTransaction).empty;
        var errors = std.ArrayListUnmanaged(ParseError).empty;
        var account_iban: ?[]const u8 = null;

        var line_num: usize = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line_raw| {
            line_num += 1;
            const line = format.strip(line_raw);

            // Skip empty lines
            if (line.len == 0) continue;

            // Parse CSV fields (semicolon-separated)
            var fields = std.mem.splitScalar(u8, line, ';');

            const iban = fields.next() orelse {
                try errors.append(arena, .{ .line = line_num, .message = "Missing IBAN field" });
                continue;
            };
            const description = fields.next() orelse {
                try errors.append(arena, .{ .line = line_num, .message = "Missing description field" });
                continue;
            };
            const booking_date = fields.next() orelse {
                try errors.append(arena, .{ .line = line_num, .message = "Missing booking date field" });
                continue;
            };
            _ = fields.next(); // value_date (skip, use booking_date)
            const amount_str = fields.next() orelse {
                try errors.append(arena, .{ .line = line_num, .message = "Missing amount field" });
                continue;
            };
            const currency = fields.next() orelse "EUR";

            // Store account IBAN from first transaction
            if (account_iban == null and iban.len > 0) {
                account_iban = try arena.dupe(u8, iban);
            }

            // Parse amount (German format)
            const amount = parseGermanAmount(amount_str) catch {
                try errors.append(arena, .{
                    .line = line_num,
                    .message = try std.fmt.allocPrint(arena, "Invalid amount format: '{s}'", .{amount_str}),
                });
                continue;
            };

            // Parse date (DD.MM.YYYY -> YYYY-MM-DD)
            const date = parseGermanDate(arena, booking_date) catch {
                try errors.append(arena, .{
                    .line = line_num,
                    .message = try std.fmt.allocPrint(arena, "Invalid date format: '{s}'", .{booking_date}),
                });
                continue;
            };

            // Parse description field (pipe-separated segments)
            const desc_info = parseDescription(arena, description) catch |err| {
                try errors.append(arena, .{
                    .line = line_num,
                    .message = try std.fmt.allocPrint(arena, "Error parsing description: {}", .{err}),
                });
                continue;
            };

            try transactions.append(arena, .{
                .ref_code = desc_info.ref_code,
                .date = date,
                .amount = amount,
                .currency = try arena.dupe(u8, format.strip(currency)),
                .description = try arena.dupe(u8, description),
                .counterparty = desc_info.counterparty,
                .reference = desc_info.reference,
                .line = line_num,
            });
        }

        return .{
            .transactions = try transactions.toOwnedSlice(arena),
            .account_iban = account_iban,
            .errors = try errors.toOwnedSlice(arena),
        };
    }
};

/// Parse German number format: "-1.800,00" -> -180000 cents
pub fn parseGermanAmount(amount_str: []const u8) !i64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    var negative = false;

    const trimmed = format.strip(amount_str);
    for (trimmed) |c| {
        switch (c) {
            '+' => continue, // Skip plus sign
            '-' => {
                negative = true;
                continue;
            },
            '.' => continue, // Skip thousand separator
            ',' => {
                buf[i] = '.'; // Replace decimal comma with dot
                i += 1;
            },
            else => {
                if (i >= buf.len) return error.AmountTooLong;
                buf[i] = c;
                i += 1;
            },
        }
    }

    if (i == 0) return error.EmptyAmount;

    const float_val = std.fmt.parseFloat(f64, buf[0..i]) catch return error.InvalidAmount;
    const cents: i64 = @intFromFloat(@round(float_val * 100));

    return if (negative) -@as(i64, @intCast(@abs(cents))) else cents;
}

/// Parse German date format: "10.06.2025" -> "2025-06-10"
fn parseGermanDate(arena: Allocator, date_str: []const u8) ![]const u8 {
    const trimmed = format.strip(date_str);
    if (trimmed.len < 10) return error.InvalidDate;

    var parts = std.mem.splitScalar(u8, trimmed, '.');
    const day = parts.next() orelse return error.InvalidDate;
    const month = parts.next() orelse return error.InvalidDate;
    const year = parts.next() orelse return error.InvalidDate;

    if (day.len != 2 or month.len != 2 or year.len != 4) {
        return error.InvalidDate;
    }

    return std.fmt.allocPrint(arena, "{s}-{s}-{s}", .{ year, month, day });
}

const DescriptionInfo = struct {
    ref_code: []const u8,
    counterparty: json.Counterparty,
    reference: ?[]const u8,
};

/// Parse description field (pipe-separated segments)
/// Segment 0: Transaction type + reference code (e.g., "Abbuchung Echtzeitüberweisung FE/000000006")
/// Segment 1: Counterparty BIC + IBAN + Name (e.g., "GIBAATWWXXX AT00YYYY00009876543210 Max Mustermann")
/// Segment 2: Reference/Purpose (e.g., "Rechnung 2025-042 Beratung")
fn parseDescription(arena: Allocator, desc: []const u8) !DescriptionInfo {
    var result = DescriptionInfo{
        .ref_code = "unknown",
        .counterparty = .{},
        .reference = null,
    };

    var segments = std.mem.splitScalar(u8, desc, '|');

    // Segment 0: Extract reference code
    if (segments.next()) |seg0| {
        result.ref_code = try extractRefCode(arena, seg0);
    }

    // Segment 1: Parse counterparty (BIC IBAN Name)
    if (segments.next()) |seg1| {
        result.counterparty = parseCounterparty(arena, seg1) catch .{};
    }

    // Segment 2: Payment reference
    if (segments.next()) |seg2| {
        const trimmed = format.strip(seg2);
        if (trimmed.len > 0) {
            result.reference = try arena.dupe(u8, trimmed);
        }
    }

    return result;
}

/// Extract reference code like "FE/000000006", "MC/000000083", etc.
fn extractRefCode(arena: Allocator, text: []const u8) ![]const u8 {
    // Look for patterns like MC/, FE/, BG/, VD/, VB/, OG/ followed by digits
    const prefixes = [_][]const u8{ "MC/", "FE/", "BG/", "VD/", "VB/", "OG/" };

    for (prefixes) |prefix| {
        if (std.mem.indexOf(u8, text, prefix)) |start| {
            var end = start + prefix.len;
            // Find end of digits
            while (end < text.len and std.ascii.isDigit(text[end])) {
                end += 1;
            }
            if (end > start + prefix.len) {
                return arena.dupe(u8, text[start..end]);
            }
        }
    }

    // Fallback: generate from hash of description
    var hash: [8]u8 = undefined;
    const desc_hash = std.hash.Wyhash.hash(0, text);
    _ = std.fmt.bufPrint(&hash, "{x:0>8}", .{@as(u32, @truncate(desc_hash))}) catch unreachable;
    return std.fmt.allocPrint(arena, "TX/{s}", .{hash});
}

/// Parse counterparty from "BIC IBAN Name" format
fn parseCounterparty(arena: Allocator, text: []const u8) !json.Counterparty {
    const trimmed = format.strip(text);
    if (trimmed.len == 0) return .{};

    var result: json.Counterparty = .{};
    var words = std.mem.splitScalar(u8, trimmed, ' ');

    // First word might be BIC (8 or 11 chars, alphanumeric)
    if (words.next()) |word| {
        if (isBic(word)) {
            result.bic = try arena.dupe(u8, word);
            // Next word should be IBAN
            if (words.next()) |iban_word| {
                if (isIban(iban_word)) {
                    result.iban = try arena.dupe(u8, iban_word);
                    // Rest is the name
                    const rest = words.rest();
                    if (rest.len > 0) {
                        result.name = try arena.dupe(u8, format.strip(rest));
                    }
                } else {
                    // No IBAN, this and rest is name
                    const rest = trimmed[word.len..];
                    if (rest.len > 0) {
                        result.name = try arena.dupe(u8, format.strip(rest));
                    }
                }
            }
        } else if (isIban(word)) {
            // Starts with IBAN (no BIC)
            result.iban = try arena.dupe(u8, word);
            const rest = words.rest();
            if (rest.len > 0) {
                result.name = try arena.dupe(u8, format.strip(rest));
            }
        } else {
            // No BIC/IBAN, entire string is name
            result.name = try arena.dupe(u8, trimmed);
        }
    }

    return result;
}

fn isBic(word: []const u8) bool {
    // BIC: 8 or 11 alphanumeric characters
    if (word.len != 8 and word.len != 11) return false;
    for (word) |c| {
        if (!std.ascii.isAlphanumeric(c)) return false;
    }
    // BICs typically end with XXX or country-specific codes
    return true;
}

fn isIban(word: []const u8) bool {
    // IBAN: starts with 2 letters, then 2 digits, then alphanumeric
    if (word.len < 15 or word.len > 34) return false;
    if (!std.ascii.isAlphabetic(word[0]) or !std.ascii.isAlphabetic(word[1])) return false;
    if (!std.ascii.isDigit(word[2]) or !std.ascii.isDigit(word[3])) return false;
    return true;
}

/// Generate transaction ID from reference code
/// "FE/000000006" -> "fe000000006"
pub fn generateId(arena: Allocator, ref_code: []const u8) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8).empty;
    for (ref_code) |c| {
        if (c == '/') continue; // Skip slash
        try result.append(arena, std.ascii.toLower(c));
    }
    return result.toOwnedSlice(arena);
}

// Tests
test "parseGermanAmount" {
    const TestCase = struct { input: []const u8, expected: i64 };
    const cases = [_]TestCase{
        .{ .input = "-2,63", .expected = -263 },
        .{ .input = "+5.000,00", .expected = 500000 },
        .{ .input = "-1.800,00", .expected = -180000 },
        .{ .input = "1.234,56", .expected = 123456 },
        .{ .input = "0,01", .expected = 1 },
        .{ .input = "-0,01", .expected = -1 },
    };

    for (cases) |tc| {
        const result = try parseGermanAmount(tc.input);
        try std.testing.expectEqual(tc.expected, result);
    }
}

test "parseGermanDate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parseGermanDate(arena.allocator(), "10.06.2025");
    try std.testing.expectEqualStrings("2025-06-10", result);
}

test "latin1ToUtf8" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Test German umlauts: ä = 0xe4, ö = 0xf6, ü = 0xfc
    const input = "M\xfcnchen"; // "München" in ISO-8859-1
    const result = try latin1ToUtf8(arena.allocator(), input);
    try std.testing.expectEqualStrings("München", result);
}

test "generateId" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try generateId(arena.allocator(), "FE/000000006");
    try std.testing.expectEqualStrings("fe000000006", result);
}
