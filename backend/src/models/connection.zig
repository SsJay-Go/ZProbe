const std = @import("std");

/// 传输类型枚举。
///
/// 当前阶段真正落地的是 tcp；
/// rtu / ascii 先把类型与配置结构立起来，后面新增实现时不用再改业务边界。
pub const TransportKind = enum {
    tcp,
    rtu,
    ascii,
};

/// 串口类传输会共用的校验项。
///
/// 先把枚举放在模型层，后续 RTU / ASCII 接入时前后端字段可以直接复用。
pub const SerialParity = enum {
    none,
    even,
    odd,
};

/// 前端提交的“新建 TCP 连接”参数。
///
/// 这次重构先把 TCP 做实，因此当前 connect 接口仍然接受这份 payload。
/// 后续若要同时支持 RTU / ASCII，可再新增独立请求模型或泛型 connect payload。
pub const ConnectRequest = struct {
    type: []const u8,
    name: []const u8,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    serialPort: ?[]const u8 = null,
    baudRate: ?u32 = null,
    dataBits: ?u8 = null,
    parity: ?SerialParity = null,
    stopBits: ?u8 = null,
    slaveId: u8,
    timeoutMs: u32,
    retryCount: u8,
};

/// TCP 连接的展示信息。
pub const TcpConnectionDetails = struct {
    host: []const u8,
    port: u16,
};

/// RTU 连接的展示信息。
pub const RtuConnectionDetails = struct {
    serialPort: []const u8,
    baudRate: u32,
    dataBits: u8,
    parity: SerialParity,
    stopBits: u8,
};

/// ASCII 连接的展示信息。
pub const AsciiConnectionDetails = struct {
    serialPort: []const u8,
    baudRate: u32,
    dataBits: u8,
    parity: SerialParity,
    stopBits: u8,
};

/// 统一的连接细节视图。
///
/// 业务层只需要知道“当前这条连接属于哪个传输类型”，
/// 然后再从对应分支里读取细节字段，不再把 TCP / RTU / ASCII 的字段混在一个大 struct 里。
pub const ConnectionDetails = union(TransportKind) {
    tcp: TcpConnectionDetails,
    rtu: RtuConnectionDetails,
    ascii: AsciiConnectionDetails,
};

/// 统一的连接信息回执。
///
/// 与旧版本相比，这里不再把 host / port 等字段平铺在最外层，
/// 而是放进 details 里，让“公共字段”和“传输特有字段”分层清晰。
pub const ConnectionInfo = struct {
    id: []const u8,
    name: []const u8,
    transport: TransportKind,
    slaveId: u8,
    timeoutMs: u32,
    retryCount: u8,
    details: ConnectionDetails,
};

/// 统一的 connect 成功响应。
pub const ConnectSuccessResponse = struct {
    success: bool,
    message: []const u8,
    connection: ConnectionInfo,
};

pub const ConnectionStatusResponse = struct {
    success: bool,
    connected: bool,
    connection: ?ConnectionInfo = null,
};

/// 统一的 API 失败响应模型。
pub const ErrorResponse = struct {
    success: bool,
    message: []const u8,
};

/// 只负责“请求参数是否合法”的错误集合。
///
/// 这类错误会映射成 400 Bad Request，因为问题在调用方输入。
pub const ConnectValidationError = error{
    InvalidConnectionType,
    UnsupportedTransport,
    InvalidConnectionName,
    InvalidHost,
    InvalidPort,
    InvalidSerialPort,
    InvalidBaudRate,
    InvalidDataBits,
    InvalidStopBits,
    InvalidSlaveId,
    InvalidTimeout,
    InvalidRetryCount,
};

/// 负责“真正创建连接”阶段的错误集合。
///
/// 这类错误表示参数已经合法，但底层传输层或内存分配失败。
pub const ConnectCreateError = std.mem.Allocator.Error || error{
    TcpConnectFailed,
    RtuConnectFailed,
    TransportNotImplemented,
};

/// 前端提交的“断开连接”参数。
pub const DisconnectRequest = struct {
    connectionId: []const u8,
};

/// 把字符串形式的 type 转成强类型枚举。
///
/// 当前请求体里 type 仍然是字符串，这是为了兼容 JSON 的直观写法。
pub fn parseTransportKind(raw: []const u8) ?TransportKind {
    if (std.mem.eql(u8, raw, "tcp")) return .tcp;
    if (std.mem.eql(u8, raw, "rtu")) return .rtu;
    if (std.mem.eql(u8, raw, "ascii")) return .ascii;
    return null;
}

pub fn makeConnectSuccess(connection: ConnectionInfo) ConnectSuccessResponse {
    return .{
        .success = true,
        .message = "连接已建立",
        .connection = connection,
    };
}

pub fn makeConnectionStatus(connection: ?ConnectionInfo) ConnectionStatusResponse {
    return .{
        .success = true,
        .connected = connection != null,
        .connection = connection,
    };
}

pub fn makeError(message: []const u8) ErrorResponse {
    return .{
        .success = false,
        .message = message,
    };
}
