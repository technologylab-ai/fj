const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Allocator = std.mem.Allocator;
const Cli = @import("../cli.zig");
const ClientCommand = Cli.ClientCommand;
const RateCommand = Cli.RateCommand;

const Git = @import("../git.zig");
const Fj = @import("../fj.zig");

const log = std.log.scoped(.resource_endpoint);

const fsutil = @import("../fsutil.zig");
const fj_json = @import("../json.zig");
const Client = fj_json.Client;
const Rate = fj_json.Rate;

const html_error = @embedFile("templates/error.html");
const html_resource_editor = @embedFile("templates/resource_editor.html");
const html_resource_list = @embedFile("templates/resource_list.html");

pub fn create(ResourceType: type) type {
    const type_string = switch (ResourceType) {
        Client => "client",
        Rate => "rate",
        else => unreachable,
    };

    const main_page = "/" ++ type_string;
    const edit_page = main_page ++ "/edit/";
    const view_page = main_page ++ "/view/";
    const new_page = main_page ++ "/new";
    const commit_page = main_page ++ "/commit";

    return struct {
        path: []const u8 = main_page,
        error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

        const Endpoint = @This();
        pub fn get(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            if (r.path) |path| {
                log.info("GET {s} {s}", .{ type_string, path });

                if (std.mem.eql(u8, path, main_page)) {
                    r.setStatus(.ok);
                    return ep.resource_list(arena, context, r);
                }
                if (std.mem.startsWith(u8, path, view_page) and
                    path.len > view_page.len)
                {
                    r.setStatus(.ok);
                    return ep.resource_view(
                        arena,
                        context,
                        r,
                        path[view_page.len..],
                        false,
                    );
                }
                if (std.mem.startsWith(u8, path, edit_page) and
                    path.len > edit_page.len)
                {
                    r.setStatus(.ok);
                    return ep.resource_view(
                        arena,
                        context,
                        r,
                        path[edit_page.len..],
                        true,
                    );
                }
            }
            return ep_utils.show_404(arena, context, r);
        }

        pub fn post(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            if (r.path) |path| {
                log.info("POST {s} {s}", .{ type_string, path });

                if (std.mem.eql(u8, path, new_page)) {
                    return ep.resource_new(
                        arena,
                        context,
                        r,
                    );
                }

                if (std.mem.startsWith(u8, path, commit_page) and
                    path.len > commit_page.len)
                {
                    return ep.resource_commit(
                        arena,
                        context,
                        r,
                        path[commit_page.len..],
                    );
                }
            }
            return ep_utils.show_404(arena, context, r);
        }

        fn resource_list(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            const ListItem = struct {
                shortname: []const u8,
                remarks: []const u8,

                pub fn lessThan(ctx: void, a: @This(), b: @This()) bool {
                    _ = ctx;
                    return std.mem.order(u8, a.shortname, b.shortname) == .lt;
                }

                pub fn greaterThan(ctx: void, a: @This(), b: @This()) bool {
                    _ = ctx;
                    return std.mem.order(u8, a.shortname, b.shortname) == .gt;
                }
            };

            var fj = ep_utils.createFj(arena, context);
            log.debug("fj_home: {s}", .{fj.fj_home.?});

            const CliCommand = switch (ResourceType) {
                Client => ClientCommand,
                Rate => RateCommand,
                else => unreachable,
            };

            const resources = blk: {
                var list = std.ArrayListUnmanaged(ListItem).empty;

                // 1. get all the clients / rates
                const list_cli: CliCommand = .{
                    .positional = .{ .subcommand = .list },
                };

                const names = try fj.handleRecordCommand(list_cli);
                for (names.list) |shortname| {
                    log.debug("trying to load {} {s} {s}", .{ ResourceType, type_string, shortname });
                    const obj = try fj.loadRecord(ResourceType, try arena.dupe(u8, shortname), .{ .custom_path = null });
                    try list.append(arena, .{
                        // we don't dup() them because of the arena
                        .shortname = obj.shortname,
                        .remarks = obj.remarks orelse "",
                    });
                }

                // 2. sort them descendingly by date
                const sorted = try list.toOwnedSlice(arena);
                std.mem.sort(ListItem, sorted, {}, ListItem.lessThan);

                break :blk sorted;
            };

            const fj_config = try fj.loadConfigJson();
            const params = .{
                .type = type_string,
                .resources = resources,
                .company = fj_config.CompanyName,
            };
            var mustache = try zap.Mustache.fromData(html_resource_list);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn resource_view(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8, editable: bool) !void {
            var fj = ep_utils.createFj(arena, context);
            log.debug("fj_home: {s}", .{fj.fj_home.?});

            const obj = try fj.loadRecord(
                ResourceType,
                try arena.dupe(u8, id),
                .{ .custom_path = null },
            );

            const json = try std.json.Stringify.valueAlloc(arena, obj, .{ .whitespace = .indent_4 });

            const fj_config = try fj.loadConfigJson();
            const params = .{
                .type = type_string,
                .shortname = id,
                .json = json,
                .editable = editable,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_resource_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn resource_new(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            var fj = ep_utils.createFj(arena, context);
            const fj_config = try fj.loadConfigJson();
            log.debug("fj_home: {s}", .{fj.fj_home.?});

            try r.parseBody();

            const shortname = try ep_utils.getBodyStrParam(arena, r, "shortname");
            const expected_filename = try std.fmt.allocPrint(arena, "{s}.json", .{shortname});
            if (fsutil.fileExists(expected_filename)) {
                const message = try std.fmt.allocPrint(
                    arena,
                    "Error: {s} {s} already exists!",
                    .{ type_string, shortname },
                );

                var mustache = try zap.Mustache.fromData(html_error);
                defer mustache.deinit();
                const result = mustache.build(.{
                    .message = message,
                    .company = fj_config.CompanyName,
                });
                defer result.deinit();

                if (result.str()) |rendered| {
                    return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
                }
                return error.Mustache;
            }

            const Command = switch (ResourceType) {
                Client => ClientCommand,
                Rate => RateCommand,
                else => unreachable,
            };

            const command: Command = .{
                .positional = .{ .subcommand = .new, .arg = shortname },
            };

            // this creates a temp file meant for manual editing. we don't need
            // it, so we're going to delete it shortly
            _ = try fj.handleRecordCommand(command);

            const obj = try fj.loadRecord(
                ResourceType,
                try arena.dupe(u8, shortname),
                .{ .custom_path = context.work_dir },
            );

            // after that, we don't need the file anymore, since we're going
            // to POST from the browser directly when committing
            var path_buf: [Fj.max_path_bytes]u8 = undefined;
            const temp_file_path = try fj.recordPath(ResourceType, shortname, context.work_dir, &path_buf);
            log.info("temp_file_path = {s}", .{temp_file_path});
            try std.fs.cwd().deleteFile(temp_file_path);

            const json = try std.json.Stringify.valueAlloc(arena, obj, .{ .whitespace = .indent_4 });

            const params = .{
                .type = type_string,
                .shortname = shortname,
                .json = json,
                .editable = true,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_resource_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn resource_commit(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, shortname: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);

            try r.parseBody();

            const json = try ep_utils.getBodyStrParam(arena, r, "json");
            // const fio_params = r.h.*.params;
            // log.debug("type of params = {s}", .{util.fiobj_type(r.h.*.params)});

            // const param_count = zap.fio.fiobj_hash_count(fio_params);
            // log.debug("param_count = {d}", .{param_count});

            var path_buf: [Fj.max_path_bytes]u8 = undefined;
            const new_revision = blk: {
                const json_path = try fj.recordPath(ResourceType, shortname, null, &path_buf);
                if (fsutil.fileExists(json_path)) {
                    const existing = try fj.loadRecord(ResourceType, shortname, .{});
                    break :blk existing.revision + 1;
                } else {
                    break :blk 0;
                }
            };

            // now parse the specified one
            var obj = try std.json.parseFromSliceLeaky(ResourceType, arena, json, .{});
            obj.revision = new_revision;
            obj.updated = try fj.isoTime();

            // and write it into fj_home
            _ = try fj.writeRecord(shortname, obj, .{ .allow_overwrite = true });
            try r.redirectTo("/dashboard", null);
        }
    };
}
