// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第六部分：display - 显示输出（格式化打印结果）                     │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/display.zig                                     │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘
const std = @import("std");
const protocol = @import("modbus/protocol.zig");
const response = @import("modbus/response.zig");
/// 打印原始帧（十六进制格式）
///
/// 用途：调试时查看实际收发的原始字节，确认协议是否正确
/// 输出示例：RX (15B): 00 01 00 00 00 09 01 03 06 00 0A 00 14 00 1E
/// label 参数是 "RX"（接收）或 "TX"（发送），data 是实际的字节数据切片。
/// Zig 格式化语法：
///   {s}       - 打印字符串切片 []const u8
///   {d}       - 打印十进制整数
///   {X:0>2}   - 打印十六进制大写，用 0 填充，宽度 2
///                例如 10 → "0A"，255 → "FF"，0 → "00"
pub fn printRawFrame(label: []const u8, data: []const u8) void {
    std.debug.print("{s} ({d}B): ", .{ label, data.len });
    for (data) |b| {
        std.debug.print("{X:0>2} ", .{b});
    }
    std.debug.print("\n", .{});
}

/// 打印 MBAP 头部的各字段
pub fn printMbapHeader(h: protocol.MbapHeader) void {
    std.debug.print(
        \\  MBAP Header:
        \\    Transaction ID : {d}
        \\    Protocol ID    : {d}
        \\    Length         : {d}
        \\    Unit ID        : {d}
        \\
    , .{ h.transaction_id, h.protocol_id, h.length, h.unit_id });
    // Zig 的 \\ 多行字符串：每行开头的 \\ 之前的空白会被去掉
}

/// 打印解析后的响应数据
///
/// 根据 ResponseData 的标签（tag），用不同格式展示数据。
/// Zig 的 switch 可以匹配 tagged union 的不同变体，
/// 并且通过 |d| 把内部数据绑定到变量 d。
pub fn printResponse(r: response.ResponseData) void {
    switch (r) {
        // ---- 读寄存器结果 ----
        .read_registers => |d| {
            std.debug.print("\n--- Read Holding Registers ({d} registers) ---\n", .{d.count});
            std.debug.print("  Index | Decimal |   Hex  \n", .{});
            std.debug.print("  ------+---------+--------\n", .{});
            for (0..d.count) |i| {
                std.debug.print("  [{d:>3}] | {d:>6}  | 0x{X:0>4}\n", .{
                    i, d.values[i], d.values[i],
                });
            }
        },

        // ---- 读线圈结果 ----
        .read_coils => |d| {
            std.debug.print("\n--- Read Coils ({d} bytes) ---\n", .{d.byte_count});
            for (0..d.byte_count) |i| {
                // {b:0>8} 打印 8位二进制，用 0 填充
                // 每一位(bit)代表一个线圈：1=ON, 0=OFF
                std.debug.print("  Byte[{d}] = 0b{b:0>8}\n", .{ i, d.data[i] });
            }
        },

        // ---- 写单个 成功 ----
        .write_single => |d| {
            std.debug.print("\n--- Write Single Register OK ---\n", .{});
            std.debug.print("  Address: {d} (0x{X:0>4})\n", .{ d.address, d.address });
            std.debug.print("  Value  : {d} (0x{X:0>4})\n", .{ d.value, d.value });
        },

        // ---- 写多个 成功 ----
        .write_multiple => |d| {
            std.debug.print("\n--- Write Multiple Registers OK ---\n", .{});
            std.debug.print("  Start Address: {d}\n", .{d.start_address});
            std.debug.print("  Quantity     : {d}\n", .{d.quantity});
        },

        // ---- 异常响应 ----
        .exception => |e| {
            std.debug.print("\n!!! MODBUS EXCEPTION !!!\n", .{});
            std.debug.print("  Function Code: 0x{X:0>2}\n", .{e.function_code});
            std.debug.print("  Exception    : 0x{X:0>2} - {s}\n", .{
                @intFromEnum(e.code),
                e.code.description(),
            });
        },
    }
}
