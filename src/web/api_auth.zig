const std = @import("std");
const zap = @import("zap");
const keys_mod = @import("../keys.zig");
const json = @import("../json.zig");
const today = @import("../today.zig");

/// Wrapper around StringHashMap that hashes tokens before lookup.
/// The hashmap stores SHA-256 hashes of valid tokens.
/// Required by zap.Auth.BearerMulti - must have .contains() method.
pub const HashedApiKeySet = struct {
    allocator: std.mem.Allocator,
    hashes: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) HashedApiKeySet {
        return .{
            .allocator = allocator,
            .hashes = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *HashedApiKeySet) void {
        // Free all duped hash strings
        var it = self.hashes.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.hashes.deinit();
    }

    /// Add a token hash (loaded from .api_keys.json)
    pub fn putHash(self: *HashedApiKeySet, token_hash: []const u8) !void {
        const duped = try self.allocator.dupe(u8, token_hash);
        try self.hashes.put(duped, {});
    }

    /// Required by BearerMulti: hash the incoming token and check if it exists
    pub fn contains(self: *HashedApiKeySet, token: []const u8) bool {
        // Hash the incoming token with SHA-256
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(token, &hash, .{});

        // Convert to hex string for lookup
        const hex = std.fmt.bytesToHex(hash, .lower);

        // Check if this hash exists in our set
        return self.hashes.contains(&hex);
    }

    /// Load API key hashes from storage file
    pub fn loadFromFile(self: *HashedApiKeySet, fj_home: []const u8) !void {
        // Use a temporary arena for loading - putHash dupes to self.allocator
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_alloc = arena.allocator();

        const store = keys_mod.loadKeys(temp_alloc, fj_home) catch |err| {
            if (err == error.FileNotFound) {
                // No keys file yet, that's fine
                return;
            }
            return err;
        };

        const today_str = today.getTodayString(temp_alloc) catch return;

        for (store.keys) |key| {
            // Skip deleted and expired keys
            if (key.deleted) continue;
            if (key.expires_at) |exp| {
                if (isExpired(exp, today_str)) continue;
            }
            try self.putHash(key.token_hash);
        }
        // arena freed here via defer, releasing store and today_str
    }

    fn isExpired(expires_at: []const u8, today_str: []const u8) bool {
        // String comparison works for YYYY-MM-DD format
        return std.mem.order(u8, expires_at, today_str) == .lt;
    }
};

/// Type alias for the Bearer authenticator
pub const BearerAuthenticator = zap.Auth.BearerMulti(HashedApiKeySet);

// Tests
test "HashedApiKeySet contains works with SHA-256" {
    var set = HashedApiKeySet.init(std.testing.allocator);
    defer set.deinit();

    // Known token and its SHA-256 hash
    const token = "fj_sk_test123456789";
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);

    // Add hash to set
    try set.putHash(&hex);

    // Should find the token
    try std.testing.expect(set.contains(token));

    // Should not find different token
    try std.testing.expect(!set.contains("fj_sk_different"));
}
