const model = @import("../models/modbus.zig");
const connection_pool = @import("./connection_pool.zig");

/// 校验读请求。
///
/// 当前只覆盖寄存器读取场景，因此 quantity 限制按标准寄存器读取范围处理。
pub fn validateReadRequest(payload: model.ReadRequest) model.ModbusRequestError!void {
    if (payload.connectionId.len == 0) {
        return error.InvalidConnectionId;
    }
    if (payload.quantity == 0 or payload.quantity > 125) {
        return error.InvalidReadQuantity;
    }
}

/// 校验写请求。
pub fn validateWriteRequest(payload: model.WriteRequest) model.ModbusRequestError!void {
    if (payload.connectionId.len == 0) {
        return error.InvalidConnectionId;
    }

    switch (payload.target) {
        .single_register => {
            if (payload.value == null or payload.values != null) {
                return error.InvalidWritePayload;
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

/// 通过连接注册表执行一次读取。
pub fn read(
    pool: *connection_pool.ConnectionPool,
    allocator: anytype,
    payload: model.ReadRequest,
) model.ModbusRequestError![]u16 {
    const record = pool.get(payload.connectionId) orelse return error.ConnectionNotFound;

    return record.handle.readRegistersAlloc(allocator, payload.target, payload.startAddress, payload.quantity) catch |err| switch (err) {
        error.TransportNotSupported => error.TransportNotSupported,
        else => error.ModbusOperationFailed,
    };
}

/// 通过连接注册表执行一次写入。
pub fn write(pool: *connection_pool.ConnectionPool, payload: model.WriteRequest) model.ModbusRequestError!u16 {
    const record = pool.get(payload.connectionId) orelse return error.ConnectionNotFound;

    return record.handle.writeRegisters(payload) catch |err| switch (err) {
        error.TransportNotSupported => return error.TransportNotSupported,
        else => return error.ModbusOperationFailed,
    };
}

pub fn errorMessage(err: model.ModbusRequestError) []const u8 {
    return switch (err) {
        error.InvalidConnectionId => "connectionId 不能为空",
        error.ConnectionNotFound => "连接不存在或已断开",
        error.InvalidReadQuantity => "读取数量必须在 1~125 之间",
        error.InvalidWritePayload => "写请求参数不完整或数量超出范围",
        error.TransportNotSupported => "当前连接类型暂不支持该 Modbus 操作",
        error.ModbusOperationFailed => "Modbus 操作失败，请检查设备状态或连接可用性",
    };
}
