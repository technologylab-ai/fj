const std = @import("std");
const log = std.log.scoped(.zip);

// Zig 0.16's translate-c (Aro) cannot translate the full miniz.h single-header,
// so the archive symbols are no longer exposed via `@cImport`. We declare the
// handful of writer bindings we use manually; miniz.c is linked by the build, so
// these `extern` functions resolve at link time. The `mz_zip_archive` layout is
// kept byte-compatible with miniz.h (all pointers, then the integer/enum fields).
const c = struct {
    const MZ_FALSE = 0;
    const MZ_DEFAULT_LEVEL = 6;

    const mz_zip_archive = extern struct {
        m_archive_size: u64,
        m_central_directory_file_ofs: u64,
        m_total_files: u32,
        m_zip_mode: c_uint,
        m_zip_type: c_uint,
        m_last_error: c_uint,
        m_file_offset_alignment: u64,
        m_pAlloc: ?*const anyopaque,
        m_pFree: ?*const anyopaque,
        m_pRealloc: ?*const anyopaque,
        m_pAlloc_opaque: ?*anyopaque,
        m_pRead: ?*const anyopaque,
        m_pWrite: ?*const anyopaque,
        m_pNeeds_keepalive: ?*const anyopaque,
        m_pIO_opaque: ?*anyopaque,
        m_pState: ?*anyopaque,
    };

    extern fn mz_zip_writer_init_file(pZip: *mz_zip_archive, pFilename: [*:0]const u8, size_to_reserve_at_beginning: u64) c_int;
    extern fn mz_zip_writer_add_file(pZip: *mz_zip_archive, pArchive_name: [*:0]const u8, pSrc_filename: [*:0]const u8, pComment: ?*const anyopaque, comment_size: u16, level_and_flags: c_uint) c_int;
    extern fn mz_zip_writer_finalize_archive(pZip: *mz_zip_archive) c_int;
    extern fn mz_zip_writer_end(pZip: *mz_zip_archive) c_int;
};

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
