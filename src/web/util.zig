const zap = @import("zap");

pub fn fiobj_type(o: zap.fio.FIOBJ) []const u8 {
    const value_type = switch (zap.fio.fiobj_type(o)) {
        zap.fio.FIOBJ_T_NULL => "null",
        zap.fio.FIOBJ_T_TRUE => "true",
        zap.fio.FIOBJ_T_FALSE => "false",
        zap.fio.FIOBJ_T_NUMBER => "number",
        zap.fio.FIOBJ_T_FLOAT => "float",
        zap.fio.FIOBJ_T_STRING => "string",
        zap.fio.FIOBJ_T_ARRAY => "array",
        zap.fio.FIOBJ_T_HASH => "hash",
        zap.fio.FIOBJ_T_DATA => "data",
        zap.fio.FIOBJ_T_UNKNOWN => "unknown",
        else => "shit",
    };
    return value_type;
}
