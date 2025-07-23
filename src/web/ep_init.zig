const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;
const Cli = @import("../cli.zig");

const fsutil = @import("../fsutil.zig");
const generateTexDefaultsTemplate = @import("../fj.zig").generateTexDefaultsTemplate;

path: []const u8 = "/init",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

const log = std.log.scoped(.init_endpoint);
const html_error = @embedFile("templates/error.html");
const html_init = @embedFile("templates/init.html");

const Init = @This();

pub fn get(_: *Init, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        if (std.mem.eql(u8, path, "/init")) {
            log.info("Using FJ_HOME = `{s}`", .{context.fj_home});
            if (fsutil.isDirPresent(context.fj_home)) {
                const message = try std.fmt.allocPrint(
                    arena,
                    "Error: FJ_HOME {s} already exists!",
                    .{context.fj_home},
                );

                var mustache = try zap.Mustache.fromData(html_error);
                defer mustache.deinit();
                const result = mustache.build(.{
                    .message = message,
                    .company = "",
                });
                defer result.deinit();

                if (result.str()) |rendered| {
                    return r.sendBody(rendered);
                }
                return error.Mustache;
            }

            // we can init
            const default_json = try generateTexDefaultsTemplate(arena);
            const params = .{
                .json = default_json,
            };
            var mustache = try zap.Mustache.fromData(html_init);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return r.sendBody(rendered);
            }
            return error.Mustache;
        }
    }
    // if /init is not the exact path, redirect to login
    try r.redirectTo("/login", null);
}

pub fn post(_: *Init, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("POST {s}", .{path});
        if (std.mem.eql(u8, path, "/init")) {
            log.info("Using FJ_HOME = `{s}`", .{context.fj_home});
            if (fsutil.isDirPresent(context.fj_home)) {
                const message = try std.fmt.allocPrint(
                    arena,
                    "Error: FJ_HOME {s} already exists!",
                    .{context.fj_home},
                );

                var mustache = try zap.Mustache.fromData(html_error);
                defer mustache.deinit();
                const result = mustache.build(.{
                    .message = message,
                    .company = "",
                });
                defer result.deinit();

                if (result.str()) |rendered| {
                    return r.sendBody(rendered);
                }
                return error.Mustache;
            }

            // we can init
            try r.parseBody();
            var cwd = try std.fs.cwd().openDir(context.work_dir, .{});
            defer cwd.close();
            const json = try r.getParamStr(arena, "json") orelse return error.Json;
            var json_file = try cwd.createFile("init.json", .{});
            {
                // block scope for immediate defer
                defer json_file.close();
                try json_file.writeAll(json);
            }
            log.debug("Wrote init.json", .{});

            const form_params = try r.parametersToOwnedList(arena);
            const logo_png_data = blk: {
                for (form_params.items) |kv| {
                    if (kv.value) |v| {
                        // let's check if it's a field we care about eventough the type would handle that for us
                        if (std.mem.startsWith(u8, kv.key, "logo")) {
                            switch (v) {
                                // single-file upload
                                zap.Request.HttpParam.Hash_Binfile => |*file| {
                                    log.info("SINGLE-FILE-UPLOAD", .{});
                                    const filename = file.filename orelse "(no filename)";
                                    const mimetype = file.mimetype orelse "(no mimetype)";
                                    const data = file.data orelse "";

                                    log.debug("    filename: `{s}`", .{filename});
                                    log.debug("    mimetype: {s}", .{mimetype});
                                    log.debug("    contents: len={d}", .{data.len});
                                    break :blk try arena.dupe(u8, data);
                                },
                                else => {},
                            }
                        }
                    }
                }
                break :blk "invalid";
            };

            // TODO: we should make sure to either use the logo filename in the json or to
            // fix the json to logo.png
            var logo_file = try cwd.createFile("logo.png", .{});
            {
                // block scope for immediate defer
                defer logo_file.close();
                try logo_file.writeAll(logo_png_data);
            }

            const command: Cli.InitCommand = .{
                .positional = .{ .init_json_file = try std.fmt.allocPrint(arena, "{s}/init.json", .{context.work_dir}) },
            };

            var fj = ep_utils.createFj(arena, context);
            try fj.cmd_init(command);
            context.gpa.free(context.logo_imgdata);
            context.logo_imgdata = try context.gpa.dupe(u8, logo_png_data);
            try r.redirectTo("/login", null);
        }
    }
    // if /init is not the exact path, redirect to login
    try r.redirectTo("/login", null);
}
