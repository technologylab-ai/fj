const std = @import("std");

pub fn fileExists(file: []const u8) bool {
    _ = std.fs.cwd().statFile(file) catch return false;
    return true;
}

pub fn isDirPresent(dirname: []const u8) bool {
    var dir: ?std.fs.Dir = std.fs.cwd().openDir(dirname, .{}) catch null;
    if (dir) |*d| {
        defer d.close();
        return true;
    }
    return false;
}

pub const FileLock = struct {
    const log = std.log.scoped(.FileLock);
    lock_path: []const u8,
    lock_file: ?std.fs.File = null,

    /// Provide the path to the file to protect (e.g. `.fj/invoices/.id`)
    pub fn acquire(arena: std.mem.Allocator, id_file_path: []const u8) !FileLock {
        var self: FileLock = .{
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
        const file = std.fs.cwd().createFile(self.lock_path, .{
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
            f.close();
            std.fs.cwd().deleteFile(self.lock_path) catch {};
            self.lock_file = null;
        }
    }
};

pub const FileLockWithRloBug = struct {
    const log = std.log.scoped(.FileLock);
    lock_path_buffer: [std.fs.max_path_bytes]u8,
    lock_path: []const u8,
    lock_file: ?std.fs.File = null,

    /// Provide the path to the file to protect (e.g. `.fj/invoices/.id`)
    pub fn acquire(id_file_path: []const u8) !FileLock {
        var self: FileLock = .{
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
        const file = std.fs.cwd().createFile(self.lock_path, .{
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
            f.close();
            std.fs.cwd().deleteFile(self.lock_path) catch {};
            self.lock_file = null;
        }
    }
};
