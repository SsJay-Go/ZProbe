const connection_pool = @import("services/connection_pool.zig");

/// 应用级共享上下文（httpz Handler 类型）。
///
/// ── httpz 的泛型 Server 机制 ────────────────────────────────────
/// httpz.Server(T) 中的类型参数 T 决定了"Handler"类型。
/// 框架在分发每个 HTTP 请求时，会把 &handler 作为第一个参数传给路由处理函数。
///
/// 当 T = void 时（默认简单模式），处理函数签名为：
///   fn(req: *httpz.Request, res: *httpz.Response) !void
///
/// 当 T = *App 时（带共享状态模式），处理函数签名为：
///   fn(app: *App, req: *httpz.Request, res: *httpz.Response) !void
///
/// 这是 Zig 中"依赖注入"的惯用写法：
///   不使用全局变量，而是通过参数将共享状态显式传递给每个函数，
///   代码的数据流向清晰可见，也便于测试时替换不同的实现。
pub const App = struct {
    /// 全局连接注册表。
    ///
    /// 当前真正落地的是 TCP 连接；
    /// 但字段类型已经不再绑定到某一个 transport，后续可以平滑接入 RTU / ASCII。
    /// 在 app.zig 中初始化，由 httpz 框架注入到每个请求处理函数中。
    pool: connection_pool.ConnectionPool,
};
