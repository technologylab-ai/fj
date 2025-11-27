const Git = @import("git.zig");

pub const InitCommand = struct {
    fj_home: ?[]const u8 = null,
    generate: bool = false,

    positional: struct {
        init_json_file: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fj_home = "C",
        .generate = "G",
    };

    pub const help =
        \\ Command: init
        \\
        \\ Usage:
        \\
        \\ fj init [options] <init_json_file>]
        \\
        \\ Options:
        \\
        \\ -G, --generate           Generates a JSON template for you to fill in.
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const GitCommand = struct {
    fj_home: ?[]const u8 = null,
    remote: ?[]const u8 = null,
    url: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { remote, pull, push, status },
        subsubcommand: ?Git.RemoteSubCommand = null,
    },

    pub const aliases = .{
        .fj_home = "C",
    };
    pub const help =
        \\ Command: git
        \\
        \\ Usage:
        \\
        \\ fj git [-C, --fj_home=<path>] [subcommand] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ remote [add|show|delete] [options]
        \\
        \\ Configure git remote(s). Usually, one is enough.
        \\
        \\    fj git remote add    [--repo=REMOTE]   --url=URL
        \\    fj git remote list
        \\    fj git remote show   [--repo=REMOTE]
        \\    fj git remote delete [--repo=REMOTE]
        \\
        \\    REMOTE defaults to origin/git default
        \\ ------------------------------------------------------------
        \\
        \\ pull                    [--repo=REMOTE]
        \\
        \\ Pull changes from remote(s).
        \\
        \\
        \\ ------------------------------------------------------------
        \\
        \\ push                    [--repo=REMOTE]
        \\
        \\ Push changes to remote(s).
        \\
        \\ ------------------------------------------------------------
        \\
        \\ status
        \\
        \\ Show git status
        \\
        \\ ------------------------------------------------------------
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const JsonResourceSubCommand = enum { new, show, checkout, commit, list };
pub const JsonResourceKind = enum { client, rate };

pub fn JsonResourceCommand(comptime kind: JsonResourceKind) type {
    return struct {
        fj_home: ?[]const u8 = null,
        verbose: bool = false,

        positional: struct {
            subcommand: JsonResourceSubCommand,
            arg: ?[]const u8 = null,
        },

        pub const aliases = .{
            .fj_home = "C",
            .verbose = "v",
        };

        pub const help = switch (kind) {
            .client =>
            \\ Command:
            \\
            \\ Usage:
            \\
            \\ fj client [new|show|checkout|commit|list] [options]
            \\
            \\ Available Subcommands:
            \\ ======================
            \\
            \\ - fj client new      <shortname>   -> <shortname>.json
            \\ - fj client show     <shortname>   -> stdout
            \\ - fj client checkout <shortname>   -> shortname.json
            \\ - fj client commit   <client.json> -> move into .fj/clients
            \\ - fj client list     [--all] [-v]
            \\
            \\ Options:
            \\
            \\ -h, --help               Displays this help message then exits.
            \\
            \\ -C, --fj_home            The FJ_HOME dir to use.
            \\                          Default: $FJ_HOME orelse ~/.fj
            \\
            ,
            .rate =>
            \\ Command: rate
            \\
            \\ Usage:
            \\
            \\ fj rate [new|show|checkout|commit|list] [options]
            \\
            \\ Available Subcommands:
            \\ ======================
            \\
            \\ - fj rate new      <shortname>   -> <shortname>.json
            \\ - fj rate show     <shortname>   -> stdout
            \\ - fj rate checkout <shortname>   -> shortname.json
            \\ - fj rate commit   <rate.json>   -> move into .fj/rates
            \\ - fj rate list     [--all] [-v]
            \\
            \\ Options:
            \\
            \\ -h, --help               Displays this help message then exits.
            \\
            \\ -C, --fj_home            The FJ_HOME dir to use.
            \\                          Default: $FJ_HOME orelse ~/.fj
            \\
            ,
        };
    };
}

pub const ClientCommand = JsonResourceCommand(.client);
pub const RateCommand = JsonResourceCommand(.rate);

pub const LetterCommand = struct {
    fj_home: ?[]const u8 = null,
    list_all: bool = false,
    to: ?[]const u8 = null,

    force: bool = false,

    positional: struct {
        subcommand: enum { new, show, checkout, commit, list, open, compile },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: letter
        \\
        \\ Usage:
        \\
        \\ fj letter [new|show|checkout|commit|list] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fj letter new <client>           [--to=<c/o name>]
        \\                                     -> <letter--YEAR-XXXX--clientshortname>/
        \\ - fj letter show     <ID>           -> stdout
        \\ - fj letter checkout <ID>           -> <letter--ID--clientshortname>/
        \\ - fj letter commit                  -> move into .fj/letters
        \\ - fj letter list     [--all] [-v]
        \\ - fj letter open     <ID>           -> open PDF
        \\ - fj letter compile [<ID>]          -> compile PDF in current dir or from ID
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const OfferCommand = struct {
    fj_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    omsproject: ?[]const u8 = null,
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,

    force: bool = false,

    positional: struct {
        subcommand: enum { new, checkout, commit, list, show, open, compile, accept, reject },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: offer
        \\
        \\ Usage:
        \\
        \\ fj offer [new|commit|checkout|list|show|open|compile|accept|reject] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fj offer new <client> --project=<project>
        \\                                      [--rates=<rates>]
        \\                                      [--to=<c/o name>]
        \\                                    -> <offer--YEAR-XXXX--clientshortname>/
        \\ - fj offer commit      >           -> move into .fj/offers
        \\ - fj offer checkout <ID>           -> <offer--ID--clientshortname>/
        \\ - fj offer list     [--all] [-v]
        \\ - fj offer show     <ID>           -> show metadata
        \\ - fj offer compile [<ID>]          -> compile PDF in current dir or from ID
        \\ - fj offer open     <ID>           -> open PDF
        \\ - fj offer accept   <ID>           -> mark offer as accepted
        \\ - fj offer reject   <ID>           -> mark offer as rejected/declined
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const InvoiceCommand = struct {
    fj_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    omsproject: ?[]const u8 = null,
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,

    force: bool = false,

    positional: struct {
        subcommand: enum { new, show, checkout, commit, list, open, compile, paid },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: invoice
        \\
        \\ Usage:
        \\
        \\ fj invoice [new|show|checkout|commit|list|paid] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fj invoice new  <client> --project=<project>
        \\                                          [--rates=<rates>]
        \\                                          [--to=<c/o name>]
        \\                                     -> <invoice--YEAR-XXXX--clientshortname>/
        \\
        \\ - fj invoice checkout <ID>          -> <invoice--ID--clientshortname>/
        \\ - fj invoice commit                 -> move into .fj/invoices and compile
        \\ - fj invoice list     [--all] [-v]
        \\ - fj invoice show     <ID>          -> show metadata
        \\ - fj invoice open     <ID>          -> open PDF
        \\ - fj invoice compile [<ID>]         -> compile PDF in current dir or from ID
        \\ - fj invoice paid    <ID>           -> mark invoice as paid
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const KeysCommand = struct {
    fj_home: ?[]const u8 = null,
    expires: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { create, list, delete },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: keys
        \\
        \\ Usage:
        \\
        \\ fj keys [create|list|delete] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fj keys create <label> [--expires=YYYY-MM-DD]
        \\                          -> Creates new API key, displays once
        \\ - fj keys list           -> Lists all API keys (tokens masked)
        \\ - fj keys delete <label> -> Soft-deletes an API key
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};

pub const ServeCommand = struct {
    fj_home: ?[]const u8 = null,
    host: []const u8 = "0.0.0.0",
    port: usize = 3000,
    work_dir: []const u8 = ".",

    username: []const u8 = "admin",
    password: []const u8 = "admin",

    // positional: struct {
    //     // subcommand: enum { start  },
    // },

    pub const aliases = .{
        .fj_home = "C",
    };

    pub const help =
        \\ Command: serve [options]
        \\
        \\ Usage:
        \\
        \\ fj serve [options]
        \\
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fj_home            The FJ_HOME dir to use.
        \\                          Default: $FJ_HOME orelse ~/.fj
        \\ --host=                  The interface to listen on.
        \\                          Default: 0.0.0.0
        \\
        \\ --port=                  The port to listen on.
        \\                          Default: 3000
        \\ --work-dir=              The working directory where drafts will be created.
        \\                          Default: .
        \\ --username=              The username for authentication in the browser.
        \\                          Default: admin
        \\ --username=              The password for authentication in the browser.
        \\                          Default: admin
        \\
    ;
};

pub const VersionCommand = struct {
    pub const help =
        \\ Command: invoice
        \\
        \\ Usage:
        \\
        \\ fj version
        \\
    ;
};

pub const Cli = union(enum) {
    init: InitCommand,
    git: GitCommand,
    client: ClientCommand,
    rate: RateCommand,
    letter: LetterCommand,
    offer: OfferCommand,
    invoice: InvoiceCommand,
    keys: KeysCommand,
    serve: ServeCommand,
    version: VersionCommand,

    pub const help =
        \\ Usage: fj [command] [options]
        \\
        \\ Commands:
        \\  init            Initialize fj
        \\  git             Configure git remotes, push, pull, status
        \\  client          Manage clients
        \\  rate            Manage rates
        \\  letter          Manager letters
        \\  offer           Manager offers
        \\  invoice         Manage invoices
        \\  keys            Manage API keys
        \\  serve           Start the HTTP server for a web UI
        \\
        \\ General Options:
        \\  -h, --help      Displays this help message then exits
        \\
        \\  -C, --fj_home   The FJ_HOME dir to use
        \\                  Default: $FJ_HOME orelse ~/.fj
        \\
    ;
};
