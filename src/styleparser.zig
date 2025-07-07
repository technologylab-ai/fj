const std = @import("std");

const StyledSpan = union(enum) {
    normal: []const u8,
    heading: []const u8,
    bold: []const u8,
    pub fn format(
        self: StyledSpan,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .heading => |s| {
                try writer.print("heading='{s}'", .{s});
            },
            .bold => |s| {
                try writer.print("bold='{s}'", .{s});
            },
            .normal => |s| {
                try writer.print("normal='{s}'", .{s});
            },
        }
    }
};

pub fn parse(arena: std.mem.Allocator, line: []const u8) ![]StyledSpan {
    var output_spans_alist: std.ArrayListUnmanaged(StyledSpan) = .empty;

    // catch heading
    if (line.len >= 2 and line[0] == '#' and line[1] == ' ') {
        try output_spans_alist.append(arena, .{ .heading = line[2..] });
        return output_spans_alist.toOwnedSlice(arena);
    }

    // else parse bolds
    const State = enum { normal, asterisk_start_1, asterisk_start_2, asterisk_end };
    var current_state: State = .normal;
    var current_span_alist: std.ArrayListUnmanaged(u8) = .empty;

    for (line) |char| {
        switch (current_state) {
            .normal => {
                if (char == '*') {
                    current_state = .asterisk_start_1;
                    continue;
                }
                try current_span_alist.append(arena, char);
            },
            .asterisk_start_1 => {
                if (char == '*') {
                    // switch style to bold
                    // commit prev span
                    if (current_span_alist.items.len > 0) {
                        try output_spans_alist.append(arena, .{ .normal = try arena.dupe(u8, current_span_alist.items) });
                        current_span_alist.clearRetainingCapacity();
                    }
                    current_state = .asterisk_start_2;
                } else {
                    // append the first asterisk and the current char
                    try current_span_alist.appendSlice(arena, &.{ '*', char });
                }
            },
            .asterisk_start_2 => {
                if (char == '*') {
                    current_state = .asterisk_end;
                    continue;
                }
                try current_span_alist.append(arena, char);
            },
            .asterisk_end => {
                if (char == '*') {
                    // switch back to normal
                    // commit bold span
                    try output_spans_alist.append(arena, .{ .bold = try arena.dupe(u8, current_span_alist.items) });
                    current_span_alist.clearRetainingCapacity();
                    current_state = .normal;
                } else {
                    // this wasn't the end yet
                    try current_span_alist.appendSlice(arena, &.{ '*', char });
                    // fall back to asterisk_star_2
                    current_state = .asterisk_start_2;
                }
            },
        }
    }

    if (current_span_alist.items.len > 0) {
        try output_spans_alist.append(arena, .{ .normal = try arena.dupe(u8, current_span_alist.items) });
    }
    return output_spans_alist.toOwnedSlice(arena);
}

test "heading" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const line = "# This is a heading";
    const result = try parse(arena, line);

    try std.testing.expectEqual(1, result.len);
    try std.testing.expectEqualStrings("This is a heading", result[0].heading);
}

test "easy bold" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const line = "This is **some bold** Text.";
    const results = try parse(arena, line);

    for (results, 0..) |result, index| {
        std.debug.print("{d}: {}, ", .{ index, result });
    }
    std.debug.print("\n", .{});

    try std.testing.expectEqual(3, results.len);
    try std.testing.expectEqualStrings("This is ", results[0].normal);
    try std.testing.expectEqualStrings("some bold", results[1].bold);
    try std.testing.expectEqualStrings(" Text.", results[2].normal);
}

test "harder bold" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_state.allocator();
    defer arena_state.deinit();

    const line = "This **is *some *bold** Text.";
    const results = try parse(arena, line);

    for (results, 0..) |result, index| {
        std.debug.print("{d}: {}, ", .{ index, result });
    }
    std.debug.print("\n", .{});

    try std.testing.expectEqual(3, results.len);
    try std.testing.expectEqualStrings("This ", results[0].normal);
    try std.testing.expectEqualStrings("is *some *bold", results[1].bold);
    try std.testing.expectEqualStrings(" Text.", results[2].normal);
}
