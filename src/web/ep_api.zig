const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;
const Cli = @import("../cli.zig");
const Fj = @import("../fj.zig");
const today = @import("../today.zig");

const fj_json = @import("../json.zig");
const Client = fj_json.Client;
const Rate = fj_json.Rate;
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const log = std.log.scoped(.api_endpoint);

path: []const u8 = "/api",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const Endpoint = @This();

// API route prefixes
const api_v1 = "/api/v1";
const clients_route = api_v1 ++ "/clients";
const rates_route = api_v1 ++ "/rates";
const invoices_route = api_v1 ++ "/invoices";
const offers_route = api_v1 ++ "/offers";
const summary_route = api_v1 ++ "/summary";

/// JSON response helper
fn sendJson(arena: Allocator, r: zap.Request, data: anytype) !void {
    const json = try std.json.Stringify.valueAlloc(arena, data, .{});
    try r.setContentType(.JSON);
    return r.sendBody(json);
}

/// JSON error response helper - use enum values like .unauthorized, .not_found, .bad_request
fn sendError(arena: Allocator, r: zap.Request, comptime status: anytype, message: []const u8) !void {
    r.setStatus(status);
    try r.setContentType(.JSON);
    const response = .{ .@"error" = message };
    const json = try std.json.Stringify.valueAlloc(arena, response, .{});
    return r.sendBody(json);
}

/// Check bearer authentication using context's bearer_authenticator
fn checkAuth(context: *Context, r: zap.Request) bool {
    if (context.bearer_authenticator) |bearer_auth| {
        const result = bearer_auth.authenticateRequest(&r);
        return result == .AuthOK;
    }
    return false;
}

pub fn get(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;

    // Check bearer authentication
    if (!checkAuth(context, r)) {
        return sendError(arena, r, .unauthorized, "Invalid or missing API key");
    }

    const path = r.path orelse return sendError(arena, r, .bad_request, "No path");
    log.info("API GET {s}", .{path});

    // Route matching
    if (std.mem.eql(u8, path, clients_route)) {
        return handleListClients(arena, context, r);
    }
    if (std.mem.startsWith(u8, path, clients_route ++ "/") and path.len > clients_route.len + 1) {
        const id = path[clients_route.len + 1 ..];
        return handleGetClient(arena, context, r, id);
    }

    if (std.mem.eql(u8, path, rates_route)) {
        return handleListRates(arena, context, r);
    }
    if (std.mem.startsWith(u8, path, rates_route ++ "/") and path.len > rates_route.len + 1) {
        const id = path[rates_route.len + 1 ..];
        return handleGetRate(arena, context, r, id);
    }

    if (std.mem.eql(u8, path, invoices_route)) {
        return handleListInvoices(arena, context, r);
    }
    if (std.mem.startsWith(u8, path, invoices_route ++ "/") and path.len > invoices_route.len + 1) {
        const rest = path[invoices_route.len + 1 ..];
        return handleInvoiceRoute(arena, context, r, rest);
    }

    if (std.mem.eql(u8, path, offers_route)) {
        return handleListOffers(arena, context, r);
    }
    if (std.mem.startsWith(u8, path, offers_route ++ "/") and path.len > offers_route.len + 1) {
        const rest = path[offers_route.len + 1 ..];
        return handleOfferRoute(arena, context, r, rest);
    }

    if (std.mem.eql(u8, path, summary_route)) {
        return handleSummary(arena, context, r);
    }

    return sendError(arena, r, .not_found, "Unknown API endpoint");
}

pub fn post(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;

    // Check bearer authentication
    if (!checkAuth(context, r)) {
        return sendError(arena, r, .unauthorized, "Invalid or missing API key");
    }

    const path = r.path orelse return sendError(arena, r, .bad_request, "No path");
    log.info("API POST {s}", .{path});

    // POST routes for status changes
    if (std.mem.startsWith(u8, path, invoices_route ++ "/") and path.len > invoices_route.len + 1) {
        const rest = path[invoices_route.len + 1 ..];
        return handleInvoicePostRoute(arena, context, r, rest);
    }

    if (std.mem.startsWith(u8, path, offers_route ++ "/") and path.len > offers_route.len + 1) {
        const rest = path[offers_route.len + 1 ..];
        return handleOfferPostRoute(arena, context, r, rest);
    }

    return sendError(arena, r, .not_found, "Unknown API endpoint");
}

// ============================================================================
// Client endpoints
// ============================================================================

fn handleListClients(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);

    const list_cli: Cli.ClientCommand = .{
        .positional = .{ .subcommand = .list },
    };
    const names = try fj.handleRecordCommand(list_cli);

    var clients = std.ArrayListUnmanaged(Client).empty;
    for (names.list) |shortname| {
        const obj = try fj.loadRecord(Client, try arena.dupe(u8, shortname), .{ .custom_path = null });
        try clients.append(arena, obj);
    }

    return sendJson(arena, r, .{ .clients = try clients.toOwnedSlice(arena) });
}

fn handleGetClient(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const obj = fj.loadRecord(Client, try arena.dupe(u8, id), .{ .custom_path = null }) catch {
        return sendError(arena, r, .not_found, "Client not found");
    };

    return sendJson(arena, r, obj);
}

// ============================================================================
// Rate endpoints
// ============================================================================

fn handleListRates(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);

    const list_cli: Cli.RateCommand = .{
        .positional = .{ .subcommand = .list },
    };
    const names = try fj.handleRecordCommand(list_cli);

    var rates = std.ArrayListUnmanaged(Rate).empty;
    for (names.list) |shortname| {
        const obj = try fj.loadRecord(Rate, try arena.dupe(u8, shortname), .{ .custom_path = null });
        try rates.append(arena, obj);
    }

    return sendJson(arena, r, .{ .rates = try rates.toOwnedSlice(arena) });
}

fn handleGetRate(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const obj = fj.loadRecord(Rate, try arena.dupe(u8, id), .{ .custom_path = null }) catch {
        return sendError(arena, r, .not_found, "Rate not found");
    };

    return sendJson(arena, r, obj);
}

// ============================================================================
// Invoice endpoints
// ============================================================================

fn handleListInvoices(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);

    const list_cli: Cli.InvoiceCommand = .{
        .positional = .{ .subcommand = .list },
    };
    const names = try fj.cmdListDocuments(list_cli);

    var invoices = std.ArrayListUnmanaged(Invoice).empty;
    for (names.list) |name| {
        const id = try ep_utils.documentIdFromName(name);
        const show_cli: Cli.InvoiceCommand = .{
            .positional = .{ .subcommand = .show, .arg = id },
        };
        const files = try fj.cmdShowDocument(show_cli);
        const obj = try std.json.parseFromSliceLeaky(Invoice, arena, files.show.json, .{});
        try invoices.append(arena, obj);
    }

    return sendJson(arena, r, .{ .invoices = try invoices.toOwnedSlice(arena) });
}

fn handleInvoiceRoute(arena: Allocator, context: *Context, r: zap.Request, rest: []const u8) !void {
    // Check if rest contains a slash (e.g., "2024-001/paid")
    if (std.mem.indexOf(u8, rest, "/")) |_| {
        // This is a sub-route, but GET only supports fetching
        return sendError(arena, r, .method_not_allowed, "Use POST for status changes");
    }

    // Just an ID - get the invoice
    return handleGetInvoice(arena, context, r, rest);
}

fn handleGetInvoice(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const show_cli: Cli.InvoiceCommand = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };
    const files = fj.cmdShowDocument(show_cli) catch {
        return sendError(arena, r, .not_found, "Invoice not found");
    };

    const obj = try std.json.parseFromSliceLeaky(Invoice, arena, files.show.json, .{});
    return sendJson(arena, r, obj);
}

fn handleInvoicePostRoute(arena: Allocator, context: *Context, r: zap.Request, rest: []const u8) !void {
    // Parse "ID/action" format
    if (std.mem.indexOf(u8, rest, "/")) |slash_pos| {
        const id = rest[0..slash_pos];
        const action = rest[slash_pos + 1 ..];

        if (std.mem.eql(u8, action, "paid")) {
            return handleMarkInvoicePaid(arena, context, r, id);
        }
    }

    return sendError(arena, r, .bad_request, "Invalid invoice action");
}

fn handleMarkInvoicePaid(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    // Load the invoice
    const show_cli: Cli.InvoiceCommand = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };
    const files = fj.cmdShowDocument(show_cli) catch {
        return sendError(arena, r, .not_found, "Invoice not found");
    };

    var obj = try std.json.parseFromSliceLeaky(Invoice, arena, files.show.json, .{});

    if (obj.paid_date != null) {
        return sendError(arena, r, .bad_request, "Invoice is already marked as paid");
    }

    // Set paid date to today
    const today_str = try today.getTodayString(arena);
    obj.paid_date = today_str;
    obj.updated = try fj.isoTime();

    // Write back using fj's document writing
    try fj.writeDocumentJson(Invoice, id, obj);

    return sendJson(arena, r, .{ .success = true, .invoice = obj });
}

// ============================================================================
// Offer endpoints
// ============================================================================

fn handleListOffers(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);

    const list_cli: Cli.OfferCommand = .{
        .positional = .{ .subcommand = .list },
    };
    const names = try fj.cmdListDocuments(list_cli);

    var offers = std.ArrayListUnmanaged(Offer).empty;
    for (names.list) |name| {
        const id = try ep_utils.documentIdFromName(name);
        const show_cli: Cli.OfferCommand = .{
            .positional = .{ .subcommand = .show, .arg = id },
        };
        const files = try fj.cmdShowDocument(show_cli);
        const obj = try std.json.parseFromSliceLeaky(Offer, arena, files.show.json, .{});
        try offers.append(arena, obj);
    }

    return sendJson(arena, r, .{ .offers = try offers.toOwnedSlice(arena) });
}

fn handleOfferRoute(arena: Allocator, context: *Context, r: zap.Request, rest: []const u8) !void {
    // Check if rest contains a slash
    if (std.mem.indexOf(u8, rest, "/")) |_| {
        return sendError(arena, r, .method_not_allowed, "Use POST for status changes");
    }

    return handleGetOffer(arena, context, r, rest);
}

fn handleGetOffer(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const show_cli: Cli.OfferCommand = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };
    const files = fj.cmdShowDocument(show_cli) catch {
        return sendError(arena, r, .not_found, "Offer not found");
    };

    const obj = try std.json.parseFromSliceLeaky(Offer, arena, files.show.json, .{});
    return sendJson(arena, r, obj);
}

fn handleOfferPostRoute(arena: Allocator, context: *Context, r: zap.Request, rest: []const u8) !void {
    // Parse "ID/action" format
    if (std.mem.indexOf(u8, rest, "/")) |slash_pos| {
        const id = rest[0..slash_pos];
        const action = rest[slash_pos + 1 ..];

        if (std.mem.eql(u8, action, "accept")) {
            return handleAcceptOffer(arena, context, r, id);
        }
        if (std.mem.eql(u8, action, "reject")) {
            return handleRejectOffer(arena, context, r, id);
        }
    }

    return sendError(arena, r, .bad_request, "Invalid offer action");
}

fn handleAcceptOffer(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const show_cli: Cli.OfferCommand = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };
    const files = fj.cmdShowDocument(show_cli) catch {
        return sendError(arena, r, .not_found, "Offer not found");
    };

    var obj = try std.json.parseFromSliceLeaky(Offer, arena, files.show.json, .{});

    if (obj.accepted_date != null) {
        return sendError(arena, r, .bad_request, "Offer is already accepted");
    }
    if (obj.declined_date != null) {
        return sendError(arena, r, .bad_request, "Offer is already declined");
    }

    const today_str = try today.getTodayString(arena);
    obj.accepted_date = today_str;
    obj.updated = try fj.isoTime();

    try fj.writeDocumentJson(Offer, id, obj);

    return sendJson(arena, r, .{ .success = true, .offer = obj });
}

fn handleRejectOffer(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const show_cli: Cli.OfferCommand = .{
        .positional = .{ .subcommand = .show, .arg = id },
    };
    const files = fj.cmdShowDocument(show_cli) catch {
        return sendError(arena, r, .not_found, "Offer not found");
    };

    var obj = try std.json.parseFromSliceLeaky(Offer, arena, files.show.json, .{});

    if (obj.accepted_date != null) {
        return sendError(arena, r, .bad_request, "Offer is already accepted");
    }
    if (obj.declined_date != null) {
        return sendError(arena, r, .bad_request, "Offer is already declined");
    }

    const today_str = try today.getTodayString(arena);
    obj.declined_date = today_str;
    obj.updated = try fj.isoTime();

    try fj.writeDocumentJson(Offer, id, obj);

    return sendJson(arena, r, .{ .success = true, .offer = obj });
}

// ============================================================================
// Summary endpoint
// ============================================================================

fn handleSummary(arena: Allocator, context: *Context, r: zap.Request) !void {
    const result = try ep_utils.allDocsAndStats(arena, context, &[_]type{ Invoice, Offer });

    const summary = .{
        .invoices = .{
            .total = result.stats.num_invoices_total,
            .open = result.stats.num_invoices_open,
            .total_amount = result.stats.invoiced_total_amount,
            .open_amount = result.stats.invoices_open_amount,
        },
        .offers = .{
            .total = result.stats.num_offers_total,
            .open = result.stats.num_offers_open,
            .pending_amount = result.stats.offers_pending_amount,
            .accepted_amount = result.stats.offers_accepted_amount,
        },
    };

    return sendJson(arena, r, summary);
}
