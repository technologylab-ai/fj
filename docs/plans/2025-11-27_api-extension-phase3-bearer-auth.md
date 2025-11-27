# Feature: FJ API Extension Phase 3 - Bearer Token Authentication

## Overview
This is Phase 3 of the FJ API Extension implementation. It adds RFC 6750 Bearer token authentication for the REST API routes (`/api/v1/*`) using Zap's `BearerMulti` authenticator, running in parallel with the existing session-based authentication for the web UI.

**Depends on**: Phase 1 (keys.zig module with `loadKeys()` function and `ApiKeyStore` struct)

## Requirements

### Functional Requirements
- API routes at `/api/v1/*` authenticate via `Authorization: Bearer <token>` header
- Tokens are verified by SHA-256 hashing and checking against stored hashes
- Expired and deleted keys are rejected
- Invalid tokens return 401 Unauthorized with proper `WWW-Authenticate` header
- Existing session auth for web UI remains unchanged

### Non-Functional Requirements
- O(1) token verification using hashmap lookup
- No plaintext token storage (only SHA-256 hashes)
- Keys loaded at server startup from `FJ_HOME/.api_keys.json`
- Standard RFC 6750 Bearer token format

## Technical Design

### Architecture

**Dual Authentication Strategy:**
```
┌─────────────────────────────────────────────────────────────────┐
│                        FJ Web Server                            │
├────────────────────────────┬────────────────────────────────────┤
│   Web UI Routes            │   API Routes                       │
│   /dashboard, /keys, etc.  │   /api/v1/*                        │
├────────────────────────────┼────────────────────────────────────┤
│   UserPassSession          │   BearerMulti(HashedApiKeySet)     │
│   (Cookie: FJ_SESSION)     │   (Header: Authorization: Bearer)  │
├────────────────────────────┼────────────────────────────────────┤
│   Validates session ID     │   SHA-256 hash token, lookup       │
│   from cookie              │   in hashmap                       │
└────────────────────────────┴────────────────────────────────────┘
```

**Token Verification Flow:**
```
Request with "Authorization: Bearer fj_sk_xyz..."
    │
    ▼
BearerMulti extracts token from header
    │
    ▼
HashedApiKeySet.contains(token) called
    │
    ├── SHA-256 hash the incoming token
    │
    ├── Convert to hex string (64 chars)
    │
    └── Check if hash exists in StringHashMap
            │
            ├── Found: Return true → Handler called
            │
            └── Not found: Return false → 401 Unauthorized
```

### Core Changes

#### 1. `src/web/api_auth.zig` (New File)

```zig
const std = @import("std");
const zap = @import("zap");
const keys_mod = @import("../keys.zig");
const json = @import("../json.zig");

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
        const store = keys_mod.loadKeys(self.allocator, fj_home) catch |err| {
            if (err == error.FileNotFound) {
                // No keys file yet, that's fine
                return;
            }
            return err;
        };

        for (store.keys) |key| {
            // Skip deleted and expired keys
            if (key.deleted) continue;
            if (key.expires_at) |exp| {
                if (isExpired(exp)) continue;
            }
            try self.putHash(key.token_hash);
        }
    }

    fn isExpired(expires_at: []const u8) bool {
        // Simple date comparison (YYYY-MM-DD format)
        // TODO: Use zeit for proper date comparison
        const now = @import("zeit").instant(.{}) catch return false;
        const today = now.time();
        const today_str = std.fmt.allocPrint(
            std.heap.page_allocator,
            "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ today.year, @intFromEnum(today.month), today.day }
        ) catch return false;
        defer std.heap.page_allocator.free(today_str);

        // String comparison works for YYYY-MM-DD format
        return std.mem.lessThan(u8, expires_at, today_str);
    }
};

/// Type alias for the Bearer authenticator
pub const BearerAuthenticator = zap.Auth.BearerMulti(HashedApiKeySet);
```

#### 2. `src/web/context.zig` Modification

Add bearer authenticator to context:
```zig
const api_auth = @import("api_auth.zig");

// Add to Context struct:
api_key_set: ?*api_auth.HashedApiKeySet = null,
bearer_authenticator: ?*api_auth.BearerAuthenticator = null,
```

#### 3. `src/web/server.zig` Modifications

Add imports at top:
```zig
const api_auth = @import("api_auth.zig");
const EpApi = @import("ep_api.zig");  // Phase 4
```

In `serve()` function, after session auth setup (~line 90):
```zig
// ============================================
// Bearer Token Auth for API routes
// ============================================
var api_key_set = api_auth.HashedApiKeySet.init(allocator);
defer api_key_set.deinit();

// Load API key hashes from storage
try api_key_set.loadFromFile(context.fj_home);

// Create Bearer authenticator
var bearer_auth = try api_auth.BearerAuthenticator.init(
    allocator,
    &api_key_set,
    "fj-api",  // realm for WWW-Authenticate header
);
defer bearer_auth.deinit();

// Store in context for potential access by handlers
context.api_key_set = &api_key_set;
context.bearer_authenticator = &bearer_auth;
```

Register API endpoint with Bearer auth (~line 200):
```zig
// API endpoint with Bearer authentication
var ep_api: EpApi = .{};
const AuthApi = App.Endpoint.Authenticating(EpApi, api_auth.BearerAuthenticator);
var auth_api = AuthApi.init(&ep_api, &bearer_auth);
// Note: No PreRouter for API - return JSON errors instead of redirects
try App.register(&auth_api);
```

#### 4. `src/web/ep_api.zig` (Stub for Phase 4)

Create minimal stub to test authentication:
```zig
const std = @import("std");
const zap = @import("zap");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;

path: []const u8 = "/api/v1",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const EpApi = @This();

pub fn get(ep: *EpApi, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = context;

    if (r.path) |path| {
        // Health check - no auth required (for testing)
        if (std.mem.eql(u8, path, "/api/v1/health")) {
            return sendJson(r, .{
                .status = "ok",
                .version = "1.0.0",
            });
        }

        // Auth test endpoint
        if (std.mem.eql(u8, path, "/api/v1/me")) {
            return sendJson(r, .{
                .authenticated = true,
                .message = "Bearer token valid",
            });
        }
    }

    // 404 for unknown API routes
    r.setStatus(.not_found);
    return sendJson(r, .{
        .@"error" = "not_found",
        .message = "Unknown API endpoint",
    });
}

pub fn post(ep: *EpApi, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    _ = arena;
    _ = context;

    r.setStatus(.method_not_allowed);
    return sendJson(r, .{
        .@"error" = "method_not_allowed",
        .message = "POST not yet implemented",
    });
}

fn sendJson(r: zap.Request, data: anytype) !void {
    r.setHeader("Content-Type", "application/json") catch {};
    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try std.json.stringify(data, .{}, fbs.writer());
    try r.sendBody(fbs.getWritten());
}
```

## Implementation Steps

### 1. Create api_auth.zig module (20 minutes)
**File**: `src/web/api_auth.zig`

**Actions**:
- Create `HashedApiKeySet` struct with `init`, `deinit`, `putHash`, `contains`
- Implement SHA-256 hashing in `contains()` method
- Implement `loadFromFile()` to load keys from storage
- Add `isExpired()` helper for date comparison
- Create `BearerAuthenticator` type alias

**Testing**:
- `zig build` should succeed
- Unit test for `contains()` with known hash

### 2. Update context.zig (5 minutes)
**File**: `src/web/context.zig`

**Actions**:
- Add import for `api_auth.zig`
- Add `api_key_set` and `bearer_authenticator` fields (optional pointers)

**Testing**:
- `zig build` succeeds

### 3. Create ep_api.zig stub (15 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- Create minimal endpoint struct with path `/api/v1`
- Implement `get()` with `/api/v1/health` and `/api/v1/me` routes
- Implement `sendJson()` helper for JSON responses
- Return 404 for unknown routes

**Testing**:
- `zig build` succeeds

### 4. Integrate in server.zig (20 minutes)
**File**: `src/web/server.zig`

**Actions**:
- Add imports for `api_auth` and `EpApi`
- Initialize `HashedApiKeySet` and load keys from file
- Create `BearerAuthenticator` instance
- Store in context
- Register API endpoint with bearer auth wrapper

**Testing**:
- Server starts without errors
- `/api/v1/health` returns JSON (no auth required initially)

### 5. End-to-end testing (15 minutes)

**Test unauthenticated request:**
```bash
curl http://localhost:3000/api/v1/me -i
# Expected: 401 Unauthorized with WWW-Authenticate header
```

**Test with invalid token:**
```bash
curl -H "Authorization: Bearer invalid_token" http://localhost:3000/api/v1/me -i
# Expected: 401 Unauthorized
```

**Test with valid token:**
```bash
# First create a key
fj keys create test-api-key

# Copy the token and test
curl -H "Authorization: Bearer fj_sk_..." http://localhost:3000/api/v1/me -i
# Expected: 200 OK with JSON response
```

## Testing Strategy

### Unit Tests
Add to `src/web/api_auth.zig`:
```zig
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
```

### Manual Testing Checklist
- [ ] Server starts with no keys file (empty set)
- [ ] Server starts with keys file (keys loaded)
- [ ] `/api/v1/health` accessible without auth
- [ ] `/api/v1/me` returns 401 without token
- [ ] `/api/v1/me` returns 401 with invalid token
- [ ] `/api/v1/me` returns 200 with valid token
- [ ] Deleted keys are rejected
- [ ] Expired keys are rejected
- [ ] Web UI still works with session auth
- [ ] `WWW-Authenticate: Bearer realm="fj-api"` header on 401

### Edge Cases
- Empty Authorization header
- Malformed Authorization header (no "Bearer " prefix)
- Very long tokens
- Token with special characters
- Race condition: key deleted while request in flight

## Risks and Mitigations

### Risk 1: Key set not reloaded on changes
**Risk**: New keys created via CLI/Web UI not recognized until server restart
**Mitigation**: For Phase 3, document this limitation. Phase 4+ can add key set reload on file change.

### Risk 2: Timing attacks on hash comparison
**Risk**: Hash comparison timing could leak information
**Mitigation**: Use `std.mem.eql` which is not constant-time, but for API keys (high entropy), this is acceptable.

### Risk 3: Memory management of hash strings
**Risk**: Hash strings in hashmap need proper cleanup
**Mitigation**: `deinit()` iterates and frees all keys; use allocator.dupe() on insert.

## Success Metrics
- [ ] Bearer authentication works for `/api/v1/*` routes
- [ ] Session authentication unchanged for web UI
- [ ] Valid tokens verified in O(1) time
- [ ] Invalid tokens rejected with proper 401 response
- [ ] Server starts successfully with and without `.api_keys.json`
- [ ] No plaintext tokens in memory (only hashes)

## Future Enhancements
- Hot-reload API keys when `.api_keys.json` changes
- Rate limiting per API key
- `last_used_at` tracking (update on successful auth)
- Key usage statistics
- API key scopes/permissions
