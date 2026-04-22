const std = @import("std");

/// 前端提交的“新建 TCP 连接”参数。
/// 字段名与前端 payload 保持一致，便于端到端调试与联调。
pub const TcpConnectRequest = struct {
    type: []const u8,
    name: []const u8,
    host: []const u8,
    port: u16,
    slaveId: u8,
    timeoutMs: u32,
    retryCount: u8,
};

/// 连接信息回执。
/// 当前阶段主要用于“参数已被后端接收并校验”的确认，后续可扩展为真实连接池元数据。
pub const ConnectionInfo = struct {
    id: []const u8,
    name: []const u8,
    host: []const u8,
    port: u16,
    slaveId: u8,
    timeoutMs: u32,
    retryCount: u8,
};

/// 统一的 API 成功响应模型，便于前端稳定消费。
pub const ConnectSuccessResponse = struct {
    success: bool,
    message: []const u8,
    connection: ConnectionInfo,
};

/// 统一的 API 失败响应模型，避免不同接口返回形态不一致。
pub const ErrorResponse = struct {
    success: bool,
    message: []const u8,
};

/// 后端服务层可能抛出的业务错误。
/// 使用强类型错误便于在 handler 层映射成更友好的中文提示。
pub const ConnectValidationError = error{
    InvalidConnectionType,
    InvalidConnectionName,
    InvalidHost,
    InvalidSlaveId,
    InvalidTimeout,
    InvalidRetryCount,
};

pub fn makeConnectSuccess(connection: ConnectionInfo) ConnectSuccessResponse {
    return .{
        .success = true,
        .message = "TCP 连接参数已接收，后端已完成校验",
        .connection = connection,
    };
}

pub fn makeError(message: []const u8) ErrorResponse {
    return .{
        .success = false,
        .message = message,
    };
}
