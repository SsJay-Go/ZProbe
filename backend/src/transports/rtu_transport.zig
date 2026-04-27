const std = @import("std");
const model = @import("../models/connection.zig");

/// RTU 客户端占位类型。
///
/// 现在先把“连接句柄类型”放在这里，
/// 等真正接入串口库时，只需要把这个文件替换成真实实现。
pub const Client = struct {
    pub fn deinit(_: *Client) void {}
};

pub const ConnectOptions = struct {
    serialPort: []const u8,
    baudRate: u32,
    dataBits: u8,
    parity: model.SerialParity,
    stopBits: u8,
    slaveId: u8,
};

pub fn connect(_: std.mem.Allocator, _: ConnectOptions) !*Client {
    return error.TransportNotImplemented;
}
