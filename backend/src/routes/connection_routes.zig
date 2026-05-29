const connection_controller = @import("../controllers/connection_controller.zig");
const route_helpers = @import("./route_helpers.zig");

/// 连接域路由注册。
/// 按业务域拆分路由文件，避免单文件持续膨胀。
pub fn register(router: anytype) void {
    route_helpers.registerPostWithPreflight(router, "/api/connection/connect", connection_controller.connect);
    route_helpers.registerPostWithPreflight(router, "/api/connection/disconnect", connection_controller.disconnect);
    router.get("/api/connection/state/:id", connection_controller.status, .{});
}
