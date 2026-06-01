const std = @import("std");

/// Read an already-open file to the end, allocating the result with `gpa`.
/// Replacement for the removed `File.readToEndAlloc` in Zig 0.16.
pub fn readToEndAlloc(io: std.Io, file: std.Io.File, gpa: std.mem.Allocator, max: usize) ![]u8 {
    var buf: [4096]u8 = undefined;
    var fr = file.reader(io, &buf);
    return fr.interface.allocRemaining(gpa, .limited(max)) catch |err| switch (err) {
        error.ReadFailed => return fr.err.?,
        else => return err,
    };
}

/// Write all `bytes` to an already-open file via a buffered writer.
/// Replacement for the removed `File.writeAll` in Zig 0.16.
pub fn writeAll(io: std.Io, file: std.Io.File, bytes: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var fw = file.writer(io, &buf);
    try fw.interface.writeAll(bytes);
    try fw.interface.flush();
}

pub fn fileExists(io: std.Io, file: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, file, .{}) catch return false;
    return true;
}

pub fn isDirPresent(io: std.Io, dirname: []const u8) bool {
    var dir: ?std.Io.Dir = std.Io.Dir.cwd().openDir(io, dirname, .{}) catch null;
    if (dir) |*d| {
        defer d.close(io);
        return true;
    }
    return false;
}

pub const FileLock = struct {
    const log = std.log.scoped(.FileLock);
    io: std.Io,
    lock_path: []const u8,
    lock_file: ?std.Io.File = null,

    /// Provide the path to the file to protect (e.g. `.fj/invoices/.id`)
    pub fn acquire(io: std.Io, arena: std.mem.Allocator, id_file_path: []const u8) !FileLock {
        var self: FileLock = .{
            .io = io,
            .lock_path = undefined,
            .lock_file = null,
        };

        const lock_extension = ".lock";

        // Construct lock file path (e.g. ".fi/invoices/.id.lock")
        if (id_file_path.len + lock_extension.len >= std.fs.max_path_bytes) {
            return error.PathTooLong;
        }
        self.lock_path = try std.fmt.allocPrint(
            arena,
            "{s}.{s}",
            .{ id_file_path, lock_extension },
        );

        // Try to create the lock file exclusively
        const file = std.Io.Dir.cwd().createFile(io, self.lock_path, .{
            .exclusive = true,
        }) catch |err| {
            if (err == error.PathAlreadyExists) {
                return error.LockAlreadyHeld;
            }
            return err;
        };
        self.lock_file = file;
        log.debug(
            "Lock acquired for {s}: {s}",
            .{ id_file_path, self.lock_path },
        );
        return self;
    }

    pub fn release(self: *FileLock) void {
        log.debug("Trying to release lock: {s}", .{self.lock_path});
        if (self.lock_file) |f| {
            f.close(self.io);
            std.Io.Dir.cwd().deleteFile(self.io, self.lock_path) catch {};
            self.lock_file = null;
        }
    }
};

pub const FileLockWithRloBug = struct {
    const log = std.log.scoped(.FileLock);
    io: std.Io,
    lock_path_buffer: [std.fs.max_path_bytes]u8,
    lock_path: []const u8,
    lock_file: ?std.Io.File = null,

    /// Provide the path to the file to protect (e.g. `.fj/invoices/.id`)
    pub fn acquire(io: std.Io, id_file_path: []const u8) !FileLockWithRloBug {
        var self: FileLockWithRloBug = .{
            .io = io,
            .lock_path = undefined,
            .lock_path_buffer = undefined,
            .lock_file = null,
        };

        // Construct lock file path (e.g. ".fj/invoices/.id.lock")
        if (id_file_path.len + 5 >= std.fs.max_path_bytes) {
            return error.PathTooLong;
        }
        @memcpy(self.lock_path_buffer[0..id_file_path.len], id_file_path);
        @memcpy(self.lock_path_buffer[id_file_path.len..][0..5], ".lock");
        self.lock_path = self.lock_path_buffer[0 .. id_file_path.len + ".lock".len];

        // Try to create the lock file exclusively
        const file = std.Io.Dir.cwd().createFile(io, self.lock_path, .{
            .exclusive = true,
        }) catch |err| {
            if (err == error.PathAlreadyExists) {
                return error.LockAlreadyHeld;
            }
            return err;
        };
        self.lock_file = file;
        log.debug(
            "Lock acquired for {s}: {s}",
            .{ id_file_path, self.lock_path },
        );
        return self;
    }

    pub fn release(self: *FileLockWithRloBug) void {
        log.debug("Trying to release lock: {s}", .{self.lock_path});
        if (self.lock_file) |f| {
            f.close(self.io);
            std.Io.Dir.cwd().deleteFile(self.io, self.lock_path) catch {};
            self.lock_file = null;
        }
    }
};
