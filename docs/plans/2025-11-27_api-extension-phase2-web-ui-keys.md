# Feature: FJ API Extension Phase 2 - Web UI for API Key Management

## Overview
This is Phase 2 of the FJ API Extension implementation. It adds a web-based management interface for API keys, allowing users to create, view, and delete keys through the browser.

**Depends on**: Phase 1 (Data Model & API Key Infrastructure) - requires `src/keys.zig` and `ApiKey`/`ApiKeyStore` structs in `json.zig`.

## Requirements

### Functional Requirements
- Web page at `/keys` listing all API keys (label, created, expires, last used)
- Form to create new API keys with optional expiration date
- Display newly created token **once** with copy-to-clipboard warning
- Delete button for each key (soft-delete with confirmation)
- Navigation link added to existing header nav

### Non-Functional Requirements
- Uses session authentication (same as dashboard)
- Follows existing Tailwind CSS styling with dark mode support
- Post-Redirect-Get pattern for form submissions
- Mobile-responsive layout

## Technical Design

### Architecture

**Route Structure:**
```
GET  /keys           → List all keys, show create form
POST /keys/create    → Create new key, redirect with token in query param
POST /keys/delete    → Delete key, redirect back to list
```

**Authentication Flow:**
```
Request → PreRouter (check fj_home) → Authenticator (session) → ep_keys handler
```
Uses same `zap.Auth.UserPassSession` middleware as other web pages.

### Core Changes

#### 1. `src/web/ep_keys.zig` (New File)

```zig
const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const keys_mod = @import("../keys.zig");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;

path: []const u8 = "/keys",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const EpKeys = @This();
const html_keys = @embedFile("templates/keys.html");

pub fn get(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    // Route: GET /keys
    if (r.path) |path| {
        if (std.mem.eql(u8, path, ep.path)) {
            return ep.listKeys(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

pub fn post(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        // Route: POST /keys/create
        if (std.mem.eql(u8, path, "/keys/create")) {
            return ep.createKey(arena, context, r);
        }
        // Route: POST /keys/delete
        if (std.mem.eql(u8, path, "/keys/delete")) {
            return ep.deleteKey(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

fn listKeys(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    var fj = ep_utils.createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    // Load keys from storage
    const store = keys_mod.loadKeys(arena, fj.fj_home) catch json.ApiKeyStore{ .keys = &.{} };

    // Check for new_token query param (after create redirect)
    const new_token = r.getParamValue("new_token");

    // Build template params
    var keys_list = std.ArrayList(KeyView).init(arena);
    for (store.keys) |key| {
        if (key.deleted) continue;
        try keys_list.append(.{
            .label = key.label,
            .created_at = if (key.created_at.len >= 10) key.created_at[0..10] else key.created_at,
            .expires_at = if (key.expires_at) |e| (if (e.len >= 10) e[0..10] else e) else "never",
            .last_used_at = if (key.last_used_at) |u| (if (u.len >= 10) u[0..10] else u) else "never",
        });
    }

    const params = .{
        .keys = keys_list.items,
        .new_token = new_token,
        .has_new_token = new_token != null,
    };

    // Render template
    var mustache = try zap.Mustache.fromData(html_keys);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

fn createKey(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    try r.parseBody();

    var fj = ep_utils.createFj(arena, context);

    const label = ep_utils.getBodyStrParam(arena, r, "label") catch {
        return r.redirectTo("/keys?error=missing_label", null);
    };

    const expires = ep_utils.getBodyStrParam(arena, r, "expires") catch null;

    // Create key using keys.zig module
    const token = keys_mod.createKey(arena, fj.fj_home, label, expires) catch |err| {
        switch (err) {
            error.LabelAlreadyExists => return r.redirectTo("/keys?error=duplicate_label", null),
            else => return r.redirectTo("/keys?error=create_failed", null),
        }
    };

    // Redirect back with token in query param (shown once)
    const redirect_url = try std.fmt.allocPrint(arena, "/keys?new_token={s}", .{token});
    return r.redirectTo(redirect_url, null);
}

fn deleteKey(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    try r.parseBody();

    var fj = ep_utils.createFj(arena, context);

    const label = ep_utils.getBodyStrParam(arena, r, "label") catch {
        return r.redirectTo("/keys?error=missing_label", null);
    };

    keys_mod.deleteKey(arena, fj.fj_home, label) catch {
        return r.redirectTo("/keys?error=delete_failed", null);
    };

    return r.redirectTo("/keys?deleted=1", null);
}

const KeyView = struct {
    label: []const u8,
    created_at: []const u8,
    expires_at: []const u8,
    last_used_at: []const u8,
};
```

#### 2. `src/web/templates/keys.html` (New File)

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <<<head_block>>>
  <title>API Keys — fj</title>
</head>
<body class="font-sans bg-gray-50 dark:bg-gray-950 text-gray-800 dark:text-gray-100 min-h-screen flex flex-col">

  <<<html_nav>>>

  <main class="container mx-auto p-4 flex-grow">
    <h2 class="text-2xl font-bold text-gray-900 dark:text-gray-100 mb-6">API Keys</h2>

    {{#has_new_token}}
    <div class="bg-green-100 dark:bg-green-900 border border-green-400 dark:border-green-600 text-green-700 dark:text-green-200 px-4 py-3 rounded-lg mb-6">
      <strong class="font-bold">New API Key Created!</strong>
      <p class="mt-2 font-mono text-sm bg-white dark:bg-gray-800 p-2 rounded border border-green-300 dark:border-green-700 break-all">{{new_token}}</p>
      <p class="mt-2 text-sm italic">Save this key now — it cannot be retrieved later!</p>
    </div>
    {{/has_new_token}}

    <!-- Create New Key Form -->
    <div class="bg-white dark:bg-gray-900 p-6 rounded-lg shadow-md dark:shadow-2xl dark:shadow-gray-900/50 border border-gray-200 dark:border-gray-700 mb-8">
      <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">Create New Key</h3>
      <form action="/keys/create" method="post" class="flex flex-col md:flex-row md:items-end gap-4">
        <div class="flex-1">
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Label</label>
          <input type="text" name="label" required placeholder="e.g., oms-integration"
                 class="w-full p-2 border border-gray-300 dark:border-gray-600 rounded-md focus:ring-blue-500 focus:border-blue-500 dark:focus:ring-blue-500 dark:focus:border-blue-500 shadow-sm bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-100" />
        </div>
        <div class="md:w-48">
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Expires (optional)</label>
          <input type="date" name="expires"
                 class="w-full p-2 border border-gray-300 dark:border-gray-600 rounded-md focus:ring-blue-500 focus:border-blue-500 dark:focus:ring-blue-500 dark:focus:border-blue-500 shadow-sm bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-100" />
        </div>
        <button type="submit"
                class="w-full md:w-auto bg-blue-600 dark:bg-blue-600 hover:bg-blue-700 dark:hover:bg-blue-500 text-white font-semibold py-2 px-4 rounded-md shadow-sm cursor-pointer transition-colors duration-200">
          Create Key
        </button>
      </form>
    </div>

    <!-- Keys Table -->
    <div class="bg-white dark:bg-gray-900 rounded-lg shadow-md dark:shadow-2xl dark:shadow-gray-900/50 border border-gray-200 dark:border-gray-700">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 dark:bg-gray-800">
          <tr>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Label</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Created</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Expires</th>
            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Last Used</th>
            <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
          {{^keys}}
          <tr>
            <td colspan="5" class="px-6 py-8 text-center text-sm text-gray-500 dark:text-gray-400 italic">
              No API keys yet. Create one above to get started.
            </td>
          </tr>
          {{/keys}}
          {{#keys}}
          <tr class="hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors duration-150">
            <td class="px-6 py-4 text-sm font-medium text-gray-900 dark:text-gray-100">{{label}}</td>
            <td class="px-6 py-4 text-sm text-gray-700 dark:text-gray-300">{{created_at}}</td>
            <td class="px-6 py-4 text-sm text-gray-700 dark:text-gray-300">{{expires_at}}</td>
            <td class="px-6 py-4 text-sm text-gray-700 dark:text-gray-300">{{last_used_at}}</td>
            <td class="px-6 py-4 text-right text-sm">
              <form action="/keys/delete" method="post" style="display:inline;"
                    onsubmit="return confirm('Delete API key \'{{label}}\'? This cannot be undone.');">
                <input type="hidden" name="label" value="{{label}}" />
                <button type="submit" class="text-red-600 dark:text-red-400 hover:text-red-900 dark:hover:text-red-300 transition-colors duration-200">
                  Delete
                </button>
              </form>
            </td>
          </tr>
          {{/keys}}
        </tbody>
      </table>
    </div>

    <p class="mt-6 text-sm text-gray-500 dark:text-gray-400">
      API keys are used for programmatic access via the REST API. Use <code class="bg-gray-100 dark:bg-gray-800 px-1 rounded">Authorization: Bearer &lt;token&gt;</code> header.
    </p>
  </main>
</body>
</html>
```

#### 3. `src/web/server.zig` Modifications

Add after other endpoint declarations (~line 150):
```zig
const EpKeys = @import("ep_keys.zig");

// ... in serve() function, after other endpoints ...

var ep_keys: EpKeys = .{};
const AuthKeys = App.Endpoint.Authenticating(EpKeys, Authenticator);
var auth_keys = AuthKeys.init(&ep_keys, &authenticator);
var pre_auth_keys = PreRouter.Create(AuthKeys).init(&auth_keys);
try App.register(&pre_auth_keys);
```

#### 4. `src/web/templates/html_nav.html` Modification

Add API Keys link (after Travel Expenses, before Logout):
```html
<a href="/keys" class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 font-medium transition-colors duration-200">API Keys</a>
```

## Implementation Steps

### 1. Create ep_keys.zig endpoint handler (30 minutes)
**File**: `src/web/ep_keys.zig`

**Actions**:
- Create new file with endpoint struct
- Implement `get()` and `post()` route dispatchers
- Implement `listKeys()` - load keys, render template
- Implement `createKey()` - parse form, call keys_mod.createKey, redirect with token
- Implement `deleteKey()` - parse form, call keys_mod.deleteKey, redirect

**Testing**:
- `zig build` should succeed (may fail on missing template initially)

### 2. Create keys.html template (20 minutes)
**File**: `src/web/templates/keys.html`

**Actions**:
- Create HTML template following existing patterns
- Add create form with label and expires fields
- Add keys table with mustache iteration
- Add new token display section (conditionally shown)
- Add delete confirmation via JavaScript confirm()
- Ensure dark mode classes on all elements

**Testing**:
- Template compiles (embedded at build time)

### 3. Register endpoint in server.zig (5 minutes)
**File**: `src/web/server.zig`

**Actions**:
- Add import for `ep_keys.zig`
- Create endpoint instance
- Wrap with Authenticating and PreRouter
- Register with App.register()

**Testing**:
- `zig build` succeeds
- Server starts without errors

### 4. Add navigation link (5 minutes)
**File**: `src/web/templates/html_nav.html`

**Actions**:
- Add `<a href="/keys">API Keys</a>` link
- Position after "Travel Expenses", before "Logout"
- Use same CSS classes as other nav links

**Testing**:
- Navigate to any page, verify "API Keys" link appears
- Click link, should go to `/keys`

### 5. Integration testing (15 minutes)
**Actions**:
- Start server: `zig build run -- serve`
- Navigate to `/keys`
- Create a new key, verify token is displayed
- Refresh page, verify key appears in list
- Delete key, verify confirmation dialog
- Verify key is removed from list

## Testing Strategy

### Manual Testing Checklist
- [ ] `/keys` page loads with empty state message
- [ ] Create form submits and shows new token
- [ ] New token cannot be retrieved after page refresh
- [ ] Keys appear in table with correct formatting
- [ ] Dates display as YYYY-MM-DD
- [ ] "never" shown for null expires/last_used
- [ ] Delete button shows confirmation dialog
- [ ] Delete removes key from list
- [ ] Dark mode styling works correctly
- [ ] Mobile responsive layout works
- [ ] Session auth required (redirect to login if not authenticated)

### Edge Cases
- Create key with duplicate label → should show error
- Create key with empty label → form validation prevents
- Delete non-existent key → graceful handling
- Very long label names → table truncation/wrapping
- Special characters in labels

## Risks and Mitigations

### Risk 1: Token exposure in URL
**Risk**: New token passed via query parameter could be logged/cached
**Mitigation**:
- Token only shown once, not stored in history
- Use POST-Redirect-GET pattern
- Consider using session flash message instead (future enhancement)

### Risk 2: Missing keys.zig dependency
**Risk**: Phase 2 depends on Phase 1's keys.zig module
**Mitigation**: Implement Phase 1 first, or stub the keys_mod functions

### Risk 3: Template compilation errors
**Risk**: Mustache template errors only caught at runtime
**Mitigation**: Test template rendering manually after each change

## Success Metrics
- [ ] API Keys link visible in navigation
- [ ] `/keys` page renders correctly
- [ ] Create/delete operations work via web UI
- [ ] Session authentication enforced
- [ ] UI matches existing FJ styling (Tailwind, dark mode)
- [ ] Mobile-responsive layout

## Future Enhancements
- Copy-to-clipboard button for new token
- Search/filter keys by label
- Pagination for large key lists
- Key usage statistics (request count)
- Regenerate key functionality
