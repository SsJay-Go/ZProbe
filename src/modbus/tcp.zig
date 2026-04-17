// ┌──────────────────────────────────────────────────────────────────────────────┐
// │                                                                              │
// │              第五部分：tcp - TCP 传输层（网络连接、收发数据）                   │
// │                                                                              │
// │  如果拆分文件，这部分对应 src/modbus/tcp.zig                                  │
// │                                                                              │
// │  Zig 0.16: std.net 已移除，网络 API 迁移到 std.Io.net                        │
// │  main 函数签名: pub fn main(init: std.process.Init) !void                    │
// │  所有 I/O 操作都通过 init.io 获取的 Io 实例进行                               │
// │                                                                              │
// └──────────────────────────────────────────────────────────────────────────────┘
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const protocol = @import("protocol.zig");
const response = @import("response.zig");

/// Modbus TCP 客户端（Zig 0.16 版本）
///
/// 封装了 TCP 连接管理和 Modbus 帧的收发逻辑。
/// 使用流程：
///   1. connect(ip, port, unit_id, io) → 建立 TCP 连接（需要传入 Io 实例）
///   2. sendRequest()                  → 发送请求＆接收响应（可反复调用）
///   3. close()                        → 关闭连接
///
/// Zig 0.16 的 I/O 模型：
///   所有网络操作都通过 std.Io 实例的 vtable 间接调用。
///   Io 实例来自 main(init) 的 init.io，贯穿整个程序生命周期。
pub const TcpClient = struct {
    stream: net.Stream, // TCP 流：Zig 0.16 中是 std.Io.net.Stream
    io: Io, // Io 实例：所有 I/O 操作的核心，来自 init.io
    transaction_id: u16 = 0, // 事务 ID：每次请求递增
    unit_id: u8, // 从站地址

    // 响应结构体
    pub const Response = struct {
        header: protocol.MbapHeader, // MBAP 头部信息
        pdu: []const u8, // PDU 数据区（功能码 + 数据）
        raw: []const u8, // 原始字节数据（MBAP 头部 + PDU）
    };

    /// 连接到 Modbus TCP 从站
    ///
    /// Zig 0.16 变化：
    ///   - 新增 io 参数（std.Io 实例）
    ///   - 使用 std.Io.net.IpAddress.connect() 代替 std.net.tcpConnectToAddress()
    ///   - IpAddress 是 tagged union，用 .ip4 变体构造 IPv4 地址
    ///
    /// 参数：
    ///   ip      - IPv4 地址的 4 个字节
    ///   port    - TCP 端口号（Modbus 默认 502）
    ///   unit_id - 从站地址（1~247）
    ///   io      - Io 实例（来自 init.io）
    pub fn connect(ip: [4]u8, port: u16, unit_id: u8, io: Io) !TcpClient {
        // 构造 IpAddress（tagged union 的 .ip4 变体）
        // Ip4Address 有 .bytes 和 .port 两个字段
        const addr: net.IpAddress = .{ .ip4 = .{ .bytes = ip, .port = port } };
        // IpAddress.connect 发起 TCP 连接
        // .mode = .stream 表示 TCP 流式连接（区别于 .dgram UDP 数据报）
        const stream = try net.IpAddress.connect(&addr, io, .{ .mode = .stream });
        return .{
            .stream = stream,
            .io = io,
            .unit_id = unit_id,
        };
    }

    /// 关闭 TCP 连接
    /// Zig 0.16: stream.close() 需要传入 io 参数
    pub fn close(self: *TcpClient) void {
        self.stream.close(self.io);
    }

    /// 获取下一个事务ID
    /// +%= 是 Zig 的"溢出回绕加法"，到 65535 后会回到 0
    fn nextTransactionId(self: *TcpClient) u16 {
        self.transaction_id +%= 1;
        return self.transaction_id;
    }

    /// 发送 Modbus 请求并接收响应（核心方法）
    ///
    /// Zig 0.16 I/O 变化：
    ///   - 使用 Stream.writer(io, &buf) 获取带缓冲的 Writer
    ///   - 使用 Stream.reader(io, &buf) 获取带缓冲的 Reader
    ///   - Writer 通过 .interface.writeAll() 写入，.interface.flush() 刷新
    ///   - Reader 通过 .interface.take(n) 精确读取 n 字节
    ///
    /// 参数：
    ///   pdu      - 由 buildXxx 函数构造的 PDU（功能码+参数）
    ///   resp_buf - 调用者提供的接收缓冲区
    pub fn sendRequest(self: *TcpClient, pdu: []const u8, resp_buf: []u8) !Response {
        // 1. 组装完整的 ADU（MBAP 头部 + PDU）
        var send_buf: [protocol.MAX_ADU_SIZE]u8 = undefined;
        const tx_id = self.nextTransactionId();
        protocol.writeMbapHeader(&send_buf, tx_id, @intCast(pdu.len), self.unit_id);
        @memcpy(send_buf[protocol.MBAP_HEADER_SIZE .. protocol.MBAP_HEADER_SIZE + pdu.len], pdu);
        const total_len = protocol.MBAP_HEADER_SIZE + pdu.len;

        // 2. 通过 TCP 发送整个 ADU
        // Stream.writer() 返回带缓冲的 Writer，内部通过 Io vtable 发送数据
        var write_buffer: [protocol.MAX_ADU_SIZE]u8 = undefined;
        var writer = self.stream.writer(self.io, &write_buffer);
        try writer.interface.writeAll(send_buf[0..total_len]);
        try writer.interface.flush(); // 确保数据实际发送到网络

        // 3. 等待并读取从站的响应
        // Stream.reader() 返回带缓冲的 Reader
        // take(n) 精确读取 n 字节，比旧版 read() 更可靠（不会少读）
        var read_buffer: [protocol.MAX_ADU_SIZE]u8 = undefined;
        var reader = self.stream.reader(self.io, &read_buffer);

        // 先读 MBAP 头部（固定 7 字节）
        const header_bytes = try reader.interface.take(protocol.MBAP_HEADER_SIZE);
        @memcpy(resp_buf[0..protocol.MBAP_HEADER_SIZE], header_bytes);

        // 解析 MBAP 头部，获取后续 PDU 长度
        const header = protocol.parseMbapHeader(resp_buf[0..protocol.MBAP_HEADER_SIZE]) orelse
            return error.EndOfStream;

        // header.length 包含 unit_id(1字节) + PDU，所以 PDU 长度 = length - 1
        const pdu_len: usize = @as(usize, header.length) - 1;

        // 读取 PDU 数据
        const pdu_bytes = try reader.interface.take(pdu_len);
        @memcpy(resp_buf[protocol.MBAP_HEADER_SIZE .. protocol.MBAP_HEADER_SIZE + pdu_len], pdu_bytes);

        const n = protocol.MBAP_HEADER_SIZE + pdu_len;

        return .{
            .header = header,
            .pdu = resp_buf[protocol.MBAP_HEADER_SIZE..n],
            .raw = resp_buf[0..n],
        };
    }
};

pub const TcpErrorCode = error{
    ConnectionResetByPeer, // 对端关闭连接
    EndOfStream, // 读取时遇到流结束
};
