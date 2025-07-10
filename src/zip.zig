const std = @import("std");
const log = std.log.scoped(.zip);
const c = @cImport(@cInclude("miniz.h")); // This works after adding miniz.c to the build

pub const ZipArgs = struct {
    zip_name: []const u8,
    filenames: []const []const u8,
    work_dir: ?[]const u8 = null,
};

pub fn zip(arena: std.mem.Allocator, args: ZipArgs) !void {
    const archive_name = blk: {
        if (args.work_dir) |wd| {
            break :blk try std.fmt.allocPrint(arena, "{s}/{s}", .{ wd, args.zip_name });
        } else {
            break :blk args.zip_name;
        }
    };

    var file_entries = std.ArrayListUnmanaged(FileEntry).empty;
    for (args.filenames) |filn| {
        const source_filn = blk: {
            if (args.work_dir) |wd| {
                break :blk try std.fmt.allocPrint(arena, "{s}/{s}", .{ wd, filn });
            } else {
                break :blk filn;
            }
        };
        try file_entries.append(
            arena,
            .{ .source_path = source_filn, .archive_path = std.fs.path.basename(filn) },
        );
    }

    try createZip(arena, archive_name, file_entries.items);
}

pub const FileEntry = struct {
    source_path: []const u8,
    archive_path: []const u8,
};

pub fn createZip(allocator: std.mem.Allocator, archive_name: []const u8, files: []const FileEntry) !void {
    // Allocate null-terminated strings for C compatibility
    const archive_name_z = try allocator.dupeZ(u8, archive_name);
    defer allocator.free(archive_name_z);

    var zip_archive: c.mz_zip_archive = std.mem.zeroes(c.mz_zip_archive);

    // Initialize the ZIP writer for a file
    if (c.mz_zip_writer_init_file(&zip_archive, archive_name_z.ptr, 0) == c.MZ_FALSE) {
        return error.ZipInitFailed;
    }
    defer _ = c.mz_zip_writer_end(&zip_archive); // Clean up on exit

    for (files) |file| {
        const source_path_z = try allocator.dupeZ(u8, file.source_path);
        defer allocator.free(source_path_z);

        const archive_path_z = try allocator.dupeZ(u8, file.archive_path);
        defer allocator.free(archive_path_z);

        // Add file from disk with the specified archive path (directories via '/')
        if (c.mz_zip_writer_add_file(&zip_archive, archive_path_z.ptr, source_path_z.ptr, null, 0, c.MZ_DEFAULT_LEVEL) == c.MZ_FALSE) {
            return error.ZipAddFileFailed;
        }
    }

    // Finalize the archive
    if (c.mz_zip_writer_finalize_archive(&zip_archive) == c.MZ_FALSE) {
        return error.ZipFinalizeFailed;
    }
}
