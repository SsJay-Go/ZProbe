const httpz = @import("httpz");

/// 控制器公共辅助函数。
///
/// 目前最重要的职责，是在 connect / disconnect / modbus 读写这些敏感接口上
/// 显式关闭当前 HTTP 连接，避免浏览器在当前环境下复用旧连接而导致下一次请求超时。
pub fn closeAfterResponse(res: *httpz.Response) void {
    res.keepalive = false;
    res.conn.handover = .close;
}
