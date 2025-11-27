const std = @import("std");
const json = @import("json.zig");
const zeit = @import("zeit");
const today = @import("today.zig");

pub const API_KEY_PREFIX = "fj_sk_";
pub const API_KEY_LENGTH = 64; // prefix (6) + random (58)
pub const TOKEN_HASH_LENGTH = 64; // SHA-256 hex

/// Generate a new API key token
pub fn generateToken(allocator: std.mem.Allocator) ![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var token = try allocator.alloc(u8, API_KEY_LENGTH);

    // Copy prefix
    @memcpy(token[0..6], API_KEY_PREFIX);

    // Generate random part
    std.crypto.random.bytes(token[6..]);
    for (token[6..]) |*byte| {
        byte.* = charset[@as(usize, byte.*) % charset.len];
    }

    return token;
}

/// Hash a token using SHA-256, return hex string
pub fn hashToken(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &hash, .{});

    // Convert to hex string
    const hex_array = std.fmt.bytesToHex(hash, .lower);
    return try allocator.dupe(u8, &hex_array);
}

/// Load API keys from FJ_HOME/.api_keys.json
pub fn loadKeys(allocator: std.mem.Allocator, fj_home: []const u8) !json.ApiKeyStore {
    const path = try std.fs.path.join(allocator, &.{ fj_home, ".api_keys.json" });
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return json.ApiKeyStore{ .keys = &.{} };
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);

    const parsed = try std.json.parseFromSlice(json.ApiKeyStore, allocator, content, .{
        .ignore_unknown_fields = true,
    });

    return parsed.value;
}

/// Save API keys to FJ_HOME/.api_keys.json
pub fn saveKeys(allocator: std.mem.Allocator, fj_home: []const u8, store: json.ApiKeyStore) !void {
    const path = try std.fs.path.join(allocator, &.{ fj_home, ".api_keys.json" });
    defer allocator.free(path);

    const file = try std.fs.createFileAbsolute(path, .{ .mode = 0o600 });
    defer file.close();

    var io_buffer: [4096]u8 = undefined;
    var writer = file.writer(&io_buffer);
    std.json.Stringify.value(store, .{ .whitespace = .indent_2 }, &writer.interface) catch return error.JsonWriteError;
    writer.interface.flush() catch return error.FlushError;
}

/// Create a new API key
pub fn createKey(allocator: std.mem.Allocator, fj_home: []const u8, label: []const u8, expires: ?[]const u8) ![]u8 {
    const store = try loadKeys(allocator, fj_home);

    // Check label uniqueness
    for (store.keys) |key| {
        if (std.mem.eql(u8, key.label, label) and !key.deleted) {
            return error.LabelAlreadyExists;
        }
    }

    // Generate token and hash
    const token = try generateToken(allocator);
    const token_hash = try hashToken(allocator, token);

    // Get current timestamp
    const now = try getCurrentTimestamp(allocator);

    // Create new key entry
    const new_key = json.ApiKey{
        .label = try allocator.dupe(u8, label),
        .token_hash = token_hash,
        .created_at = now,
        .expires_at = if (expires) |e| try allocator.dupe(u8, e) else null,
        .last_used_at = null,
        .deleted = false,
    };

    // Append to keys
    var keys_list = std.ArrayListUnmanaged(json.ApiKey).empty;
    try keys_list.appendSlice(allocator, store.keys);
    try keys_list.append(allocator, new_key);

    const new_store = json.ApiKeyStore{
        .keys = try keys_list.toOwnedSlice(allocator),
    };

    // Save
    try saveKeys(allocator, fj_home, new_store);

    return token; // Return plaintext token (shown once)
}

/// Delete an API key (soft-delete)
pub fn deleteKey(allocator: std.mem.Allocator, fj_home: []const u8, label: []const u8) !void {
    const store = try loadKeys(allocator, fj_home);

    var found = false;
    var new_keys = std.ArrayListUnmanaged(json.ApiKey).empty;

    for (store.keys) |key| {
        if (std.mem.eql(u8, key.label, label) and !key.deleted) {
            // Mark as deleted
            try new_keys.append(allocator, .{
                .label = key.label,
                .token_hash = key.token_hash,
                .created_at = key.created_at,
                .expires_at = key.expires_at,
                .last_used_at = key.last_used_at,
                .deleted = true,
            });
            found = true;
        } else {
            try new_keys.append(allocator, key);
        }
    }

    if (!found) {
        return error.KeyNotFound;
    }

    const new_store = json.ApiKeyStore{
        .keys = try new_keys.toOwnedSlice(allocator),
    };

    try saveKeys(allocator, fj_home, new_store);
}

/// Verify a token against stored hashes
pub fn verifyToken(allocator: std.mem.Allocator, fj_home: []const u8, token: []const u8) !?json.ApiKey {
    // Validate format
    if (token.len != API_KEY_LENGTH or !std.mem.startsWith(u8, token, API_KEY_PREFIX)) {
        return null;
    }

    const store = try loadKeys(allocator, fj_home);
    const token_hash = try hashToken(allocator, token);
    defer allocator.free(token_hash);

    const today_str = try today.getTodayString(allocator);

    for (store.keys) |key| {
        if (key.deleted) continue;
        if (key.expires_at) |exp| {
            // Check if expired (string comparison works for YYYY-MM-DD)
            if (std.mem.order(u8, exp, today_str) == .lt) continue;
        }
        if (std.mem.eql(u8, key.token_hash, token_hash)) {
            return key;
        }
    }

    return null;
}

fn getCurrentTimestamp(allocator: std.mem.Allocator) ![]u8 {
    const ts = zeit.instant(.{}) catch return error.TimeError;
    const dt = ts.time();
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        dt.year, @intFromEnum(dt.month), dt.day, dt.hour, dt.minute, dt.second,
    });
}

// Tests
test "generateToken has correct format" {
    const token = try generateToken(std.testing.allocator);
    defer std.testing.allocator.free(token);

    try std.testing.expectEqual(@as(usize, 64), token.len);
    try std.testing.expect(std.mem.startsWith(u8, token, "fj_sk_"));
}

test "hashToken produces consistent output" {
    const hash1 = try hashToken(std.testing.allocator, "fj_sk_test123");
    defer std.testing.allocator.free(hash1);
    const hash2 = try hashToken(std.testing.allocator, "fj_sk_test123");
    defer std.testing.allocator.free(hash2);

    try std.testing.expectEqualStrings(hash1, hash2);
    try std.testing.expectEqual(@as(usize, 64), hash1.len);
}
