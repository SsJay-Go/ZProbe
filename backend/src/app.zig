const std = @import("std");
const httpz = @import("httpz");
const routes = @import("./routes/index.zig");

const Cors = httpz.middleware.Cors;

/// 应用启动与生命周期管理。
/// main 只负责调用 run，所有服务初始化都下沉到 app 层，便于测试与扩展。
pub fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    var server = try httpz.Server(void).init(init.io, allocator, .{
        .address = .localhost(8080),
        .timeout = .{
            .request = 10,
            .keepalive = 30,
            .request_count = 100,
        },
    }, {});
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
