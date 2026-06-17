const std = @import("std");

pub const Mode = enum { cli, server };
pub var mode: Mode = .cli; // set once in main.zig; read-only after — benign global

/// Per-request error context chain. Accumulates the whole context chain (root
/// cause first, each outer wrapper after) so the server can render the full
/// chain instead of a single last-writer-wins message. Tied to the per-request
/// arena allocator and threaded explicitly through the carrier structs (`Fj`,
/// `Git`, `PdfLatex`, `OpenCommand`); disposed with the request (arena reset).
pub const ErrorStack = struct {
    arena: std.mem.Allocator,
    messages: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn init(arena: std.mem.Allocator) ErrorStack {
        return .{ .arena = arena };
    }

    /// best-effort append; never fails the caller
    pub fn push(self: *ErrorStack, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.arena, fmt, args) catch return;
        self.messages.append(self.arena, msg) catch {};
    }

    /// append, then: CLI -> abort printing THIS (innermost) message;
    ///               server -> return err so caller's `try` propagates it
    pub fn fail(self: *ErrorStack, comptime fmt: []const u8, args: anytype, err: anyerror) anyerror!noreturn {
        self.push(fmt, args);
        switch (mode) {
            .cli => std.process.fatal(fmt, args),
            .server => return err,
        }
    }

    /// join chain, broadest context first, root cause last; "" if empty
    pub fn render(self: *const ErrorStack, arena: std.mem.Allocator) []const u8 {
        if (self.messages.items.len == 0) return "";

        var out: std.Io.Writer.Allocating = .init(arena);
        var i: usize = self.messages.items.len;
        while (i > 0) {
            i -= 1;
            out.writer.writeAll(self.messages.items[i]) catch return "";
            if (i > 0) out.writer.writeByte('\n') catch return "";
        }
        return out.written();
    }
};
