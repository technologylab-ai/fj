const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;

const Git = @import("../git.zig");
const Format = @import("../format.zig");
const Version = @import("../version.zig");

path: []const u8 = "/dashboard",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const Dashboard = @This();

const fj_json = @import("../json.zig");
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const Document = ep_utils.Document;

const html_dashboard = @embedFile("templates/dashboard.html");

/// GET the dashboard
pub fn get(_: *Dashboard, arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);
    const year = try fj.year();
    const fj_config = try fj.loadConfigJson();

    const docs_and_stats = try ep_utils.allDocsAndStats(arena, context, &.{ Invoice, Offer, Letter });
    const stats = docs_and_stats.stats;

    std.mem.sort(Document, docs_and_stats.documents, {}, Document.greaterThan);
    const recent_documents = docs_and_stats.documents[0..@min(docs_and_stats.documents.len, 8)]; // cap at 5

    const git: Git = .{
        .arena = arena,
        .repo_dir = context.fj_home,
    };

    var status_writer = std.io.Writer.Allocating.init(arena);
    _ = try git.status(&status_writer.writer);

    const params = .{
        .recent_docs = recent_documents,
        .currency_symbol = fj_config.CurrencySymbol,
        .invoices_total = stats.num_invoices_total,
        .invoices_open = stats.num_invoices_open,
        .offers_total = stats.num_offers_total,
        .offers_open = stats.num_offers_open,
        .git_status = status_writer.written(),
        .invoiced_total = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.invoiced_total_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .offers_accepted_amount = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.offers_accepted_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .offers_pending_amount = try Format.floatThousandsAlloc(
            arena,
            @as(f32, @floatFromInt(stats.offers_pending_amount)),
            .{ .comma = ',', .sep = '.' },
        ),
        .year = year,
        .company = fj_config.CompanyName,
        .version = Version.version(),
        .fj_home = fj.fj_home.?,
    };

    var mustache = try zap.Mustache.fromData(html_dashboard);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

/// We come here from the login form, and redirect to the GET version (PRG)
pub fn post(ep: *Dashboard, _: Allocator, _: *Context, r: zap.Request) !void {
    try r.redirectTo(ep.path, .see_other);
}
