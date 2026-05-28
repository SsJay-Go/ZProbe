const std = @import("std");
const model = @import("../models/connection.zig");
const connection_pool = @import("./connection_pool.zig");
const tcp_transport = @import("../transports/tcp_transport.zig");
const rtu_transport = @import("../transports/rtu_transport.zig");

/// 校验统一 connect 请求。
pub fn validateConnectRequest(payload: model.ConnectRequest) model.ConnectValidationError!void {
    const transport = model.parseTransportKind(payload.type) orelse return error.InvalidConnectionType;

    if (payload.name.len == 0 or payload.name.len > 32) {
        return error.InvalidConnectionName;
    }
    if (payload.slaveId < 1 or payload.slaveId > 247) {
        return error.InvalidSlaveId;
    }
    if (payload.timeoutMs < 100 or payload.timeoutMs > 120_000) {
        return error.InvalidTimeout;
    }
    if (payload.retryCount > 10) {
        return error.InvalidRetryCount;
    }

    switch (transport) {
        .tcp => {
            const host = payload.host orelse return error.InvalidHost;
            const port = payload.port orelse return error.InvalidPort;
            if (host.len == 0 or host.len > 255) {
                return error.InvalidHost;
            }
            if (port == 0) {
                return error.InvalidPort;
            }
        },
        .rtu => {
            const serial_port = payload.serialPort orelse return error.InvalidSerialPort;
            const baud_rate = payload.baudRate orelse return error.InvalidBaudRate;
            const data_bits = payload.dataBits orelse return error.InvalidDataBits;
            const stop_bits = payload.stopBits orelse return error.InvalidStopBits;
            _ = payload.parity orelse return error.InvalidConnectionType;

            if (serial_port.len == 0 or serial_port.len > 260) {
                return error.InvalidSerialPort;
            }
            if (baud_rate == 0) {
                return error.InvalidBaudRate;
            }
            if (data_bits < 5 or data_bits > 8) {
                return error.InvalidDataBits;
            }
            if (stop_bits < 1 or stop_bits > 2) {
                return error.InvalidStopBits;
            }
        },
        .ascii => return error.UnsupportedTransport,
    }
}

/// 根据连接参数生成稳定连接 ID。
///
/// 后续即使接入 RTU / ASCII，也可以继续沿用“transport 前缀 + 参数哈希”这个模式。
pub fn buildConnectionId(payload: model.ConnectRequest, id_buf: []u8) ![]const u8 {
    const transport = model.parseTransportKind(payload.type) orelse return error.InvalidConnectionType;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(payload.type);
    hasher.update(payload.name);
    hasher.update(std.mem.asBytes(&payload.slaveId));
    switch (transport) {
        .tcp => {
            const host = payload.host orelse return error.InvalidHost;
            const port = payload.port orelse return error.InvalidPort;
            hasher.update(host);
            hasher.update(std.mem.asBytes(&port));
        },
        .rtu => {
            const serial_port = payload.serialPort orelse return error.InvalidSerialPort;
            const baud_rate = payload.baudRate orelse return error.InvalidBaudRate;
            const data_bits = payload.dataBits orelse return error.InvalidDataBits;
            const stop_bits = payload.stopBits orelse return error.InvalidStopBits;
            const parity = payload.parity orelse return error.InvalidConnectionType;
            hasher.update(serial_port);
            hasher.update(std.mem.asBytes(&baud_rate));
            hasher.update(std.mem.asBytes(&data_bits));
            hasher.update(@tagName(parity));
            hasher.update(std.mem.asBytes(&stop_bits));
        },
        .ascii => return error.UnsupportedTransport,
    }
    // hasher.final() 会返回一个 u64 哈希值，我们把它格式化成十六进制字符串，拼接上 "tcp-" 前缀，构成最终的连接 ID。
    const h = hasher.final();

    return std.fmt.bufPrint(id_buf, "{s}-{x}", .{ payload.type, h });
}

/// 创建一条完整的 TCP 连接记录。
///
/// 这一步既会建立底层 Modbus TCP 客户端，也会把元数据复制成“长生命周期拥有内存”，
/// 从而让这份记录可以安全放进连接注册表，而不依赖 req.arena。
pub fn createTcpConnectionRecord(
    allocator: std.mem.Allocator,
    connection_id: []const u8,
    payload: model.ConnectRequest,
) model.ConnectCreateError!connection_pool.ConnectionRecord {
    const client = tcp_transport.connect(allocator, .{
        .host = payload.host.?,
        .port = payload.port.?,
        .slaveId = payload.slaveId,
        .timeoutMs = payload.timeoutMs,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TcpConnectFailed,
    };
    errdefer {
        client.deinit();
        allocator.destroy(client);
    }
    // 为了把短生命周期数据，转成长生命周期自有数据，必须在这里复制一份。
    const owned_id = try allocator.dupe(u8, connection_id);
    errdefer allocator.free(owned_id);

    const owned_name = try allocator.dupe(u8, payload.name);
    errdefer allocator.free(owned_name);

    const owned_host = try allocator.dupe(u8, payload.host.?);
    errdefer allocator.free(owned_host);

    return .{
        .id = owned_id,
        .name = owned_name,
        .transport = .tcp,
        .slave_id = payload.slaveId,
        .timeout_ms = payload.timeoutMs,
        .retry_count = payload.retryCount,
        .details = .{
            .tcp = .{
                .host = owned_host,
                .port = payload.port.?,
            },
        },
        .handle = .{ .tcp = client },
    };
}

pub fn createRtuConnectionRecord(
    allocator: std.mem.Allocator,
    connection_id: []const u8,
    payload: model.ConnectRequest,
) model.ConnectCreateError!connection_pool.ConnectionRecord {
    const client = rtu_transport.connect(allocator, .{
        .serialPort = payload.serialPort.?,
        .baudRate = payload.baudRate.?,
        .dataBits = payload.dataBits.?,
        .parity = payload.parity.?,
        .stopBits = payload.stopBits.?,
        .slaveId = payload.slaveId,
        .timeoutMs = payload.timeoutMs,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.RtuConnectFailed,
    };
    errdefer {
        client.deinit();
        allocator.destroy(client);
    }

    const owned_id = try allocator.dupe(u8, connection_id);
    errdefer allocator.free(owned_id);

    const owned_name = try allocator.dupe(u8, payload.name);
    errdefer allocator.free(owned_name);

    const owned_serial_port = try allocator.dupe(u8, payload.serialPort.?);
    errdefer allocator.free(owned_serial_port);

    return .{
        .id = owned_id,
        .name = owned_name,
        .transport = .rtu,
        .slave_id = payload.slaveId,
        .timeout_ms = payload.timeoutMs,
        .retry_count = payload.retryCount,
        .details = .{
            .rtu = .{
                .serialPort = owned_serial_port,
                .baudRate = payload.baudRate.?,
                .dataBits = payload.dataBits.?,
                .parity = payload.parity.?,
                .stopBits = payload.stopBits.?,
            },
        },
        .handle = .{ .rtu = client },
    };
}

pub fn createConnectionRecord(
    allocator: std.mem.Allocator,
    connection_id: []const u8,
    payload: model.ConnectRequest,
) model.ConnectCreateError!connection_pool.ConnectionRecord {
    const transport = model.parseTransportKind(payload.type) orelse return error.TransportNotImplemented;
    return switch (transport) {
        .tcp => createTcpConnectionRecord(allocator, connection_id, payload),
        .rtu => createRtuConnectionRecord(allocator, connection_id, payload),
        .ascii => error.TransportNotImplemented,
    };
}

pub fn validationErrorMessage(err: model.ConnectValidationError) []const u8 {
    return switch (err) {
        error.InvalidConnectionType => "连接类型无效",
        error.UnsupportedTransport => "libmodbus 当前只接入了 TCP 和 RTU，ASCII 尚未支持",
        error.InvalidConnectionName => "连接名称长度必须在 1~32 之间",
        error.InvalidHost => "主机地址不能为空且长度不能超过 255",
        error.InvalidPort => "TCP 端口必须大于 0",
        error.InvalidSerialPort => "串口路径不能为空且长度不能超过 260",
        error.InvalidBaudRate => "波特率必须大于 0",
        error.InvalidDataBits => "数据位范围必须为 5~8",
        error.InvalidStopBits => "停止位范围必须为 1~2",
        error.InvalidSlaveId => "Slave ID 范围必须为 1~247",
        error.InvalidTimeout => "超时范围必须为 100~120000 ms",
        error.InvalidRetryCount => "重试次数范围必须为 0~10",
    };
}

pub fn createErrorMessage(err: model.ConnectCreateError) []const u8 {
    return switch (err) {
        error.OutOfMemory => "服务器内存不足，无法创建连接记录",
        error.TcpConnectFailed => "Modbus TCP 连接建立失败，请检查目标主机、端口和设备状态",
        error.RtuConnectFailed => "Modbus RTU 连接建立失败，请检查串口参数、占用状态和设备连线",
        error.TransportNotImplemented => "当前传输类型尚未接入底层实现",
    };
}
