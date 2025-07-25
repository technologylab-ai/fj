const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const Fj = @import("../fj.zig");

const Dir = std.fs.Dir;

const auth_types = @import("auth_types.zig");
const Authenticator = auth_types.Authenticator;
const AuthLookup = auth_types.AuthLookup;

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
const EpInit = @import("ep_init.zig");
const EpPreRoute = @import("ep_preroute.zig");
const EpLogout = @import("ep_logout.zig");

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
    // Authentication
    //
    var auth_lookup: AuthLookup = .empty;
    var authenticator = try Authenticator.init(allocator, &auth_lookup, .{
        .usernameParam = "username",
        .passwordParam = "password",
        .loginPage = "/login",
        .cookieName = "FJ_SESSION",
    });
    defer authenticator.deinit();

    //
    // Context
    //
    var context: Context = .{
        .gpa = allocator,
        .auth_lookup = &auth_lookup,
        .authenticator = &authenticator,
        .fj_home = try allocator.dupe(u8, fj_home),
        .work_dir = opts.work_dir,
        .logo_imgdata = blk: {
            break :blk readLogo(allocator, fj_home) catch |err| {
                log.warn("Unable to read logo from fj home: {}", .{err});
                break :blk try allocator.dupe(u8, "empty");
            };
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
    try App.init(allocator, &context, .{});
    defer App.deinit();

    //
    // Endpoints
    //

    // The Pre-Router redirects all requests to /init if FJ is not initialized
    const PreRouter: EpPreRoute = .{ .App = App, .init_route = "/init" };

    var ep_dashboard: EpDashboard = .{};
    const AuthDashboard = App.Endpoint.Authenticating(EpDashboard, Authenticator);
    var auth_dashboard = AuthDashboard.init(&ep_dashboard, &authenticator);
    var pre_auth_dashboard = PreRouter.Create(AuthDashboard).init(&auth_dashboard);

    var ep_login: EpLogin = .{ .main_page = ep_dashboard.path };
    const AuthLogin = App.Endpoint.Authenticating(EpLogin, Authenticator);
    var auth_login = AuthLogin.init(&ep_login, &authenticator);
    var pre_auth_login = PreRouter.Create(AuthLogin).init(&auth_login);

    var ep_git: EpGit = .{};
    const AuthGit = App.Endpoint.Authenticating(EpGit, Authenticator);
    var auth_git = AuthGit.init(&ep_git, &authenticator);
    var pre_auth_git = PreRouter.Create(AuthGit).init(&auth_git);

    const EpClient = EpResource.create(Client);
    var ep_client: EpClient = .{};
    const AuthClient = App.Endpoint.Authenticating(EpClient, Authenticator);
    var auth_client = AuthClient.init(&ep_client, &authenticator);
    var pre_auth_client = PreRouter.Create(AuthClient).init(&auth_client);

    const EpRate = EpResource.create(Rate);
    var ep_rate: EpRate = .{};
    const AuthRate = App.Endpoint.Authenticating(EpRate, Authenticator);
    var auth_rate = AuthRate.init(&ep_rate, &authenticator);
    var pre_auth_rate = PreRouter.Create(AuthRate).init(&auth_rate);

    const EpInvoice = EpDocument.create(Invoice);
    var ep_invoice: EpInvoice = .{};
    const AuthInvoice = App.Endpoint.Authenticating(EpInvoice, Authenticator);
    var auth_invoice = AuthInvoice.init(&ep_invoice, &authenticator);
    var pre_auth_invoice = PreRouter.Create(AuthInvoice).init(&auth_invoice);

    const EpOffer = EpDocument.create(Offer);
    var ep_offer: EpOffer = .{};
    const AuthOffer = App.Endpoint.Authenticating(EpOffer, Authenticator);
    var auth_offer = AuthOffer.init(&ep_offer, &authenticator);
    var pre_auth_offer = PreRouter.Create(AuthOffer).init(&auth_offer);

    const EpLetter = EpDocument.create(Letter);
    var ep_letter: EpLetter = .{};
    const AuthLetter = App.Endpoint.Authenticating(EpLetter, Authenticator);
    var auth_letter = AuthLetter.init(&ep_letter, &authenticator);
    var pre_auth_letter = PreRouter.Create(AuthLetter).init(&auth_letter);

    var ep_travel: EpTravel = .{};
    const AuthTravel = App.Endpoint.Authenticating(EpTravel, Authenticator);
    var auth_travel = AuthTravel.init(&ep_travel, &authenticator);
    var pre_auth_travel = PreRouter.Create(AuthTravel).init(&auth_travel);

    var ep_init: EpInit = .{};

    var ep_logout: EpLogout = .{ .redirect_to = "/login" };
    const AuthLogout = App.Endpoint.Authenticating(EpLogout, Authenticator);
    var auth_logout = AuthLogout.init(&ep_logout, &authenticator);
    var pre_auth_logout = PreRouter.Create(AuthLogout).init(&auth_logout);

    try App.register(&pre_auth_login);
    try App.register(&pre_auth_dashboard);
    try App.register(&pre_auth_git);
    try App.register(&pre_auth_client);
    try App.register(&pre_auth_rate);
    try App.register(&pre_auth_invoice);
    try App.register(&pre_auth_offer);
    try App.register(&pre_auth_letter);
    try App.register(&pre_auth_travel);
    try App.register(&ep_init);
    try App.register(&pre_auth_logout);

    //
    // zap
    //
    const interface = try std.fmt.allocPrintZ(allocator, "{s}", .{opts.host});
    defer allocator.free(interface);

    try App.listen(.{
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
