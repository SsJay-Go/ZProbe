const httpz = @import("httpz");
const context = @import("../context.zig");

/// 系统健康检查控制器。
/// 用于探活、部署检查和本地联调。
/// 第一个参数 _: *context.App 是框架注入的共享上下文，此接口无需使用故忽略。
pub fn health(_: *context.App, _: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .status = "ok" }, .{});
}
