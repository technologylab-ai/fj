# Feature: FJ API Extension Phase 4 - REST API Endpoints

## Overview
This is Phase 4 of the FJ API Extension implementation. It creates the full REST API endpoint handler (`ep_api.zig`) that serves JSON responses for all `/api/v1/*` routes.

**Depends on**: Phase 3 (Bearer authentication with `BearerMulti` and `HashedApiKeySet`)

## Requirements

### Functional Requirements
- All API endpoints return JSON (`application/json`)
- `/api/v1/health` is accessible without authentication
- All other endpoints require Bearer token authentication
- Query parameters support filtering (status, client, project, date ranges)
- Responses include computed fields (status, days_until_due, etc.)
- 404 errors return JSON, not HTML

### Non-Functional Requirements
- Reuse existing document reading logic from `ep_utils.zig` and `fj.zig`
- Consistent error response format across all endpoints
- Support for query parameter parsing

## Technical Design

### Architecture

**Endpoint Structure:**
```
/api/v1/
├── health                      # No auth - server health check
├── me                          # Auth info for current key
├── clients                     # List all clients
├── clients/{name}              # Single client with statistics
├── rates                       # List all rates
├── invoices                    # List invoices (with filters)
├── invoices/{id}               # Single invoice with line items
├── offers                      # List offers (with filters)
├── offers/{id}                 # Single offer with line items
├── summary                     # Financial summary
├── summary/client/{name}       # Client-specific summary
└── summary/project/{project}   # OMS project summary
```

### Core Implementation

#### 1. `src/web/ep_api.zig` (New File)

```zig
const std = @import("std");
const zap = @import("zap");
const Context = @import("context.zig");
const ep_utils = @import("ep_utils.zig");
const Fj = @import("../fj.zig");
const fj_json = @import("../json.zig");
const Allocator = std.mem.Allocator;
const zeit = @import("zeit");

const Invoice = fj_json.Invoice;
const Offer = fj_json.Offer;
const Client = fj_json.Client;
const Rate = fj_json.Rate;

path: []const u8 = "/api/v1",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const EpApi = @This();

pub fn get(ep: *EpApi, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;

    if (r.path) |path| {
        // Health check - no auth required
        if (std.mem.eql(u8, path, "/api/v1/health")) {
            return sendJson(r, arena, .{
                .status = "ok",
                .version = "1.0.0",
                .fj_home = context.fj_home,
            });
        }

        // Auth info
        if (std.mem.eql(u8, path, "/api/v1/me")) {
            return handleMe(arena, context, r);
        }

        // Clients
        if (std.mem.eql(u8, path, "/api/v1/clients")) {
            return handleListClients(arena, context, r);
        }
        if (std.mem.startsWith(u8, path, "/api/v1/clients/")) {
            const name = path["/api/v1/clients/".len..];
            return handleGetClient(arena, context, r, name);
        }

        // Rates
        if (std.mem.eql(u8, path, "/api/v1/rates")) {
            return handleListRates(arena, context, r);
        }

        // Invoices
        if (std.mem.eql(u8, path, "/api/v1/invoices")) {
            return handleListInvoices(arena, context, r);
        }
        if (std.mem.startsWith(u8, path, "/api/v1/invoices/")) {
            const id = path["/api/v1/invoices/".len..];
            return handleGetInvoice(arena, context, r, id);
        }

        // Offers
        if (std.mem.eql(u8, path, "/api/v1/offers")) {
            return handleListOffers(arena, context, r);
        }
        if (std.mem.startsWith(u8, path, "/api/v1/offers/".len..)) {
            const id = path["/api/v1/offers/".len..];
            return handleGetOffer(arena, context, r, id);
        }

        // Summary endpoints
        if (std.mem.eql(u8, path, "/api/v1/summary")) {
            return handleSummary(arena, context, r);
        }
        if (std.mem.startsWith(u8, path, "/api/v1/summary/client/")) {
            const name = path["/api/v1/summary/client/".len..];
            return handleClientSummary(arena, context, r, name);
        }
        if (std.mem.startsWith(u8, path, "/api/v1/summary/project/")) {
            const project = path["/api/v1/summary/project/".len..];
            return handleProjectSummary(arena, context, r, project);
        }
    }

    // 404 for unknown routes
    return sendJsonError(r, arena, .not_found, "not_found", "Unknown API endpoint");
}

// ... handler implementations below
```

#### 2. JSON Response Helpers

```zig
fn sendJson(r: zap.Request, arena: Allocator, data: anytype) !void {
    r.setHeader("Content-Type", "application/json") catch {};
    var buffer = std.ArrayList(u8).init(arena);
    try std.json.stringify(data, .{ .emit_null_optional_fields = false }, buffer.writer());
    try r.sendBody(buffer.items);
}

fn sendJsonError(r: zap.Request, arena: Allocator, status: zap.StatusCode, code: []const u8, message: []const u8) !void {
    r.setStatus(status);
    return sendJson(r, arena, .{
        .@"error" = code,
        .message = message,
    });
}
```

#### 3. Invoice/Offer Status Computation

```zig
const InvoiceStatus = enum { pending, paid, overdue };
const OfferStatus = enum { draft, sent, accepted, rejected, expired };

fn computeInvoiceStatus(invoice: Invoice, today: []const u8) InvoiceStatus {
    if (invoice.paid_date != null) return .paid;

    if (invoice.due_date) |due| {
        if (std.mem.order(u8, due, today) == .lt) return .overdue;
    }
    return .pending;
}

fn computeOfferStatus(offer: Offer, today: []const u8) OfferStatus {
    if (offer.accepted_date != null) return .accepted;
    if (offer.declined_date != null) return .rejected;

    // Check if expired
    if (offer.valid_thru) |valid| {
        if (std.mem.order(u8, valid, today) == .lt) return .expired;
    }

    // Has date means it was sent
    if (!std.mem.eql(u8, offer.date, "HEUTE") and offer.date.len > 0) {
        return .sent;
    }
    return .draft;
}

fn daysBetween(from: []const u8, to: []const u8) ?i32 {
    // Parse YYYY-MM-DD format and compute difference
    // Implementation uses zeit library
    // ...
}
```

#### 4. Handler Implementations

**handleListInvoices:**
```zig
fn handleListInvoices(arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);
    const today = try getTodayString(arena);

    // Parse query parameters
    const status_filter = r.getParamSlice("status") orelse "all";
    const client_filter = r.getParamSlice("client");
    const project_filter = r.getParamSlice("project");

    // Reuse existing document listing logic
    const docs_and_stats = try ep_utils.allDocsAndStats(arena, context, &.{Invoice});

    var invoices = std.ArrayList(InvoiceResponse).init(arena);
    var total_amount: i64 = 0;

    for (docs_and_stats.documents) |doc| {
        // Get full invoice data
        const files = try fj.cmdShowDocument(.{
            .positional = .{ .subcommand = .show, .arg = doc.id },
        });
        const invoice = try std.json.parseFromSliceLeaky(
            Invoice,
            arena,
            files.show.json,
            .{},
        );

        // Apply filters
        if (client_filter) |cf| {
            if (!std.mem.eql(u8, invoice.client_shortname, cf)) continue;
        }
        if (project_filter) |pf| {
            if (invoice.oms_project) |op| {
                if (!std.mem.eql(u8, op, pf)) continue;
            } else continue;
        }

        const status = computeInvoiceStatus(invoice, today);
        if (!std.mem.eql(u8, status_filter, "all")) {
            const expected = std.meta.stringToEnum(InvoiceStatus, status_filter) orelse {
                return sendJsonError(r, arena, .bad_request, "invalid_parameter",
                    "Invalid status filter. Allowed: pending, paid, overdue, all");
            };
            if (status != expected) continue;
        }

        const response = InvoiceResponse{
            .id = invoice.id,
            .client = invoice.client_shortname,
            .oms_project = invoice.oms_project,
            .date = invoice.date,
            .due_date = invoice.due_date,
            .status = @tagName(status),
            .days_until_due = if (status == .pending) daysBetween(today, invoice.due_date.?) else null,
            .days_overdue = if (status == .overdue) daysBetween(invoice.due_date.?, today) else null,
            .total = invoice.total,
            .paid_at = invoice.paid_date,
        };

        try invoices.append(response);
        total_amount += invoice.total orelse 0;
    }

    return sendJson(r, arena, .{
        .invoices = invoices.items,
        .summary = .{
            .count = invoices.items.len,
            .total_amount = total_amount,
            .currency = "EUR",
        },
    });
}
```

**handleGetInvoice (with line items):**
```zig
fn handleGetInvoice(arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
    var fj = ep_utils.createFj(arena, context);

    const files = fj.cmdShowDocument(.{
        .positional = .{ .subcommand = .show, .arg = id },
    }) catch {
        return sendJsonError(r, arena, .not_found, "not_found",
            try std.fmt.allocPrint(arena, "Invoice '{s}' not found", .{id}));
    };

    const invoice = try std.json.parseFromSliceLeaky(
        Invoice,
        arena,
        files.show.json,
        .{},
    );

    // Parse billables.csv for line items
    const items = try parseBillables(arena, files.show.billables);

    const today = try getTodayString(arena);
    const status = computeInvoiceStatus(invoice, today);

    return sendJson(r, arena, .{
        .id = invoice.id,
        .client = invoice.client_shortname,
        .oms_project = invoice.oms_project,
        .date = invoice.date,
        .due_date = invoice.due_date,
        .status = @tagName(status),
        .days_until_due = if (status == .pending) daysBetween(today, invoice.due_date.?) else null,
        .days_overdue = if (status == .overdue) daysBetween(invoice.due_date.?, today) else null,
        .vat_rate = invoice.vat.percent,
        .total = invoice.total,
        .paid_at = invoice.paid_date,
        .description = invoice.project_name,
        .items = items,
        .files = .{
            .meta = try std.fmt.allocPrint(arena, "invoices/invoice--{s}--{s}/meta.json",
                .{ invoice.id, invoice.client_shortname }),
        },
    });
}
```

## Implementation Steps

### 1. Create ep_api.zig framework (30 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- Create endpoint struct with path `/api/v1`
- Implement `get()` method with route matching
- Add `sendJson()` and `sendJsonError()` helpers
- Add `/api/v1/health` and `/api/v1/me` handlers

**Testing**:
- `zig build` succeeds
- Server starts, `/api/v1/health` returns JSON

### 2. Implement status computation (15 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- Add `InvoiceStatus` and `OfferStatus` enums
- Implement `computeInvoiceStatus()` with pending/paid/overdue logic
- Implement `computeOfferStatus()` with draft/sent/accepted/rejected/expired logic
- Add `daysBetween()` helper using zeit

**Testing**:
- Unit tests for status computation

### 3. Implement client/rate endpoints (20 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- `handleListClients()` - iterate `FJ_HOME/clients/*.json`
- `handleGetClient()` - read single client + compute statistics
- `handleListRates()` - iterate `FJ_HOME/rates/*.json`

**Testing**:
- `/api/v1/clients` returns client list
- `/api/v1/rates` returns rate list

### 4. Implement invoice endpoints (30 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- `handleListInvoices()` - reuse `ep_utils.allDocsAndStats()`, add filtering
- `handleGetInvoice()` - read invoice + parse billables.csv for line items
- Add query parameter parsing for status, client, project, since, until

**Testing**:
- `/api/v1/invoices` returns invoice list
- `/api/v1/invoices?status=pending` filters correctly
- `/api/v1/invoices/{id}` returns invoice with items

### 5. Implement offer endpoints (25 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- `handleListOffers()` - similar to invoices with offer-specific status
- `handleGetOffer()` - read offer + parse billables.csv

**Testing**:
- `/api/v1/offers` returns offer list
- `/api/v1/offers?status=sent` filters correctly

### 6. Implement summary endpoints (30 minutes)
**File**: `src/web/ep_api.zig`

**Actions**:
- `handleSummary()` - aggregate data for period (revenue, pending, overdue, pipeline)
- `handleClientSummary()` - client-specific aggregation
- `handleProjectSummary()` - filter by `oms_project` field

**Testing**:
- `/api/v1/summary` returns financial overview
- `/api/v1/summary/client/{name}` returns client stats
- `/api/v1/summary/project/{project}` returns project stats

### 7. Register endpoint in server.zig (10 minutes)
**File**: `src/web/server.zig`

**Actions**:
- Import `EpApi` and `api_auth`
- Register `/api/v1` endpoint with Bearer authentication
- Ensure health endpoint bypasses auth

**Testing**:
- Unauthenticated request to `/api/v1/invoices` returns 401
- Request with valid token returns 200

## Billables CSV Parsing

The `billables.csv` format (for line items):
```csv
Group;Description;Qty;Unit;Rate
Development;Model architecture design;16;hours;120.00
Development;Training pipeline;12;hours;120.00
Documentation;Docs;1;flat;211.43
```

Parser implementation:
```zig
const BillableItem = struct {
    group: []const u8,
    description: []const u8,
    quantity: f32,
    unit: []const u8,
    unit_price: f32,
    amount: f32,
};

fn parseBillables(arena: Allocator, csv: []const u8) ![]BillableItem {
    var items = std.ArrayList(BillableItem).init(arena);
    var lines = std.mem.splitScalar(u8, csv, '\n');

    // Skip header
    _ = lines.next();

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');

        const group = fields.next() orelse continue;
        const desc = fields.next() orelse continue;
        const qty_str = fields.next() orelse continue;
        const unit = fields.next() orelse continue;
        const rate_str = fields.next() orelse continue;

        const qty = try std.fmt.parseFloat(f32, qty_str);
        const rate = try std.fmt.parseFloat(f32, rate_str);

        try items.append(.{
            .group = group,
            .description = desc,
            .quantity = qty,
            .unit = unit,
            .unit_price = rate,
            .amount = qty * rate,
        });
    }

    return items.toOwnedSlice();
}
```

## Response Type Structs

Define explicit response structs for type safety:

```zig
const InvoiceListItem = struct {
    id: []const u8,
    client: []const u8,
    oms_project: ?[]const u8,
    date: []const u8,
    due_date: ?[]const u8,
    status: []const u8,
    days_until_due: ?i32,
    days_overdue: ?i32,
    total: ?i64,
    paid_at: ?[]const u8,
};

const InvoiceDetail = struct {
    id: []const u8,
    client: []const u8,
    oms_project: ?[]const u8,
    date: []const u8,
    due_date: ?[]const u8,
    status: []const u8,
    days_until_due: ?i32,
    days_overdue: ?i32,
    vat_rate: usize,
    total: ?i64,
    paid_at: ?[]const u8,
    description: []const u8,
    items: []BillableItem,
    files: struct {
        meta: []const u8,
    },
};

const ClientListItem = struct {
    name: []const u8,
    company: []const u8,
    address: struct {
        street: []const u8,
        city: []const u8,
        postal_code: []const u8,
        country: []const u8,
    },
};
```

## Testing Strategy

### Manual Testing Checklist
- [ ] `/api/v1/health` returns JSON without auth
- [ ] `/api/v1/me` returns 401 without token
- [ ] `/api/v1/me` returns key info with valid token
- [ ] `/api/v1/clients` lists all clients
- [ ] `/api/v1/clients/{name}` returns 404 for unknown client
- [ ] `/api/v1/rates` lists all rates
- [ ] `/api/v1/invoices` lists all invoices
- [ ] `/api/v1/invoices?status=pending` filters correctly
- [ ] `/api/v1/invoices?client=X` filters by client
- [ ] `/api/v1/invoices?project=Y` filters by OMS project
- [ ] `/api/v1/invoices/{id}` includes line items
- [ ] `/api/v1/offers` lists all offers with correct status
- [ ] `/api/v1/summary` returns financial overview
- [ ] Invalid query parameters return 400 with helpful message
- [ ] Unknown routes return 404 JSON (not HTML)

### Test Commands
```bash
# Health (no auth)
curl http://localhost:3000/api/v1/health | jq

# With auth
TOKEN="fj_sk_..."
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/me | jq
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/invoices | jq
curl -H "Authorization: Bearer $TOKEN" "http://localhost:3000/api/v1/invoices?status=pending" | jq
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/summary | jq
```

## Risks and Mitigations

### Risk 1: Performance with many documents
**Risk**: Large number of invoices/offers could slow down listing
**Mitigation**: Implement `limit` query parameter (default 100, max 500)

### Risk 2: Field name mapping errors
**Risk**: API response field names differ from json.zig struct field names
**Mitigation**: Use explicit response structs, not direct serialization of internal types

### Risk 3: Date parsing/formatting issues
**Risk**: Different date formats in meta.json vs API expectations
**Mitigation**: Validate and normalize dates; use zeit for all date operations

## Success Metrics
- [ ] All 12+ API endpoints implemented and working
- [ ] Query parameter filtering works for all list endpoints
- [ ] Status computation accurate for invoices and offers
- [ ] Line items (billables) included in single-document endpoints
- [ ] Summary endpoints aggregate data correctly
- [ ] JSON error responses instead of HTML for all error cases
- [ ] Bearer authentication enforced (except /health)

## Future Enhancements
- Pagination with cursor-based navigation
- More flexible date filtering (this_month, last_quarter, etc.)
- CSV export endpoint
- Webhook notifications for status changes
