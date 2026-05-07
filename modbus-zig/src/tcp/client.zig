const std = @import("std");
const codec = @import("../codec.zig");

pub const ModbusError = codec.ModbusError;
pub const FunctionCode = codec.FunctionCode;

// 连接参数保持简单直接，第一版先服务当前 Modbus TCP 主站场景。
pub const ConnectOptions = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16 = 502,
    unit_id: u8 = 1,
};

// TcpClient 负责：建立 TCP 连接、附加 MBAP 头、发送请求、读取响应、校验事务一致性。
pub const TcpClient = struct {
    allocator: std.mem.Allocator,
    runtime: *std.Io.Threaded, // 堆指针：确保 io.userdata 稳定，不随 struct 移动而失效
    io: std.Io,
    stream: std.Io.net.Stream,
    unit_id: u8,
    transaction_id: u16 = 0,

    pub fn connect(options: ConnectOptions) !TcpClient {
        if (options.unit_id == 0 or options.unit_id > 247) return error.InvalidUnitId;

        // Zig 0.16 的 std.Io.Threaded 可以提供一套跨平台的阻塞式 IO 运行时，
        // 当前库先用它把“能稳定通信”作为第一目标，不额外引入更复杂的异步抽象。
        // 堆分配 Threaded，使 io.userdata（= runtime 指针）在整个生命周期内地址不变。
        // 若直接存值字段，connect() 返回时 struct 被复制/移动，io.userdata 指向旧栈地址 → 悬空指针。
        const runtime = try options.allocator.create(std.Io.Threaded);
        errdefer options.allocator.destroy(runtime);
        runtime.* = std.Io.Threaded.init(options.allocator, .{});
        errdefer runtime.deinit();

        const io = runtime.io();
        // host 可以是 IP，也可以是域名；resolve 会统一把它解析成可连接地址。
        const address = try std.Io.net.IpAddress.resolve(io, options.host, options.port);
        const stream = try std.Io.net.IpAddress.connect(&address, io, .{
            .mode = .stream,
            .protocol = .tcp,
        });

        return .{
            .allocator = options.allocator,
            .runtime = runtime,
            .io = io,
            .stream = stream,
            .unit_id = options.unit_id,
        };
    }

    pub fn deinit(self: *TcpClient) void {
        // 先关 socket，再 deinit runtime（关闭后台线程），最后释放堆内存。
        self.stream.close(self.io);
        self.runtime.deinit();
        self.allocator.destroy(self.runtime); // 对应 connect() 中的 allocator.create
    }

    // 常见数据采集场景：批量读取保持寄存器。
    pub fn readHoldingRegistersAlloc(self: *TcpClient, allocator: std.mem.Allocator, start_address: u16, quantity: u16) ![]u16 {
        return self.readRegistersAlloc(allocator, .read_holding_registers, start_address, quantity);
    }

    // 输入寄存器常用于设备只读测量值，例如电压、电流、温度等。
    pub fn readInputRegistersAlloc(self: *TcpClient, allocator: std.mem.Allocator, start_address: u16, quantity: u16) ![]u16 {
        return self.readRegistersAlloc(allocator, .read_input_registers, start_address, quantity);
    }

    pub fn writeSingleRegister(self: *TcpClient, address: u16, value: u16) !void {
        var payload: [4]u8 = undefined;
        const payload_len = try codec.encodeWriteSingleRegister(payload[0..], address, value);
        try self.exchangeWrite(.write_single_register, payload[0..payload_len], address, value);
    }

    pub fn writeMultipleRegisters(self: *TcpClient, start_address: u16, values: []const u16) !void {
        var payload: [251]u8 = undefined;
        const payload_len = try codec.encodeWriteMultipleRegisters(payload[0..], start_address, values);
        try self.exchangeWrite(.write_multiple_registers, payload[0..payload_len], start_address, @as(u16, @intCast(values.len)));
    }

    fn readRegistersAlloc(self: *TcpClient, allocator: std.mem.Allocator, function: FunctionCode, start_address: u16, quantity: u16) ![]u16 {
        var pdu: [4]u8 = undefined;
        const pdu_len = try codec.encodeReadRegisters(pdu[0..], function, start_address, quantity);

        // response 必须在本函数栈帧上分配，确保 parsed.payload（指向 response 内部的切片）在
        // decodeRegisterPayload 调用期间仍然有效。若放在 exchange() 内部，函数返回后栈帧销毁，
        // 后续 allocator.alloc() 等调用可能覆盖那段内存，造成随机性解析错误。
        var response: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        const parsed = try self.exchange(function, pdu[0..pdu_len], response[0..]);

        // 为了让调用方 API 更直接，这里由库分配结果缓冲区，外部只需要负责释放。
        const registers = try allocator.alloc(u16, quantity);
        errdefer allocator.free(registers);

        const count = try codec.decodeRegisterPayload(parsed.payload, registers);
        return registers[0..count];
    }

    fn exchangeWrite(self: *TcpClient, function: FunctionCode, payload: []const u8, start_address: u16, expected_tail: u16) !void {
        // 同样把 response buffer 放在本帧，保证 validateWriteAck 读到的 payload 有效。
        var response: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        const parsed = try self.exchange(function, payload, response[0..]);
        try codec.validateWriteAck(parsed.payload, start_address, expected_tail);
    }

    // response_buf 由调用方提供，确保返回的 ParsedResponse.payload 切片在调用方栈帧内有效。
    fn exchange(self: *TcpClient, function: FunctionCode, payload: []const u8, response_buf: []u8) !codec.ParsedResponse {
        // 事务号在 Modbus TCP 中由主站递增生成，用于把请求和响应配对。
        const transaction_id = self.nextTransactionId();

        var request: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        // buildTcpRequest 把MBAP 头（包含事务 ID、协议 ID、长度、单元 ID）和 PDU（功能码 + 负载）组合成完整的请求帧
        const request_len = try codec.buildTcpRequest(request[0..], transaction_id, self.unit_id, function, payload);

        // 这里每次临时构造 writer，逻辑最直观，也便于后续替换成更高级的连接复用策略。
        var writer_buffer: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        var writer = self.stream.writer(self.io, writer_buffer[0..]);
        var chunks = [_][]const u8{request[0..request_len]};
        try writer.interface.writeVecAll(&chunks);
        try writer.interface.flush();

        const response_len = try self.readAdu(response_buf);
        return codec.parseTcpResponse(response_buf[0..response_len], transaction_id, self.unit_id, function);
    }

    fn readAdu(self: *TcpClient, buffer: []u8) !usize {
        // 同一个响应帧内必须复用同一个 Reader，避免第一次读 MBAP 头时把 payload 预读到临时缓冲后丢失。
        var reader_buffer: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        var reader = self.stream.reader(self.io, reader_buffer[0..]);

        // 先读固定长度的 MBAP 头，再根据 length 字段补齐剩余 PDU。
        try self.readExactWithReader(&reader, buffer[0..7]);

        const length: u16 = (@as(u16, buffer[4]) << 8) | @as(u16, buffer[5]);
        if (length < 2) return error.InvalidLengthField;

        const remain = @as(usize, length) - 1;
        const total_len = 7 + remain;
        if (buffer.len < total_len) return error.BufferTooSmall;

        try self.readExactWithReader(&reader, buffer[7..total_len]);
        return total_len;
    }

    fn readExactWithReader(self: *TcpClient, reader: *std.Io.net.Stream.Reader, buffer: []u8) codec.ModbusError!void {
        _ = self;
        var fixed_writer = std.Io.Writer.fixed(buffer);
        reader.interface.streamExact(&fixed_writer, buffer.len) catch {
            return error.EndOfStream;
        };
    }

    fn nextTransactionId(self: *TcpClient) u16 {
        self.transaction_id +%= 1;
        // 回卷到 0 时直接跳到 1，避免把 0 当作常规事务号使用。
        if (self.transaction_id == 0) self.transaction_id = 1;
        return self.transaction_id;
    }
};

test "事务号会自动递增并跳过 0" {
    var client: TcpClient = .{
        .allocator = std.testing.allocator,
        .runtime = undefined,
        .io = undefined,
        .stream = undefined,
        .unit_id = 1,
        .transaction_id = 0xFFFF,
    };

    try std.testing.expectEqual(@as(u16, 1), client.nextTransactionId());
    try std.testing.expectEqual(@as(u16, 2), client.nextTransactionId());
}
