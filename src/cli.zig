const Git = @import("git.zig");

pub const InitCommand = struct {
    fi_home: ?[]const u8 = null,
    generate: bool = false,

    positional: struct {
        init_json_file: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fi_home = "C",
        .generate = "G",
    };

    pub const help =
        \\ Command: init
        \\
        \\ Usage:
        \\
        \\ fi init [options] <init_json_file>]
        \\
        \\ Options:
        \\
        \\ -G, --generate           Generates a JSON template for you to fill in.
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fi_home            The FI_HOME dir to use.
        \\                          Default: $FI_HOME orelse ~/.fi
        \\
    ;
};

pub const GitCommand = struct {
    fi_home: ?[]const u8 = null,
    remote: ?[]const u8 = null,
    url: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { remote, pull, push, status },
        subsubcommand: ?Git.RemoteSubCommand = null,
    },

    pub const aliases = .{
        .fi_home = "C",
    };
    pub const help =
        \\ Command: git
        \\
        \\ Usage:
        \\
        \\ fi git [-C, --fi_home=<path>] [subcommand] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ remote [add|show|delete] [options]
        \\
        \\ Configure git remote(s). Usually, one is enough.
        \\
        \\    fi git remote add    [--repo=REMOTE]   --url=URL
        \\    fi git remote list
        \\    fi git remote show   [--repo=REMOTE]
        \\    fi git remote delete [--repo=REMOTE]
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
        \\ -C, --fi_home            The FI_HOME dir to use.
        \\                          Default: $FI_HOME orelse ~/.fi
        \\
    ;
};

pub const JsonResourceSubCommand = enum { new, show, checkout, commit, list };
pub const JsonResourceKind = enum { client, rate };

pub fn JsonResourceCommand(comptime kind: JsonResourceKind) type {
    return struct {
        fi_home: ?[]const u8 = null,
        verbose: bool = false,

        positional: struct {
            subcommand: JsonResourceSubCommand,
            arg: ?[]const u8 = null,
        },

        pub const aliases = .{
            .fi_home = "C",
            .verbose = "v",
        };

        pub const help = switch (kind) {
            .client =>
            \\ Command:
            \\
            \\ Usage:
            \\
            \\ fi client [new|show|checkout|commit|list] [options]
            \\
            \\ Available Subcommands:
            \\ ======================
            \\
            \\ - fi client new      <shortname>   -> <shortname>.json
            \\ - fi client show     <shortname>   -> stdout
            \\ - fi client checkout <shortname>   -> shortname.json
            \\ - fi client commit   <client.json> -> move into .fi/clients
            \\ - fi client list     [--all] [-v]
            \\
            \\ Options:
            \\
            \\ -h, --help               Displays this help message then exits.
            \\
            \\ -C, --fi_home            The FI_HOME dir to use.
            \\                          Default: $FI_HOME orelse ~/.fi
            \\
            ,
            .rate =>
            \\ Command: rate
            \\
            \\ Usage:
            \\
            \\ fi rate [new|show|checkout|commit|list] [options]
            \\
            \\ Available Subcommands:
            \\ ======================
            \\
            \\ - fi rate new      <shortname>   -> <shortname>.json
            \\ - fi rate show     <shortname>   -> stdout
            \\ - fi rate checkout <shortname>   -> shortname.json
            \\ - fi rate commit   <rate.json>   -> move into .fi/rates
            \\ - fi rate list     [--all] [-v]
            \\
            \\ Options:
            \\
            \\ -h, --help               Displays this help message then exits.
            \\
            \\ -C, --fi_home            The FI_HOME dir to use.
            \\                          Default: $FI_HOME orelse ~/.fi
            \\
            ,
        };
    };
}

pub const ClientCommand = JsonResourceCommand(.client);
pub const RateCommand = JsonResourceCommand(.rate);

pub const LetterCommand = struct {
    fi_home: ?[]const u8 = null,
    list_all: bool = false,
    to: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { new, show, checkout, commit, list, open, compile },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fi_home = "C",
    };

    pub const help =
        \\ Command: letter
        \\
        \\ Usage:
        \\
        \\ fi letter [new|show|checkout|commit|list] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fi letter new <client>           [--to=<c/o name>]
        \\                                     -> <letter--YEAR-XXXX--clientshortname>/
        \\ - fi letter show     <ID>           -> stdout
        \\ - fi letter checkout <ID>           -> <letter--ID--clientshortname>/
        \\ - fi letter commit                  -> move into .fi/letters
        \\ - fi letter list     [--all] [-v]
        \\ - fi letter open     <ID>           -> open PDF
        \\ - fi letter compile [<ID>]          -> compile PDF in current dir or from ID
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fi_home            The FI_HOME dir to use.
        \\                          Default: $FI_HOME orelse ~/.fi
        \\
    ;
};

pub const OfferCommand = struct {
    fi_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { new, checkout, commit, list, show, open, compile },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fi_home = "C",
    };

    pub const help =
        \\ Command: offer
        \\
        \\ Usage:
        \\
        \\ fi offer [new|commit|checkout|list|show|open|compile] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fi offer new <client> --project=<project>
        \\                                      [--rates=<rates>]
        \\                                      [--to=<c/o name>]
        \\                                    -> <offer--YEAR-XXXX--clientshortname>/
        \\ - fi offer commit      >           -> move into .fi/offers
        \\ - fi offer checkout <ID>           -> <offer--ID--clientshortname>/
        \\ - fi offer list     [--all] [-v]
        \\ - fi offer show     <ID>           -> show metadata
        \\ - fi offer compile [<ID>]          -> compile PDF in current dir or from ID
        \\ - fi offer open     <ID>           -> open PDF
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fi_home            The FI_HOME dir to use.
        \\                          Default: $FI_HOME orelse ~/.fi
        \\
    ;
};

pub const InvoiceCommand = struct {
    fi_home: ?[]const u8 = null,
    project: ?[]const u8 = null,
    rates: ?[]const u8 = null,
    to: ?[]const u8 = null,

    positional: struct {
        subcommand: enum { new, show, checkout, commit, list, open, compile },
        arg: ?[]const u8 = null,
    },

    pub const aliases = .{
        .fi_home = "C",
    };

    pub const help =
        \\ Command: invoice
        \\
        \\ Usage:
        \\
        \\ fi invoice [new|show|checkout|commit|list] [options]
        \\
        \\ Available Subcommands:
        \\ ======================
        \\
        \\ - fi invoice new  <client> --project=<project>
        \\                                          [--rates=<rates>]
        \\                                          [--to=<c/o name>]
        \\                                     -> <invoice--YEAR-XXXX--clientshortname>/
        \\
        \\ - fi invoice checkout <ID>          -> <invoice--ID--clientshortname>/
        \\ - fi invoice commit                 -> move into .fi/invoices and compile
        \\ - fi invoice list     [--all] [-v]
        \\ - fi invoice show     <ID>          -> show metadata
        \\ - fi invoice open     <ID>          -> open PDF
        \\ - fi invoice compile [<ID>]         -> compile PDF in current dir or from ID
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -C, --fi_home            The FI_HOME dir to use.
        \\                          Default: $FI_HOME orelse ~/.fi
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

    pub const help =
        \\ Usage: fi [command] [options]
        \\
        \\ Commands:
        \\  init            Initialize fi
        \\  git             Configure git remotes, push, pull, status
        \\  client          Manage clients
        \\  rate            Manage rates
        \\  letter          Manager letters
        \\  offer           Manager offers
        \\  invoice         Manage invoices
        \\
        \\ General Options:
        \\  -h, --help      Displays this help message then exits
        \\
        \\  -C, --fi_home   The FI_HOME dir to use
        \\                  Default: $FI_HOME orelse ~/.fi
        \\
    ;
};
