const std = @import("std");
const zeit = @import("zeit");
const Cli = @import("cli.zig");
const templates = @import("templates.zig");
const fsutil = @import("fsutil.zig");
const Git = @import("git.zig");
const fi_json = @import("json.zig");
const format = @import("format.zig");
const PdfLatex = @import("pdflatex.zig");
const OpenCommand = @import("opencommand.zig");

const Fatal = @import("fatal.zig");
const fatal = Fatal.fatal;

const Allocator = std.mem.Allocator;
const path = std.fs.path;
const assert = std.debug.assert;
const File = std.fs.File;
const Dir = std.fs.Dir;
const cwd = std.fs.cwd;
pub const startsWithIC = std.ascii.startsWithIgnoreCase;

const max_path_bytes = std.fs.max_path_bytes;
const max_name_bytes = std.fs.max_name_bytes;

const log = std.log.scoped(.fi);

const Fi = @This();

arena: Allocator,

// buffer for fi_home: so the arena can be reset between commands, outside of Fi
buf_fi_home: [1024]u8 = undefined,
fi_home: ?[]const u8 = null,

max_json_file_size: usize = 1024 * 1024,
max_bin_file_size: usize = 10 * 1024 * 1024,

const SubDirs = enum {
    clients,
    rates,
    letters,
    offers,
    invoices,
    templates,
};

pub fn setup(self: *Fi, fi_home: ?[]const u8) !void {
    _ = try self.fiHome(fi_home);
}

pub fn deinit(self: *const Fi) void {
    _ = self;
}

fn expandHomeDir(self: *const Fi, p: []const u8) ![]const u8 {
    if (std.process.getEnvVarOwned(self.arena, "HOME")) |v| {
        return std.mem.replaceOwned(u8, self.arena, p, "~", v) catch |err| {
            try fatal("Cannot get expand {s}: {}\n", .{ p, err }, err);
        };
    } else |err| {
        try fatal("Cannot get $HOME: {}\n", .{err}, err);
    }
    unreachable;
}

fn fiHome(self: *Fi, from_args: ?[]const u8) ![]const u8 {
    // return cached
    if (self.fi_home) |p| return p;

    // try from -C cmdline arg
    if (from_args) |p| return p;
    self.fi_home = blk: {
        // try from env var
        if (std.process.getEnvVarOwned(self.arena, "FI_HOME")) |v| {
            if (v.len >= self.buf_fi_home.len) {
                try fatal(
                    "Error: FI_HOME content is too large: {d} > {d}\n",
                    .{ v.len, self.buf_fi_home.len },
                    error.NoSpaceLeft,
                );
            }
            @memcpy(self.buf_fi_home[0..v.len], v);
            break :blk self.buf_fi_home[0..v.len];
        } else |err| {
            switch (err) {
                error.OutOfMemory => try fatal("Cannot get $FI_HOME: Out of memory!\n", .{}, err),
                error.InvalidWtf8 => try fatal("Cannot get $FI_HOME: Invalid Wtf8 sequence!\n", .{}, err),
                error.EnvironmentVariableNotFound => break :blk "",
            }
            return err;
        }
    };

    // still no match -> try $HOME/.fi
    if (self.fi_home.?.len == 0) {
        const expanded_dir = try self.expandHomeDir("~/.fi");
        if (expanded_dir.len >= self.buf_fi_home.len) {
            try fatal(
                "Error: expanded ~/.fi content is too large: {d} > {d}\n",
                .{ expanded_dir.len, self.buf_fi_home.len },
                error.NoSpaceLeft,
            );
        }
        @memcpy(self.buf_fi_home[0..expanded_dir.len], expanded_dir);
        self.fi_home = self.buf_fi_home[0..expanded_dir.len];
    }
    return self.fi_home.?;
}

fn fiHomeTest(self: *Fi, from_args: ?[]const u8) ![]const u8 {
    const fi_home = try self.fiHome(from_args);
    if (!fsutil.isDirPresent(fi_home)) {
        try fatal(
            "No FI_HOME ({s}) found! Did you call `fi init`?",
            .{fi_home},
            error.NotFound,
        );
    }
    return fi_home;
}

fn generateTexDefaultsTemplate(self: *Fi) ![]const u8 {
    var alist = std.ArrayListUnmanaged(u8).empty;
    const writer = alist.writer(self.arena);
    const defaults: fi_json.TexDefaults = .{};
    std.json.stringify(defaults, .{ .whitespace = .indent_4 }, writer) catch |err| {
        try fatal("Error generating Tex defaults: {}", .{err}, err);
    };

    return self.arena.dupe(u8, alist.items) catch |err| {
        try fatal("OOM returning Tex defaults: {}", .{err}, err);
    };
}

pub fn loadConfigJson(self: *const Fi) !fi_json.TexDefaults {
    if (self.fi_home == null) return error.Uninitialized;
    const fi_home = self.fi_home.?;
    var fi_home_dir = cwd().openDir(fi_home, .{}) catch |err| {
        try fatal("Cannot open fi_home dir `{s}`: {}", .{ fi_home, err }, err);
    };
    defer fi_home_dir.close();

    var fi_config_file = fi_home_dir.openFile("config.json", .{}) catch |err| {
        try fatal("Error opening file `{s}/config.json`: {}", .{ fi_home, err }, err);
    };
    defer fi_config_file.close();

    const json_string = try fi_config_file.readToEndAlloc(self.arena, self.max_json_file_size);
    const json_config = std.json.parseFromSliceLeaky(fi_json.TexDefaults, self.arena, json_string, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        try fatal("Error parsing config.json: {}", .{err}, err);
    };
    return json_config;
}

pub fn cmd_init(self: *Fi, args: Cli.InitCommand) !void {
    const fi_home = try self.fiHome(args.fi_home);

    log.info("Using FI_HOME = `{s}`", .{fi_home});
    if (fsutil.isDirPresent(fi_home)) {
        try fatal("FI_HOME `{s}` already exists!", .{fi_home}, error.PathAlreadyExists);
    }

    if (args.generate) {
        if (args.positional.init_json_file) |output_filename| {
            const default_json = try self.generateTexDefaultsTemplate();
            var ofile = cwd().createFile(output_filename, .{ .exclusive = true }) catch |err| {
                try fatal("Unable to create {s}: {}", .{ output_filename, err }, err);
            };
            defer ofile.close();
            ofile.writeAll(default_json) catch |err| {
                try fatal("Unable to write {s}: {}", .{ output_filename, err }, err);
            };
            log.info("✅ Generated: {s}", .{output_filename});
            return;
        }
        try fatal(
            "Please provide an output json filename: --generate=true <filename.json>. See -h.",
            .{},
            error.Cli,
        );
    }

    // try to read json config
    var json_config: fi_json.TexDefaults = .{};
    {
        const init_json_file = if (args.positional.init_json_file) |json_file| json_file else {
            try fatal(
                "Please provide an input json filename.\nGenerate a template with --generate=true <filename.json>. See -h.",
                .{},
                error.Cli,
            );
        };
        var ifile = cwd().openFile(init_json_file, .{}) catch |err| {
            try fatal("Unable to open {s}: {}", .{ init_json_file, err }, err);
        };
        defer ifile.close();

        const json_string = ifile.readToEndAlloc(self.arena, self.max_json_file_size) catch |err| {
            switch (err) {
                error.OutOfMemory => try fatal(
                    "File {s} too large: > {d} bytes!",
                    .{
                        init_json_file,
                        self.max_json_file_size,
                    },
                    err,
                ),
                else => try fatal("Error reading {s}: {}", .{ init_json_file, err }, err),
            }
        };

        json_config = std.json.parseFromSliceLeaky(fi_json.TexDefaults, self.arena, json_string, .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            try fatal("Error parsing {s}: {}", .{ init_json_file, err }, err);
        };

        // check logo extension
        if (!std.ascii.endsWithIgnoreCase(json_config.Logo, ".png")) {
            try fatal(
                "Sorry, logo filename must end with .png! ({s})",
                .{json_config.Logo},
                error.WrongExtension,
            );
        }

        // try to see if logo is present
        var logo_file = cwd().openFile(json_config.Logo, .{}) catch |err| {
            try fatal("Error reading logo file {s}: {}", .{ json_config.Logo, err }, err);
        };
        logo_file.close();
    }

    // create dirs, incl. archive subdir
    {
        const dirs = &[_][]const u8{
            @tagName(SubDirs.clients),
            @tagName(SubDirs.rates),
            try path.join(self.arena, &[_][]const u8{ @tagName(SubDirs.letters), "generated" }),
            try path.join(self.arena, &[_][]const u8{ @tagName(SubDirs.offers), "generated" }),
            try path.join(self.arena, &[_][]const u8{ @tagName(SubDirs.invoices), "generated" }),
            @tagName(SubDirs.templates),
        };

        for (dirs) |dir| {
            const archive = try path.join(self.arena, &[_][]const u8{ fi_home, dir, "archive" });
            log.info("Creating... {s}", .{archive});
            try cwd().makePath(archive);

            // put a .keep file in there
            const dest_path = try path.join(
                self.arena,
                &[_][]const u8{ archive, ".keep" },
            );
            const f = try cwd().createFile(dest_path, .{});
            defer f.close();
            try f.writeAll("fi-autogenerated");
        }
    }

    // now that we have an fi_home, also archive the json_config there
    {
        var fi_home_dir = cwd().openDir(fi_home, .{}) catch |err| {
            try fatal("Cannot open fi_home dir `{s}`: {}", .{ fi_home, err }, err);
        };
        defer fi_home_dir.close();

        var fi_config_file = fi_home_dir.createFile("config.json", .{}) catch |err| {
            try fatal("Error creating file `{s}/config.json`: {}", .{ fi_home, err }, err);
        };
        defer fi_config_file.close();

        const writer = fi_config_file.writer();
        std.json.stringify(json_config, .{ .whitespace = .indent_4 }, writer) catch |err| {
            try fatal("Error writing to file `{s}/config.json`: {}", .{ fi_home, err }, err);
        };
    }

    // create .id files
    {
        const dirs = &[_][]const u8{
            @tagName(SubDirs.letters),
            @tagName(SubDirs.offers),
            @tagName(SubDirs.invoices),
        };

        for (dirs) |dir| {
            // write id file
            const id_filename = try path.join(self.arena, &[_][]const u8{ fi_home, dir, ".id" });
            const f = try cwd().createFile(id_filename, .{});
            defer f.close();
            try f.writer().print("{d}-001\n", .{try self.year()});
        }
    }

    // write .current_year file
    {
        const id_filename = try path.join(self.arena, &[_][]const u8{ fi_home, ".current_year" });
        const f = try cwd().createFile(id_filename, .{});
        defer f.close();
        try f.writer().print("{d}\n", .{try self.year()});
    }

    // now, copy all templates
    {
        for (try templates.all(self.arena)) |file| {
            log.info("Creating... {s}/templates/{s}", .{ fi_home, file.filename });

            const dest_path = try path.join(
                self.arena,
                &[_][]const u8{ fi_home, "templates", file.filename },
            );
            const f = try cwd().createFile(dest_path, .{});
            defer f.close();
            try f.writeAll(file.content);
        }
    }

    // now, append to default-config.sty
    {
        const ofilename = "config-defaults.sty";
        log.info("Fiending to... {s}/templates/{s}", .{ fi_home, ofilename });

        const dest_path = try path.join(
            self.arena,
            &[_][]const u8{ fi_home, "templates", ofilename },
        );
        const f = cwd().createFile(dest_path, .{ .truncate = false }) catch |err| {
            try fatal(
                "Unable to create {s}: {}",
                .{ dest_path, err },
                err,
            );
        };
        defer f.close();
        // goto end
        f.seekFromEnd(0) catch |err| {
            try fatal(
                "Unable to append to {s}: {}",
                .{ dest_path, err },
                err,
            );
        };
        var writer = f.writer();
        writer.print(
            \\
            \\ \makeatletter\@ifundefined{{greeting}}{{
            \\   \def\greeting{{{s}}}
            \\ }}{{}}\makeatother
            \\
            \\ \def\FiUID{{{s}}}
            \\ \def\FiCompanyID{{{s}}}
            \\ \def\FiCompanyName{{{s}}}
            \\ \def\FiCompanyStreet{{{s}}}
            \\ \def\FiCompanyAreaCodeCity{{{s}}}
            \\ \def\FiCompanyUrl{{\url{{{s}}}}}
            \\ \def\FiCompanyEmail{{\url{{{s}}}}}
            \\
            \\ \def\FiCompanyRegisteredAt{{{s}}}
            \\
            \\ \def\FiCurrency{{{s}}}
            \\ \def\FiMyName{{{s}}}
            \\ \def\FiGoodbye{{{s}}}
            \\ \def\FiLetterCityDate{{{s}}}
            \\ \def\FiTermsOfServiceUrl{{{s}}}
            \\ \def\FiBankName{{{s}}}
            \\ \def\FiBankBIC{{{s}}}
            \\ \def\FiBankIBAN{{{s}}}
            \\
            \\
        , .{
            json_config.DefaultGreeting,
            json_config.CompanyVatUID,
            json_config.CompanyRegisteredID,
            json_config.CompanyName,
            json_config.CompanyStreet,
            json_config.CompanyAreaCodeCity,
            json_config.CompanyUrl,
            json_config.CompanyEmail,
            json_config.CompanyRegisteredAt,
            json_config.CurrencySymbol,
            json_config.YourName,
            json_config.DefaultGoodbye,
            json_config.LetterCityDate,
            json_config.GeneralTermsUrl,
            json_config.BankName,
            json_config.BankBIC,
            json_config.BankIBAN,
        }) catch |err| {
            try fatal(
                "Unable to write to {s}: {}",
                .{ dest_path, err },
                err,
            );
        };
    }

    // try to copy the logo
    {
        log.info("Copying logo.. {s}/templates/logo.png", .{fi_home});

        const dest_path = try path.join(
            self.arena,
            &[_][]const u8{ fi_home, "templates" },
        );

        var dest_dir = cwd().openDir(dest_path, .{}) catch |err| {
            try fatal(
                "Unable to open dir {s}: {}",
                .{ dest_path, err },
                err,
            );
        };
        defer dest_dir.close();
        cwd().copyFile(json_config.Logo, dest_dir, "logo.png", .{}) catch |err| {
            try fatal(
                "Error copying logo file {s}: {}",
                .{ json_config.Logo, err },
                err,
            );
        };
    }

    // time to call git init, then do the initial commit
    {
        var git: Git = .{ .arena = self.arena, .repo_dir = fi_home };
        if (!try git.init()) {
            try fatal("Aborting git init!", .{}, error.Abort);
        }
        if (!try git.stage(.all)) {
            try fatal("Aborting git stage!", .{}, error.Abort);
        }
        if (!try git.commit("[auto-fi] Initial commit")) {
            try fatal("Aborting git commit!", .{}, error.Abort);
        }
        _ = try git.status(null);
    }
    log.info("✅ fi init ... DONE!", .{});
}

pub fn cmd_git(self: *Fi, args: Cli.GitCommand) !void {
    const fi_home = try self.fiHomeTest(args.fi_home);
    var git: Git = .{ .arena = self.arena, .repo_dir = fi_home };

    switch (args.positional.subcommand) {
        .remote => {
            if (args.positional.subsubcommand) |subsubcommand| {
                _ = try git.remote(.{
                    .subcommand = subsubcommand,
                    .remote = args.remote,
                    .url = args.url,
                });
            } else {
                try fatal(
                    "fi git remote requires subcommand (add|list|show|delete)!",
                    .{},
                    error.Cli,
                );
            }
        },
        .pull => {
            _ = try git.pull(null);
        },
        .push => {
            _ = try git.push(null);
        },
        .status => {
            _ = try git.status(null);
        },
    }
}

pub fn today(self: *const Fi) ![]const u8 {
    var today_buf: ["2025-12-31".len]u8 = undefined;

    var now = zeit.instant(.{}) catch |err| {
        try fatal("Unable to get current time: {}", .{err}, err);
    };
    const timezone = zeit.local(self.arena, null) catch |err| {
        try fatal("Unable to get local timezone: {}", .{err}, err);
    };
    now = now.in(&timezone);

    const time = now.time();
    const ret = std.fmt.bufPrint(&today_buf, "{d}-{d:02}-{d:02}", .{
        time.year,
        @intFromEnum(time.month),
        time.day,
    }) catch unreachable;
    return self.arena.dupe(u8, ret) catch try fatal("OOM returning DATE", .{}, error.OutOfMemory);
}

pub fn isoTime(self: *const Fi) ![]const u8 {
    var today_buf: ["2025-12-31 16:32:00".len]u8 = undefined;

    var now = zeit.instant(.{}) catch |err| {
        try fatal("Unable to get current time: {}", .{err}, err);
    };
    const timezone = zeit.local(self.arena, null) catch |err| {
        try fatal("Unable to get local timezone: {}", .{err}, err);
    };
    now = now.in(&timezone);

    const time = now.time();
    const ret = std.fmt.bufPrint(&today_buf, "{d}-{d:02}-{d:02} {d:02}:{d:02}:{d:02}", .{
        time.year,
        @intFromEnum(time.month),
        time.day,
        time.hour,
        time.minute,
        time.second,
    }) catch unreachable;
    return self.arena.dupe(u8, ret) catch try fatal("OOM returning DATE", .{}, error.OutOfMemory);
}

pub fn year(self: *const Fi) !i32 {
    var now = zeit.instant(.{}) catch |err| {
        try fatal("Unable to get current time: {}", .{err}, err);
    };
    const timezone = zeit.local(self.arena, null) catch |err| {
        try fatal("Unable to get local timezone: {}", .{err}, err);
    };
    now = now.in(&timezone);
    const time = now.time();
    return time.year;
}

pub fn cmdClient(self: *Fi, args: Cli.ClientCommand) !HandleRecordCommandResult {
    return self.handleRecordCommand(args);
}

pub fn cmdRate(self: *Fi, args: Cli.RateCommand) !HandleRecordCommandResult {
    return self.handleRecordCommand(args);
}

fn recordPath(self: *const Fi, RecordType: type, shortname: []const u8, custom_path_: ?[]const u8, path_out: []u8) ![]const u8 {
    const json_path: []const u8 = blk: {
        if (custom_path_) |custom_path| {
            log.debug("custom_path = {s}", .{custom_path});
            break :blk std.fmt.bufPrint(path_out, "{s}/{s}.json", .{
                custom_path,
                shortname,
            }) catch |err| {
                log.err("JSON path for {s}.json grew > {d} bytes! -> {}", .{
                    shortname,
                    max_path_bytes,
                    err,
                });
                try fatal("Aborting", .{}, err);
            };
        } else {
            const subdir =
                switch (RecordType) {
                    fi_json.Client => "clients",
                    fi_json.Rate => "rates",
                    else => unreachable,
                };
            log.debug("subdir={s}, shortname={s}", .{ subdir, shortname });
            break :blk std.fmt.bufPrint(path_out, "{s}/{s}/{s}.json", .{
                self.fi_home.?,
                subdir,
                shortname,
            }) catch |err| {
                log.err("JSON path for {s}.json grew > {d} bytes! -> {}", .{
                    shortname,
                    max_path_bytes,
                    err,
                });
                try fatal("Aborting", .{}, err);
            };
        }
    };
    return json_path;
}

fn recordExists(self: *const Fi, RecordType: type, shortname: []const u8) !bool {
    var path_buf: [max_path_bytes]u8 = undefined;
    const json_path = try self.recordPath(RecordType, shortname, null, &path_buf);
    return fsutil.fileExists(json_path);
}

fn recordDir(self: *const Fi, RecordType: type, dir_out: []u8) ![]const u8 {
    const json_dir: []const u8 = blk: {
        const subdir =
            switch (RecordType) {
                fi_json.Client => "clients",
                fi_json.Rate => "rates",
                else => unreachable,
            };
        break :blk std.fmt.bufPrint(dir_out, "{s}/{s}", .{
            self.fi_home.?,
            subdir,
        }) catch |err| {
            log.err("JSON path for {s}.json grew > {d} bytes! -> {}", .{
                subdir,
                max_path_bytes,
                err,
            });
            try fatal("Aborting", .{}, err);
        };
    };
    return json_dir;
}

pub fn loadRecord(self: *const Fi, RecordType: type, shortname: []const u8, opts: struct {
    custom_path: ?[]const u8 = null,
}) !RecordType {
    assert(self.fi_home != null); // fiHome() must have been called, e.g. in setup()

    var path_buf: [max_path_bytes]u8 = undefined;
    const json_path = try self.recordPath(RecordType, shortname, opts.custom_path, &path_buf);
    log.debug("json_path = {s}", .{json_path});

    // now load it
    var json_file = cwd().openFile(json_path, .{}) catch |err| {
        try fatal("Error opening {s}: {}", .{ json_path, err }, err);
    };
    defer json_file.close();

    const json_string = json_file.readToEndAlloc(self.arena, self.max_json_file_size) catch |err| {
        switch (err) {
            error.OutOfMemory => try fatal(
                "File {s} too large: > {d} bytes!",
                .{
                    json_path,
                    self.max_json_file_size,
                },
                err,
            ),
            else => try fatal("Error reading {s}: {}", .{ json_path, err }, err),
        }
    };

    return std.json.parseFromSliceLeaky(RecordType, self.arena, json_string, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        try fatal("Error parsing {s}: {}", .{ json_path, err }, err);
    };
}

fn writeRecord(self: *const Fi, shortname: []const u8, obj: anytype, opts: struct {
    allow_overwrite: bool = false,
    custom_path: ?[]const u8 = null,
}) ![]const u8 {
    var path_buf: [max_path_bytes]u8 = undefined;
    const json_path = try self.recordPath(@TypeOf(obj), shortname, opts.custom_path, &path_buf);

    if (!opts.allow_overwrite and fsutil.fileExists(json_path)) {
        try fatal("File `{s}` exists! Refusing to overwrite!", .{json_path}, error.PathAlreadyExists);
    }

    const f = cwd().createFile(json_path, .{ .exclusive = !opts.allow_overwrite }) catch |err| {
        try fatal("Error creating file {s}.json: {}", .{ shortname, err }, err);
    };

    defer f.close();
    const writer = f.writer();
    std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer) catch |err| {
        try fatal("Error writing to file {s}.json: {}", .{ shortname, err }, err);
    };
    return json_path;
}

pub const HandleRecordCommandResult = union(enum) {
    new: []const u8,
    show: []const u8,
    checkout: []const u8,
    commit: void,
    list: []const []const u8,
};

pub fn handleRecordCommand(self: *Fi, args: anytype) !HandleRecordCommandResult {
    _ = try self.fiHomeTest(args.fi_home);

    const RecordType = switch (@TypeOf(args)) {
        Cli.ClientCommand => fi_json.Client,
        Cli.RateCommand => fi_json.Rate,
        else => unreachable,
    };

    switch (args.positional.subcommand) {
        .new => {
            switch (RecordType) {
                fi_json.Client => {
                    if (args.positional.arg) |shortname| {
                        const record_path = try self.writeRecord(shortname, RecordType{
                            .shortname = shortname,
                            .created = try self.today(),
                            .updated = try self.isoTime(),
                            .revision = 0,
                        }, .{ .custom_path = "." });
                        log.info("✅  {s}.json created.", .{shortname});
                        return .{ .new = record_path };
                    } else {
                        try fatal(
                            "Please provide a shortname: fi " ++ (if (@TypeOf(args) == Cli.ClientCommand) "client " else "rate ") ++ "new <shortname>",
                            .{},
                            error.Cli,
                        );
                    }
                },
                fi_json.Rate => {
                    if (args.positional.arg) |shortname| {
                        const record_path = try self.writeRecord(shortname, RecordType{
                            .shortname = shortname,
                            .hourly = 0,
                            .hours_per_day = 0,
                            .daily = 0,
                            .weekly = 0,
                            .created = try self.today(),
                            .updated = try self.isoTime(),
                            .revision = 0,
                        }, .{ .custom_path = "." });
                        log.info("✅  {s}.json created.", .{shortname});
                        return .{ .new = record_path };
                    } else {
                        try fatal(
                            "Please provide a shortname: fi " ++ (if (@TypeOf(args) == Cli.ClientCommand) "client " else "rate ") ++ "new <shortname>",
                            .{},
                            error.Cli,
                        );
                    }
                },
                else => unreachable,
            }
        },
        .show => {
            // if -v, show entire json else just show shortname, name, and remarks

            const shortname = args.positional.arg orelse {
                try fatal(
                    "Please specify a <shortname>. See -h for help",
                    .{},
                    error.Cli,
                );
            };

            const obj = try self.loadRecord(RecordType, shortname, .{});

            var alist: std.ArrayListUnmanaged(u8) = .empty;
            const writer = alist.writer(self.arena);
            if (args.verbose) {
                std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer) catch |err| {
                    try fatal("Cannot jsonify output: {}", .{err}, err);
                };
            } else {
                switch (RecordType) {
                    fi_json.Client => writer.print(
                        \\ Client:
                        \\    shortname   : {s}
                        \\    company-name: {s}
                        \\    remarks     : {?s}
                        \\
                    , .{ obj.shortname, obj.@"company-name", obj.remarks }) catch unreachable,
                    fi_json.Rate => writer.print(
                        \\ Rate:
                        \\    shortname   : {s}
                        \\    hourly      : {d}
                        \\    daily       : {d}
                        \\    remarks     : {?s}
                        \\
                    , .{ obj.shortname, obj.hourly, obj.daily, obj.remarks }) catch unreachable,
                    else => unreachable,
                }
            }
            std.io.getStdOut().writeAll(alist.items) catch unreachable;
            std.io.getStdOut().writeAll("\n") catch unreachable;
            return .{
                .show = alist.toOwnedSlice(self.arena) catch |err| {
                    try fatal("Error cloning json string: {}", .{err}, err);
                },
            };
        },
        .checkout => {
            const shortname = args.positional.arg orelse {
                try fatal(
                    "Please specify a <shortname>. See -h for help",
                    .{},
                    error.Cli,
                );
            };

            const obj = try self.loadRecord(RecordType, shortname, .{});

            const record_path = try self.writeRecord(shortname, obj, .{ .custom_path = "." });
            log.info("✅  {s} created.", .{record_path});
            return .{ .checkout = record_path };
        },
        .commit => {
            //
            // TODO: locking
            //

            // bump revision: read current revision from JSON in fi_home
            // retrieve current revision
            const shortname = args.positional.arg orelse {
                try fatal(
                    "Please specify a <shortname>. See -h for help",
                    .{},
                    error.Cli,
                );
            };

            var path_buf: [max_path_bytes]u8 = undefined;
            const json_path = try self.recordPath(RecordType, shortname, null, &path_buf);
            const new_revision: usize = blk: {
                if (fsutil.fileExists(json_path)) {
                    const existing = try self.loadRecord(RecordType, shortname, .{});
                    break :blk existing.revision + 1;
                } else {
                    break :blk 0;
                }
            };

            // now load the specified one
            var new_one = try self.loadRecord(RecordType, shortname, .{ .custom_path = "." });
            new_one.revision = new_revision;
            new_one.updated = try self.isoTime();

            // and save it internally
            _ = try self.writeRecord(shortname, new_one, .{ .allow_overwrite = true });

            // now, delete the provided one.
            const provided_json_file = try self.recordPath(RecordType, shortname, ".", &path_buf);
            cwd().deleteFile(provided_json_file) catch |err| {
                log.warn("Unable to delete `{s}`: {}", .{ provided_json_file, err });
            };

            log.info("✅  {s}.json committed.", .{shortname});
            return .{ .commit = {} };
        },
        .list => {
            var path_buf: [max_path_bytes]u8 = undefined;
            const json_dir_str = try self.recordDir(RecordType, &path_buf);
            var json_dir = cwd().openDir(json_dir_str, .{ .iterate = true }) catch |err| {
                try fatal("Unable to enter directory `{s}`: {}", .{ json_dir_str, err }, err);
            };
            defer json_dir.close();

            var it = json_dir.iterate();
            var alist = std.ArrayListUnmanaged([]const u8).empty;
            var count: usize = 0;
            while (it.next() catch |err|
                {
                    try fatal("Cannot iterate a step in dir `{s}`: {}", .{ json_dir_str, err }, err);
                }) |element|
            {
                if (element.kind == .file) {
                    count += 1;
                    if (std.mem.endsWith(u8, element.name, ".json")) {
                        std.io.getStdOut().writer().print("- {s}\n", .{element.name[0 .. element.name.len - 5]}) catch |err| {
                            try fatal("Cannot print to stdout: {}", .{err}, err);
                        };
                        try alist.append(self.arena, element.name[0 .. element.name.len - 5]);
                    }
                }
            }
            std.io.getStdOut().writer().print("{d} element(s).\n", .{count}) catch |err| {
                try fatal("Cannot print to stdout: {}", .{err}, err);
            };
            return .{ .list = try alist.toOwnedSlice(self.arena) };
        },
    }
}

pub fn cmdLetter(self: *Fi, args: Cli.LetterCommand) !HandleDocumentCommandResult {
    return self.handleDocumentCommand(args);
}

pub fn cmdOffer(self: *Fi, args: Cli.OfferCommand) !HandleDocumentCommandResult {
    return self.handleDocumentCommand(args);
}

pub fn cmdInvoice(self: *Fi, args: Cli.InvoiceCommand) !HandleDocumentCommandResult {
    return self.handleDocumentCommand(args);
}

pub const DocumentFileContents = struct {
    json: []const u8,
    billables: []const u8,
    tex: []const u8,
};

pub const HandleDocumentCommandResult = union(enum) {
    /// dir path
    new: DocumentFileContents,
    show: DocumentFileContents,
    open: void,
    checkout: DocumentFileContents, // dir path
    /// updates  updated, total of JSON
    commit: DocumentFileContents,
    /// updates  updated, total of JSON
    compile: DocumentFileContents,
    /// dir paths
    list: []const []const u8,
};

pub fn handleDocumentCommand(
    self: *Fi,
    args: anytype, // args will be inferred by CLI command type
) !HandleDocumentCommandResult {
    _ = try self.fiHomeTest(args.fi_home);
    switch (args.positional.subcommand) {
        .new => {
            // Generic logic for creating new dir + initial JSON files
            return try self.cmdCreateNewDocument(args);
        },
        .checkout => {
            // Generic checkout logic
            return try self.cmdCheckoutDocument(args);
        },
        .compile => {
            // Generic compile logic (LaTeX, CSV parsing, etc.)
            return try self.cmdCompileDocument(args);
        },
        .commit => {
            // Generic commit logic (ID increment, archive, move)
            return try self.cmdCommitDocument(args);
        },
        .show => {
            return try self.cmdShowDocument(args);
        },
        .open => {
            return try self.cmdOpenDocument(args);
        },
        .list => {
            return try self.cmdListDocuments(args);
        },
    }
}

pub fn documentTypeHumanName(DocumentType: type) []const u8 {
    return switch (DocumentType) {
        fi_json.Letter => "letter",
        fi_json.Invoice => "invoice",
        fi_json.Offer => "offer",
        else => unreachable,
    };
}

const DocumentSubdirSpec = struct {
    dir: Dir,
    name: []const u8,
};

fn documentTypeCreateSubdir(self: *const Fi, DocumentType: type, id: []const u8, client: []const u8) !DocumentSubdirSpec {
    const subdir_name_buf = self.arena.alloc(u8, max_name_bytes) catch |err| {
        try fatal("OOM creating subdir_name_buf!: {}", .{err}, err);
    };
    const subdir_name = try createDocumentName(DocumentType, id, client, subdir_name_buf);
    cwd().makeDir(subdir_name) catch |err| {
        try fatal("Cannot create directory `{s}/`: {}", .{ subdir_name, err }, err);
    };

    // now open the dir
    const subdir = cwd().openDir(subdir_name, .{}) catch |err| {
        try fatal("Cannot open subdir {subdir_name}: {}", .{ subdir_name, err }, err);
    };

    return .{
        .name = subdir_name,
        .dir = subdir,
    };
}

fn documentCreateJsonFile(DocumentType: type, subdir_spec: DocumentSubdirSpec) !File {
    var filename_buf: [max_name_bytes]u8 = undefined;
    const json_file_stem = documentTypeHumanName(DocumentType);
    const filename = std.fmt.bufPrint(&filename_buf, "{s}.json", .{json_file_stem}) catch |err| {
        try fatal("Unable to create filename `{s}.json`: {}", .{ json_file_stem, err }, err);
    };
    const file = subdir_spec.dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        try fatal("Unable to create file `{s}`: {}", .{ filename, err }, err);
    };
    return file;
}

pub fn loadDocumentMeta(self: *const Fi, subdir_spec: DocumentSubdirSpec, DocumentType: type) !DocumentType {
    var filename_buf: [max_name_bytes]u8 = undefined;

    const document_type_name = documentTypeHumanName(DocumentType);
    const json_path = std.fmt.bufPrint(&filename_buf, "{s}.json", .{document_type_name}) catch |err| {
        try fatal(
            "JSON path for {s}.json grew > {d} bytes! -> {}",
            .{ document_type_name, max_name_bytes, err },
            err,
        );
    };

    // now load it
    var json_file = subdir_spec.dir.openFile(json_path, .{}) catch |err| {
        try fatal("Error opening {s}/{s}: {}", .{ subdir_spec.name, json_path, err }, err);
    };
    defer json_file.close();

    const json_string = json_file.readToEndAlloc(self.arena, self.max_json_file_size) catch |err| {
        switch (err) {
            error.OutOfMemory => try fatal(
                "File {s} too large: > {d} bytes!",
                .{
                    json_path,
                    self.max_json_file_size,
                },
                err,
            ),
            else => try fatal("Error reading {s}: {}", .{ json_path, err }, err),
        }
    };

    return std.json.parseFromSliceLeaky(DocumentType, self.arena, json_string, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        try fatal("Error parsing {s}: {}", .{ json_path, err }, err);
    };
}

fn saveDocumentMeta(_: *const Fi, DocumentType: type, subdir_spec: DocumentSubdirSpec, obj: anytype) !void {
    var filename_buf: [max_name_bytes]u8 = undefined;

    const document_type_name = documentTypeHumanName(DocumentType);
    const json_path = std.fmt.bufPrint(&filename_buf, "{s}.json", .{document_type_name}) catch |err| {
        try fatal(
            "JSON path for {s}.json grew > {d} bytes! -> {}",
            .{ document_type_name, max_name_bytes, err },
            err,
        );
    };

    // now rewrite it
    // TODO: do that to a temp file, then delete orig and rename temp file
    var json_file = subdir_spec.dir.createFile(json_path, .{}) catch |err| {
        try fatal("Error creating {s}/{s}: {}", .{ subdir_spec.name, json_path, err }, err);
    };
    defer json_file.close();
    const writer = json_file.writer();

    std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer) catch |err| {
        try fatal(
            "Error writing to file {s}/{s}.json: {}",
            .{ subdir_spec.name, json_path, err },
            err,
        );
    };
}

fn createDocumentName(DocumentType: type, id: []const u8, client: []const u8, out_buf: []u8) ![]const u8 {
    const document_type_name = documentTypeHumanName(DocumentType);
    return std.fmt.bufPrint(
        out_buf,
        "{s}--{s}--{s}",
        .{ document_type_name, id, client },
    ) catch |err| {
        try fatal(
            "Cannot create filename: `{s}--{s}--{s}`: {}",
            .{ document_type_name, id, client, err },
            err,
        );
    };
}

fn copyTemplateFile(self: *const Fi, filename: []const u8, dest_dir_spec: DocumentSubdirSpec) !void {
    const ifile_path = path.join(
        self.arena,
        &[_][]const u8{ self.fi_home.?, "templates", filename },
    ) catch |err| {
        try fatal(
            "Unable to create path string for {s}: {}",
            .{ filename, err },
            err,
        );
    };
    var ifile = cwd().openFile(ifile_path, .{}) catch |err| {
        try fatal(
            "Unable to open {s}: {}",
            .{ filename, err },
            err,
        );
    };
    defer ifile.close();

    const ifile_content = ifile.readToEndAlloc(self.arena, self.max_bin_file_size) catch |err| {
        try fatal(
            "Unable to read {s}: {}",
            .{ ifile_path, err },
            err,
        );
    };
    var document_file = dest_dir_spec.dir.createFile(filename, .{ .exclusive = true }) catch |err| {
        try fatal(
            "Could not create `{s}/{s}`: {}",
            .{ dest_dir_spec.name, filename, err },
            err,
        );
    };
    defer document_file.close();
    document_file.writeAll(ifile_content) catch |err| {
        try fatal(
            "Error writing `{s}/{s}`: {}",
            .{ dest_dir_spec.name, filename, err },
            err,
        );
    };
}

fn cmdCreateNewDocument(self: *const Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };

    // validate we received a client shortname
    const client_name = blk: {
        if (args.positional.arg) |client| {
            break :blk client;
        } else {
            try fatal("Please provide a <client>! See -h for help.", .{}, error.Cli);
        }
    };

    // validate provided client exists
    if (!try self.recordExists(fi_json.Client, client_name)) {
        try fatal("Client `{s}` does not exist!", .{client_name}, error.NotFound);
    }

    // if !letter: validate rates exist
    const rates_name: []const u8 = blk: {
        if (DocumentType == fi_json.Letter) {
            // letter doesn't need it
            break :blk "";
        } else {
            if (args.rates) |rates| {
                // validate provided client exists
                if (!try self.recordExists(fi_json.Rate, rates)) {
                    try fatal("Rates `{s}` do not exist!", .{rates}, error.NotFound);
                }
                break :blk rates;
            } else {
                try fatal("--rates=<rates> missing!", .{}, error.Cli);
            }
        }
    };

    // create temp id
    var temp_id_buffer: ["2025-XXX".len]u8 = undefined;
    const temp_id = std.fmt.bufPrint(&temp_id_buffer, "{d}-XXX", .{try self.year()}) catch unreachable;

    // generate default JSON file,
    //      use temp ID YEAR-XXX
    //      set current time for created, updated
    //      set revision to 0
    var obj: DocumentType = undefined;
    {
        obj = switch (DocumentType) {
            fi_json.Letter => .{
                .id = temp_id,
                .created = try self.isoTime(),
                .updated = try self.isoTime(),
                .revision = 0,

                .coverletter = .{},
                .footer = .{},

                .client_shortname = client_name,
            },
            fi_json.Offer => .{
                .id = temp_id,
                .client_shortname = client_name,
                .project_name = args.project orelse {
                    try fatal("--project=<project name> missing!", .{}, error.Cli);
                },
                .created = try self.isoTime(),
                .updated = try self.isoTime(),
                .revision = 0,
                .applicable_rates = args.rates orelse {
                    try fatal("--rates=<rates> missing!", .{}, error.Cli);
                },
                .coverletter = .{},
                .footer = .{},
                .vat = .{},
            },
            fi_json.Invoice => .{
                .id = temp_id,
                .created = try self.isoTime(),
                .updated = try self.isoTime(),
                .revision = 0,

                .client_shortname = client_name,
                .year = try self.year(),

                .coverletter = .{},
                .footer = .{},
                .vat = .{},
            },
            else => unreachable,
        };

        if (DocumentType != fi_json.Letter) {
            obj.applicable_rates = rates_name;
        }
    }

    // create new subdir
    var subdir_spec = try self.documentTypeCreateSubdir(DocumentType, temp_id, client_name);
    log.info("Creating {s} in {s}/", .{ documentTypeHumanName(DocumentType), subdir_spec.name });
    defer subdir_spec.dir.close();

    //
    // in subdir:
    //
    {
        var json_file = try documentCreateJsonFile(DocumentType, subdir_spec);
        defer json_file.close();
        const writer = json_file.writer();

        std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer) catch |err| {
            try fatal(
                "Error writing to file {s}/{s}.json: {}",
                .{ subdir_spec.name, subdir_spec.name, err },
                err,
            );
        };
    }

    // if !letter: generate default billables.csv
    if (DocumentType != fi_json.Letter) {
        var billables_file = subdir_spec.dir.createFile("billables.csv", .{ .exclusive = true }) catch |err| {
            try fatal("Cannot create `billables.csv` in `{s}/`: {}", .{ subdir_spec.name, err }, err);
        };
        defer billables_file.close();
        billables_file.writer().writeAll(
            \\# Lines starting with # are comments and ignored
            \\# Empty lines are ignored, too
            \\# All values are trimmed: preceding & trailing blanks are removed
            \\#
            \\# Format:
            \\# -------
            \\#
            \\# GroupName | Items
            \\#
            \\# GroupName: any string NOT containing a comma
            \\# Items: description, amount, rate_name, optional_price_per_unit | null, optional remarks | null
            \\#
            \\# Example:
            \\# --------
            \\#
            \\#    Software Development
            \\#    Backend, 2.5, week    , null, null
            \\#    Frontend, 1  , pauschal, 1000, (blah-blubb)
            \\
            \\
        ) catch |err| {
            try fatal(
                "Error writing `{s}/billables.csv`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
    }

    // if !letter: generate rates.tex
    if (DocumentType != fi_json.Letter) {
        self.generateRatesTex(subdir_spec, rates_name) catch |err| {
            try fatal(
                "Error writing `{s}/rates.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
    }

    // Copy from tempates dir:
    // - <DocumentType>.tex
    // - config-defaults.sty
    // - logo.png
    {
        const template_filn = switch (DocumentType) {
            fi_json.Letter => "letter.tex",
            fi_json.Offer => "offer.tex",
            fi_json.Invoice => "invoice.tex",
            else => unreachable,
        };

        try self.copyTemplateFile(template_filn, subdir_spec);
        try self.copyTemplateFile("config-defaults.sty", subdir_spec);
        try self.copyTemplateFile("logo.png", subdir_spec);
    }

    // generate default config.tex
    {
        var tex_config_file = subdir_spec.dir.createFile("config.tex", .{ .exclusive = true }) catch |err| {
            try fatal(
                "Could not create `{s}/config.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
        self.generateTexConfig(tex_config_file, temp_id, obj) catch |err| {
            try fatal(
                "Error generating `{s}/config.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
        defer tex_config_file.close();
    }

    // DONE!
    log.info("✅ created in `{s}/`!", .{subdir_spec.name});
    return .{ .new = try self.readDocumentFiles(DocumentType, subdir_spec) };
}

pub fn readDocumentFiles(self: *const Fi, DocumentType: type, subdir_spec: DocumentSubdirSpec) !DocumentFileContents {
    const document_type_name = documentTypeHumanName(DocumentType);

    const json_string = blk: {
        const json_path = try std.fmt.allocPrint(
            self.arena,
            "{s}.json",
            .{document_type_name},
        );
        var json_file = subdir_spec.dir.openFile(json_path, .{}) catch |err| {
            try fatal(
                "Error opening `{s}.json`: {}",
                .{ document_type_name, err },
                err,
            );
        };
        defer json_file.close();

        break :blk try json_file.readToEndAlloc(self.arena, self.max_json_file_size);
    };

    const tex_string = blk: {
        const tex_path = try std.fmt.allocPrint(
            self.arena,
            "{s}.tex",
            .{document_type_name},
        );
        var tex_file = try subdir_spec.dir.openFile(tex_path, .{});
        defer tex_file.close();

        break :blk try tex_file.readToEndAlloc(self.arena, self.max_json_file_size);
    };

    const billables_string = blk: {
        if (DocumentType == fi_json.Letter) {
            break :blk "";
        } else {
            const billables_path = try std.fmt.allocPrint(
                self.arena,
                "billables.csv",
                .{},
            );
            var billables_file = try subdir_spec.dir.openFile(billables_path, .{});
            defer billables_file.close();

            break :blk try billables_file.readToEndAlloc(self.arena, self.max_json_file_size);
        }
    };

    return .{
        .json = json_string,
        .billables = billables_string,
        .tex = tex_string,
    };
}

pub fn findDocumentById(self: *const Fi, DocumentType: type, id: []const u8) ![]const u8 {
    const base_dir_name = try self.documentBaseDir(DocumentType);
    const human_doctype = documentTypeHumanName(DocumentType);
    const pattern = try std.fmt.allocPrint(self.arena, "{s}--{s}--", .{ human_doctype, id });

    log.debug("Searching for {s} in {s}", .{ pattern, base_dir_name });

    var base_dir = try cwd().openDir(base_dir_name, .{ .iterate = true });
    defer base_dir.close();
    var it = base_dir.iterate();
    while (try it.next()) |entry| {
        if (startsWithIC(entry.name, pattern)) {
            log.debug("Found {s} in {s}", .{ entry.name, base_dir_name });
            return try self.arena.dupe(u8, entry.name);
        }
    } else {
        return error.NotFound;
    }
}

fn cmdCheckoutDocument(self: *Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };
    const document_base = try self.documentBaseDir(DocumentType);
    const id = args.positional.arg orelse {
        try fatal("Please provide an id!", .{}, error.Cli);
    };

    const human_doctype = documentTypeHumanName(DocumentType);

    const document_dir_name = blk: {
        if (startsWithIC(id, human_doctype)) {
            break :blk id;
        } else {
            break :blk self.findDocumentById(DocumentType, id) catch |err| {
                try fatal(
                    "No such {s} with ID {s}: {}",
                    .{ human_doctype, id, err },
                    err,
                );
            };
        }
    };

    const dest_path = document_dir_name;
    cwd().makeDir(dest_path) catch |err| {
        try fatal(
            "Cannot create document dir {s}: {}",
            .{ dest_path, err },
            err,
        );
    };

    var dest_dir = cwd().openDir(dest_path, .{}) catch |err| {
        try fatal(
            "Cannot open destination document dir {s}: {}",
            .{ dest_path, err },
            err,
        );
    };
    defer dest_dir.close();

    const source_path = try path.join(self.arena, &[_][]const u8{ document_base, document_dir_name });
    var source_dir = cwd().openDir(source_path, .{ .iterate = true }) catch |err| {
        try fatal(
            "Cannot open source document dir {s}: {}",
            .{ source_path, err },
            err,
        );
    };
    defer source_dir.close();

    var file_it = source_dir.iterate();
    while (try file_it.next()) |entry| {
        log.info(
            "    {s}/{s} -> {s}/{s}",
            .{ source_path, entry.name, dest_path, entry.name },
        );
        try source_dir.copyFile(entry.name, dest_dir, entry.name, .{});
    }
    log.info("✅ created in `{s}/`!", .{dest_path});
    return .{ .checkout = try self.readDocumentFiles(
        DocumentType,
        .{ .name = dest_path, .dir = dest_dir },
    ) };
}

pub fn cmdShowDocument(self: *Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };
    const document_base = try self.documentBaseDir(DocumentType);
    const id = args.positional.arg orelse {
        try fatal("Please provide an id!", .{}, error.Cli);
    };

    const human_doctype = documentTypeHumanName(DocumentType);

    const document_dir_name = blk: {
        if (startsWithIC(id, human_doctype)) {
            break :blk id;
        } else {
            break :blk self.findDocumentById(DocumentType, id) catch |err| {
                try fatal(
                    "No such {s} with ID {s}: {}",
                    .{ human_doctype, id, err },
                    err,
                );
            };
        }
    };

    var alist_json = std.ArrayListUnmanaged(u8).empty;
    var writer_json = alist_json.writer(self.arena);
    var alist_billables = std.ArrayListUnmanaged(u8).empty;
    var writer_billables = alist_billables.writer(self.arena);
    var alist_tex = std.ArrayListUnmanaged(u8).empty;
    var writer_tex = alist_tex.writer(self.arena);
    var writer_stdout = std.io.getStdOut().writer();

    {
        const json_filename = try std.fmt.allocPrint(self.arena, "{s}.json", .{human_doctype});
        const json_path = try path.join(
            self.arena,
            &[_][]const u8{ document_base, document_dir_name, json_filename },
        );
        var json_file = cwd().openFile(json_path, .{}) catch |err| {
            try fatal(
                "Unable to load JSON file {s}: {}",
                .{ json_path, err },
                err,
            );
        };
        defer json_file.close();
        const json_string = try json_file.readToEndAlloc(self.arena, self.max_json_file_size);
        try writer_json.writeAll(json_string);
        try writer_stdout.writeAll(json_string);
        try writer_stdout.writeByte('\n');
    }

    if (DocumentType != fi_json.Letter) {
        const billables_filename = "billables.csv";
        const billables_path = try path.join(
            self.arena,
            &[_][]const u8{ document_base, document_dir_name, billables_filename },
        );
        var billables_file = cwd().openFile(billables_path, .{}) catch |err| {
            try fatal(
                "Unable to load billables file {s}: {}",
                .{ billables_path, err },
                err,
            );
        };
        defer billables_file.close();
        const billables_string = try billables_file.readToEndAlloc(self.arena, self.max_json_file_size);
        try writer_billables.writeAll(billables_string);
        try writer_stdout.writeAll(billables_string);
        try writer_stdout.writeByte('\n');
    }

    {
        const tex_filename = try std.fmt.allocPrint(self.arena, "{s}.tex", .{human_doctype});
        const tex_path = try path.join(
            self.arena,
            &[_][]const u8{ document_base, document_dir_name, tex_filename },
        );
        var tex_file = cwd().openFile(tex_path, .{}) catch |err| {
            try fatal(
                "Unable to load tex file {s}: {}",
                .{ tex_path, err },
                err,
            );
        };
        defer tex_file.close();
        const tex_string = try tex_file.readToEndAlloc(self.arena, self.max_json_file_size);
        try writer_tex.writeAll(tex_string);
    }

    return .{
        .show = .{
            .json = try alist_json.toOwnedSlice(self.arena),
            .billables = try alist_billables.toOwnedSlice(self.arena),
            .tex = try alist_tex.toOwnedSlice(self.arena),
        },
    };
}

fn cmdOpenDocument(self: *Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };
    const document_base = try self.documentBaseDir(DocumentType);
    const id = args.positional.arg orelse {
        try fatal("Please provide an id!", .{}, error.Cli);
    };

    const human_doctype = documentTypeHumanName(DocumentType);

    const document_dir_name = blk: {
        if (startsWithIC(id, human_doctype)) {
            break :blk id;
        } else {
            break :blk self.findDocumentById(DocumentType, id) catch |err| {
                try fatal("No such {s} with ID {s}: {}", .{ human_doctype, id, err }, err);
            };
        }
    };

    // Linux XDG_OPEN || macos open || windows: explorer.exe?
    const pdf_filename = try std.fmt.allocPrint(
        self.arena,
        "{s}.pdf",
        .{document_dir_name},
    );
    const pdf_path = try path.join(
        self.arena,
        &[_][]const u8{ document_base, document_dir_name, pdf_filename },
    );
    log.info("Opening {s}", .{pdf_path});
    const open: OpenCommand = .{ .arena = self.arena };
    _ = try open.openDocument(pdf_path);
    return .{ .open = {} };
}

pub fn cmdListDocuments(self: *Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };
    const human_doctype = documentTypeHumanName(DocumentType);
    const documents_path = try self.documentBaseDir(DocumentType);
    var documents_dir = try cwd().openDir(documents_path, .{ .iterate = true });
    var it = documents_dir.iterate();

    var alist = std.ArrayListUnmanaged([]const u8).empty;
    var writer = std.io.getStdOut().writer();
    var count: usize = 0;
    while (try it.next()) |entry| {
        if (startsWithIC(entry.name, human_doctype)) {
            count += 1;
            try writer.print("  - {s}\n", .{entry.name});
            try alist.append(self.arena, entry.name);
        }
    }
    try writer.print("{d} element(s).\n", .{count});
    return .{ .list = try alist.toOwnedSlice(self.arena) };
}

fn generateRatesTex(
    self: *const Fi,
    subdir_spec: DocumentSubdirSpec,
    rates_name: []const u8,
) !void {
    const rates = try self.loadRecord(fi_json.Rate, rates_name, .{});
    var rates_file = subdir_spec.dir.createFile("rates.tex", .{ .exclusive = false }) catch |err| {
        try fatal("Cannot create `rates.tex` in `{s}/`: {}", .{ subdir_spec.name, err }, err);
    };
    defer rates_file.close();

    var number_format_buffer: [32]u8 = undefined;

    try rates_file.writer().print(
        \\ \def\FiRateHourly{{{s},00}}
        \\ \def\FiRateHoursPerDay{{{d},00}}
        \\ \def\FiRateDaily{{{s},00}}
        \\ \def\FiRateWeekly{{{s},00}}
        \\
        \\
    , .{
        try format.intThousands(rates.hourly, .german, &number_format_buffer),
        rates.hours_per_day,
        try format.intThousands(rates.daily, .german, &number_format_buffer),
        try format.intThousands(rates.weekly, .german, &number_format_buffer),
    });
}

fn generateTexConfig(self: *const Fi, file: File, id: []const u8, opts: anytype) !void {
    const DocumentType = @TypeOf(opts);

    const client = try self.loadRecord(fi_json.Client, opts.client_shortname, .{});
    const draft = opts.draft;

    // \def\FiDocType
    // \def\FiDocId
    // \def\FiProjectName
    // \Drafttrue
    // \ShowAllNettotrue
    // \ShowAgbtrue
    // \ShowRatesfalse
    // \def\greeting{}

    // FiClientCompany
    // FiClientCareOf
    // FiClientStreet
    // FiClientAreaCode
    // FiClientCity
    // FiClientCountry

    // \def\validthru
    // \def\devtime

    switch (DocumentType) {
        fi_json.Letter => {
            try file.writer().print(
                \\ \Draft{}
                \\ \def\FiDocType{{{s}}}
                \\ \def\FiDocId{{{s}}}
                \\ \def\FiDate{{{s}}}
                \\ \def\FiSubject{{{s}}}
                \\ \def\FiClientCompany{{{s}}}
                \\ \def\FiClientCareOf{{{s}}}
                \\ \def\FiClientStreet{{{s}}}
                \\ \def\FiClientAreaCode{{{s}}}
                \\ \def\FiClientCity{{{s}}}
                \\ \def\FiClientCountry{{{s}}}
                \\
            , .{
                draft,
                "Brief",
                id,
                opts.date,
                opts.subject,
                client.@"company-name",
                client.@"c/o-name" orelse "\\hspace{1em}",
                if (client.street.len > 0) client.street else "\\hspace{1em}",
                if (client.areacode.len > 0) client.areacode else "\\hspace{1em}",
                if (client.city.len > 0) client.city else "\\hspace{1em}",
                if (client.country.len > 0) client.country else "\\hspace{1em}",
            });

            if (opts.coverletter.greeting) |greeting| {
                try file.writer().print(
                    \\ \def\greeting{{{s}}}
                    \\
                , .{greeting});
            }
            if (opts.footer.goodbye) |goodbye| {
                try file.writer().print(
                    \\ \def\goodbye{{{s}}}
                    \\
                , .{goodbye});
            }
        },
        fi_json.Offer => {
            try file.writer().print(
                \\ \Draft{}
                \\ \ShowAllNetto{}
                \\ \ShowAgb{}
                \\ \ShowRates{}
                \\ \def\FiDocType{{{s}}}
                \\ \def\FiDocId{{{s}}}
                \\ \def\FiDate{{{s}}}
                \\ \def\FiProjectName{{{s}}}
                \\ \def\FiClientCompany{{{s}}}
                \\ \def\FiClientCareOf{{{s}}}
                \\ \def\FiClientStreet{{{s}}}
                \\ \def\FiClientAreaCode{{{s}}}
                \\ \def\FiClientCity{{{s}}}
                \\ \def\FiClientCountry{{{s}}}
                \\
                \\ \def\FiVatPercent{{{d}}}
                \\ \ShowNoVat{}
                \\
            , .{
                draft,
                opts.footer.show_allnetto,
                opts.footer.show_agb,
                opts.coverletter.show_rates,
                "Angebot",
                id,
                opts.date,
                opts.project_name,
                client.@"company-name",
                client.@"c/o-name" orelse "\\hspace{1em}",
                if (client.street.len > 0) client.street else "\\hspace{1em}",
                if (client.areacode.len > 0) client.areacode else "\\hspace{1em}",
                if (client.city.len > 0) client.city else "\\hspace{1em}",
                if (client.country.len > 0) client.country else "\\hspace{1em}",
                opts.vat.percent,
                opts.vat.show_exempt_notice,
            });

            if (opts.coverletter.greeting) |greeting| {
                try file.writer().print(
                    \\ \def\greeting{{{s}}}
                    \\
                , .{greeting});
            }

            if (opts.valid_thru) |validthru| {
                try file.writer().print(
                    \\ \def\validthru{{{s}}}
                    \\
                , .{validthru});
            }

            if (opts.devtime) |devtime| {
                try file.writer().print(
                    \\ \def\devtime{{{s}}}
                    \\
                , .{devtime});
            }
        },
        fi_json.Invoice => {
            try file.writer().print(
                \\ \Draft{}
                \\ \ShowAgb{}
                \\ \def\FiDocType{{{s}}}
                \\ \def\FiDocId{{{s}}}
                \\ \def\FiDate{{{s}}}
                \\ \def\FiClientCompany{{{s}}}
                \\ \def\FiClientCareOf{{{s}}}
                \\ \def\FiClientStreet{{{s}}}
                \\ \def\FiClientAreaCode{{{s}}}
                \\ \def\FiClientCity{{{s}}}
                \\ \def\FiClientCountry{{{s}}}
                \\
                \\ \def\FiVatPercent{{{d}}}
                \\ \ShowNoVat{}
                \\ \def\FiInvoiceFrom{{{s}}}
                \\ \def\FiTermsOfPayment{{{s}}}
                \\
            , .{
                draft,
                opts.footer.show_agb,
                "Rechnung",
                id,
                opts.date,
                client.@"company-name",
                client.@"c/o-name" orelse "\\hspace{1em}",
                if (client.street.len > 0) client.street else "\\hspace{1em}",
                if (client.areacode.len > 0) client.areacode else "\\hspace{1em}",
                if (client.city.len > 0) client.city else "\\hspace{1em}",
                if (client.country.len > 0) client.country else "\\hspace{1em}",
                opts.vat.percent,
                opts.vat.show_exempt_notice,
                opts.leistungszeitraum,
                opts.terms_of_payment,
            });

            if (opts.leistungszeitraum_bis) |invoice_to| {
                try file.writer().print(
                    \\ \def\FiInvoiceTo{{{s}}}
                    \\
                , .{invoice_to});
            }
        },
        else => unreachable,
    }
}

pub fn documentBaseDir(self: *const Fi, DocumentType: type) ![]const u8 {
    const subdir =
        switch (DocumentType) {
            fi_json.Letter => "letters",
            fi_json.Offer => "offers",
            fi_json.Invoice => "invoices",
            else => unreachable,
        };
    return path.join(self.arena, &[_][]const u8{ self.fi_home.?, subdir });
}

fn documentDir(self: *const Fi, DocumentType: type, doc_dir_: ?[]const u8, dir_out: []u8) ![]const u8 {
    const document_base: []const u8 = blk: {
        const subdir =
            switch (DocumentType) {
                fi_json.Letter => "letters",
                fi_json.Offer => "offers",
                fi_json.Invoice => "invoices",
                else => unreachable,
            };
        if (doc_dir_) |doc_dir| {
            // if user specified . by habit, let them have it
            if (doc_dir.len == 1 and doc_dir[0] == '.') break :blk ".";
            break :blk std.fmt.bufPrint(dir_out, "{s}/{s}/{s}", .{
                self.fi_home.?,
                subdir,
                doc_dir,
            }) catch |err| {
                log.err("Document path for {s} > {d} bytes! -> {}", .{
                    doc_dir,
                    max_path_bytes,
                    err,
                });
                try fatal("Aborting", .{}, error.OutOfMemory);
            };
        } else {
            break :blk ".";
        }
    };
    return document_base;
}

/// returns the grand total
fn generateBillablesTex(self: *const Fi, subdir_spec: DocumentSubdirSpec, obj: anytype) !usize {
    var bfile = try subdir_spec.dir.openFile("billables.csv", .{});
    defer bfile.close();

    const friendly_filename = try std.fmt.allocPrint(self.arena, "{s}/billables.csv", .{subdir_spec.name});

    var billables_alist = std.ArrayListUnmanaged(u8).empty;

    const rates = try self.loadRecord(fi_json.Rate, obj.applicable_rates, .{});

    const lines = try bfile.readToEndAlloc(self.arena, self.max_json_file_size);
    var it = std.mem.splitScalar(u8, lines, '\n');
    var line_count: usize = 0;
    var item_count: usize = 0;
    var grand_total: usize = 0;

    var group_sum_map: std.StringArrayHashMapUnmanaged(usize) = .empty;
    var current_group: []const u8 = "unnamed";

    while (it.next()) |line| {
        line_count += 1;

        // check if it's a comment
        if (std.mem.startsWith(u8, line, "#")) continue;

        // skip empty lines
        if (line.len == 0) continue;

        // if there's at least one comma: it might be a GroupName line
        if (std.mem.containsAtLeastScalar(u8, line, 1, ',')) {
            if (std.mem.containsAtLeastScalar(u8, line, 4, ',')) {} else {
                try fatal("{s}:{d} Expected 5 columns!", .{ friendly_filename, line_count }, error.InvalidFileFormat);
            }

            var col_it = std.mem.splitScalar(u8, line, ',');
            const description = format.strip(col_it.next() orelse unreachable); // we checked above
            const amount_str = format.strip(col_it.next() orelse unreachable);
            const rate_name = format.strip(col_it.next() orelse unreachable);
            const price_per_unit_str = format.strip(col_it.next() orelse unreachable);
            var remarks = format.strip(col_it.next() orelse unreachable);
            if (std.ascii.eqlIgnoreCase(remarks, "null")) {
                remarks = "\\hspace{1em}";
            }

            // validate numbers
            const amount: f32 = std.fmt.parseFloat(f32, amount_str) catch |err| {
                try fatal(
                    "{s}/{d}: Column 2 (amount): `{s}` cannot be parsed into a number: {}",
                    .{ friendly_filename, line_count, amount_str, err },
                    err,
                );
            };

            item_count += 1;

            const price_per_unit = blk: {
                if (startsWithIC(price_per_unit_str, "null")) {
                    if (startsWithIC(rate_name, "hour") or
                        startsWithIC(rate_name, "stunde"))
                        break :blk rates.daily;
                    if (startsWithIC(rate_name, "day") or
                        startsWithIC(rate_name, "tag"))
                        break :blk rates.daily;
                    if (startsWithIC(rate_name, "week") or
                        startsWithIC(rate_name, "woche"))
                        break :blk rates.weekly;

                    try fatal(
                        "{s}/{d}: Column 3 (rate name): price_per_unit is null yet `{s}` is neither hourly, daily, nor weekly ",
                        .{ friendly_filename, line_count, rate_name },
                        error.InvalidFileFormat,
                    );
                } else {
                    break :blk std.fmt.parseUnsigned(usize, price_per_unit_str, 10) catch |err| {
                        try fatal(
                            "{s}/{d}: Column 3 (price_per_unit): `{s}` cannot be parsed into a number: {}",
                            .{ friendly_filename, line_count, price_per_unit_str, err },
                            err,
                        );
                    };
                }
            };

            // update sums
            const line_price: usize = @intFromFloat(@as(f32, @floatFromInt(price_per_unit)) * amount);
            grand_total += line_price;
            if (group_sum_map.getPtr(current_group)) |group_sum| {
                group_sum.* += line_price;
            }

            try billables_alist.writer(self.arena).print("\\itemrow{{{d}}}{{{s}}}{{{s}}}{{{s}}}{{{s},00 €}}{{{s},00 €}}{{\\grayit{{{s}}}}}\n", .{
                item_count,
                description,
                try format.floatThousandsAlloc(self.arena, amount, .german),
                rate_name,
                try format.intThousandsAlloc(self.arena, price_per_unit, .german),
                try format.intThousandsAlloc(self.arena, line_price, .german),
                remarks,
            });
        } else {
            if (line.len >= 3) {
                current_group = format.strip(line);
                try billables_alist.writer(self.arena).print("\\groupheader{{{s}}}\n", .{current_group});

                // SANITY CHECK
                if (group_sum_map.count() == 0 and grand_total != 0) {
                    try fatal(
                        "{s}/{d}: First group header: `{s}` is not the first item!",
                        .{ friendly_filename, line_count, current_group },
                        error.InvalidFileFormat,
                    );
                }
                try group_sum_map.put(self.arena, current_group, 0);
            } else {
                try fatal(
                    "{s}/{d}: Group header `{s}` is shorter than 3 characters!",
                    .{ friendly_filename, line_count, line },
                    error.InvalidFileFormat,
                );
            }
        }
    }

    // now write the sums.tex
    var groups_tex_alist: std.ArrayListUnmanaged(u8) = .empty;

    // TODO: Mit und ohne Optionen

    // if we have more than the default group
    if (group_sum_map.count() > 0) {
        // omit default group
        var group_it = group_sum_map.iterator();
        while (group_it.next()) |kv| {
            const group_name = kv.key_ptr.*;
            const value = kv.value_ptr.*;
            try groups_tex_alist.writer(self.arena).print("\\textbf{{{s}}} & {{{s},00 €}} \\\\\n", .{
                group_name,
                try format.intThousandsAlloc(self.arena, value, .german),
            });
        }
    }

    //write the grand total(s)
    var totals_tex_file = try subdir_spec.dir.createFile("totals.tex", .{ .exclusive = false });
    try totals_tex_file.writer().print(
        "\\def\\FiGrandTotal{{{s},00}}\n",
        .{
            try format.intThousandsAlloc(self.arena, grand_total, .german),
        },
    );

    // invoices need the VAT treatment
    const DocumentType = @TypeOf(obj);
    const vat_amount: usize = @divTrunc(grand_total * obj.vat.percent, 100);
    grand_total += vat_amount;
    try totals_tex_file.writer().print(
        "\\def\\FiVatAmount{{{s},00}}\n" ++
            "\\def\\FiGrandTotalPlusVat{{{s},00}}\n",

        .{
            try format.intThousandsAlloc(self.arena, vat_amount, .german),
            try format.intThousandsAlloc(self.arena, grand_total, .german),
        },
    );

    // now read invoice.tex and replace
    const input_tex_name = try std.fmt.allocPrint(self.arena, "{s}.tex", .{documentTypeHumanName(DocumentType)});
    var input_tex_file = try subdir_spec.dir.openFile(input_tex_name, .{ .mode = .read_write });
    defer input_tex_file.close();

    const orig_tex = try input_tex_file.readToEndAlloc(self.arena, 1024 * 1024);
    const temp_tex_billables = try self.replaceSection(orig_tex, "BILLABLES", billables_alist.items);
    const new_tex = try self.replaceSection(temp_tex_billables, "GROUPSUMS", groups_tex_alist.items);
    try input_tex_file.seekTo(0);
    try input_tex_file.writeAll(new_tex);
    return grand_total;
}

fn replaceSection(self: *const Fi, input: []const u8, section: []const u8, replacement: []const u8) ![]const u8 {
    var alist = std.ArrayListUnmanaged(u8).empty;
    var writer = alist.writer(self.arena);

    const section_marker_start = try std.fmt.allocPrint(self.arena, "% <BEGIN {s}>", .{section});
    const section_marker_end = try std.fmt.allocPrint(self.arena, "% <END {s}>", .{section});

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line_untrimmed| {
        try writer.print("{s}\n", .{line_untrimmed});
        const line = format.strip(line_untrimmed);
        if (std.ascii.startsWithIgnoreCase(line, section_marker_start)) {
            try writer.writeAll(replacement);

            // now skip until end
            while (it.next()) |trash_line_untrimmed| {
                const trash_line = format.strip(trash_line_untrimmed);
                if (std.ascii.startsWithIgnoreCase(trash_line, section_marker_end)) {
                    try writer.print("{s}\n", .{trash_line});
                    break;
                } else {
                    // log.debug("SKIPPING LINE: {s}", .{trash_line});
                }
            } else {
                try fatal("Missing END MARKER `{s}` in tex file!", .{section_marker_end}, error.InvalidFileFormat);
                unreachable;
            }
        }
    }
    return alist.items;
}

fn cmdCompileDocument(self: *const Fi, args: anytype) !HandleDocumentCommandResult {
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };

    var docdir_buf: [max_path_bytes]u8 = undefined;

    // check if we need to operate in current directory or if we got an id
    const subdir_name = blk: {
        if (args.positional.arg) |id_str| {
            break :blk try self.documentDir(DocumentType, id_str, &docdir_buf);
        } else {
            break :blk try self.documentDir(DocumentType, null, &docdir_buf);
        }
    };
    if (!fsutil.isDirPresent(subdir_name)) {
        try fatal("Directory `{s}` does not exist!", .{subdir_name}, error.NotFound);
    }
    const subdir = cwd().openDir(subdir_name, .{ .iterate = true }) catch |err| {
        try fatal("Unable to enter directory `{s}`: {}", .{ subdir_name, err }, err);
    };
    var subdir_spec: DocumentSubdirSpec = .{
        .dir = subdir,
        .name = subdir_name,
    };
    defer subdir_spec.dir.close();

    var obj = try self.loadDocumentMeta(subdir_spec, DocumentType);

    // generate config.tex
    {
        var tex_config_file = subdir_spec.dir.createFile("config.tex", .{ .exclusive = false }) catch |err| {
            try fatal(
                "Could not create `{s}/config.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
        self.generateTexConfig(tex_config_file, obj.id, obj) catch |err| {
            try fatal(
                "Error generating `{s}/config.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
        defer tex_config_file.close();
    }

    // if !letter: generate rates.tex
    if (DocumentType != fi_json.Letter) {
        self.generateRatesTex(subdir_spec, obj.applicable_rates) catch |err| {
            try fatal(
                "Error writing `{s}/rates.tex`: {}",
                .{ subdir_spec.name, err },
                err,
            );
        };
    }

    var grand_total: usize = 0;
    // generate billables if ! letter
    if (DocumentType != fi_json.Letter) {
        grand_total = self.generateBillablesTex(subdir_spec, obj) catch |err| {
            try fatal(
                "Error generating billables: {}",
                .{err},
                err,
            );
        };

        // now update the json
        obj.total = grand_total;
    }
    obj.updated = try self.isoTime();
    try self.saveDocumentMeta(DocumentType, subdir_spec, obj);

    // compile
    const pdflatex: PdfLatex = .{ .arena = self.arena, .work_dir = subdir_spec.name };
    const input_tex = try std.fmt.allocPrint(self.arena, "{s}.tex", .{documentTypeHumanName(DocumentType)});
    const temp_pdf = try std.fmt.allocPrint(self.arena, "{s}.pdf", .{documentTypeHumanName(DocumentType)});
    var filename_buf: [max_name_bytes]u8 = undefined;
    const final_pdf = try std.fmt.allocPrint(
        self.arena,
        "{s}.pdf",
        .{try createDocumentName(DocumentType, obj.id, obj.client_shortname, &filename_buf)},
    );
    if (try pdflatex.run(input_tex)) {
        // 2nd run
        if (try pdflatex.run(input_tex)) {
            // rename pdf
            try subdir_spec.dir.rename(temp_pdf, final_pdf);
        }
    }
    log.info("✅ compiled to `{s}/{s}`!", .{ subdir_spec.name, final_pdf });
    return .{ .compile = try self.readDocumentFiles(DocumentType, subdir_spec) };
}

fn cmdCommitDocument(self: *Fi, args: anytype) !HandleDocumentCommandResult {
    // validate it
    // update it
    // compile it
    // then copy it
    const DocumentType = switch (@TypeOf(args)) {
        Cli.LetterCommand => fi_json.Letter,
        Cli.OfferCommand => fi_json.Offer,
        Cli.InvoiceCommand => fi_json.Invoice,
        else => unreachable,
    };
    const human_doctype = documentTypeHumanName(DocumentType);

    const subdir_name = ".";
    const subdir = cwd().openDir(subdir_name, .{ .iterate = true }) catch |err| {
        try fatal("Unable to enter directory `{s}`: {}", .{ subdir_name, err }, err);
    };
    var subdir_spec: DocumentSubdirSpec = .{
        .dir = subdir,
        .name = subdir_name,
    };
    defer subdir_spec.dir.close();

    // automatically validates the json
    var obj = try self.loadDocumentMeta(subdir_spec, DocumentType);
    if (!std.ascii.endsWithIgnoreCase(obj.id, "XXX")) {
        try fatal("This document already has a non-temporary ID `{s}`! Have you committed it already?", .{obj.id}, error.AlreadyCommitted);
    }

    // validate by compiling to pdf
    const compile_args = blk: {
        const CliType = switch (DocumentType) {
            fi_json.Letter => Cli.LetterCommand,
            fi_json.Offer => Cli.OfferCommand,
            fi_json.Invoice => Cli.InvoiceCommand,
            else => unreachable,
        };
        const compile_args: CliType = .{
            .positional = .{ .subcommand = .compile },
        };
        _ = try self.cmdCompileDocument(compile_args);
        break :blk compile_args;
    };

    // bump ID
    const new_id = try self.incrementDocumentTypeId(DocumentType);
    const old_id = try self.arena.dupe(u8, obj.id);
    obj.id = new_id;

    // update json
    {
        var filename_buf: [max_name_bytes]u8 = undefined;
        const json_file_stem = human_doctype;
        const filename = std.fmt.bufPrint(&filename_buf, "{s}.json", .{json_file_stem}) catch |err| {
            try fatal("Unable to create filename `{s}.json`: {}", .{ json_file_stem, err }, err);
        };
        const file = subdir_spec.dir.createFile(filename, .{ .exclusive = false }) catch |err| {
            try fatal("Unable to update file `{s}`: {}", .{ filename, err }, err);
        };

        defer file.close();
        const writer = file.writer();
        std.json.stringify(obj, .{ .whitespace = .indent_4 }, writer) catch |err| {
            try fatal("Error writing to file {s}.json: {}", .{ filename, err }, err);
        };
    }

    // now that the ID has been updated, compile again!
    _ = try self.cmdCompileDocument(compile_args);

    var dest_path_buf: [max_path_bytes]u8 = undefined;
    // delete the .pdf with the temp id XXX
    {
        const temp_pdf = try std.fmt.allocPrint(
            self.arena,
            "{s}.pdf",
            .{try createDocumentName(DocumentType, old_id, obj.client_shortname, &dest_path_buf)},
        );
        subdir_spec.dir.deleteFile(temp_pdf) catch {};
    }

    // only if all went well, we'll commit to fi_home
    {
        // const document_dir_name = try std.fmt.allocPrint(
        //     self.arena,
        //     "{s}--{s}--{s}",
        //     .{ human_doctype, obj.id, obj.client_shortname },
        // );
        var dir_name_buf: [max_name_bytes]u8 = undefined;
        const document_dir_name = try createDocumentName(DocumentType, obj.id, obj.client_shortname, &dir_name_buf);
        const dest_path = try self.documentDir(DocumentType, document_dir_name, &dest_path_buf);
        cwd().makeDir(dest_path) catch |err| {
            try fatal("Error creating dir `{s}`: {}", .{ dest_path, err }, err);
        };
        var dest_dir = try cwd().openDir(dest_path, .{});
        defer dest_dir.close();

        var file_it = subdir_spec.dir.iterate();
        while (try file_it.next()) |entry| {
            log.info("    {s} -> {s}/{s}", .{ entry.name, dest_path, entry.name });
            try subdir_spec.dir.copyFile(entry.name, dest_dir, entry.name, .{});
        }
    }

    // git commit
    {
        var git: Git = .{ .arena = self.arena, .repo_dir = self.fi_home.? };
        if (!try git.stage(.all)) {
            try fatal("Aborting Git commit!", .{}, error.Abort);
        }
        const commit_msg = try std.fmt.allocPrint(
            self.arena,
            "[auto-fi] Committing {s} {s}",
            .{ human_doctype, obj.id },
        );
        if (!try git.commit(commit_msg)) {
            try fatal("Aborting! Git commit", .{}, error.Abort);
        }
    }
    log.info("✅  {s} {s} committed!", .{ documentTypeHumanName(DocumentType), obj.id });
    return .{ .commit = try self.readDocumentFiles(DocumentType, subdir_spec) };
}

fn getDocumentTypeId(self: *const Fi, DocumentType: type, lock_ptr: ?*fsutil.FileLock) ![]const u8 {
    const fi_home = self.fi_home.?; // we assert this has been set previously
    const subdir = switch (DocumentType) {
        fi_json.Letter => @tagName(SubDirs.letters),
        fi_json.Offer => @tagName(SubDirs.offers),
        fi_json.Invoice => @tagName(SubDirs.invoices),
        else => unreachable,
    };

    const id_filename = try path.join(self.arena, &[_][]const u8{ fi_home, subdir, ".id" });

    var lock: fsutil.FileLock = blk: {
        if (lock_ptr) |ptr| {
            break :blk ptr.*;
        } else {
            break :blk try fsutil.FileLock.acquire(self.arena, id_filename);
        }
    };

    defer {
        if (lock_ptr == null) lock.release();
    }

    var f = try cwd().openFile(id_filename, .{});
    defer f.close();
    const line = format.strip(try f.readToEndAlloc(self.arena, 1024));
    if (line.len != "2025-XXX".len) {
        lock.release();
        try fatal(
            "Corrupted ID file: `{s}` contains `{s}`! ",
            .{ id_filename, line },
            error.FileCorrupted,
        );
    }
    return self.arena.dupe(u8, line);
}

fn incrementDocumentTypeId(self: *const Fi, DocumentType: type) ![]const u8 {
    const fi_home = self.fi_home.?; // we assert this has been set previously

    // create .id files
    const subdir = switch (DocumentType) {
        fi_json.Letter => @tagName(SubDirs.letters),
        fi_json.Offer => @tagName(SubDirs.offers),
        fi_json.Invoice => @tagName(SubDirs.invoices),
        else => unreachable,
    };

    const id_filename = try path.join(self.arena, &[_][]const u8{ fi_home, subdir, ".id" });

    // lock the id
    var lock: fsutil.FileLock = try fsutil.FileLock.acquire(self.arena, id_filename);
    defer lock.release();

    // get current id, locked
    const current_id_str = try self.getDocumentTypeId(DocumentType, &lock);
    if (current_id_str.len != "2025-XXX".len) {
        lock.release();
        try fatal("Corrupted ID file: `{s}`!", .{current_id_str}, error.FileCorrupted);
    }
    var numeric_id: usize = try std.fmt.parseUnsigned(usize, current_id_str[5..], 10);
    numeric_id += 1;

    const new_id_str = try std.fmt.allocPrint(
        self.arena,
        "{s}{d:03}",
        .{ current_id_str[0..5], numeric_id },
    );

    const f = try cwd().createFile(id_filename, .{});
    defer f.close();
    try f.writer().print("{s}\n", .{new_id_str});
    return self.arena.dupe(u8, new_id_str);
}
