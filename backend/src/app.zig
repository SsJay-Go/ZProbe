const std = @import("std");
const httpz = @import("httpz");
const routes = @import("./routes/index.zig");
const context = @import("./context.zig");
const connection_pool = @import("./services/connection_pool.zig");
const traffic_log = @import("./services/traffic_log.zig");
const libmodbus = @import("./protocol_bindings/libmodbus.zig");

const Cors = httpz.middleware.Cors;

/// 应用启动与生命周期管理。
/// main 只负责调用 run，所有服务初始化都下沉到 app 层，便于测试与扩展。
pub fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    // 初始化应用上下文，其中包含全局连接池。
    // 注意：app 是一个栈变量，后面通过 &app 把指针传给 httpz。
    // httpz 框架在整个 listen() 期间都会持有并使用这个指针，
    // 所以 app 必须在 server.deinit() 之前保持有效（在同一作用域内声明即可）。
    var app = context.App{
        .pool = connection_pool.ConnectionPool.init(allocator),
        .traffic_log = traffic_log.TrafficLog.init(allocator),
    };
    // defer 确保无论 run 函数如何退出（正常 return 或返回错误），
    // 都会释放连接池中所有连接及其关联内存，避免资源泄漏。
    defer app.pool.deinit();
    defer app.traffic_log.deinit();

    libmodbus.installTraceLog(&app.traffic_log);
    defer libmodbus.uninstallTraceLog();

    // httpz.Server(*context.App)：
    //   将 *context.App 作为 Handler 类型参数。
    //   框架每次分发请求时，会把 &app 作为第一个参数传给对应的路由处理函数。
    //   这样所有控制器都能通过 app.pool 访问全局连接池，而不依赖全局变量。
    //
    // 与之前 Server(void) 的区别：
    //   Server(void) → 处理函数签名：fn(req, res) !void
    //   Server(*App) → 处理函数签名：fn(app: *App, req, res) !void
    var server = try httpz.Server(*context.App).init(init.io, allocator, .{
        .address = .localhost(8080),
        .timeout = .{
            .request = 10,
            .keepalive = 30,

            .request_count = 1,
        },
    }, &app);
    defer {
        server.stop();
        server.deinit();
    }

    // 当前前端开发环境和后续桌面壳联调都需要跨域访问后端，
    // 因此在入口统一挂载 CORS，中间件会自动处理普通请求和 OPTIONS 预检。
    const cors = try server.middleware(Cors, .{
        .origin = "*",
        .headers = "Content-Type, Authorization, X-Requested-With",
        .methods = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        .max_age = "86400",
    });

    const router = try server.router(.{});
    router.middlewares = &.{cors};
    routes.registerAll(router);

    std.debug.print("Server listening on http://localhost:8080\n", .{});
    try server.listen();
}
