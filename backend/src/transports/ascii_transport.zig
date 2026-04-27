const std = @import("std");
const model = @import("../models/connection.zig");

/// ASCII 客户端占位类型。
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
