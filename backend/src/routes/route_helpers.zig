const httpz = @import("httpz");
const context = @import("../context.zig");

/// 统一的 OPTIONS 预检响应处理函数。
/// 浏览器在跨域请求前会先发一个 OPTIONS 预检（preflight）请求，
/// 若没有路由命中，httpz 的 CORS middleware 不会被触发，跨域就会失败。
/// 这个函数只需返回 204，让请求能命中路由链并经过 middleware 补全跨域头。
///
/// 第一个参数类型必须与 Server(*context.App) 的泛型参数一致，
/// 否则注册到 router.options 时类型不匹配，编译报错。
pub fn preflight(_: *context.App, _: *httpz.Request, res: *httpz.Response) !void {
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
