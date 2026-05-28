const std = @import("std");
const model = @import("../models/modbus.zig");
const connection_pool = @import("./connection_pool.zig");

/// 校验读请求。
///
pub fn validateReadRequest(payload: model.ReadRequest) model.ModbusRequestError!void {
    if (payload.connectionId.len == 0) {
        return error.InvalidConnectionId;
    }

    const max_quantity: u16 = switch (payload.target) {
        .read_coils, .read_discrete_inputs => 2000,
        .holding_registers, .input_registers => 125,
    };
    if (payload.quantity == 0 or payload.quantity > max_quantity) {
        return error.InvalidReadQuantity;
    }
}

/// 校验写请求。
pub fn validateWriteRequest(payload: model.WriteRequest) model.ModbusRequestError!void {
    if (payload.connectionId.len == 0) {
        return error.InvalidConnectionId;
    }

    switch (payload.target) {
        .single_coil => {
            if (payload.value == null or payload.values != null or payload.value.? > 1) {
                return error.InvalidWritePayload;
            }
        },
        .single_register => {
            if (payload.value == null or payload.values != null) {
                return error.InvalidWritePayload;
            }
        },
        .multiple_coils => {
            const values = payload.values orelse return error.InvalidWritePayload;
            if (values.len == 0 or values.len > 1968 or payload.value != null) {
                return error.InvalidWritePayload;
            }
            for (values) |value| {
                if (value > 1) {
                    return error.InvalidWritePayload;
                }
            }
        },
        .multiple_registers => {
            const values = payload.values orelse return error.InvalidWritePayload;
            if (values.len == 0 or values.len > 123 or payload.value != null) {
                return error.InvalidWritePayload;
            }
        },
    }
}

pub fn validateWriteReadRequest(payload: model.WriteReadRequest) model.ModbusRequestError!void {
    if (payload.connectionId.len == 0) {
        return error.InvalidConnectionId;
    }
    if (payload.values.len == 0 or payload.values.len > 121) {
        return error.InvalidWriteReadPayload;
    }
    if (payload.readQuantity == 0 or payload.readQuantity > 125) {
        return error.InvalidWriteReadPayload;
    }
}

/// 通过连接注册表执行一次读取。
pub fn read(
    pool: *connection_pool.ConnectionPool,
    allocator: anytype,
    payload: model.ReadRequest,
) model.ModbusRequestError![]u16 {
    const record = pool.get(payload.connectionId) orelse return error.ConnectionNotFound;

    return record.handle.readValuesAlloc(allocator, payload.target, payload.startAddress, payload.quantity) catch |err| switch (err) {
        error.TransportNotSupported => error.TransportNotSupported,
        else => {
            std.log.err("modbus read failed: {s}", .{@errorName(err)});
            return error.ModbusOperationFailed;
        },
    };
}

/// 通过连接注册表执行一次写入。
pub fn write(
    pool: *connection_pool.ConnectionPool,
    allocator: std.mem.Allocator,
    payload: model.WriteRequest,
) model.ModbusRequestError!u16 {
    const record = pool.get(payload.connectionId) orelse return error.ConnectionNotFound;

    return record.handle.writeValues(allocator, payload) catch |err| switch (err) {
        error.TransportNotSupported => return error.TransportNotSupported,
        else => {
            std.log.err("modbus write failed: {s}", .{@errorName(err)});
            return error.ModbusOperationFailed;
        },
    };
}

pub fn writeAndRead(
    pool: *connection_pool.ConnectionPool,
    allocator: std.mem.Allocator,
    payload: model.WriteReadRequest,
) model.ModbusRequestError![]u16 {
    const record = pool.get(payload.connectionId) orelse return error.ConnectionNotFound;

    return record.handle.writeAndReadRegistersAlloc(allocator, payload) catch |err| switch (err) {
        error.TransportNotSupported => return error.TransportNotSupported,
        else => {
            std.log.err("modbus write-read failed: {s}", .{@errorName(err)});
            return error.ModbusOperationFailed;
        },
    };
}

pub fn errorMessage(err: model.ModbusRequestError) []const u8 {
    return switch (err) {
        error.InvalidConnectionId => "connectionId 不能为空",
        error.ConnectionNotFound => "连接不存在或已断开",
        error.InvalidReadQuantity => "读取数量超出当前功能码允许范围",
        error.InvalidWritePayload => "写请求参数不完整、数量超限或 bit 值不是 0/1",
        error.InvalidWriteReadPayload => "FC17 请求参数不完整或数量超出范围",
        error.TransportNotSupported => "当前连接类型暂不支持该 Modbus 操作",
        error.ModbusOperationFailed => "Modbus 操作失败，请检查设备状态或连接可用性",
    };
}
