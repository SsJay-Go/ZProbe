const std = @import("std");
const errors = @import("errors.zig");

pub const ModbusError = errors.ModbusError;

// 常用功能码先覆盖寄存器读取和写入，这也是工业采集场景里最常用的一组操作。
pub const FunctionCode = enum(u8) {
    read_coils = 0x01,
    read_discrete_inputs = 0x02,
    read_holding_registers = 0x03,
    read_input_registers = 0x04,
    write_single_coil = 0x05,
    write_single_register = 0x06,
    write_multiple_coils = 0x0F,
    write_multiple_registers = 0x10,
};

// 这些限制来自 Modbus 应用协议本身。
pub const Limits = struct {
    pub const max_tcp_adu_size: usize = 260;
    pub const max_read_registers: u16 = 125;
    pub const max_write_registers: u16 = 123;
};

// Modbus 的 16 位字段统一使用大端序，这里集中封装，避免每处都重复写底层转换。
fn writeU16(dest: []u8, value: u16) void {
    std.mem.writeInt(u16, @ptrCast(dest[0..2]), value, .big);
}

// 与 writeU16 对应的读取辅助函数，用于把报文中的 2 字节字段还原成 u16。
fn readU16(src: []const u8) u16 {
    return std.mem.readInt(u16, @ptrCast(src[0..2]), .big);
}

// MBAP 头是 Modbus TCP 独有的 7 字节报文头，用于在 TCP 流里识别事务和负载长度。
pub const MbapHeader = struct {
    transaction_id: u16,
    protocol_id: u16 = 0,
    length: u16,
    unit_id: u8,

    pub fn encode(self: MbapHeader, dest: []u8) ModbusError!usize {
        if (dest.len < 7) return error.BufferTooSmall;

        // MBAP 头的布局固定为：事务号 2 字节、协议号 2 字节、长度 2 字节、单元号 1 字节。
        writeU16(dest[0..2], self.transaction_id);
        writeU16(dest[2..4], self.protocol_id);
        writeU16(dest[4..6], self.length);
        dest[6] = self.unit_id;
        return 7;
    }

    pub fn decode(src: []const u8) ModbusError!MbapHeader {
        if (src.len < 7) return error.ResponseTooShort;

        // Modbus TCP 的协议号固定为 0，非 0 说明收到的并不是合法 Modbus TCP 报文。
        const protocol_id = readU16(src[2..4]);
        if (protocol_id != 0) return error.InvalidProtocolId;

        return .{
            .transaction_id = readU16(src[0..2]),
            .protocol_id = protocol_id,
            .length = readU16(src[4..6]),
            .unit_id = src[6],
        };
    }
};

// 解析完 TCP 响应后，把真正的功能码和 PDU 负载暴露给上层。
pub const ParsedResponse = struct {
    transaction_id: u16,
    unit_id: u8,
    function: FunctionCode,
    payload: []const u8,
};

pub fn buildTcpRequest(dest: []u8, transaction_id: u16, unit_id: u8, function: FunctionCode, pdu_payload: []const u8) ModbusError!usize {
    const total_len = 8 + pdu_payload.len;
    if (dest.len < total_len) return error.BufferTooSmall;

    // length 字段表示“unit id + function code + payload”的长度。
    const header = MbapHeader{
        .transaction_id = transaction_id,
        .length = @as(u16, @intCast(2 + pdu_payload.len)),
        .unit_id = unit_id,
    };

    _ = try header.encode(dest[0..7]);
    dest[7] = @intFromEnum(function);
    @memcpy(dest[8..total_len], pdu_payload);
    return total_len;
}

pub fn parseTcpResponse(src: []const u8, expected_transaction_id: u16, expected_unit_id: u8, expected_function: FunctionCode) ModbusError!ParsedResponse {
    if (src.len < 8) return error.ResponseTooShort;

    const header = try MbapHeader.decode(src[0..7]);
    // 至少要包含 unit id 和 function code 这两个字节。
    if (header.length < 2) return error.InvalidLengthField;

    const total_len = 6 + header.length;
    if (src.len < total_len) return error.ResponseTooShort;
    // 事务号和单元号都要匹配，才能确认当前响应确实属于这次请求。
    if (header.transaction_id != expected_transaction_id) return error.ResponseTransactionMismatch;
    if (header.unit_id != expected_unit_id) return error.ResponseUnitMismatch;

    const raw_function = src[7];
    const expected_raw = @intFromEnum(expected_function);
    if (raw_function == (expected_raw | 0x80)) {
        if (total_len < 9) return error.ResponseTooShort;
        // 异常响应的第一个数据字节就是异常码，这里直接提升为 Zig 错误。
        try errors.raiseException(src[8]);
        return error.UnknownExceptionCode;
    }
    if (raw_function != expected_raw) return error.ResponseFunctionMismatch;

    return .{
        .transaction_id = header.transaction_id,
        .unit_id = header.unit_id,
        .function = expected_function,
        .payload = src[8..total_len],
    };
}

pub fn encodeReadRegisters(dest: []u8, function: FunctionCode, start_address: u16, quantity: u16) ModbusError!usize {
    switch (function) {
        .read_holding_registers, .read_input_registers => {},
        else => return error.UnsupportedFunction,
    }

    // 协议规定单次读寄存器数量不能超过 125。
    if (quantity == 0 or quantity > Limits.max_read_registers) return error.InvalidQuantity;
    if (dest.len < 4) return error.BufferTooSmall;

    writeU16(dest[0..2], start_address);
    writeU16(dest[2..4], quantity);
    return 4;
}

pub fn encodeWriteSingleRegister(dest: []u8, address: u16, value: u16) ModbusError!usize {
    if (dest.len < 4) return error.BufferTooSmall;

    // FC06 的负载结构就是“寄存器地址 + 寄存器值”。
    writeU16(dest[0..2], address);
    writeU16(dest[2..4], value);
    return 4;
}

pub fn encodeWriteMultipleRegisters(dest: []u8, start_address: u16, values: []const u16) ModbusError!usize {
    if (values.len == 0 or values.len > Limits.max_write_registers) return error.InvalidQuantity;

    const register_count: u16 = @intCast(values.len);
    const byte_count: u8 = @intCast(values.len * 2);
    const total_len = 5 + values.len * 2;
    if (dest.len < total_len) return error.BufferTooSmall;

    // FC16 负载结构：起始地址、数量、字节数、寄存器值序列。
    writeU16(dest[0..2], start_address);
    writeU16(dest[2..4], register_count);
    dest[4] = byte_count;

    for (values, 0..) |value, index| {
        const offset = 5 + index * 2;
        // 每个寄存器值都以大端序连续写入负载尾部。
        writeU16(dest[offset .. offset + 2], value);
    }

    return total_len;
}

// 读取寄存器的响应负载结构为：字节数 + N 个 16 位寄存器值。
pub fn decodeRegisterPayload(payload: []const u8, out: []u16) ModbusError!usize {
    if (payload.len < 1) return error.ResponseTooShort;

    const byte_count = payload[0];
    // 寄存器总是 16 位，所以 byte count 必须是正偶数。
    if (byte_count == 0 or byte_count % 2 != 0) return error.InvalidByteCount;
    if (payload.len != @as(usize, byte_count) + 1) return error.UnexpectedPayloadLength;

    const register_count = @as(usize, byte_count) / 2;
    if (out.len < register_count) return error.BufferTooSmall;

    for (0..register_count) |index| {
        const offset = 1 + index * 2;
        // 第 0 字节是字节数，真正的寄存器数据从偏移 1 开始。
        out[index] = readU16(payload[offset .. offset + 2]);
    }

    return register_count;
}

// 写单寄存器与写多寄存器的响应都会回显起始地址和数量/值。
pub fn validateWriteAck(payload: []const u8, expected_address: u16, expected_tail: u16) ModbusError!void {
    if (payload.len != 4) return error.UnexpectedPayloadLength;

    // 写单寄存器和写多寄存器响应都会回显地址与值/数量，用来确认设备真正执行了目标操作。
    const address = readU16(payload[0..2]);
    const tail = readU16(payload[2..4]);
    if (address != expected_address or tail != expected_tail) return error.ResponsePayloadMismatch;
}

test "构造并解析读取保持寄存器响应" {
    var pdu: [4]u8 = undefined;
    const pdu_len = try encodeReadRegisters(pdu[0..], .read_holding_registers, 0x0010, 2);
    try std.testing.expectEqual(@as(usize, 4), pdu_len);

    var request: [Limits.max_tcp_adu_size]u8 = undefined;
    const request_len = try buildTcpRequest(request[0..], 7, 1, .read_holding_registers, pdu[0..pdu_len]);
    try std.testing.expectEqual(@as(usize, 12), request_len);

    const response = [_]u8{
        0x00, 0x07,
        0x00, 0x00,
        0x00, 0x07,
        0x01, 0x03,
        0x04, 0x12,
        0x34, 0xAB,
        0xCD,
    };

    const parsed = try parseTcpResponse(response[0..], 7, 1, .read_holding_registers);
    var out: [4]u16 = undefined;
    const count = try decodeRegisterPayload(parsed.payload, out[0..]);

    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(u16, 0x1234), out[0]);
    try std.testing.expectEqual(@as(u16, 0xABCD), out[1]);
}

test "写多个寄存器请求会生成合法负载" {
    const values = [_]u16{ 0x1001, 0x1002, 0x1003 };
    var payload: [32]u8 = undefined;
    const len = try encodeWriteMultipleRegisters(payload[0..], 0x0020, values[0..]);

    try std.testing.expectEqual(@as(usize, 11), len);
    try std.testing.expectEqual(@as(u8, 0x06), payload[4]);
    try std.testing.expectEqual(@as(u8, 0x10), payload[5]);
    try std.testing.expectEqual(@as(u8, 0x01), payload[6]);
}
