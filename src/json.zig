pub const TexDefaults = struct {
    CompanyVatUID: []const u8 = "UID: XXX-YYYYYYY",
    CompanyRegisteredID: []const u8 = "Firmenbuch-Nr.: XXXXXXX",
    CompanyRegisteredAt: []const u8 = "Registriert beim Landesgericht X",
    CompanyName: []const u8 = "The Commandline Company Ltd.",
    CompanyStreet: []const u8 = "21 Jump Street",
    CompanyAreaCodeCity: []const u8 = "5555 Metropolis",
    CompanyUrl: []const u8 = "https://21jumpstreet.com",
    CompanyEmail: []const u8 = "me@21jumpstreet.com",
    DefaultGreeting: []const u8 = "Dear Sirs and Madams,",
    CurrencySymbol: []const u8 = "€",
    Logo: []const u8 = "logo.png",
    YourName: []const u8 = "Mr. X",
    DefaultGoodbye: []const u8 = "Goodbye",
    LetterCityDate: []const u8 = "Metropolis, ",
    GeneralTermsUrl: []const u8 = "https://21jumpstreet.com/terms-of-service",
    BankName: []const u8 = "Bank of Metropolis",
    BankBIC: []const u8 = "METROPWW",
    BankIBAN: []const u8 = "US21 2121 2121 2121 2121",
};

pub const Client = struct {
    shortname: []const u8,

    @"company-name": []const u8 = "",
    @"c/o-name": ?[]const u8 = null,
    street: []const u8 = "",
    areacode: []const u8 = "",
    city: []const u8 = "",
    country: []const u8 = "",
    tax_uid: []const u8 = "",

    remarks: ?[]const u8 = null,
    created: []const u8,
    updated: []const u8,
    revision: usize,
};

pub const Rate = struct {
    shortname: []const u8,

    hourly: usize,
    hours_per_day: usize,
    daily: usize,
    weekly: usize,

    remarks: ?[]const u8 = null,
    created: []const u8,
    updated: []const u8,
    revision: usize,
};

pub const Letter = struct {
    id: []const u8 = "",
    client_shortname: []const u8,
    subject: []const u8 = "Subject",
    date: []const u8 = "HEUTE",

    coverletter: struct {
        greeting: ?[]const u8 = null,
    },
    footer: struct {
        goodbye: ?[]const u8 = null,
    },

    remarks: ?[]const u8 = null,
    draft: bool = true,
    created: []const u8,
    updated: []const u8,
    revision: usize,
};

pub const Offer = struct {
    id: []const u8 = "",

    accepted_date: ?[]const u8 = null,
    declined_date: ?[]const u8 = null,
    client_shortname: []const u8,
    date: []const u8 = "HEUTE",
    project_name: []const u8 = "",
    applicable_rates: []const u8 = "",
    valid_thru: ?[]const u8 = null,
    coverletter: struct {
        greeting: ?[]const u8 = null,
        show_rates: bool = false,
    },

    devtime: ?[]const u8 = null,

    footer: struct {
        show_allnetto: bool = true,
        show_agb: bool = true,
    },

    vat: struct {
        percent: usize = 0,
        show_exempt_notice: bool = true,
    },

    remarks: ?[]const u8 = null,
    draft: bool = true,
    created: []const u8,
    updated: []const u8,
    revision: usize,
    total: ?usize = null,
};

pub const Invoice = struct {
    id: []const u8 = "",

    due_date: ?[]const u8 = null,
    paid_date: ?[]const u8 = null,

    client_shortname: []const u8,
    date: []const u8 = "HEUTE",
    year: i32,
    applicable_rates: []const u8 = "",
    leistungszeitraum: []const u8 = "",
    leistungszeitraum_bis: ?[]const u8 = null,
    terms_of_payment: []const u8 = "binnen 14 Tagen",

    coverletter: struct {
        greeting: ?[]const u8 = null,
    },

    footer: struct {
        show_agb: bool = true,
    },

    vat: struct {
        percent: usize = 0,
        show_exempt_notice: bool = true,
    },

    remarks: ?[]const u8 = null,
    draft: bool = true,
    created: []const u8,
    updated: []const u8,
    revision: usize,
    total: ?usize = null,
};
