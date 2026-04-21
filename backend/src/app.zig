const std = @import("std");
const httpz = @import("httpz");
const routes = @import("./routes/index.zig");

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

    const router = try server.router(.{});
    routes.registerAll(router);

    std.debug.print("Server listening on http://localhost:8080\n", .{});
    try server.listen();
}
