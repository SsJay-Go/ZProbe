/// Modbus 读写相关的数据模型。
///
/// 把它单独拆出来的目的，是避免连接模型文件继续膨胀；
/// 连接管理关心“连不连得上”和“怎么持有连接”，
/// Modbus 业务关心“通过哪条连接执行什么功能码”。
/// 读寄存器目标。
pub const ReadTarget = enum {
    read_coils,
    read_discrete_inputs,
    holding_registers,
    input_registers,
};

/// 写寄存器目标。
pub const WriteTarget = enum {
    single_coil,
    single_register,
    multiple_coils,
    multiple_registers,
};

/// 读取结果的数据类型。
///
/// 前端只需要知道当前返回的是 bit 还是 register，
/// 就能决定显示和编辑时该用哪套规则。
pub const ValueKind = enum {
    bit,
    register,
};

/// 统一的读请求。
pub const ReadRequest = struct {
    connectionId: []const u8,
    // 预留给 RTU / 未来多从站串口总线场景；TCP 当前仍走连接级 slaveId。
    slaveId: ?u8 = null,
    target: ReadTarget,
    startAddress: u16,
    quantity: u16,
};

/// 统一的写请求。
pub const WriteRequest = struct {
    connectionId: []const u8,
    // 与 ReadRequest 保持相同扩展位，避免后续为 RTU 另拆一套写请求模型。
    slaveId: ?u8 = null,
    target: WriteTarget,
    startAddress: u16,
    value: ?u16 = null,
    values: ?[]const u16 = null,
};

/// FC17 读写多寄存器请求。
///
/// 这类请求本质上是“先写一段寄存器，再立刻读另一段寄存器”，
/// 因此单独拆一个模型，避免硬塞进普通写请求后出现很多无意义的可选字段。
pub const WriteReadRequest = struct {
    connectionId: []const u8,
    slaveId: ?u8 = null,
    writeStartAddress: u16,
    values: []const u16,
    readStartAddress: u16,
    readQuantity: u16,
};

/// 统一的读成功响应。
pub const ReadSuccessResponse = struct {
    success: bool,
    message: []const u8,
    valueKind: ValueKind,
    values: []const u16,
};

/// 统一的写成功响应。
pub const WriteSuccessResponse = struct {
    success: bool,
    message: []const u8,
    writtenCount: u16,
};

pub const WriteReadSuccessResponse = struct {
    success: bool,
    message: []const u8,
    valueKind: ValueKind,
    values: []const u16,
};

/// Modbus 请求阶段的业务错误。
///
/// 这类错误尽量保持“业务含义明确”，
/// 控制器只负责把它们映射成合适的 HTTP 状态码和中文提示。
pub const ModbusRequestError = error{
    InvalidConnectionId,
    ConnectionNotFound,
    InvalidReadQuantity,
    InvalidWritePayload,
    InvalidWriteReadPayload,
    TransportNotSupported,
    ModbusOperationFailed,
};

pub fn makeReadSuccess(registers: []const u16) ReadSuccessResponse {
    return .{
        .success = true,
        .message = "读取成功",
        .valueKind = .register,
        .values = registers,
    };
}

pub fn valueKindForReadTarget(target: ReadTarget) ValueKind {
    return switch (target) {
        .read_coils, .read_discrete_inputs => .bit,
        .holding_registers, .input_registers => .register,
    };
}

pub fn makeReadSuccessForTarget(target: ReadTarget, values: []const u16) ReadSuccessResponse {
    return .{
        .success = true,
        .message = "读取成功",
        .valueKind = valueKindForReadTarget(target),
        .values = values,
    };
}

pub fn makeWriteSuccess(written_count: u16) WriteSuccessResponse {
    return .{
        .success = true,
        .message = "写入成功",
        .writtenCount = written_count,
    };
}

pub fn makeWriteReadSuccess(values: []const u16) WriteReadSuccessResponse {
    return .{
        .success = true,
        .message = "读写成功",
        .valueKind = .register,
        .values = values,
    };
}
