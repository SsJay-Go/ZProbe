const std = @import("std");
const protocol = @import("protocol.zig");
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
pub fn buildReadHoldingRegisters(buf: []u8, start_addr: u16, quantity: u16) []u8 {
    buf[0] = @intFromEnum(protocol.FunctionCode.read_holding_registers); // 功能码 0x03
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
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
pub fn buildReadCoils(buf: []u8, start_addr: u16, quantity: u16) []u8 {
    buf[0] = @intFromEnum(protocol.FunctionCode.read_coils); // 功能码 0x01
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    return buf[0..5];
}

/// ====================== 0x02 读离散输入│ ======================
pub fn buildReadDiscreteInputs(buf: []u8, start_addr: u16, quantity: u16) []u8 {
    buf[0] = @intFromEnum(protocol.FunctionCode.read_discrete_inputs); // 功能码 0x02
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    return buf[0..5];
}

/// ====================== 0x05 写单个线圈 ======================
pub fn buildWriteSingleCoil(buf: []u8, addr: u16, value: u16) []u8 {
    buf[0] = @intFromEnum(protocol.FunctionCode.write_single_coil);
    std.mem.writeInt(u16, buf, addr, .big);
    std.mem.writeInt(u16, buf[3..5], value, .big);
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
pub fn buildWriteSingleRegister(buf: []u8, addr: u16, value: u16) []u8 {
    buf[0] = @intFromEnum(protocol.FunctionCode.write_single_register); // 功能码 0x06
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
pub fn buildWriteMultipleRegisters(buf: []u8, start_addr: u16, values: []const u16) []u8 {
    // values.len 是 usize 类型，需要转换为 u16 和 u8
    const quantity: u16 = @intCast(values.len); // 寄存器数量
    const byte_count: u8 = @intCast(values.len * 2); // 字节计数

    buf[0] = @intFromEnum(protocol.FunctionCode.write_multiple_registers); // 功能码 0x10
    std.mem.writeInt(u16, buf[1..3], start_addr, .big);
    std.mem.writeInt(u16, buf[3..5], quantity, .big);
    buf[5] = byte_count;

    // 逐个写入寄存器值，每个值占 2 字节
    for (values, 0..) |value, i| {
        // 先从 buf 的第 (6 + i*2) 字节开始取切片,然后从这个切片中取前 2 字节（给 writeInt 提供精确的 *[2]u8 类型）
        std.mem.writeInt(u16, buf[6 + i * 2 ..][0..2], value, .big);
    }
    return buf[0 .. 6 + values.len * 2];
}
