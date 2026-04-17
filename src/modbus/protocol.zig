const std = @import("std");

pub const FunctionCode = enum(u8) {
    read_coils = 0x01,
    read_discrete_inputs = 0x02,
    read_holding_registers = 0x03,
    read_input_registers = 0x04,
    write_single_coil = 0x05,
    write_single_register = 0x06,
    write_multiple_coils = 0x0F,
    write_multiple_registers = 0x10,
    _,
};

/// 异常码枚举
/// 当从站无法正常处理请求时，返回异常码告诉你出了什么问题。
pub const ExceptionCode = enum(u8) {
    illegal_function = 0x01,
    illegal_data_address = 0x02,
    illegal_data_value = 0x03,
    server_device_failure = 0x04,
    acknowledge = 0x05,
    server_device_busy = 0x06,
    memory_parity_error = 0x08,
    gateway_path_unavailable = 0x0A,
    gateway_target_failed = 0x0B,
    _,

    /// 获取异常码的文字描述
    pub fn description(self: ExceptionCode) []const u8 {
        return switch (self) {
            .illegal_function => "Illegal Function (非法功能码)",
            .illegal_data_address => "Illegal Data Address (非法数据地址)",
            .illegal_data_value => "Illegal Data Value (非法数据值)",
            .server_device_failure => "Server Device Failure (从站设备故障)",
            .acknowledge => "Acknowledge (确认，需等待)",
            .server_device_busy => "Server Device Busy (从站设备忙)",
            .memory_parity_error => "Memory Parity Error (存储校验错误)",
            .gateway_path_unavailable => "Gateway Path Unavailable (网关路径不可用)",
            .gateway_target_failed => "Gateway Target Failed (网关目标无响应)",
            _ => "Unknown Exception (未知异常)",
        };
    }
};

/// Modbus TCP 协议常量定义
pub const MBAP_HEADER_SIZE: usize = 7; // MBAP 头部固定占 7 个字节
pub const MAX_PDU_SIZE: usize = 253; // PDU（功能码+数据）最大 253 字节，这是 Modbus 规范硬性限制
pub const MAX_ADU_SIZE: usize = MBAP_HEADER_SIZE + MAX_PDU_SIZE; // 完整帧最大 260 字节 (7 + 253)

/// MBAP 头部结构体 MBAP = Modbus Application Protocol Header
/// 这是 Modbus TCP 独有的帧头（Modbus RTU 串口版没有这个）。
/// TCP 是流式协议，没有消息边界概念，MBAP 头部的作用就是告诉接收方：
/// "从这里开始是一条新的 Modbus 消息，长度是 XX 字节"
pub const MbapHeader = struct {
    transaction_id: u16, // 事务ID (2字节)：请求/响应配对编号
    protocol_id: u16, // 协议ID (2字节)：永远是 0x0000，表示 Modbus 协议
    length: u16, // 告诉接收方后面还有多少字节要读(2字节)：后续数据的字节数=从站地址(1字节) + PDU的长度
    unit_id: u8, // 从站ID (1字节)：目标设备地址 1~247
};

/// 将 MBAP 头部各字段写入字节缓冲区
/// 为什么不直接把 struct 转成字节？因为 Modbus 要求大端序，
/// 而大多数电脑 CPU（x86、ARM）默认是小端序。
/// 例如 u16 的 0x0102，在小端序 CPU 内存中实际存为 [0x02, 0x01]，
/// 如果直接 memcpy struct 就会发错顺序！
/// 所以必须用 std.mem.writeInt 显式指定 .big（大端序）。
///
/// 参数解释：
///   buf     - 目标字节数组，必须至少 7 字节
///   tx_id   - 事务ID
///   pdu_len - PDU 部分的长度（不含 MBAP 头部本身）
///   unit_id - 从站地址
/// 不用指针直接转为 *const u16 去读写的原因就是（可能有对齐和字节序问题）
pub fn writeMbapHeader(buf: []u8, tx_id: u16, pdu_len: u16, unit_id: u8) void {
    // buf[0..2] 表示从 buf 中取第 0、1 两个字节的切片（Zig 切片是左闭右开的）
    // writeInt(u16, ..., .big) 把 u16 值按大端序写入 2 字节
    std.mem.writeInt(u16, buf[0..2], tx_id, .big);
    std.mem.writeInt(u16, buf[2..4], 0x0000, .big);
    std.mem.writeInt(u16, buf[4..6], @intCast(pdu_len + 1), .big);
    buf[6] = unit_id; // 从站地址直接写入第 6 字节
}

/// 从接收到的字节流中解析出 MBAP 头部
/// 如果数据不足 7 字节，返回 null（表示"还没收完整"）
///
/// 返回类型 ?MbapHeader 是 Zig 的可选类型（Optional），等价于"可能有值，也可能是 null"
pub fn parseMbapHeader(data: []const u8) ?MbapHeader {
    if (data.len < MBAP_HEADER_SIZE) return null; // 数据不足 7 字节，无法解析完整 MBAP 头部
    return MbapHeader{
        .transaction_id = std.mem.readInt(u16, data[0..2], .big),
        .protocol_id = std.mem.readInt(u16, data[2..4], .big),
        .length = std.mem.readInt(u16, data[4..6], .big),
        .unit_id = data[6],
    };
}
