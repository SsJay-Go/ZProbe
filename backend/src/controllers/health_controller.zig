const httpz = @import("httpz");
const context = @import("../context.zig");
const controller_helpers = @import("./controller_helpers.zig");
const traffic_log = @import("../services/traffic_log.zig");

/// 系统健康检查控制器。
/// 用于探活、部署检查和本地联调。
/// 第一个参数 _: *context.App 是框架注入的共享上下文，此接口无需使用故忽略。
pub fn health(_: *context.App, _: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .status = "ok" }, .{});
}

pub fn traffic(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const entries = try app.traffic_log.snapshotAlloc(req.arena);
    controller_helpers.closeAfterResponse(res);
    try res.json(traffic_log.TrafficLogResponse{ .entries = entries }, .{});
}

pub fn clearTraffic(app: *context.App, _: *httpz.Request, res: *httpz.Response) !void {
    app.traffic_log.clear();
    controller_helpers.closeAfterResponse(res);
    try res.json(.{ .success = true, .message = "日志已清空" }, .{});
}
