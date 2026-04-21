const std = @import("std");
const model = @import("../models/connection.zig");

pub fn validateTcpConnectRequest(payload: model.TcpConnectRequest) model.ConnectValidationError!void {
    // 类型校验：避免未来扩展 RTU/ASCII 时误走 TCP 逻辑。
    if (!std.mem.eql(u8, payload.type, "tcp")) {
        return error.InvalidConnectionType;
    }

    // 基础可读性与地址合法性约束。
    if (payload.name.len == 0 or payload.name.len > 32) {
        return error.InvalidConnectionName;
    }
    if (payload.host.len == 0 or payload.host.len > 255) {
        return error.InvalidHost;
    }

    // Modbus 从站地址常见范围。
    if (payload.slaveId < 1 or payload.slaveId > 247) {
        return error.InvalidSlaveId;
    }

    // 超时与重试属于系统保护参数，限制范围可防止异常配置造成资源浪费。
    if (payload.timeoutMs < 100 or payload.timeoutMs > 120_000) {
        return error.InvalidTimeout;
    }
    if (payload.retryCount > 10) {
        return error.InvalidRetryCount;
    }
}

pub fn buildConnectionId(payload: model.TcpConnectRequest, id_buf: []u8) ![]const u8 {
    // 使用稳定哈希构造演示连接 ID。
    // 后续接入真实连接池后可替换为 UUID / 雪花 ID。
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(payload.name);
    hasher.update(payload.host);
    hasher.update(std.mem.asBytes(&payload.port));
    hasher.update(std.mem.asBytes(&payload.slaveId));
    const h = hasher.final();

    return std.fmt.bufPrint(id_buf, "tcp-{x}", .{h});
}

pub fn validationErrorMessage(err: model.ConnectValidationError) []const u8 {
    return switch (err) {
        error.InvalidConnectionType => "连接类型必须为 tcp",
        error.InvalidConnectionName => "连接名称长度必须在 1~32 之间",
        error.InvalidHost => "主机地址不能为空且长度不能超过 255",
        error.InvalidSlaveId => "Slave ID 范围必须为 1~247",
        error.InvalidTimeout => "超时范围必须为 100~120000 ms",
        error.InvalidRetryCount => "重试次数范围必须为 0~10",
    };
}
