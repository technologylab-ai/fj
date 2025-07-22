const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const Fj = @import("../fj.zig");

const Dir = std.fs.Dir;

const Context = @import("context.zig");
const Version = @import("../version.zig");
const Server = @This();

const fj_json = @import("../json.zig");
const Client = fj_json.Client;
const Rate = fj_json.Rate;
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const EpLogin = @import("ep_login.zig");
const EpDashboard = @import("ep_dashboard.zig");
const EpGit = @import("ep_git.zig");
const EpResource = @import("ep_resource.zig");
const EpDocument = @import("ep_document.zig");
const EpTravel = @import("ep_travel.zig");

const log = std.log.scoped(.server);

pub const InitOpts = struct {
    host: []const u8,
    port: usize,
    username: []const u8,
    password: []const u8,
    work_dir: []const u8 = ".",
};

fn readLogo(allocator: Allocator, fj_home: []const u8) ![]const u8 {
    var fj_home_dir = try std.fs.cwd().openDir(fj_home, .{});
    defer fj_home_dir.close();

    var logo_file = try fj_home_dir.openFile("templates/logo.png", .{});
    defer logo_file.close();

    return logo_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

pub fn start(fj_home: []const u8, opts: InitOpts) !void {
    //
    // Allocator
    //
    var gpa: std.heap.GeneralPurposeAllocator(.{
        // just to be explicit
        .thread_safe = true,
    }) = .{};
    defer std.debug.print("\n\nLeaks detected: {}\n\n", .{gpa.deinit() != .ok});
    const allocator = gpa.allocator();

    log.info("fj version {s} is starting", .{Version.version() orelse "<unknown>"});

    //
    // Context
    //
    var context: Context = .{
        .auth_lookup = .empty,
        .fj_home = try allocator.dupe(u8, fj_home),
        .work_dir = opts.work_dir,
        .logo_imgdata = readLogo(allocator, fj_home) catch |err| {
            std.process.fatal("Unable to read logo from fj home: {}", .{err});
        },
    };
    defer allocator.free(context.fj_home);
    defer allocator.free(context.logo_imgdata);

    // cd into the working directory
    std.process.changeCurDir(context.work_dir) catch |err| {
        std.process.fatal(
            "Cannot change into working directory `{s}`: {}",
            .{ context.work_dir, err },
        );
    };
    // get it back
    context.work_dir = try std.process.getCwdAlloc(allocator);
    log.info("My working directory is: {s}", .{context.work_dir});
    defer allocator.free(context.work_dir);

    // fill the lookup table
    try context.auth_lookup.put(allocator, opts.username, opts.password);
    defer context.auth_lookup.deinit(allocator);

    // debug
    var it = context.auth_lookup.iterator();
    std.log.debug("Registered credentials:", .{});
    while (it.next()) |entry| {
        std.log.debug("    `{s}`: `{s}`", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    std.debug.print("\n", .{});

    //
    // App
    //
    const App = zap.App.Create(Context);
    var app = try App.init(allocator, &context, .{});
    defer app.deinit();

    //
    // Authentication
    //
    const Authenticator = zap.Auth.UserPassSession(@TypeOf(context.auth_lookup), false);
    var authenticator = try Authenticator.init(allocator, &context.auth_lookup, .{
        .usernameParam = "username",
        .passwordParam = "password",
        .loginPage = "/login",
        .cookieName = "FJ_SESSION",
    });
    defer authenticator.deinit();

    //
    // Endpoints
    //

    var ep_dashboard: EpDashboard = .{};
    const AuthDashboard = App.Endpoint.Authenticating(EpDashboard, Authenticator);
    var auth_dashboard = AuthDashboard.init(&ep_dashboard, &authenticator);

    var ep_login: EpLogin = .{ .main_page = ep_dashboard.path };
    const AuthLogin = App.Endpoint.Authenticating(EpLogin, Authenticator);
    var auth_login = AuthLogin.init(&ep_login, &authenticator);

    var ep_git: EpGit = .{};
    const AuthGit = App.Endpoint.Authenticating(EpGit, Authenticator);
    var auth_git = AuthGit.init(&ep_git, &authenticator);

    const EpClient = EpResource.create(Client);
    var ep_client: EpClient = .{};
    const AuthClient = App.Endpoint.Authenticating(EpClient, Authenticator);
    var auth_client = AuthClient.init(&ep_client, &authenticator);

    const EpRate = EpResource.create(Rate);
    var ep_rate: EpRate = .{};
    const AuthRate = App.Endpoint.Authenticating(EpRate, Authenticator);
    var auth_rate = AuthRate.init(&ep_rate, &authenticator);

    const EpInvoice = EpDocument.create(Invoice);
    var ep_invoice: EpInvoice = .{};
    const AuthInvoice = App.Endpoint.Authenticating(EpInvoice, Authenticator);
    var auth_invoice = AuthInvoice.init(&ep_invoice, &authenticator);

    const EpOffer = EpDocument.create(Offer);
    var ep_offer: EpOffer = .{};
    const AuthOffer = App.Endpoint.Authenticating(EpOffer, Authenticator);
    var auth_offer = AuthOffer.init(&ep_offer, &authenticator);

    const EpLetter = EpDocument.create(Letter);
    var ep_letter: EpLetter = .{};
    const AuthLetter = App.Endpoint.Authenticating(EpLetter, Authenticator);
    var auth_letter = AuthLetter.init(&ep_letter, &authenticator);

    var ep_travel: EpTravel = .{};
    const AuthTravel = App.Endpoint.Authenticating(EpTravel, Authenticator);
    var auth_travel = AuthTravel.init(&ep_travel, &authenticator);

    try app.register(&auth_login);
    try app.register(&auth_dashboard);
    try app.register(&auth_git);
    try app.register(&auth_client);
    try app.register(&auth_rate);
    try app.register(&auth_invoice);
    try app.register(&auth_offer);
    try app.register(&auth_letter);
    try app.register(&auth_travel);

    //
    // zap
    //
    const interface = try std.fmt.allocPrintZ(allocator, "{s}", .{opts.host});
    defer allocator.free(interface);

    try app.listen(.{
        .interface = interface,
        .port = opts.port,
    });

    std.debug.print(
        "Serving: {s}\n\nVisit me at http://{s}:{d}\n\n",
        .{
            context.fj_home,
            opts.host,
            opts.port,
        },
    );

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
