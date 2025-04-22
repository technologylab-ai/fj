const std = @import("std");
const zap = @import("zap");
const App = @import("../app.zig");

pub fn start(app: *const App, host: []const u8, port: usize) !void {
    const interface = try std.fmt.allocPrintZ(app.arena, "{s}", .{host});

    var listener = zap.HttpListener.init(.{
        .interface = interface,
        .port = port,
        .on_request = on_request,
        .log = true,
        // .public_folder = app.fi_home.?,
    });
    try listener.listen();

    std.debug.print(
        "Listening on {s}:{d}\nServing: {s}\n\n",
        .{ host, port, app.fi_home.? },
    );

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

fn on_request(r: zap.Request) !void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }
    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}
