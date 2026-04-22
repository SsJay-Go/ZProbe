const health_controller = @import("../controllers/health_controller.zig");

/// 系统域路由注册。
pub fn register(router: anytype) void {
    router.get("/api/health", health_controller.health, .{});
}
