const httpz = @import("httpz");

/// 系统健康检查控制器。
/// 用于探活、部署检查和本地联调。
pub fn health(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .status = "ok" }, .{});
}
