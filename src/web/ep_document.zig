const std = @import("std");
const zap = @import("zap");
const ep_utils = @import("ep_utils.zig");
const Context = @import("context.zig");
const Fatal = @import("../fatal.zig");
const Format = @import("../format.zig");
const Allocator = std.mem.Allocator;
const Cli = @import("../cli.zig");
const LetterCommand = Cli.LetterCommand;
const OfferCommand = Cli.OfferCommand;
const InvoiceCommand = Cli.InvoiceCommand;

const Git = @import("../git.zig");
const Fj = @import("../fj.zig");

const log = std.log.scoped(.document_endpoint);

const fsutil = @import("../fsutil.zig");
const fj_json = @import("../json.zig");
const Letter = fj_json.Letter;
const Offer = fj_json.Offer;
const Invoice = fj_json.Invoice;

const Document = ep_utils.Document;
const Stats = ep_utils.Stats;

const html_error = @embedFile("templates/error.html");
const html_document_list = @embedFile("templates/document_list.html");
const html_document_editor = @embedFile("templates/document_editor.html");

pub fn create(DocumentType: type) type {
    const doc_type = Fj.documentTypeHumanName(DocumentType);

    const main_page = "/" ++ doc_type;
    const edit_page = main_page ++ "/edit/";
    const view_page = main_page ++ "/view/";
    const pdf_page = main_page ++ "/pdf/";
    const download_page = main_page ++ "/download/";
    const draftpdf_page = main_page ++ "/draftpdf/";

    const new_page = main_page ++ "/new";
    const compile_page = main_page ++ "/compile/";
    const commit_page = main_page ++ "/commit/";

    return struct {
        path: []const u8 = main_page,
        error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

        const Endpoint = @This();
        pub fn get(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            if (r.path) |path| {
                log.info("GET {s} {s}", .{ doc_type, path });

                if (std.mem.eql(u8, path, main_page)) {
                    r.setStatus(.ok);
                    return ep.document_list(arena, context, r);
                }

                if (std.mem.startsWith(u8, path, view_page) and
                    path.len > view_page.len)
                {
                    r.setStatus(.ok);
                    return ep.document_view(
                        arena,
                        context,
                        r,
                        path[view_page.len..],
                    );
                }
                if (std.mem.startsWith(u8, path, edit_page) and
                    path.len > edit_page.len)
                {
                    r.setStatus(.ok);
                    return ep.document_edit(
                        arena,
                        context,
                        r,
                        path[edit_page.len..],
                    );
                }
                if (std.mem.startsWith(u8, path, pdf_page) and
                    path.len > pdf_page.len)
                {
                    r.setStatus(.ok);
                    return ep.document_pdf(
                        arena,
                        context,
                        r,
                        path[pdf_page.len..],
                    );
                }
                if (std.mem.startsWith(u8, path, download_page) and
                    path.len > download_page.len)
                {
                    r.setStatus(.ok);
                    return ep.download_pdf(
                        arena,
                        context,
                        r,
                        path[download_page.len..],
                    );
                }
                if (std.mem.startsWith(u8, path, draftpdf_page) and
                    path.len > draftpdf_page.len)
                {
                    r.setStatus(.ok);
                    return ep.document_draft_pdf(
                        arena,
                        context,
                        r,
                        path[draftpdf_page.len..],
                    );
                }
            }
            return ep_utils.show_404(arena, context, r);
        }

        pub fn post(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            if (r.path) |path| {
                log.info("POST {s} {s}", .{ doc_type, path });

                // /invoice/new/:shortname
                if (std.mem.eql(u8, path, new_page)) {
                    return ep.document_new(
                        arena,
                        context,
                        r,
                    );
                }

                // /invoice/compile/:shortname
                if (std.mem.startsWith(u8, path, compile_page) and
                    path.len > compile_page.len)
                {
                    return ep.document_compile(
                        arena,
                        context,
                        r,
                        path[compile_page.len..],
                    );
                }

                // /invoice/commit/:shortname
                if (std.mem.startsWith(u8, path, commit_page) and
                    path.len > commit_page.len)
                {
                    return ep.document_commit(
                        arena,
                        context,
                        r,
                        path[commit_page.len..],
                    );
                }
            }
            return ep_utils.show_404(arena, context, r);
        }

        fn document_list(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request) !void {
            var fj = ep_utils.createFj(arena, context);
            const year = try fj.year();
            const fj_config = try fj.loadConfigJson();

            const docs_and_stats = try ep_utils.allDocsAndStats(arena, context, &.{DocumentType});
            std.mem.sort(Document, docs_and_stats.documents, {}, Document.greaterThan);

            const params = .{
                .type = doc_type,
                .documents = docs_and_stats.documents,
                .currency_symbol = fj_config.CurrencySymbol,
                .year = year,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_list);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn toDocument(_: *Endpoint, arena: Allocator, obj: anytype, files: Fj.DocumentFileContents) !Document {
            // const DocumentType = @TypeOf(obj);
            // const doc_type = Fj.documentTypeHumanName(DocumentType);
            const status: []const u8 = blk: {
                switch (DocumentType) {
                    Invoice => {
                        if (obj.paid_date == null) {
                            break :blk "open";
                        } else {
                            break :blk "paid";
                        }
                    },
                    Offer => {
                        if (obj.accepted_date == null) {
                            break :blk "open";
                        } else {
                            break :blk "accepted";
                        }
                    },
                    Letter => break :blk "",
                    else => unreachable,
                }
            };

            const amount = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                } else {
                    break :blk try Format.floatThousandsAlloc(
                        arena,
                        @as(f32, @floatFromInt(obj.total orelse 0)),
                        .{ .comma = ',', .sep = '.' },
                    );
                }
            };

            return .{
                .type = doc_type,
                .id = obj.id,
                .client = obj.client_shortname,
                .project = obj.project_name,
                .date = obj.date,
                .sort_date = obj.updated,
                .status = status,
                .amount = amount,
                .json = files.json,
                .billables = files.billables,
                .tex = files.tex,
            };
        }
        fn document_view(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);
            const fj_config = try fj.loadConfigJson();

            const Command = switch (DocumentType) {
                Invoice => InvoiceCommand,
                Offer => OfferCommand,
                Letter => LetterCommand,
                else => unreachable,
            };

            const command: Command = .{
                .positional = .{ .subcommand = .show, .arg = id },
            };

            const files = try fj.cmdShowDocument(command);

            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                files.show.json,
                .{},
            );

            const document = try ep.toDocument(arena, obj, files.show);

            const params = .{
                .type = doc_type,
                .document = document,
                .currency_symbol = fj_config.CurrencySymbol,
                .editable = false,
                .json = document.json,
                .billables = document.billables,
                .tex = document.tex,
                .id = document.id,
                .compile = false,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn document_edit(ep: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);
            const fj_config = try fj.loadConfigJson();

            const document_subdir_name = try fj.findDocumentById(DocumentType, id);
            const document_dir_path = try std.fs.path.join(arena, &.{ context.work_dir, document_subdir_name });
            // we are in workdir
            if (fsutil.isDirPresent(document_dir_path)) {
                // delete it!
                try std.fs.cwd().deleteTree(document_dir_path);
            }

            const Command = switch (DocumentType) {
                Invoice => InvoiceCommand,
                Offer => OfferCommand,
                Letter => LetterCommand,
                else => unreachable,
            };

            const command: Command = .{
                .positional = .{ .subcommand = .checkout, .arg = id },
            };

            const files = try fj.cmdCheckoutDocument(command);

            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                files.checkout.json,
                .{},
            );

            const document = try ep.toDocument(arena, obj, files.checkout);

            const params = .{
                .type = doc_type,
                .document = document,
                .currency_symbol = fj_config.CurrencySymbol,
                .editable = true,
                .json = document.json,
                .billables = document.billables,
                .tex = document.tex,
                .id = document.id,
                .compile = true,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn document_new(
            ep: *Endpoint,
            arena: Allocator,
            context: *Context,
            r: zap.Request,
        ) !void {
            var fj = ep_utils.createFj(arena, context);

            // get the files passed in from the browser
            try r.parseBody();

            const client = try ep_utils.getBodyStrParam(arena, r, "client");
            const rates = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                }
                break :blk try ep_utils.getBodyStrParam(arena, r, "rates");
            };

            const project = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                }
                break :blk try ep_utils.getBodyStrParam(arena, r, "project");
            };

            const expected_path = try std.fmt.allocPrint(
                arena,
                "{s}--{d}-XXX--{s}",
                .{ doc_type, try fj.year(), client },
            );
            if (fsutil.isDirPresent(expected_path)) {
                // delete it
                try std.fs.cwd().deleteTree(expected_path);
            }

            const Command = switch (DocumentType) {
                Invoice => InvoiceCommand,
                Offer => OfferCommand,
                Letter => LetterCommand,
                else => unreachable,
            };

            const command: Command = blk: {
                if (DocumentType == Letter) {
                    break :blk .{
                        // .positional = .{ .subcommand = .new, .arg = client },
                        .positional = .{ .subcommand = .new, .arg = client },
                    };
                } else {
                    break :blk .{
                        .positional = .{ .subcommand = .new, .arg = client },
                        .rates = rates,
                        .project = project,
                    };
                }
            };

            const result = fj.cmdCreateNewDocument(command) catch |err| {
                const message = try std.fmt.allocPrint(
                    arena,
                    "{}:\n{s}",
                    .{ err, Fatal.errormsg },
                );
                var mustache = try zap.Mustache.fromData(html_error);
                defer mustache.deinit();
                const fj_config = try fj.loadConfigJson();
                const result = mustache.build(
                    .{ .message = message, .company = fj_config.CompanyName },
                );
                defer result.deinit();

                if (result.str()) |rendered| {
                    return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
                }
                return error.Mustache;
            };

            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                result.new.files.json,
                .{},
            );

            const document = try ep.toDocument(arena, obj, result.new.files);
            const fj_config = try fj.loadConfigJson();

            // const document_name_instead_of_id = try std.fmt.allocPrint(
            //     arena,
            //     "{s}--{s}--{s}",
            //     .{ doc_type, document.id, document.client },
            // );
            const params = .{
                .type = doc_type,
                .document = document,
                .currency_symbol = fj_config.CurrencySymbol,
                .editable = true,
                .json = document.json,
                .billables = document.billables,
                .tex = document.tex,
                .id = document.id,
                .compile = true,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_editor);
            defer mustache.deinit();
            const mustache_result = mustache.build(params);
            defer mustache_result.deinit();

            if (mustache_result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn document_compile(
            ep: *Endpoint,
            arena: Allocator,
            context: *Context,
            r: zap.Request,
            id: []const u8,
        ) !void {
            var fj = ep_utils.createFj(arena, context);
            const fj_config = try fj.loadConfigJson();
            const document_subdir_name = try fj.findDocumentById(DocumentType, id);
            var cwd = try std.fs.cwd().openDir(document_subdir_name, .{});
            defer cwd.close();

            // get the files passed in from the browser
            try r.parseBody();

            const json = try ep_utils.getBodyStrParam(arena, r, "json");
            const billables = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                }
                break :blk try ep_utils.getBodyStrParam(arena, r, "billables");
            };

            const tex = try ep_utils.getBodyStrParam(arena, r, "tex");

            // now save them
            const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
            const billables_filename = "billables.csv";
            const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

            var json_file = try cwd.createFile(json_filename, .{});
            {
                // block scope for immediate defer
                defer json_file.close();
                try json_file.writeAll(json);
            }

            if (DocumentType != Letter) {
                var billables_file = try cwd.createFile(billables_filename, .{});
                defer billables_file.close();
                try billables_file.writeAll(billables);
            }

            var tex_file = try cwd.createFile(tex_filename, .{});
            {
                defer tex_file.close();
                try tex_file.writeAll(tex);
            }

            const CompileCommand = switch (DocumentType) {
                Invoice => InvoiceCommand,
                Offer => OfferCommand,
                Letter => LetterCommand,
                else => unreachable,
            };

            const compileCommand: CompileCommand = .{
                .positional = .{ .subcommand = .compile, .arg = document_subdir_name },
            };

            const files = fj.cmdCompileDocument(compileCommand, document_subdir_name) catch |err| {
                // show error
                const message = try std.fmt.allocPrint(
                    arena,
                    "Error: {}\n\n{s}",
                    .{ err, Fatal.errormsg },
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
            };

            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                files.compile.json,
                .{},
            );

            const document = try ep.toDocument(arena, obj, files.compile);

            const params = .{
                .type = doc_type,
                .document = document,
                .currency_symbol = fj_config.CurrencySymbol,
                .editable = true,
                .json = document.json,
                .billables = document.billables,
                .tex = document.tex,
                .id = document.id,
                .compile = true,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn document_commit(
            ep: *Endpoint,
            arena: Allocator,
            context: *Context,
            r: zap.Request,
            id: []const u8,
        ) !void {
            var fj = ep_utils.createFj(arena, context);
            const fj_config = try fj.loadConfigJson();
            // we need to find the subdir of the checked out invoice
            const document_subdir_name = std.fs.path.basename(try fj.findDocumentById(DocumentType, id));

            var cwd = try std.fs.cwd().openDir(document_subdir_name, .{});
            defer cwd.close();

            // get the files passed in from the browser
            try r.parseBody();

            const json = try ep_utils.getBodyStrParam(arena, r, "json");
            const billables = blk: {
                if (DocumentType == Letter) {
                    break :blk "";
                }
                break :blk try ep_utils.getBodyStrParam(arena, r, "billables");
            };

            const tex = try ep_utils.getBodyStrParam(arena, r, "tex");

            // now save them
            const json_filename = try std.fmt.allocPrint(arena, "{s}.json", .{doc_type});
            const billables_filename = "billables.csv";
            const tex_filename = try std.fmt.allocPrint(arena, "{s}.tex", .{doc_type});

            var json_file = try cwd.createFile(json_filename, .{});
            {
                // block scope so file is closed immediately
                defer json_file.close();
                try json_file.writeAll(json);
            }

            if (DocumentType != Letter) {
                var billables_file = try cwd.createFile(billables_filename, .{});
                defer billables_file.close();
                try billables_file.writeAll(billables);
            }

            var tex_file = try cwd.createFile(tex_filename, .{});
            {
                defer tex_file.close();
                try tex_file.writeAll(tex);
            }

            const CommitCommand = switch (DocumentType) {
                Invoice => InvoiceCommand,
                Offer => OfferCommand,
                Letter => LetterCommand,
                else => unreachable,
            };

            const commitCommand: CommitCommand = .{
                .force = true,
                .positional = .{ .subcommand = .commit, .arg = document_subdir_name },
            };

            // last parameter makes fj delete the working copy after committing.
            // that way, we don't leave it lying around
            const files = try fj.cmdCommitDocument(commitCommand, document_subdir_name, true);

            const obj = try std.json.parseFromSliceLeaky(
                DocumentType,
                arena,
                files.commit.json,
                .{},
            );

            const document = try ep.toDocument(arena, obj, files.commit);

            const params = .{
                .type = doc_type,
                .document = document,
                .currency_symbol = fj_config.CurrencySymbol,
                .editable = false,
                .json = document.json,
                .billables = document.billables,
                .tex = document.tex,
                .id = document.id,
                .compile = true,
                .is_letter = DocumentType == Letter,
                .company = fj_config.CompanyName,
            };

            var mustache = try zap.Mustache.fromData(html_document_editor);
            defer mustache.deinit();
            const result = mustache.build(params);
            defer result.deinit();

            if (result.str()) |rendered| {
                return ep_utils.sendBody(arena, rendered, fj_config.CompanyName, r);
            }
            return error.Mustache;
        }

        fn document_pdf(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);

            const document_base = try fj.documentBaseDir(DocumentType);

            const human_doctype = Fj.documentTypeHumanName(DocumentType);

            const document_dir_name = blk: {
                if (Fj.startsWithIC(id, human_doctype)) {
                    break :blk id;
                } else {
                    break :blk try fj.findDocumentById(DocumentType, id);
                }
            };

            const pdf_filename = try std.fmt.allocPrint(
                arena,
                "{s}.pdf",
                .{document_dir_name},
            );
            const pdf_path = try std.fs.path.join(
                arena,
                &[_][]const u8{ document_base, document_dir_name, pdf_filename },
            );
            log.info("Opening {s}", .{pdf_path});

            try r.setHeader("Cache-Control", "no-store");
            try r.setContentTypeFromFilename(pdf_filename);
            try r.sendFile(pdf_path);
        }

        fn download_pdf(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);
            const client = r.getParamSlice("client") orelse return error.NoClient;

            const document_base = try fj.documentBaseDir(DocumentType);

            const human_doctype = Fj.documentTypeHumanName(DocumentType);

            const document_dir_name = blk: {
                if (Fj.startsWithIC(id, human_doctype)) {
                    break :blk id;
                } else {
                    break :blk try fj.findDocumentById(DocumentType, id);
                }
            };

            // note: this equals document_dir_name
            const human_pdf_filename = try std.fmt.allocPrint(
                arena,
                "{s}--{s}--{s}.pdf",
                .{ human_doctype, id, client },
            );

            const pdf_filename = try std.fmt.allocPrint(
                arena,
                "{s}.pdf",
                .{document_dir_name},
            );
            const pdf_path = try std.fs.path.join(
                arena,
                &[_][]const u8{ document_base, document_dir_name, pdf_filename },
            );
            log.info("Downloading {s} as {s}", .{ pdf_path, human_pdf_filename });

            try r.setHeader("Cache-Control", "no-store");
            try r.setContentTypeFromFilename(human_pdf_filename);
            const content_disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}\"", .{human_pdf_filename});
            try r.setHeader("Content-Disposition", content_disposition);
            try r.sendFile(pdf_path);
        }

        fn document_draft_pdf(_: *Endpoint, arena: Allocator, context: *Context, r: zap.Request, id: []const u8) !void {
            var fj = ep_utils.createFj(arena, context);

            log.debug("document_draft_pdf called with id {s}", .{id});

            const document_subdir_name = try fj.findDocumentById(DocumentType, id);

            // Linux XDG_OPEN || macos open || windows: explorer.exe?
            const pdf_filename = try std.fmt.allocPrint(
                arena,
                "{s}.pdf",
                .{document_subdir_name},
            );
            const pdf_path = try std.fs.path.join(
                arena,
                &[_][]const u8{ document_subdir_name, pdf_filename },
            );
            log.info("Opening {s}", .{pdf_path});

            try r.setHeader("Cache-Control", "no-store");
            if (fsutil.fileExists(pdf_path)) {
                try r.sendFile(pdf_path);
            } else {
                try r.sendBody(try std.fmt.allocPrint(arena, "{s} not found", .{pdf_path}));
            }
        }
    };
}
