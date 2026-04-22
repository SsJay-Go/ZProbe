const httpz = @import("httpz");
const model = @import("../models/connection.zig");
const service = @import("../services/connection_service.zig");

/// 连接控制器：负责 HTTP 协议层与业务服务层的衔接。
/// Node.js 语境里可理解为 controller（不承载核心业务规则）。
pub fn connect(req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_payload = try req.json(model.TcpConnectRequest);
    if (maybe_payload == null) {
        res.setStatus(.bad_request);
        try res.json(model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    service.validateTcpConnectRequest(payload) catch |err| {
        res.setStatus(.bad_request);
        try res.json(model.makeError(service.validationErrorMessage(err)), .{});
        return;
    };

    var id_buf: [40]u8 = undefined;
    const connection_id = try service.buildConnectionId(payload, &id_buf);

    const connection: model.ConnectionInfo = .{
        .id = connection_id,
        .name = payload.name,
        .host = payload.host,
        .port = payload.port,
        .slaveId = payload.slaveId,
        .timeoutMs = payload.timeoutMs,
        .retryCount = payload.retryCount,
    };

    try res.json(model.makeConnectSuccess(connection), .{});
}

/// 断开连接控制器。
/// 当前先返回占位结果，后续接入连接池后可根据 connectionId 执行真实断连。
pub fn disconnect(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .success = true, .message = "disconnected" }, .{});
}
