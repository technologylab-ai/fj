const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const travelpdfs = @import("../travelpdfs.zig");
const zip = @import("../zip.zig");

const html_travellog = @embedFile("templates/travellog.html");
const html_traveldocs = @embedFile("templates/traveldocsdownload.html");

const Allocator = std.mem.Allocator;
const Travel = @This();
const log = std.log.scoped(.travel);

comptime path: []const u8 = "/travel",
error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

/// Show the login form
pub fn get(ep: *Travel, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("GET {s}", .{path});

        if (std.mem.eql(u8, path, ep.path)) {
            return ep.show_travel_form(arena, context, r);
        }
        if (std.mem.startsWith(u8, path, ep.path ++ "-download")) {
            return ep.downloadZip(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

pub fn post(ep: *Travel, arena: Allocator, context: *Context, r: zap.Request) !void {
    if (r.path) |path| {
        log.info("POST {s}", .{path});

        if (std.mem.eql(u8, path, ep.path ++ "-submit")) {
            return ep.submit_travel_form(arena, context, r);
        }
    }
    try ep_utils.show_404(arena, context, r);
}

fn show_travel_form(_: *Travel, arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    const params = .{
        .company = fj_config.CompanyName,
    };

    var mustache = try zap.Mustache.fromData(html_travellog);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

fn submit_travel_form(_: *Travel, arena: Allocator, context: *Context, r: zap.Request) !void {
    var fj = ep_utils.createFj(arena, context);
    const fj_config = try fj.loadConfigJson();

    // parse STRING form parameters
    //
    try r.parseBody();
    const travelerName = try ep_utils.getBodyStrParam(arena, r, "travelerName");
    const travelDestination = try ep_utils.getBodyStrParam(arena, r, "travelDestination");
    const travelPeriodFrom = try ep_utils.getBodyStrParam(arena, r, "travelPeriodFrom");
    const travelPeriodTo = try ep_utils.getBodyStrParam(arena, r, "travelPeriodTo");
    const travelPurpose = try ep_utils.getBodyStrParam(arena, r, "travelPurpose");
    const travelComments = try ep_utils.getBodyStrParam(arena, r, "travelComments");

    // parse TRANSPORT TABLES
    //
    const Transport = struct {
        kind: []const u8,
        description: []const u8,
        pub fn format(
            self: @This(),
            writer: *std.io.Writer,
        ) !void {
            try writer.print(
                "{{type=\"{s}\", description=\"{s}\"",
                .{ self.kind, self.description },
            );
        }
    };
    var outbound_transports: std.ArrayListUnmanaged(Transport) = .empty;
    var return_transports: std.ArrayListUnmanaged(Transport) = .empty;

    var key_buffer: [128]u8 = undefined;
    var key: []const u8 = undefined;
    var transport_index: usize = 0;
    while (transport_index < 100) : ({
        transport_index += 1;
    }) { // safety-net
        key = try std.fmt.bufPrint(&key_buffer, "outboundTravelTableType_{d}", .{transport_index});
        const ttype_param = ep_utils.getBodyStrParam(arena, r, key) catch |err| {
            switch (err) {
                error.NotFound => break,
                else => return err,
            }
        };

        key = try std.fmt.bufPrint(&key_buffer, "outboundTravelTableDescription_{d}", .{transport_index});
        const tdesc_param = ep_utils.getBodyStrParam(arena, r, key) catch |err| {
            switch (err) {
                error.NotFound => break,
                else => return err,
            }
        };

        try outbound_transports.append(arena, .{ .kind = ttype_param, .description = tdesc_param });
    }

    log.info("outbound_transports = ", .{});
    for (outbound_transports.items) |item| {
        log.info("    - {f}", .{item});
    }

    transport_index = 0;
    while (transport_index < 100) : ({
        transport_index += 1;
    }) { // safety-net
        key = try std.fmt.bufPrint(&key_buffer, "returnTravelTableType_{d}", .{transport_index});
        const ttype_param = ep_utils.getBodyStrParam(arena, r, key) catch |err| {
            switch (err) {
                error.NotFound => break,
                else => return err,
            }
        };

        key = try std.fmt.bufPrint(&key_buffer, "returnTravelTableDescription_{d}", .{transport_index});
        const tdesc_param = ep_utils.getBodyStrParam(arena, r, key) catch |err| {
            switch (err) {
                error.NotFound => break,
                else => return err,
            }
        };

        try return_transports.append(arena, .{ .kind = ttype_param, .description = tdesc_param });
    }
    log.info("return_transports = ", .{});
    for (return_transports.items) |item| {
        log.info("    - {f}", .{item});
    }

    // parse RECEIPT UPLOADS
    //

    const Receipt = struct {
        filename: []const u8,
        human_given_name: []const u8,
        contents: []const u8,
        pub fn format(
            self: @This(),
            writer: *std.io.Writer,
        ) !void {
            try writer.print(
                "{{filename=\"{s}\", human_given_name=\"{s}\", data_len={d}",
                .{ self.filename, self.human_given_name, self.contents.len },
            );
        }
    };

    var receipts_list = std.ArrayListUnmanaged(Receipt).empty;

    // I am lazy
    const form_params = try r.parametersToOwnedList(arena);
    // defer params.deinit(); // it's an arena, bro!
    for (form_params.items) |kv| {
        if (kv.value) |v| {
            // let's check if it's a field we care about eventough the type would handle that for us
            if (std.mem.startsWith(u8, kv.key, "receiptFile_")) {
                const form_index = kv.key["receiptFile_".len..];
                const associated_desc_param_name = try std.fmt.allocPrint(arena, "receiptName_{s}", .{form_index});
                const userdefined_filename = try ep_utils.getBodyStrParam(arena, r, associated_desc_param_name);
                log.info("Upload {s}={s}", .{ kv.key, userdefined_filename });

                const vv = try ep_utils.getBodyParam(r, kv.key);
                log.info("\n\n\n       found key : {s} = {}", .{ kv.key, vv });
                var vvv = try zap.Request.fiobj2HttpParam(arena, vv) orelse unreachable;

                _ = v; // v makes us crash
                switch (vvv) {
                    // single-file upload
                    zap.Request.HttpParam.Hash_Binfile => |*file| {
                        log.info("SINGLE-FILE-UPLOAD", .{});
                        const filename = file.filename orelse "(no filename)";
                        const mimetype = file.mimetype orelse "(no mimetype)";
                        const data = file.data orelse "";

                        std.log.debug("    filename: `{s}`", .{filename});
                        std.log.debug("    mimetype: {s}", .{mimetype});
                        std.log.debug("    contents: len={d}", .{data.len});
                        try receipts_list.append(arena, .{
                            .filename = try arena.dupe(u8, filename),
                            .contents = try arena.dupe(u8, data),
                            .human_given_name = try arena.dupe(u8, userdefined_filename),
                        });
                    },
                    // multi-file upload
                    // NOTE: probably due to how our form is structured, we get each file twice
                    //       hence, we explicitly BREAK in the for loop below
                    zap.Request.HttpParam.Array_Binfile => |*files| {
                        log.info("MULTI-FILE-UPLOAD", .{});
                        for (files.*.items, 0..) |file, file_index| {
                            const filename = file.filename orelse "(no filename)";
                            const mimetype = file.mimetype orelse "(no mimetype)";
                            const data = file.data orelse "";

                            std.log.debug("    ---------------", .{});
                            std.log.debug("    filename: `{s}`", .{filename});
                            std.log.debug("    mimetype: {s}", .{mimetype});
                            std.log.debug("    contents: len={d}", .{data.len});
                            std.log.debug("    ---------------", .{});

                            // NOTE: for whatever reason, we receive all filed TWICE.
                            //       yet we only need to keep one instance, obvsly.

                            if (file_index == 0) {
                                try receipts_list.append(arena, .{
                                    .filename = try arena.dupe(u8, filename),
                                    .contents = try arena.dupe(u8, data),
                                    .human_given_name = try arena.dupe(u8, userdefined_filename),
                                });
                            }
                            // break;
                        }
                        files.*.deinit(arena);
                    },
                    else => {
                        // let's just get it as its raw slice
                        const value: []const u8 = r.getParamSlice(kv.key) orelse "(no value)";
                        std.log.debug("   {s} = {s}", .{ kv.key, value });
                    },
                }
            }
        }
    }
    log.info("Received receipts: ", .{});
    for (receipts_list.items) |item| {
        log.info("    - {f}", .{item});
    }

    // process UPLOADS
    //

    // convert images to resized JPEGS and then to PDF in output dir
    //
    const TMP = context.work_dir;
    const pre_prefix = try std.fmt.allocPrint(arena, "Reise_{s}", .{travelPeriodFrom[0.."2025-07-04".len]});
    const temp_dir_name = try std.fmt.allocPrint(arena, "{s}/{s}", .{ TMP, pre_prefix });
    try std.fs.cwd().makePath(temp_dir_name);
    var temp_dir = try std.fs.cwd().openDir(temp_dir_name, .{});
    defer temp_dir.close();

    var receipt_pdf_list = std.ArrayListUnmanaged(struct { pdf_name: []const u8 }).empty;
    for (receipts_list.items) |receipt| {
        const pdf_nameZ = try std.fmt.allocPrintSentinel(
            arena,
            "{s}/{s}_Beleg_{s}.pdf",
            .{ temp_dir_name, pre_prefix, receipt.human_given_name },
            0,
        );
        const pdf_basename = std.fs.path.basename(pdf_nameZ);
        try receipt_pdf_list.append(arena, .{ .pdf_name = pdf_basename });
        if (std.ascii.endsWithIgnoreCase(receipt.filename, ".pdf")) {
            var ofile = try temp_dir.createFile(pdf_nameZ, .{});
            defer ofile.close();
            var obuf: [1024]u8 = undefined;
            var ofile_writer = ofile.writer(&obuf);
            const writer = &ofile_writer.interface;
            try writer.writeAll(receipt.contents);
            try writer.flush();
            log.info("Generated {s})", .{pdf_basename});
        } else {
            // generate the PDF from image
            try travelpdfs.generateReceiptPdf(receipt.filename, receipt.contents, pdf_nameZ, arena);
        }
    }

    // now generate the protocol
    const protocol_mustache =
        \\# Reiseprotokoll {{{companyName}}}
        \\
        \\**Reisender:** {{{travelerName}}}
        \\
        \\**Reiseziel:** {{{travelDestination}}}
        \\**Reisezeitraum:** {{{travelPeriodFrom}}} — {{{travelPeriodTo}}}
        \\**Reisezweck:** {{{travelPurpose}}}
        \\
        \\**Transportmittel:**
        \\
        \\    **Hinfahrt:**
        \\ {{#outbound_transports}}
        \\        • **{{{kind}}}:** {{{description}}}
        \\ {{/outbound_transports}}
        \\
        \\
        \\    **Rückfahrt:**
        \\ {{#return_transports}}
        \\        • **{{{kind}}}:** {{{description}}}
        \\ {{/return_transports}}
        \\
        \\**Liste der hochgeladenen Belege:**
        \\ {{#receipt_pdf_list}}
        \\    • {{{pdf_name}}}
        \\ {{/receipt_pdf_list}}
        \\
        \\**Anmerkungen:** {{{travelComments}}}
    ;

    const ts_from = try arena.dupe(u8, travelPeriodFrom);
    std.mem.replaceScalar(u8, ts_from, 'T', ' ');
    const ts_to = try arena.dupe(u8, travelPeriodTo);
    std.mem.replaceScalar(u8, ts_to, 'T', ' ');
    const protocol_text = blk: {
        var mustache = try zap.Mustache.fromData(protocol_mustache);
        defer mustache.deinit();
        const result = mustache.build(.{
            .companyName = fj_config.CompanyName,
            .travelerName = travelerName,
            .travelDestination = travelDestination,
            .travelPeriodFrom = ts_from,
            .travelPeriodTo = ts_to,
            .travelPurpose = travelPurpose,
            .outbound_transports = outbound_transports.items,
            .return_transports = return_transports.items,
            .receipt_pdf_list = receipt_pdf_list.items,
            .travelComments = travelComments,
        });
        defer result.deinit();

        if (result.str()) |rendered| {
            break :blk rendered;
        }
        break :blk "error";
    };

    const protocol_pdf_name = try std.fmt.allocPrintSentinel(
        arena,
        "{s}/{s}.pdf",
        .{ temp_dir_name, pre_prefix },
        0,
    );
    try travelpdfs.generateProtocolPdf(arena, protocol_pdf_name, protocol_text);
    try receipt_pdf_list.append(arena, .{ .pdf_name = std.fs.path.basename(protocol_pdf_name) });

    // now zip it
    var zip_pdf_path_list = std.ArrayList([]const u8).empty;
    for (receipt_pdf_list.items) |item| {
        try zip_pdf_path_list.append(
            arena,
            try std.fmt.allocPrint(arena, "{s}/{s}", .{ pre_prefix, item.pdf_name }),
        );
    }

    const zip_basename = try std.fmt.allocPrint(arena, "{s}.zip", .{pre_prefix});
    try zip.zip(arena, .{
        .zip_name = zip_basename,
        .filenames = zip_pdf_path_list.items,
        .work_dir = TMP,
    });

    // remove zipped dir
    try std.fs.cwd().deleteTree(temp_dir_name);

    // output HTML
    //
    const params = .{
        .message = protocol_text,
        .zip_name = zip_basename,
    };

    var mustache = try zap.Mustache.fromData(html_traveldocs);
    defer mustache.deinit();
    const result = mustache.build(params);
    defer result.deinit();

    if (result.str()) |rendered| {
        return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
    }
    return error.Mustache;
}

pub fn downloadZip(ep: *Travel, arena: Allocator, context: *Context, r: zap.Request) !void {
    _ = ep;
    const TMP = context.work_dir;
    const zip_basename = r.getParamSlice("zip") orelse return error.NoZipParam;
    r.setStatus(.ok);
    try r.setHeader("Cache-Control", "no-store");
    const full_zip_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ TMP, zip_basename });
    log.debug("trying to send: `{s}`", .{full_zip_path});
    try r.setContentTypeFromFilename(zip_basename);
    const content_disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}\"", .{zip_basename});
    try r.setHeader("Content-Disposition", content_disposition);
    try r.sendFile(full_zip_path);
}
