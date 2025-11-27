# Feature: FJ API Extension Phase 1 - Data Model & API Key Infrastructure

## Overview
This is Phase 1 of the FJ API Extension implementation. It establishes the foundational data model changes and API key management infrastructure needed for the REST API.

**Components:**
1. Add `oms_project` field to Invoice and Offer structs for OMS integration
2. Add `--omsproject` CLI flag to invoice and offer commands
3. Create complete API key management system with CLI commands

## Requirements

### Functional Requirements
- Invoice and Offer documents can store an optional `oms_project` field
- `fj invoice new` and `fj offer new` accept `--omsproject=<name>` flag
- API keys can be created, listed, and deleted via CLI
- API keys are stored securely using SHA-256 hashing
- Keys follow format: `fj_sk_` prefix + 58 alphanumeric chars (64 total)

### Non-Functional Requirements
- Backwards compatible (existing documents without `oms_project` work fine)
- Key storage file has restrictive permissions
- No external dependencies for crypto (use `std.crypto.hash.sha2.Sha256`)

## Technical Design

### Architecture

**Data Flow for `oms_project`:**
```
CLI --omsproject flag → InvoiceCommand/OfferCommand struct
  → cmdCreateNewDocument() → Invoice/Offer struct in json.zig
  → JSON file in document directory
```

**API Key Storage:**
```
FJ_HOME/.api_keys.json
├── Array of key entries
│   ├── label (unique identifier)
│   ├── token_hash (SHA-256 hex, 64 chars)
│   ├── created_at (ISO8601)
│   ├── expires_at (ISO8601 | null)
│   ├── last_used_at (ISO8601 | null)
│   └── deleted (bool, soft-delete)
```

### Data/State Changes

#### 1. `src/json.zig` - Add `oms_project` to Invoice and Offer

**Invoice struct** (around line 109):
```zig
pub const Invoice = struct {
    // ... existing fields ...
    project_name: []const u8 = "",
    oms_project: ?[]const u8 = null,  // NEW
    // ... rest of fields ...
};
```

**Offer struct** (around line 74):
```zig
pub const Offer = struct {
    // ... existing fields ...
    project_name: []const u8 = "",
    oms_project: ?[]const u8 = null,  // NEW
    // ... rest of fields ...
};
```

#### 2. `src/json.zig` - Add ApiKey struct

```zig
pub const ApiKey = struct {
    label: []const u8,
    token_hash: []const u8,
    created_at: []const u8,
    expires_at: ?[]const u8 = null,
    last_used_at: ?[]const u8 = null,
    deleted: bool = false,
};

pub const ApiKeyStore = struct {
    keys: []ApiKey,
};
```

### Core Changes

#### 1. `src/cli.zig` - Add `omsproject` to InvoiceCommand and OfferCommand

**OfferCommand** (line 218):
```zig
pub const OfferCommand = struct {
    fj_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    omsproject: ?[]const u8 = null,  // NEW
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,
    force: bool = false,
    // ... rest unchanged ...
};
```

**InvoiceCommand** (line 266):
```zig
pub const InvoiceCommand = struct {
    fj_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    omsproject: ?[]const u8 = null,  // NEW
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,
    force: bool = false,
    // ... rest unchanged ...
};
```

#### 2. `src/cli.zig` - Add KeysCommand

```zig
pub const KeysCommand = struct {
    fj_home: ?[]const u8 = null,
    expires: ?[]const u8 = null,  // For create: --expires=YYYY-MM-DD

    positional: struct {
        subcommand: enum { create, list, delete },
        arg: ?[]const u8 = null,  // label for create/delete
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: keys
        \\
        \\ Usage:
        \\
        \\ fj keys [create|list|delete] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fj keys create <label> [--expires=YYYY-MM-DD]
        \\                          -> Creates new API key, displays once
        \\ - fj keys list           -> Lists all API keys (tokens masked)
        \\ - fj keys delete <label> -> Soft-deletes an API key
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};
```

**Add to Cli union** (line 372):
```zig
pub const Cli = union(enum) {
    // ... existing ...
    keys: KeysCommand,  // NEW
    // ...
};
```

**Update Cli help text** to include keys command.

#### 3. `src/keys.zig` - New file for API key management

```zig
const std = @import("std");
const json = @import("json.zig");
const zeit = @import("zeit");
const Fatal = @import("fatal.zig");

pub const API_KEY_PREFIX = "fj_sk_";
pub const API_KEY_LENGTH = 64;  // prefix (6) + random (58)
pub const TOKEN_HASH_LENGTH = 64;  // SHA-256 hex

/// Generate a new API key token
pub fn generateToken(allocator: std.mem.Allocator) ![]const u8 {
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
pub fn hashToken(allocator: std.mem.Allocator, token: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
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
    defer allocator.free(content);

    return try std.json.parseFromSlice(json.ApiKeyStore, allocator, content, .{
        .ignore_unknown_fields = true,
    });
}

/// Save API keys to FJ_HOME/.api_keys.json
pub fn saveKeys(allocator: std.mem.Allocator, fj_home: []const u8, store: json.ApiKeyStore) !void {
    const path = try std.fs.path.join(allocator, &.{ fj_home, ".api_keys.json" });
    defer allocator.free(path);

    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    // Set restrictive permissions (owner read/write only)
    // Note: This is Unix-specific, may need conditional compilation for Windows
    const metadata = try file.metadata();
    var perms = metadata.permissions();
    perms.inner.unixSet(.group, .{ .read = false, .write = false, .execute = false });
    perms.inner.unixSet(.other, .{ .read = false, .write = false, .execute = false });
    try file.setPermissions(perms);

    try std.json.stringify(store, .{ .whitespace = .indent_2 }, file.writer());
}

/// Create a new API key
pub fn createKey(allocator: std.mem.Allocator, fj_home: []const u8, label: []const u8, expires: ?[]const u8) ![]const u8 {
    var store = try loadKeys(allocator, fj_home);

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
    var keys_list = std.ArrayList(json.ApiKey).init(allocator);
    try keys_list.appendSlice(store.keys);
    try keys_list.append(new_key);
    store.keys = try keys_list.toOwnedSlice();

    // Save
    try saveKeys(allocator, fj_home, store);

    return token;  // Return plaintext token (shown once)
}

/// Delete an API key (soft-delete)
pub fn deleteKey(allocator: std.mem.Allocator, fj_home: []const u8, label: []const u8) !void {
    var store = try loadKeys(allocator, fj_home);

    var found = false;
    for (store.keys) |*key| {
        if (std.mem.eql(u8, key.label, label) and !key.deleted) {
            key.deleted = true;
            found = true;
            break;
        }
    }

    if (!found) {
        return error.KeyNotFound;
    }

    try saveKeys(allocator, fj_home, store);
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

    for (store.keys) |key| {
        if (key.deleted) continue;
        if (key.expires_at) |exp| {
            // TODO: Check if expired
            _ = exp;
        }
        if (std.mem.eql(u8, key.token_hash, token_hash)) {
            return key;
        }
    }

    return null;
}

fn getCurrentTimestamp(allocator: std.mem.Allocator) ![]const u8 {
    const ts = zeit.instant(.{}) catch return error.TimeError;
    const dt = ts.time();
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        dt.year, @intFromEnum(dt.month), dt.day, dt.hour, dt.minute, dt.second,
    });
}
```

#### 4. `src/main.zig` - Add dispatch for keys command

Add to the command dispatch switch:
```zig
.keys => |args| try fj.cmdKeys(args),
```

#### 5. `src/fj.zig` - Implement cmdKeys and update cmdCreateNewDocument

**Add cmdKeys function:**
```zig
pub fn cmdKeys(args: Cli.KeysCommand) !void {
    const fj_home = try resolveFjHome(args.fj_home);

    switch (args.positional.subcommand) {
        .create => {
            const label = args.positional.arg orelse {
                fatal.fatal("Label required for 'keys create'", .{});
            };
            const token = keys.createKey(allocator, fj_home, label, args.expires) catch |err| {
                switch (err) {
                    error.LabelAlreadyExists => fatal.fatal("Key with label '{s}' already exists", .{label}),
                    else => return err,
                }
            };
            std.debug.print("Created API key: {s}\n\n", .{token});
            std.debug.print("⚠️  Save this key now - it cannot be retrieved later!\n", .{});
        },
        .list => {
            const store = try keys.loadKeys(allocator, fj_home);
            std.debug.print("{s:<20} {s:<20} {s:<12} {s:<20}\n", .{
                "LABEL", "CREATED", "EXPIRES", "LAST USED",
            });
            std.debug.print("{s}\n", .{"-" ** 72});
            for (store.keys) |key| {
                if (key.deleted) continue;
                std.debug.print("{s:<20} {s:<20} {s:<12} {s:<20}\n", .{
                    key.label,
                    key.created_at[0..10],  // Just date part
                    if (key.expires_at) |e| e[0..10] else "never",
                    if (key.last_used_at) |u| u[0..10] else "never",
                });
            }
        },
        .delete => {
            const label = args.positional.arg orelse {
                fatal.fatal("Label required for 'keys delete'", .{});
            };
            keys.deleteKey(allocator, fj_home, label) catch |err| {
                switch (err) {
                    error.KeyNotFound => fatal.fatal("Key '{s}' not found", .{label}),
                    else => return err,
                }
            };
            std.debug.print("Deleted API key '{s}'\n", .{label});
        },
    }
}
```

**Update cmdCreateNewDocument** (around line 1245):
Add `oms_project` field initialization when creating Invoice/Offer:
```zig
// For Invoice (in the invoice-specific block):
.oms_project = args.omsproject,

// For Offer (in the offer-specific block):
.oms_project = args.omsproject,
```

## Implementation Steps

### 1. Add `oms_project` to JSON structs (5 minutes)
**File**: `src/json.zig`

**Actions**:
- Add `oms_project: ?[]const u8 = null,` to Invoice struct after `project_name`
- Add `oms_project: ?[]const u8 = null,` to Offer struct after `project_name`
- Add `ApiKey` and `ApiKeyStore` structs at end of file

**Testing**:
- `zig build` should succeed
- Existing invoice/offer JSON files should still parse (field defaults to null)

### 2. Add `omsproject` to CLI commands (10 minutes)
**File**: `src/cli.zig`

**Actions**:
- Add `omsproject: ?[]const u8 = null,` to OfferCommand struct
- Add `omsproject: ?[]const u8 = null,` to InvoiceCommand struct
- Update help text for both commands to document `--omsproject`
- Add KeysCommand struct
- Add `keys: KeysCommand` to Cli union
- Update Cli help text

**Testing**:
- `zig build run -- invoice --help` should show `--omsproject`
- `zig build run -- keys --help` should show keys subcommands

### 3. Create keys.zig module (30 minutes)
**File**: `src/keys.zig` (new file)

**Actions**:
- Create file with all key management functions
- Implement generateToken, hashToken, loadKeys, saveKeys
- Implement createKey, deleteKey, verifyToken
- Add proper error handling

**Testing**:
- Unit tests for generateToken (correct length, prefix)
- Unit tests for hashToken (deterministic output)

### 4. Wire up cmdKeys in main.zig (5 minutes)
**File**: `src/main.zig`

**Actions**:
- Add import for keys module
- Add `.keys => |args| try fj.cmdKeys(args),` to dispatch switch

**Testing**:
- `zig build` should succeed

### 5. Implement cmdKeys in fj.zig (20 minutes)
**File**: `src/fj.zig`

**Actions**:
- Add import for keys module at top
- Implement cmdKeys function with create/list/delete subcommands
- Format output nicely for list command

**Testing**:
- `fj keys create test-key` should output a token
- `fj keys list` should show the created key
- `fj keys delete test-key` should remove it
- `fj keys list` should show empty (or not show deleted key)

### 6. Wire up oms_project in cmdCreateNewDocument (15 minutes)
**File**: `src/fj.zig`

**Actions**:
- Find the Invoice/Offer initialization in cmdCreateNewDocument (~line 1245)
- Add `.oms_project = args.omsproject,` for both document types

**Testing**:
- `fj invoice new testclient --project="Test" --omsproject="test-oms"`
- Check generated `invoice.json` contains `"oms_project": "test-oms"`
- `fj offer new testclient --project="Test"` (without --omsproject)
- Check generated `offer.json` contains `"oms_project": null`

### 7. Update help text (5 minutes)
**File**: `src/cli.zig`

**Actions**:
- Add `--omsproject` to InvoiceCommand help text
- Add `--omsproject` to OfferCommand help text

**Testing**:
- `fj invoice --help` shows new option
- `fj offer --help` shows new option

## Testing Strategy

### Unit Tests
Add to `src/keys.zig`:
```zig
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
```

### Manual Testing Checklist
- [ ] `zig build` succeeds
- [ ] `zig build test` passes
- [ ] `fj invoice --help` shows `--omsproject` option
- [ ] `fj offer --help` shows `--omsproject` option
- [ ] `fj keys --help` shows subcommands
- [ ] `fj keys create my-key` generates and displays key
- [ ] `fj keys list` shows created key with masked token
- [ ] `fj keys delete my-key` removes key
- [ ] `fj keys create my-key --expires=2025-12-31` works
- [ ] `fj invoice new testclient --project=Test --omsproject=test-oms` creates invoice with oms_project
- [ ] Invoice JSON contains `"oms_project": "test-oms"`
- [ ] `fj offer new testclient --project=Test` creates offer with null oms_project
- [ ] Existing documents without oms_project field still load correctly

### Edge Cases
- Create key with duplicate label → should error
- Delete non-existent key → should error
- Load keys when .api_keys.json doesn't exist → should return empty
- Very long label names
- Special characters in labels

## Risks and Mitigations

### Risk 1: Breaking existing document parsing
**Risk**: Adding new field could break parsing of existing documents
**Mitigation**: Field has default `null` value, and parser uses `ignore_unknown_fields = true`

### Risk 2: Key file permissions on Windows
**Risk**: Unix-specific permission setting may fail on Windows
**Mitigation**: Add conditional compilation or catch permission errors gracefully

### Risk 3: Random number generation
**Risk**: Weak randomness for key generation
**Mitigation**: Use `std.crypto.random` which uses system CSPRNG

## Success Metrics
- [ ] All existing functionality unchanged
- [ ] New `--omsproject` flag works for invoice and offer creation
- [ ] API keys can be created, listed, and deleted
- [ ] Key tokens are 64 chars with `fj_sk_` prefix
- [ ] Keys are stored with SHA-256 hashes, not plaintext
- [ ] `.api_keys.json` has restrictive file permissions

## Future Enhancements (Phase 2+)
- Web UI for API key management (`/keys` page)
- Bearer token authentication in web server
- API endpoints using the keys
- `last_used_at` tracking on API requests
- Key expiration checking and warnings
