const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;
const Cli = @import("../cli.zig");

const fsutil = @import("../fsutil.zig");
const generateTexDefaultsTemplate = @import("../fj.zig").generateTexDefaultsTemplate;
const fj_json = @import("../json.zig");

path: []const u8 = "/init",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,
on_ok: []const u8,

const log = std.log.scoped(.init_endpoint);
const html_error = @embedFile("templates/error.html");
const html_init = @embedFile("templates/init.html");

const Init = @This();

pub fn get(ep: *Init, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET {s}", .{path});
        if (std.mem.eql(u8, path, ep.path)) {
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
                    return ep_utils.sendBody(arena, rendered, "", r);
                }
                return error.Mustache;
            }

            // we can init
            const default_json = try generateTexDefaultsTemplate(arena);
            const params = .{
                .json = default_json,
                .csrf_token = ep_utils.csrfTokenFromSession(arena, r),
            };
            var mustache = try zap.Mustache.fromData(html_init);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, "", r);
            }
            return error.Mustache;
        }
    }
    // if /init is not the exact path, redirect to login
    try r.redirectTo(ep.on_ok, null);
}

pub fn post(ep: *Init, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("POST {s}", .{path});
        if (std.mem.eql(u8, path, ep.path)) {
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
                    return ep_utils.sendBody(arena, rendered, "", r);
                }
                return error.Mustache;
            }

            // we can init
            try r.parseBody();

            // CSRF validation
            if (!ep_utils.validateCsrf(arena, r)) {
                r.setStatus(.forbidden);
                try r.sendBody("403 Forbidden: CSRF validation failed");
                return;
            }

            var cwd = try std.fs.cwd().openDir(context.work_dir, .{});
            defer cwd.close();
            const json = try r.getParamStr(arena, "json") orelse return error.Json;
            var json_file = try cwd.createFile("init.json", .{});
            {
                // block scope for immediate defer
                defer json_file.close();
                const fixedup_json = try fixLogoFilenameInJson(arena, json);
                try json_file.writeAll(fixedup_json);
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

            // logo filename got fixed to logo.png in input json
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

            // cleanup the workdir/init.json and the workdir/logo.png
            try cwd.deleteFile("init.json");
            try cwd.deleteFile("logo.png");

            context.gpa.free(context.logo_imgdata);
            context.logo_imgdata = try context.gpa.dupe(u8, logo_png_data);
            return r.redirectTo(ep.on_ok, null);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

fn fixLogoFilenameInJson(arena: std.mem.Allocator, json_in: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSliceLeaky(fj_json.TexDefaults, arena, json_in, .{ .ignore_unknown_fields = true });
    parsed.Logo = "logo.png";
    return std.json.Stringify.valueAlloc(arena, parsed, .{ .whitespace = .indent_4 });
}
