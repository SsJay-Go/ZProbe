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
    runtime: std.Io.Threaded,
    io: std.Io,
    stream: std.Io.net.Stream,
    unit_id: u8,
    transaction_id: u16 = 0,

    pub fn connect(options: ConnectOptions) !TcpClient {
        if (options.unit_id == 0 or options.unit_id > 247) return error.InvalidUnitId;

        // Zig 0.16 的 std.Io.Threaded 可以提供一套跨平台的阻塞式 IO 运行时，
        // 当前库先用它把“能稳定通信”作为第一目标，不额外引入更复杂的异步抽象。
        var runtime = std.Io.Threaded.init(options.allocator, .{});
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
        // 先关 socket，再释放 IO runtime，避免句柄留在运行时内部。
        self.stream.close(self.io);
        self.runtime.deinit();
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
        var payload: [4]u8 = undefined;
        const payload_len = try codec.encodeReadRegisters(payload[0..], function, start_address, quantity);
        const parsed = try self.exchange(function, payload[0..payload_len]);

        // 为了让调用方 API 更直接，这里由库分配结果缓冲区，外部只需要负责释放。
        const registers = try allocator.alloc(u16, quantity);
        errdefer allocator.free(registers);

        const count = try codec.decodeRegisterPayload(parsed.payload, registers);
        return registers[0..count];
    }

    fn exchangeWrite(self: *TcpClient, function: FunctionCode, payload: []const u8, start_address: u16, expected_tail: u16) !void {
        const parsed = try self.exchange(function, payload);
        try codec.validateWriteAck(parsed.payload, start_address, expected_tail);
    }

    fn exchange(self: *TcpClient, function: FunctionCode, payload: []const u8) !codec.ParsedResponse {
        // 事务号在 Modbus TCP 中由主站递增生成，用于把请求和响应配对。
        const transaction_id = self.nextTransactionId();

        var request: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        const request_len = try codec.buildTcpRequest(request[0..], transaction_id, self.unit_id, function, payload);

        // 这里每次临时构造 writer，逻辑最直观，也便于后续替换成更高级的连接复用策略。
        var writer_buffer: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        var writer = self.stream.writer(self.io, writer_buffer[0..]);
        try writer.writeAll(request[0..request_len]);
        try writer.flush();

        var response: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        const response_len = try self.readAdu(response[0..]);
        return codec.parseTcpResponse(response[0..response_len], transaction_id, self.unit_id, function);
    }

    fn readAdu(self: *TcpClient, buffer: []u8) !usize {
        // 先读固定长度的 MBAP 头，再根据 length 字段补齐剩余 PDU。
        try self.readExact(buffer[0..7]);

        const length = std.mem.readInt(u16, @ptrCast(buffer[4..6]), .big);
        if (length < 2) return error.InvalidLengthField;

        const remain = @as(usize, length) - 1;
        const total_len = 7 + remain;
        if (buffer.len < total_len) return error.BufferTooSmall;

        try self.readExact(buffer[7..total_len]);
        return total_len;
    }

    fn readExact(self: *TcpClient, buffer: []u8) !void {
        // Modbus 帧长度明确，Reader.take(n) 很适合用来读取“恰好 n 字节”的协议数据。
        var reader_buffer: [codec.Limits.max_tcp_adu_size]u8 = undefined;
        var reader = self.stream.reader(self.io, reader_buffer[0..]);
        const bytes = try reader.take(buffer.len);
        @memcpy(buffer, bytes);
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
