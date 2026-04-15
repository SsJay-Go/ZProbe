// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║              Modbus TCP 调试工具 - 学习参考文件（单文件版）                    ║
// ║                                                                              ║
// ║  本文件仅供学习参考，包含完整的 Modbus TCP 客户端实现。                         ║
// ║  建议阅读后自行按模块拆分重写。                                                ║
// ║                                                                              ║
// ║  代码组织顺序：                                                                ║
// ║    1. 协议定义 (protocol)   - 常量、枚举、帧结构                               ║
// ║    2. 请求构造 (request)    - 把参数变成字节流                                  ║
// ║    3. 响应解析 (response)   - 把字节流变成结构化数据                             ║
// ║    4. TCP客户端 (tcp)       - 网络连接、收发数据                                ║
// ║    5. 显示输出 (display)    - 格式化打印结果                                    ║
// ║    6. 主入口   (main)       - 程序入口，组装以上模块                             ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

const std = @import("std");

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │                    第一部分：Modbus 基础知识（必读！）                          │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘
//
// ======================== 什么是 Modbus？ ========================
//
// Modbus 是 1979 年发明的工业通信协议，至今仍是最广泛使用的工业协议之一。
// 它用于 PLC（可编程逻辑控制器）、传感器、仪表、变频器等设备之间的数据交换。
//
// 核心模型非常简单，只有两个角色：
//   - 主站（Master / Client）：发起请求的一方（就是我们要写的程序）
//   - 从站（Slave / Server）：响应请求的一方（工业设备，或模拟器）
//
// 通信永远是 "主站问 → 从站答"，从站不会主动发数据。
//
//
// ======================== Modbus TCP vs Modbus RTU ========================
//
// Modbus 有两种常见的传输方式：
//
//   ┌─────────────┬──────────────────┬──────────────────┐
//   │             │   Modbus RTU     │   Modbus TCP     │
//   ├─────────────┼──────────────────┼──────────────────┤
//   │ 物理层      │ 串口 RS485/RS232 │ 以太网 TCP/IP    │
//   │ 帧校验      │ CRC16 校验       │ TCP 自带校验     │
//   │ 帧头        │ 无               │ MBAP Header      │
//   │ 默认端口    │ 无（串口波特率）  │ 502              │
//   │ 连接方式    │ 一根线连多设备    │ 网线/网口        │
//   └─────────────┴──────────────────┴──────────────────┘
//
// 本文件实现的是 Modbus TCP。
//
//
// ======================== 什么是大端序（Big-Endian）？ ========================
//
// 计算机存储多字节数据时，有两种字节排列方式：
//
//   假设要存储数字 0x1234（十进制 4660）：
//
//   大端序（Big-Endian）：高位字节在前
//     内存地址:  [0]  [1]
//     存储内容:  0x12 0x34     ← 先放高位 0x12，再放低位 0x34
//     人类阅读顺序，直观！
//
//   小端序（Little-Endian）：低位字节在前
//     内存地址:  [0]  [1]
//     存储内容:  0x34 0x12     ← 先放低位 0x34，再放高位 0x12
//     x86/ARM 等 CPU 默认使用这种
//
//   Modbus 协议规定统一使用 **大端序**（也叫"网络字节序"）。
//   所以在代码中你会看到大量的 .big 参数，就是指定大端序。
//
//
// ======================== Modbus TCP 完整帧结构 ========================
//
// 一个完整的 Modbus TCP 数据帧（也叫 ADU = Application Data Unit）：
//
//   ┌═══════════════════════════ ADU (应用数据单元) ═══════════════════════════┐
//   │                                                                          │
//   │  ┌──────────── MBAP Header (7字节，Modbus TCP 独有) ────────────┐        │
//   │  │                                                               │        │
//   │  │  字节0-1     字节2-3     字节4-5      字节6                   │        │
//   │  │ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐               │        │
//   │  │ │ 事务ID │ │ 协议ID │ │  长度  │ │ 从站地址 │               │        │
//   │  │ │ (2字节)│ │ (2字节)│ │ (2字节)│ │  (1字节) │               │        │
//   │  │ │Transaction│Protocol│ Length  │ │ Unit ID  │               │        │
//   │  │ └────────┘ └────────┘ └────────┘ └──────────┘               │        │
//   │  └───────────────────────────────────────────────────────────────┘        │
//   │                                                                          │
//   │  ┌────────────────── PDU (协议数据单元) ──────────────────┐              │
//   │  │                                                         │              │
//   │  │  字节7         字节8 ~ 字节N                            │              │
//   │  │ ┌──────────┐ ┌──────────────────────┐                  │              │
//   │  │ │ 功能码   │ │      数据区域        │                  │              │
//   │  │ │ (1字节)  │ │  (0~252字节，可变)   │                  │              │
//   │  │ │Func Code │ │       Data           │                  │              │
//   │  │ └──────────┘ └──────────────────────┘                  │              │
//   │  └─────────────────────────────────────────────────────────┘              │
//   │                                                                          │
//   └══════════════════════════════════════════════════════════════════════════┘
//
//   各字段详解：
//
//   【事务ID (Transaction Identifier)】2字节，大端序
//      - 作用：给每次请求编个号，响应里会带同样的编号，用来配对
//      - 类比：就像快递单号，你发了10个包裹，用单号对应哪个到了
//      - 取值：0~65535，每次请求递增1，溢出后回到0
//
//   【协议ID (Protocol Identifier)】2字节，大端序
//      - 作用：标识这是什么协议
//      - 取值：固定为 0x0000，表示 Modbus 协议
//      - 注意：永远是 0x00 0x00，不需要改
//
//   【长度 (Length)】2字节，大端序
//      - 作用：告诉接收方后面还有多少字节要读
//      - 计算：= 从站地址(1字节) + PDU的长度
//      - 示例：如果PDU是5字节，则长度 = 1 + 5 = 6，即 0x00 0x06
//
//   【从站地址 (Unit Identifier)】1字节
//      - 作用：指定要和哪个从站设备通信
//      - 取值：1~247（0和248~255有特殊用途）
//      - 类比：就像公寓的门牌号，指定你要找哪间房
//
//   【功能码 (Function Code)】1字节
//      - 作用：告诉从站你想做什么操作
//      - 详见下方功能码说明
//
//   【数据区域 (Data)】0~252字节
//      - 作用：功能码的参数或返回数据
//      - 长度和格式取决于功能码
//
//
// ======================== 功能码详解 ========================
//
//   Modbus 定义了很多功能码，但日常最常用的就这几个：
//
//   ┌──────┬──────────────────┬──────────────────────────────┐
//   │ 代码 │ 名称             │ 说明                         │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x01 │ Read Coils       │ 读线圈（数字输出 DO）        │
//   │      │ 读线圈           │ 每个线圈 = 1 个 bit (0或1)   │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x02 │ Read Discrete    │ 读离散输入（数字输入 DI）    │
//   │      │ Inputs 读离散输入│ 只读，每个 = 1 个 bit        │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x03 │ Read Holding     │ 读保持寄存器 ★最常用★       │
//   │      │ Registers        │ 每个寄存器 = 16 位无符号整数 │
//   │      │ 读保持寄存器     │ 可读可写，存设备参数、数据等 │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x04 │ Read Input       │ 读输入寄存器（只读数据）     │
//   │      │ Registers        │ 每个 = 16位，通常是传感器值  │
//   │      │ 读输入寄存器     │                              │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x05 │ Write Single Coil│ 写单个线圈                   │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x06 │ Write Single     │ 写单个寄存器                 │
//   │      │ Register         │                              │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x0F │ Write Multiple   │ 写多个线圈                   │
//   │      │ Coils            │                              │
//   ├──────┼──────────────────┼──────────────────────────────┤
//   │ 0x10 │ Write Multiple   │ 写多个寄存器                 │
//   │      │ Registers        │                              │
//   └──────┴──────────────────┴──────────────────────────────┘
//
//
// ======================== 异常响应机制 ========================
//
// 当从站无法正常处理请求时（比如你读了一个不存在的地址），它会返回"异常响应"：
//
//   正常响应：功能码 = 请求的功能码
//    请求: [0x03, 0x00, 0x00, 0x00, 0x0A]     ← 功能码 0x03
//    响应: [0x03, 0x14, ...]                   ← 功能码还是 0x03，后面跟数据
//
//   异常响应：功能码 = 请求功能码 + 0x80（最高位置1）
//    请求: [0x03, 0x00, 0x00, 0x00, 0x0A]     ← 功能码 0x03
//    响应: [0x83, 0x02]                        ← 0x83 = 0x03 + 0x80，异常码 0x02
//
//   常见异常码：
//     0x01 = 非法功能码（从站不支持这个操作）
//     0x02 = 非法数据地址（你读的地址不存在）
//     0x03 = 非法数据值（写入的值超出范围）
//     0x04 = 从站设备故障（设备内部出错了）
//

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第二部分：protocol - 协议定义（常量、枚举、帧结构）               │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/modbus/protocol.zig                             │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

/// 功能码枚举
/// 功能码是 PDU 的第一个字节，决定了这次请求要做什么操作。
/// 类比：功能码就像 HTTP 方法（GET/POST/PUT/DELETE），告诉服务器你想做什么。
///
/// 在 Zig 中，enum(u8) 表示这个枚举底层用 u8（1字节无符号整数）存储。
/// 末尾的 `_` 表示"非穷尽枚举"，允许存在未列出的值（比如 0xFF），
/// 这样遇到未知功能码时不会编译错误。
const FunctionCode = enum(u8) {
    read_coils = 0x01, // 读线圈（读数字输出 DO 的开/关状态）
    read_discrete_inputs = 0x02, // 读离散输入（读数字输入 DI 的状态）
    read_holding_registers = 0x03, // ★ 读保持寄存器（最常用！读 16 位数据）
    read_input_registers = 0x04, // 读输入寄存器（只读的 16 位数据）
    write_single_coil = 0x05, // 写单个线圈（控制一个数字输出）
    write_single_register = 0x06, // 写单个寄存器（写入一个 16 位值）
    write_multiple_coils = 0x0F, // 写多个线圈（批量控制数字输出）
    write_multiple_registers = 0x10, // 写多个寄存器（批量写入 16 位值）
    _, // 非穷尽标记：允许其他未定义的功能码值存在
};

/// 异常码枚举
/// 当从站无法正常处理请求时，返回异常码告诉你出了什么问题。
/// 类比：就像 HTTP 状态码（404 Not Found、500 Internal Server Error）。
const ExceptionCode = enum(u8) {
    illegal_function = 0x01, // 从站不支持该功能码（你发了它看不懂的指令）
    illegal_data_address = 0x02, // 寄存器地址不存在（你读了不存在的"门牌号"）
    illegal_data_value = 0x03, // 数据值超出范围（你写的值不合法）
    server_device_failure = 0x04, // 从站内部故障（设备自己坏了）
    acknowledge = 0x05, // 已收到请求，但需要较长时间处理
    server_device_busy = 0x06, // 从站正忙，请稍后重试
    memory_parity_error = 0x08, // 存储器校验出错
    gateway_path_unavailable = 0x0A, // 网关路径不可用
    gateway_target_failed = 0x0B, // 网关无法到达目标设备
    _, // 允许其他未知异常码

    /// 获取异常码的文字描述
    /// Zig 允许在枚举内部定义方法，self 就是枚举值本身
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

// ===== 协议常量 =====
const MBAP_HEADER_SIZE: usize = 7; // MBAP 头部固定占 7 个字节
const MAX_PDU_SIZE: usize = 253; // PDU（功能码+数据）最大 253 字节，这是 Modbus 规范硬性限制
const MAX_ADU_SIZE: usize = MBAP_HEADER_SIZE + MAX_PDU_SIZE; // 完整帧最大 260 字节 (7 + 253)

/// MBAP 头部结构体
/// MBAP = Modbus Application Protocol Header
///
/// 这是 Modbus TCP 独有的帧头（Modbus RTU 串口版没有这个）。
/// TCP 是流式协议，没有消息边界概念，MBAP 头部的作用就是告诉接收方：
///   "从这里开始是一条新的 Modbus 消息，长度是 XX 字节"
///
/// 在 Zig 中，struct 是值类型（分配在栈上），没有隐式指针，非常轻量。
const MbapHeader = struct {
    transaction_id: u16, // 事务ID (2字节)：请求/响应配对编号，像快递单号一样
    protocol_id: u16, // 协议ID (2字节)：永远是 0x0000，表示 Modbus 协议
    length: u16, // 长度   (2字节)：后续数据的字节数（= 1 + PDU长度）
    unit_id: u8, // 从站ID (1字节)：目标设备地址 1~247
};

/// 将 MBAP 头部各字段写入字节缓冲区
///
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
fn writeMbapHeader(buf: []u8, tx_id: u16, pdu_len: usize, unit_id: u8) void {
    // buf[0..2] 表示从 buf 中取第 0、1 两个字节的切片（Zig 切片是左闭右开的）
    // writeInt(u16, ..., .big) 把 u16 值按大端序写入 2 字节
    std.mem.writeInt(u16, buf[0..2], tx_id, .big); // 字节 0~1：事务ID
    std.mem.writeInt(u16, buf[2..4], 0, .big); // 字节 2~3：协议ID（固定为 0）
    std.mem.writeInt(u16, buf[4..6], @intCast(pdu_len + 1), .big); // 字节 4~5：长度 = UnitID(1) + PDU长度
    // @intCast 是 Zig 的类型转换内建函数：把 usize 安全转为 u16
    buf[6] = unit_id; // 字节 6：从站地址
}

/// 从接收到的字节流中解析出 MBAP 头部
/// 如果数据不足 7 字节，返回 null（表示"还没收完整"）
///
/// 返回类型 ?MbapHeader 是 Zig 的可选类型（Optional），等价于"可能有值，也可能是 null"
fn parseMbapHeader(data: []const u8) ?MbapHeader {
    if (data.len < MBAP_HEADER_SIZE) return null; // 数据不够，返回 null
    return .{
        // readInt 和 writeInt 对应，从字节切片中按大端序读出 u16
        .transaction_id = std.mem.readInt(u16, data[0..2], .big),
        .protocol_id = std.mem.readInt(u16, data[2..4], .big),
        .length = std.mem.readInt(u16, data[4..6], .big),
        .unit_id = data[6],
    };
}

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第三部分：request - 请求构造（把参数变成字节流）                   │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/modbus/request.zig                              │
// │                                                                              │
// │  这些函数只构造 PDU（功能码+参数），不包含 MBAP 头部。                         │
// │  MBAP 头部由 TCP 客户端在发送时自动添加。                                      │
// │  这种设计是为了 "协议逻辑" 和 "传输逻辑" 分开，将来换成串口 RTU 也能复用。    │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

/// ====================== 0x03 读保持寄存器 ======================
///
/// 这是 Modbus 中最常用的功能码，几乎所有设备都支持。
/// "保持寄存器" 是设备上的数据存储单元，每个寄存器是 16 位（0~65535）。
/// 常用来存：温度、压力、转速、设定值、状态码等。
///
/// 请求 PDU 结构（固定 5 字节）：
///
///   字节序号:    [0]        [1]   [2]      [3]   [4]
///            ┌──────────┬─────────────┬─────────────┐
///            │ 功能码   │  起始地址    │  寄存器数量  │
///            │  0x03    │  高字节 低字节│  高字节 低字节│
///            └──────────┴─────────────┴─────────────┘
///            │← 1字节 →│←── 2字节 ──→│←── 2字节 ──→│
///
///   示例：读从地址 0 开始的 10 个寄存器
///     [0x03, 0x00, 0x00, 0x00, 0x0A]
///      │     │     │     │     │
///      │     └─ 起始地址 0 ──┘     └─ 数量 10 ──┘
///      └─ 功能码 0x03
///
/// 参数：
///   buf        - 输出缓冲区（调用者提供，至少 5 字节）
///   start_addr - 起始寄存器地址（从 0 开始编号）
///   quantity   - 要读的寄存器个数（1~125，Modbus 规范限制单次最多 125 个）
///
/// 返回：buf 中有效数据的切片（5 字节）
fn buildReadHoldingRegisters(buf: []u8, start_addr: u16, quantity: u16) []u8 {
    // @intFromEnum 把枚举值转为对应的 u8 整数（FunctionCode.read_holding_registers → 0x03）
    buf[0] = @intFromEnum(FunctionCode.read_holding_registers);
    // 大端序写入起始地址（2字节）
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    // 大端序写入寄存器数量（2字节）
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    // 返回 buf 的前 5 字节的切片（指向 buf 的一部分，不是新分配内存）
    return buf[0..5];
}

/// ====================== 0x01 读线圈 ======================
///
/// "线圈"(Coil) 是 Modbus 术语，代表一个数字输出点。
/// 每个线圈只有两个状态：0（关/OFF）或 1（开/ON）。
/// 名称来源于继电器的线圈——通电就吸合（ON），断电就释放（OFF）。
///
/// 请求格式和 0x03 完全一样，只是功能码不同：
///
///   字节序号:    [0]        [1]   [2]      [3]   [4]
///            ┌──────────┬─────────────┬─────────────┐
///            │  0x01    │  起始地址    │  线圈数量    │
///            └──────────┴─────────────┴─────────────┘
///
///   注意：这里的 quantity 是线圈个数（按 bit 计），不是字节数。
///   比如读 16 个线圈，响应里会返回 2 字节（16 bit = 2 byte）。
fn buildReadCoils(buf: []u8, start_addr: u16, quantity: u16) []u8 {
    buf[0] = @intFromEnum(FunctionCode.read_coils);
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    return buf[0..5];
}

/// ====================== 0x06 写单个寄存器 ======================
///
/// 向指定地址的一个寄存器写入一个 16 位值。
///
/// 请求 PDU 结构（固定 5 字节）：
///
///   字节序号:    [0]        [1]   [2]      [3]   [4]
///            ┌──────────┬─────────────┬─────────────┐
///            │  0x06    │  寄存器地址  │   写入的值   │
///            └──────────┴─────────────┴─────────────┘
///
///   示例：在地址 1 写入值 255
///     [0x06, 0x00, 0x01, 0x00, 0xFF]
///
///   响应：从站会原样回显这 5 字节（表示写入成功）
fn buildWriteSingleRegister(buf: []u8, addr: u16, value: u16) []u8 {
    buf[0] = @intFromEnum(FunctionCode.write_single_register);
    std.mem.writeInt(u16, buf[1..3], addr, .big);
    std.mem.writeInt(u16, buf[3..5], value, .big);
    return buf[0..5];
}

/// ====================== 0x10 写多个寄存器 ======================
///
/// 一次向连续的多个寄存器写入数据。
///
/// 请求 PDU 结构（可变长度）：
///
///   字节序号:    [0]        [1][2]      [3][4]      [5]         [6]~[N]
///            ┌──────────┬───────────┬───────────┬──────────┬──────────────┐
///            │  0x10    │ 起始地址  │ 寄存器数量 │ 字节计数 │ 寄存器值数据 │
///            └──────────┴───────────┴───────────┴──────────┴──────────────┘
///            │← 1字节 →│←─ 2字节 ─→│←─ 2字节 ─→│← 1字节 →│←─ N*2字节 ─→│
///
///   字节计数 = 寄存器数量 × 2（因为每个寄存器 2 字节）
///
///   示例：从地址 0 开始写入 2 个寄存器，值分别为 100 和 200
///     [0x10, 0x00, 0x00, 0x00, 0x02, 0x04, 0x00, 0x64, 0x00, 0xC8]
///      │     └─起始地址0─┘ └─数量2──┘  │    └─100──┘  └─200──┘
///      └─功能码0x10               字节数4
///
///   响应：从站回显 起始地址 和 寄存器数量（5字节），表示写入成功
fn buildWriteMultipleRegisters(buf: []u8, start_addr: u16, values: []const u16) []u8 {
    // values.len 是 usize 类型，需要转换为 u16 和 u8
    const quantity: u16 = @intCast(values.len);
    const byte_count: u8 = @intCast(values.len * 2);

    buf[0] = @intFromEnum(FunctionCode.write_multiple_registers);
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    buf[5] = byte_count;

    // 逐个写入每个寄存器的值
    // `for (values, 0..)` 是 Zig 的同时遍历：val 是值，i 是索引
    for (values, 0..) |val, i| {
        // buf[6 + i * 2 ..][0..2] 的含义：
        //   先从 buf 的第 (6 + i*2) 字节开始取切片
        //   然后从这个切片中取前 2 字节（给 writeInt 提供精确的 *[2]u8 类型）
        std.mem.writeInt(u16, buf[6 + i * 2 ..][0..2], val, .big);
    }

    // 总长度 = 功能码(1) + 起始地址(2) + 数量(2) + 字节计数(1) + 数据(N*2)
    return buf[0 .. 6 + values.len * 2];
}

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第四部分：response - 响应解析（把字节流变成结构化数据）             │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/modbus/response.zig                             │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

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
const ReadRegistersResult = struct {
    values: [125]u16 = undefined, // 固定大小数组，最多 125 个寄存器（Modbus 规范上限）
    // `= undefined` 表示不初始化，节省性能（反正后面会覆盖写入）
    count: usize = 0, // 实际读到了几个寄存器
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
const ReadCoilsResult = struct {
    data: [256]u8 = undefined, // 原始字节数据（位打包的）
    byte_count: usize = 0, // 实际收到了几个字节
};

/// 写单个寄存器/线圈的响应（0x06 / 0x05）
/// 从站原样回显请求的地址和值，表示"我收到了，写入成功"
const WriteSingleResult = struct {
    address: u16, // 回显的地址
    value: u16, // 回显的值
};

/// 写多个寄存器/线圈的响应（0x10 / 0x0F）
/// 从站回显起始地址和写入数量
const WriteMultipleResult = struct {
    start_address: u16, // 起始地址
    quantity: u16, // 写入的数量
};

/// 统一的响应数据类型
///
/// Zig 的 tagged union（标记联合体）可以在一个变量中存储不同类型的数据，
/// 并且知道当前存的是哪种类型。
///
/// 类比：就像一个信封，里面可能装着"寄存器数据"或"线圈数据"或"异常信息"，
/// 你打开信封时可以通过标签知道里面装的是什么。
const ResponseData = union(enum) {
    read_registers: ReadRegistersResult, // 读寄存器成功
    read_coils: ReadCoilsResult, // 读线圈成功
    write_single: WriteSingleResult, // 写单个成功
    write_multiple: WriteMultipleResult, // 写多个成功
    exception: struct { // 异常响应（从站报错了）
        function_code: u8, // 原始功能码（已去掉 0x80 标记）
        code: ExceptionCode, // 具体的异常原因
    },
};

/// 响应解析可能遇到的错误
const ParseError = error{
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
fn parsePdu(data: []const u8) ParseError!ResponseData {
    if (data.len < 1) return error.FrameTooShort;

    const fc = data[0]; // PDU 的第一个字节永远是功能码

    // ---- 步骤1：检查是否为异常响应 ----
    // 异常响应的标志：功能码的最高位(bit7)被置为 1
    // 位运算：fc & 0x80 提取最高位。
    //   0x03 = 0b00000011，& 0x80 = 0b00000000 = 0 → 正常
    //   0x83 = 0b10000011，& 0x80 = 0b10000000 ≠ 0 → 异常！
    if (fc & 0x80 != 0) {
        if (data.len < 2) return error.FrameTooShort;
        return .{
            .exception = .{
                .function_code = fc & 0x7F, // & 0x7F 把最高位清零，还原原始功能码
                // 0x83 & 0x7F = 0x03
                .code = @enumFromInt(data[1]), // 第二个字节是异常码
                // @enumFromInt 把 u8 值转为 ExceptionCode 枚举
            },
        };
    }

    // ---- 步骤2：正常响应，根据功能码类型分别处理 ----
    const fc_enum: FunctionCode = @enumFromInt(fc);

    switch (fc_enum) {

        // ---- 0x03 / 0x04：读寄存器响应 ----
        .read_holding_registers, .read_input_registers => {
            if (data.len < 2) return error.FrameTooShort;
            const bc = data[1]; // 字节计数：后面有多少字节的寄存器数据
            if (data.len < 2 + bc) return error.FrameTooShort;
            if (bc % 2 != 0) return error.InvalidByteCount;
            // 每个寄存器占 2 字节，所以字节数必须是偶数
            // 如果不是偶数，说明数据有问题

            var r = ReadRegistersResult{};
            r.count = bc / 2; // 寄存器个数 = 字节数 / 2

            // 逐个解析每个寄存器的 16 位值
            for (0..r.count) |i| {
                // data[2 + i * 2 ..][0..2]：
                //   从数据中跳过（功能码1 + 字节计数1 + 前面寄存器的字节数i*2）
                //   取 2 字节，按大端序解析为 u16
                r.values[i] = std.mem.readInt(u16, data[2 + i * 2 ..][0..2], .big);
            }
            return .{ .read_registers = r };
        },

        // ---- 0x01 / 0x02：读线圈响应 ----
        .read_coils, .read_discrete_inputs => {
            if (data.len < 2) return error.FrameTooShort;
            const bc = data[1];
            if (data.len < 2 + bc) return error.FrameTooShort;

            var r = ReadCoilsResult{};
            r.byte_count = bc;
            // @memcpy：内存拷贝，把响应中的线圈数据复制到结果结构体中
            @memcpy(r.data[0..bc], data[2 .. 2 + bc]);
            return .{ .read_coils = r };
        },

        // ---- 0x06 / 0x05：写单个寄存器/线圈 响应 ----
        // 从站原样回显请求的地址和值
        .write_single_register, .write_single_coil => {
            if (data.len < 5) return error.FrameTooShort;
            return .{
                .write_single = .{
                    .address = std.mem.readInt(u16, data[1..3], .big),
                    .value = std.mem.readInt(u16, data[3..5], .big),
                },
            };
        },

        // ---- 0x10 / 0x0F：写多个寄存器/线圈 响应 ----
        // 从站回显起始地址和写入数量
        .write_multiple_registers, .write_multiple_coils => {
            if (data.len < 5) return error.FrameTooShort;
            return .{
                .write_multiple = .{
                    .start_address = std.mem.readInt(u16, data[1..3], .big),
                    .quantity = std.mem.readInt(u16, data[3..5], .big),
                },
            };
        },

        // 兜底：不认识的功能码
        _ => return error.UnexpectedFunctionCode,
    }
}

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第五部分：tcp - TCP 传输层（网络连接、收发数据）                   │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/modbus/tcp.zig                                  │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

/// Modbus TCP 客户端
///
/// 封装了 TCP 连接管理和 Modbus 帧的收发逻辑。
/// 使用流程：
///   1. connect()      → 建立 TCP 连接
///   2. sendRequest()  → 发送请求＆接收响应（可反复调用）
///   3. close()        → 关闭连接
///
/// 在 Zig 中 struct 既可以当数据结构用，也可以当命名空间用。
/// 把方法定义在 struct 内部，类似于面向对象的"类"。
const TcpClient = struct {
    stream: std.net.Stream, // TCP 流：双向读写通道，代表一条已建立的 TCP 连接
    transaction_id: u16 = 0, // 事务ID计数器，每次 sendRequest 自动 +1
    unit_id: u8, // 从站地址，建连时指定，之后每次请求都用它

    /// 响应结构体
    /// sendRequest 返回这个，把原始数据和解析后的信息打包在一起
    const Response = struct {
        header: MbapHeader, // 已解析的 MBAP 头部
        pdu: []const u8, // PDU 部分（功能码+数据），不含 MBAP 头部
        raw: []const u8, // 完整原始帧（含 MBAP 头部），用于调试打印
    };

    /// 连接到 Modbus TCP 从站
    ///
    /// 参数：
    ///   ip      - IPv4 地址的 4 个字节，如 [4]u8{192, 168, 1, 100}
    ///   port    - TCP 端口号（Modbus 默认 502）
    ///   unit_id - 从站地址（1~247）
    ///
    /// 返回：成功则返回 TcpClient 实例，失败则返回错误
    ///
    /// `!TcpClient` 是 Zig 的错误联合类型简写，等价于 `anyerror!TcpClient`
    /// 意思是"要么返回一个 TcpClient，要么返回一个错误"
    pub fn connect(ip: [4]u8, port: u16, unit_id: u8) !TcpClient {
        // initIp4 把 4 字节 IP + 端口号组合成一个地址结构体
        const addr = std.net.Address.initIp4(ip, port);
        // tcpConnectToAddress 发起 TCP 三次握手，阻塞直到连接成功或超时
        // `try` 关键字：如果函数返回错误，立即把错误传播给调用者
        const stream = try std.net.tcpConnectToAddress(addr);
        // 连接成功，返回初始化好的 TcpClient
        // .{ ... } 是 Zig 的结构体字面量语法
        return .{
            .stream = stream,
            .unit_id = unit_id,
        };
    }

    /// 关闭 TCP 连接
    /// 通常配合 `defer client.close()` 使用，确保函数退出时自动关闭
    pub fn close(self: *TcpClient) void {
        self.stream.close();
    }

    /// 获取下一个事务ID
    /// +%= 是 Zig 的"溢出回绕加法"，到 65535 后会回到 0，不会报错
    /// （普通的 + 在溢出时会 panic）
    fn nextTransactionId(self: *TcpClient) u16 {
        self.transaction_id +%= 1;
        return self.transaction_id;
    }

    /// 发送 Modbus 请求并接收响应（核心方法）
    ///
    /// 这个方法自动完成以下步骤：
    ///   ① 在 PDU 前面加上 MBAP 头部，组成完整的 ADU（应用数据单元）
    ///   ② 通过 TCP 发送整个 ADU
    ///   ③ 等待并读取从站的响应
    ///   ④ 解析响应的 MBAP 头部
    ///   ⑤ 把结果打包返回
    ///
    /// 参数：
    ///   pdu      - 由 buildXxx 函数构造的 PDU（功能码+参数）
    ///   resp_buf - 调用者提供的接收缓冲区（存原始响应数据）
    ///
    /// 为什么要调用者提供缓冲区？
    ///   因为 Zig 没有隐式堆分配，所有内存都由调用者管理。
    ///   返回的 Response.raw 和 Response.pdu 都是指向 resp_buf 的切片，
    ///   只要 resp_buf 还活着（没出作用域），它们就有效。
    pub fn sendRequest(self: *TcpClient, pdu: []const u8, resp_buf: []u8) !Response {
        // ---- 第①步：组装完整帧 ----
        // ADU = MBAP Header(7字节) + PDU
        var send_buf: [MAX_ADU_SIZE]u8 = undefined;
        const tx_id = self.nextTransactionId();
        writeMbapHeader(&send_buf, tx_id, pdu.len, self.unit_id);
        // @memcpy：把 PDU 复制到 MBAP 头部后面的位置
        @memcpy(send_buf[MBAP_HEADER_SIZE .. MBAP_HEADER_SIZE + pdu.len], pdu);

        // ---- 第②步：通过 TCP 发送 ----
        // stream.write 发送字节到对端
        // 发送的总长度 = MBAP头(7) + PDU长度
        _ = try self.stream.write(send_buf[0 .. MBAP_HEADER_SIZE + pdu.len]);

        // ---- 第③步：接收响应 ----
        // stream.read 从 TCP 连接读取数据到 resp_buf
        // n 是实际读到的字节数
        const n = try self.stream.read(resp_buf);
        if (n == 0) return error.ConnectionResetByPeer;
        // n=0 表示对方关闭了连接（TCP 的 FIN 信号）

        // ---- 第④⑤步：解析 MBAP 头部并返回 ----
        const header = parseMbapHeader(resp_buf[0..n]) orelse return error.EndOfStream;
        // `orelse` 处理 null：如果 parseMbapHeader 返回 null，就返回错误

        return .{
            .header = header,
            .pdu = resp_buf[MBAP_HEADER_SIZE..n], // 跳过 7 字节 MBAP 头就是 PDU
            .raw = resp_buf[0..n], // 完整的原始帧
        };
    }
};

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第六部分：display - 显示输出（格式化打印结果）                     │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/display.zig                                     │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

/// 打印原始帧（十六进制格式）
///
/// 用途：调试时查看实际收发的原始字节，确认协议是否正确
/// 输出示例：RX (15B): 00 01 00 00 00 09 01 03 06 00 0A 00 14 00 1E
///
/// Zig 格式化语法：
///   {s}       - 打印字符串切片 []const u8
///   {d}       - 打印十进制整数
///   {X:0>2}   - 打印十六进制大写，用 0 填充，宽度 2
///                例如 10 → "0A"，255 → "FF"，0 → "00"
fn printRawFrame(label: []const u8, data: []const u8) void {
    std.debug.print("{s} ({d}B): ", .{ label, data.len });
    for (data) |b| {
        std.debug.print("{X:0>2} ", .{b});
    }
    std.debug.print("\n", .{});
}

/// 打印 MBAP 头部的各字段
fn printMbapHeader(h: MbapHeader) void {
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
fn printResponse(r: ResponseData) void {
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

// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第七部分：main - 程序入口（组装以上所有模块）                      │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/main.zig                                        │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘

/// 程序入口
///
/// 演示完整流程：连接 → 构造请求 → 发送 → 接收 → 解析 → 显示
///
/// `pub fn main() !void` 中的 `!void` 表示：
///   - 函数可能返回错误（! 部分）
///   - 正常情况下不返回值（void 部分）
///   - 如果是 main 函数返回了错误，Zig 运行时会打印错误信息并以非零退出码退出
pub fn main() !void {
    // ===== 通信参数配置 =====
    // 后续可以改为从命令行参数读取
    const ip = [4]u8{ 127, 0, 0, 1 }; // 目标 IP：127.0.0.1（本机回环地址）
    const port: u16 = 502; // Modbus TCP 标准端口
    const unit_id: u8 = 1; // 从站地址（大多数设备默认 1）
    const start_addr: u16 = 0; // 起始寄存器地址（从第 0 个开始读）
    const quantity: u16 = 10; // 读取数量（读 10 个寄存器）

    // ===== 打印启动信息 =====
    std.debug.print(
        \\
        \\╔══════════════════════════════════════════╗
        \\║       Modbus TCP Debug Tool v0.1         ║
        \\╚══════════════════════════════════════════╝
        \\
        \\  Target : {d}.{d}.{d}.{d}:{d}
        \\  Unit ID: {d}
        \\  Action : Read Holding Registers
        \\  Address: {d} ~ {d}  (quantity: {d})
        \\
        \\
    , .{
        ip[0],   ip[1],      ip[2],                     ip[3],    port,
        unit_id, start_addr, start_addr + quantity - 1, quantity,
    });

    // ===== 第1步：建立 TCP 连接 =====
    std.debug.print("[1/5] Connecting...\n", .{});

    var client = TcpClient.connect(ip, port, unit_id) catch |err| {
        std.debug.print(
            \\
            \\  ERROR: Connect failed: {}
            \\
            \\  请确保有一个 Modbus TCP 从站正在运行！
            \\  推荐工具：
            \\    - diagslave（免费命令行从站模拟器）
            \\    - Modbus Slave（Windows GUI 软件，有试用版）
            \\    - Python pymodbus: pip install pymodbus
            \\
            \\
        , .{err});
        return err;
    };
    // defer：延迟执行，函数返回时（无论正常还是出错）自动调用 close()
    // 这是 Zig 的 RAII 模式，保证资源一定会被释放
    defer client.close();
    std.debug.print("  Connected!\n\n", .{});

    // ===== 第2步：构造请求 PDU =====
    std.debug.print("[2/5] Building request PDU...\n", .{});

    var pdu_buf: [256]u8 = undefined; // 栈上分配缓冲区（不需要堆内存）
    const pdu = buildReadHoldingRegisters(&pdu_buf, start_addr, quantity);
    // 此时 pdu 指向 pdu_buf[0..5]，内容是：[0x03, 0x00, 0x00, 0x00, 0x0A]

    printRawFrame("  TX PDU", pdu);
    std.debug.print("\n", .{});

    // ===== 第3步：发送请求并接收响应 =====
    std.debug.print("[3/5] Sending request & waiting for response...\n", .{});

    var resp_buf: [256]u8 = undefined;
    const result = client.sendRequest(pdu, &resp_buf) catch |err| {
        std.debug.print("  Communication error: {}\n", .{err});
        return err;
    };
    std.debug.print("  Received response!\n\n", .{});

    // ===== 第4步：输出原始帧（方便对照抓包工具验证） =====
    std.debug.print("[4/5] Raw frame data:\n", .{});
    printRawFrame("  RX", result.raw);
    printMbapHeader(result.header);
    std.debug.print("\n", .{});

    // ===== 第5步：解析并格式化输出 =====
    std.debug.print("[5/5] Parsing response:\n", .{});

    const parsed = parsePdu(result.pdu) catch |err| {
        std.debug.print("  Parse error: {}\n", .{err});
        return err;
    };
    printResponse(parsed);
}
