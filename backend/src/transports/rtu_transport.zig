const std = @import("std");
const model = @import("../models/connection.zig");
const libmodbus = @import("../protocol_bindings/libmodbus.zig");

pub const Client = libmodbus.RtuClient;

pub const ConnectOptions = struct {
    serialPort: []const u8,
    baudRate: u32,
    dataBits: u8,
    parity: model.SerialParity,
    stopBits: u8,
    slaveId: u8,
    timeoutMs: u32,
};

pub fn connect(allocator: std.mem.Allocator, options: ConnectOptions) !*Client {
    const client = try allocator.create(Client);
    errdefer allocator.destroy(client);

    client.* = try libmodbus.RtuClient.connectRtu(.{
        .allocator = allocator,
        .device = options.serialPort,
        .baud_rate = options.baudRate,
        .parity = switch (options.parity) {
            .none => 'N',
            .even => 'E',
            .odd => 'O',
        },
        .data_bits = options.dataBits,
        .stop_bits = options.stopBits,
        .unit_id = options.slaveId,
        .timeout_ms = options.timeoutMs,
    });

    return client;
}
