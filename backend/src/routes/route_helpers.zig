const httpz = @import("httpz");

/// 统一的预检响应入口。
/// 这里不负责写跨域头，跨域头仍由 app 层挂载的 CORS middleware 统一补齐；
/// 它的职责只是让 OPTIONS 请求命中路由链，从而触发对应 middleware。
pub fn preflight(_: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.no_content);
}

/// 由于当前 httpz 的 middleware 是附着在“已命中的路由”上，
/// 所以浏览器预检请求如果没有对应 OPTIONS 路由，就不会进入 CORS middleware。
/// 这里把 POST 接口常见的“业务路由 + 预检路由”绑定成一个辅助方法，
/// 后续新增 API 时只需要调用一次，避免每个文件手写一对注册语句。
pub fn registerPostWithPreflight(router: anytype, path: []const u8, action: anytype) void {
    router.post(path, action, .{});
    router.options(path, preflight, .{});
}
