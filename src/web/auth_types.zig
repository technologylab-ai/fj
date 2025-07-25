const std = @import("std");
const zap = @import("zap");

pub const AuthLookup = std.StringHashMapUnmanaged([]const u8);
pub const Authenticator = zap.Auth.UserPassSession(AuthLookup, false);
