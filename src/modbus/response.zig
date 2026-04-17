// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第四部分：response - 响应解析（把字节流变成结构化数据）            │
// |                    每类功能玛的响应结构是有差异的                              │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘
const std = @import("std");
const protocol = @import("protocol.zig");

/// 读寄存器的响应结果（0x03 / 0x04）
///
/// 从站响应 PDU 结构：
///
///   字节序号:    [0]        [1]         [2]~[N]
///            ┌──────────┬──────────┬───────────────────────┐
///            │ 功能码   │ 字节计数 │    寄存器值数据        │
///            │  0x03    │   0x14   │ HH LL HH LL HH LL .. │
///            └──────────┴──────────┴───────────────────────┘
///
///   字节计数 = 寄存器数量 × 2
///   数据区每 2 字节是一个寄存器的值（大端序）
pub const ReadRegistersResult = struct {
    values: [125]u16 = undefined, // 固定大小数组，最多 125 个寄存器（Modbus 规范上限）,undefined表示不初始化，节省性能（反正后面会覆盖写入）
    count: usize = 0, // 实际读到的寄存器数量
};

/// 读线圈的响应结果（0x01 / 0x02）
///
/// 从站响应 PDU 结构：
///
///   字节序号:    [0]        [1]         [2]~[N]
///            ┌──────────┬──────────┬───────────────────────┐
///            │ 功能码   │ 字节计数 │    线圈状态（位打包）  │
///            │  0x01    │   0x02   │  0b00000101  0b...    │
///            └──────────┴──────────┴───────────────────────┘
///
///   "位打包"是什么意思？
///   8 个线圈的状态被挤进 1 个字节里。
///   例如 0b00000101 = 5，表示：
///     线圈0 = 1（开），线圈1 = 0（关），线圈2 = 1（开），
///     线圈3~7 = 0（关）
///   最低位(bit0) 对应最小地址的线圈。
pub const ReadCoilsResult = struct {
    data: [256]u8 = undefined, // 原始字节数据（位打包的）
    byte_count: usize = 0, // 实际收到的字节数
};

/// 写单个寄存器/线圈的响应（0x06 / 0x05）
/// 从站原样回显请求的地址和值，表示"我收到了，写入成功"
pub const WriteSingleResult = struct {
    address: u16, // 回显的地址
    value: u16, // 回显的值
};

/// 写多个寄存器/线圈的响应（0x10 / 0x0F）
/// 从站回显起始地址和写入数量
pub const WriteMultipleResult = struct {
    start_address: u16, // 起始地址
    quantity: u16, // 写入的数量
};

/// 统一的响应数据类型
///
/// Zig 的 tagged union（标记联合体）可以在一个变量中存储不同类型的数据，
/// 并且知道当前存的是哪种类型。
pub const ResponseData = union(enum) {
    read_registers: ReadRegistersResult, // 读寄存器成功
    read_coils: ReadCoilsResult, // 读线圈成功
    write_single: WriteSingleResult, // 写单个成功
    write_multiple: WriteMultipleResult, // 写多个成功
    exception: struct { // 异常响应（从站报错了）
        function_code: u8, // 原始功能码（已去掉 0x80 标记）
        code: protocol.ExceptionCode, // 具体的异常原因
    },
};

/// 响应解析可能遇到的错误
pub const ParseError = error{
    FrameTooShort, // 数据字节不够（可能丢包或传输中断）
    InvalidByteCount, // 字节计数不合理（比如声称有奇数个字节的寄存器数据）
    UnexpectedFunctionCode, // 遇到了不认识的功能码
};

/// 解析响应 PDU
///
/// 输入：data 是 PDU 部分的字节切片（从功能码开始，不含 MBAP 头部）
///       MBAP 头部已经在 TCP 客户端层被剥离了。
///
/// 输出：ParseError 或者 ResponseData
///       Zig 的错误联合类型 `ParseError!ResponseData` 意思是
///       "要么返回一个错误，要么返回一个 ResponseData"
///
/// 解析流程：
///   1. 读第一个字节（功能码）
///   2. 检查最高位 → 如果是 1，说明是异常响应
///   3. 否则根据功能码类型，用不同方式解析后续数据
pub fn parsePdu(data: []const u8) ParseError!ResponseData {
    if (data.len < 2) return error.FrameTooShort; // 至少要有功能码 + 1字节数据（异常码/字节计数等）

    const fc_code = data[0]; // PDU的第一个字节为功能码

    // ---- 步骤1：检查是否为异常响应 ----
    // 异常响应的标志：功能码的最高位(bit7)被置为 1 （即0x80）
    // 位运算：fc & 0x80 提取最高位(与运算都为1才为1)。
    //   0x03 = 0b00000011，& 0x80 = 0b00000000 = 0 → 正常
    //   0x83 = 0b10000011，& 0x80 = 0b10000000 ≠ 0 → 异常！
    if (fc_code & 0x80 != 0) {
        return .{
            .exception = .{
                .function_code = fc_code & 0x7F, // 去掉最高位，恢复原始功能码
                .code = @enumFromInt(data[1]), // 第二个字节是异常码
            },
        };
    }

    // ---- 步骤2：正常响应，根据功能码类型分别处理 ----
    const fc_enum: protocol.FunctionCode = @enumFromInt(fc_code);

    switch (fc_enum) {
        // ---- 0x03 / 0x04：读寄存器响应 ----
        .read_holding_registers, .read_input_registers => {
            const b_count = data[1]; // 字节计数：后面有多少字节的寄存器数据
            if (data.len < 2 + b_count) return error.FrameTooShort;
            if (b_count % 2 != 0) return error.InvalidByteCount; // 寄存器数据必须是偶数个字节

            var result = ReadRegistersResult{ .count = b_count / 2 }; // 寄存器数量 = 字节计数 / 2

            // 解析寄存器数据，每 2 字节一个寄存器（大端序）
            for (0..result.count) |i| {
                result.values[i] = std.mem.readInt(u16, data[2 + i * 2 ..][0..2], .big);
            }
            return .{ .read_registers = result };
        },

        // ---- 0x01 / 0x02：读线圈响应 ----
        .read_coils, .read_discrete_inputs => {
            const b_count = data[1];
            var result = ReadCoilsResult{ .byte_count = b_count }; // 字节计数
            // @memcpy：内存拷贝，把响应中的线圈数据复制到结果结构体中
            @memcpy(result.data[0..b_count], data[2 .. 2 + b_count]);
            return .{ .read_coils = result };
        },

        // ---- 0x06 / 0x05：写单个寄存器/线圈响应 ----
        .write_single_register, .write_single_coil => {
            return .{
                .write_single = .{
                    .address = std.mem.readInt(u16, data[1..3], .big), // 地址
                    .value = std.mem.readInt(u16, data[3..5], .big), // 值
                },
            };
        },

        // ---- 0x10 / 0x0F：写多个寄存器/线圈响应 ----
        .write_multiple_registers, .write_multiple_coils => {
            return .{
                .write_multiple = .{
                    .start_address = std.mem.readInt(u16, data[1..3], .big), // 起始地址
                    .quantity = std.mem.readInt(u16, data[3..5], .big), // 写入数量
                },
            };
        },

        // ---- 其他功能码：目前不支持，返回错误 ----
        else => return error.UnexpectedFunctionCode,
    }
}
