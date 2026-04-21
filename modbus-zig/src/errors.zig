const std = @import("std");

// 统一定义库内会抛出的错误，调用方只要围绕这一组错误做恢复和日志即可。
// 这里刻意把协议校验、设备异常响应、连接流结束统一收口到一个 error set，
// 这样上层在轮询调度或通讯测试时，只需要围绕一套错误语义做处理。
pub const ModbusError = error{
    InvalidQuantity,
    InvalidUnitId,
    BufferTooSmall,
    ResponseTooShort,
    InvalidProtocolId,
    InvalidLengthField,
    ResponseTransactionMismatch,
    ResponseUnitMismatch,
    ResponseFunctionMismatch,
    ResponsePayloadMismatch,
    InvalidByteCount,
    UnexpectedPayloadLength,
    UnsupportedFunction,
    UnknownExceptionCode,
    IllegalFunction,
    IllegalDataAddress,
    IllegalDataValue,
    SlaveDeviceFailure,
    Acknowledge,
    DeviceBusy,
    NegativeAcknowledge,
    MemoryParityError,
    GatewayPathUnavailable,
    GatewayTargetNoResponse,
    EndOfStream,
};

// Modbus 异常码本质上是设备对某个请求的失败响应。
// 从站不会因为地址非法就一定断开连接，更常见的是回一帧“异常响应”，
// 再用 1 字节异常码告诉主站具体失败原因。
// 这里把异常码映射为明确的 Zig 错误，方便上层直接 `switch` 或 `catch`。
pub fn raiseException(code: u8) ModbusError!void {
    return switch (code) {
        0x01 => error.IllegalFunction,
        0x02 => error.IllegalDataAddress,
        0x03 => error.IllegalDataValue,
        0x04 => error.SlaveDeviceFailure,
        0x05 => error.Acknowledge,
        0x06 => error.DeviceBusy,
        0x07 => error.NegativeAcknowledge,
        0x08 => error.MemoryParityError,
        0x0A => error.GatewayPathUnavailable,
        0x0B => error.GatewayTargetNoResponse,
        else => error.UnknownExceptionCode,
    };
}

test "异常码映射到 Zig 错误" {
    try std.testing.expectError(error.IllegalDataAddress, raiseException(0x02));
    try std.testing.expectError(error.UnknownExceptionCode, raiseException(0x7F));
}
