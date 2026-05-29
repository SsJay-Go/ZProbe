const health_controller = @import("../controllers/health_controller.zig");
const route_helpers = @import("./route_helpers.zig");

/// 系统域路由注册。
pub fn register(router: anytype) void {
    router.get("/api/health", health_controller.health, .{});
    router.get("/api/system/traffic", health_controller.traffic, .{});
    route_helpers.registerPostWithPreflight(router, "/api/system/traffic/clear", health_controller.clearTraffic);
}
