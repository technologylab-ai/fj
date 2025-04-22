const std = @import("std");

pub const File = struct {
    filename: []const u8,
    content: []const u8,
};

pub const Files = struct {
    pub const @".gitignore": []const u8 = @embedFile("templates/.gitignore");
    pub const @"offer.tex": []const u8 = @embedFile("templates/offer.tex");
    pub const @"invoice.tex": []const u8 = @embedFile("templates/invoice.tex");
    pub const @"letter.tex": []const u8 = @embedFile("templates/letter.tex");
    pub const @"config-defaults.sty": []const u8 = @embedFile("templates/config-defaults.sty");
};

pub fn all(alloc: std.mem.Allocator) ![]File {
    const decls = @typeInfo(Files).@"struct".decls;
    var l = try std.ArrayListUnmanaged(File).initCapacity(alloc, decls.len);
    inline for (decls) |decl| {
        l.appendAssumeCapacity(
            .{ .filename = decl.name, .content = @field(Files, decl.name) },
        );
    }
    return try l.toOwnedSlice(alloc);
}
