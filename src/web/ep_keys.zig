const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const keys_mod = @import("../keys.zig");
const json = @import("../json.zig");
const Allocator = std.mem.Allocator;
const Fj = @import("../fj.zig");

const log = std.log.scoped(.keys_endpoint);

path: []const u8 = "/keys",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const EpKeys = @This();
const html_keys = @embedFile("templates/keys.html");

pub fn get(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET keys {s}", .{path});

        if (std.mem.eql(u8, path, ep.path)) {
            return ep.listKeys(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

pub fn post(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("POST keys {s}", .{path});

        // CSRF validation for all POST requests
        try r.parseBody();
        if (!ep_utils.validateCsrf(arena, r)) {
            r.setStatus(.forbidden);
            try r.sendBody("403 Forbidden: CSRF validation failed");
            return;
        }

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
    const store = keys_mod.loadKeys(arena, context.fj_home) catch json.ApiKeyStore{ .keys = &.{} };

    // Check for new_token query param (after create redirect)
    const new_token = r.getParamSlice("new_token");
    const error_param = r.getParamSlice("error");
    const deleted = r.getParamSlice("deleted");

    // Build template params
    var keys_list = std.ArrayListUnmanaged(KeyView).empty;
    for (store.keys) |key| {
        if (key.deleted) continue;
        try keys_list.append(arena, .{
            .label = key.label,
            .created_at = if (key.created_at.len >= 10) key.created_at[0..10] else key.created_at,
            .expires_at = if (key.expires_at) |e| (if (e.len >= 10) e[0..10] else e) else "never",
            .last_used_at = if (key.last_used_at) |u| (if (u.len >= 10) u[0..10] else u) else "never",
        });
    }

    const params = .{
        .keys = keys_list.items,
        .new_token = new_token orelse "",
        .has_new_token = new_token != null,
        .error_message = error_param orelse "",
        .has_error = error_param != null,
        .deleted = deleted != null,
        .csrf_token = ep_utils.csrfTokenFromSession(arena, r),
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
    // Body already parsed in post() handler

    const label = ep_utils.getBodyStrParam(arena, r, "label") catch {
        return r.redirectTo("/keys?error=missing_label", null);
    };

    // Check for empty label
    if (label.len == 0) {
        return r.redirectTo("/keys?error=empty_label", null);
    }

    const expires_raw = ep_utils.getBodyStrParam(arena, r, "expires") catch null;
    const expires = if (expires_raw) |e| (if (e.len > 0) e else null) else null;

    // Create key using keys.zig module
    const token = keys_mod.createKey(arena, context.fj_home, label, expires) catch |err| {
        switch (err) {
            error.LabelAlreadyExists => return r.redirectTo("/keys?error=duplicate_label", null),
            else => return r.redirectTo("/keys?error=create_failed", null),
        }
    };

    // Add the new key's hash to the in-memory set for immediate use
    if (context.api_key_set) |key_set| {
        const token_hash = try keys_mod.hashToken(arena, token);
        try key_set.putHash(token_hash);
    }

    // Redirect back with token in query param (shown once)
    const redirect_url = try std.fmt.allocPrint(arena, "/keys?new_token={s}", .{token});
    return r.redirectTo(redirect_url, null);
}

fn deleteKey(ep: *EpKeys, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    // Body already parsed in post() handler

    const label = ep_utils.getBodyStrParam(arena, r, "label") catch {
        return r.redirectTo("/keys?error=missing_label", null);
    };

    keys_mod.deleteKey(arena, context.fj_home, label) catch {
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
