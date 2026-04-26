const std = @import("std");
const model = @import("../models/connection.zig");
const connection_pool = @import("./connection_pool.zig");
const tcp_transport = @import("../transports/tcp_transport.zig");

/// 校验当前阶段仍在使用的 TCP connect 请求。
pub fn validateTcpConnectRequest(payload: model.TcpConnectRequest) model.ConnectValidationError!void {
    const transport = model.parseTransportKind(payload.type) orelse return error.InvalidConnectionType;
    if (transport != .tcp) return error.InvalidConnectionType;

    if (payload.name.len == 0 or payload.name.len > 32) {
        return error.InvalidConnectionName;
    }
    if (payload.host.len == 0 or payload.host.len > 255) {
        return error.InvalidHost;
    }
    if (payload.port == 0) {
        return error.InvalidPort;
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
}

/// 根据连接参数生成稳定连接 ID。
///
/// 后续即使接入 RTU / ASCII，也可以继续沿用“transport 前缀 + 参数哈希”这个模式。
pub fn buildConnectionId(payload: model.TcpConnectRequest, id_buf: []u8) ![]const u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update("tcp");
    hasher.update(payload.name);
    hasher.update(payload.host);
    hasher.update(std.mem.asBytes(&payload.port));
    hasher.update(std.mem.asBytes(&payload.slaveId));
    // hasher.final() 会返回一个 u64 哈希值，我们把它格式化成十六进制字符串，拼接上 "tcp-" 前缀，构成最终的连接 ID。
    const h = hasher.final();

    return std.fmt.bufPrint(id_buf, "tcp-{x}", .{h});
}

/// 创建一条完整的 TCP 连接记录。
///
/// 这一步既会建立底层 Modbus TCP 客户端，也会把元数据复制成“长生命周期拥有内存”，
/// 从而让这份记录可以安全放进连接注册表，而不依赖 req.arena。
pub fn createTcpConnectionRecord(
    allocator: std.mem.Allocator,
    connection_id: []const u8,
    payload: model.TcpConnectRequest,
) model.ConnectCreateError!connection_pool.ConnectionRecord {
    const client = tcp_transport.connect(allocator, .{
        .host = payload.host,
        .port = payload.port,
        .slaveId = payload.slaveId,
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

    const owned_host = try allocator.dupe(u8, payload.host);
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
                .port = payload.port,
            },
        },
        .handle = .{ .tcp = client },
    };
}

pub fn validationErrorMessage(err: model.ConnectValidationError) []const u8 {
    return switch (err) {
        error.InvalidConnectionType => "当前接口只接受 tcp 类型连接",
        error.InvalidConnectionName => "连接名称长度必须在 1~32 之间",
        error.InvalidHost => "主机地址不能为空且长度不能超过 255",
        error.InvalidPort => "TCP 端口必须大于 0",
        error.InvalidSlaveId => "Slave ID 范围必须为 1~247",
        error.InvalidTimeout => "超时范围必须为 100~120000 ms",
        error.InvalidRetryCount => "重试次数范围必须为 0~10",
    };
}

pub fn createErrorMessage(err: model.ConnectCreateError) []const u8 {
    return switch (err) {
        error.OutOfMemory => "服务器内存不足，无法创建连接记录",
        error.TcpConnectFailed => "Modbus TCP 连接建立失败，请检查目标主机、端口和设备状态",
        error.TransportNotImplemented => "当前传输类型尚未接入底层实现",
    };
}
