const connection_controller = @import("../controllers/connection_controller.zig");

/// 连接域路由注册。
/// 按业务域拆分路由文件，避免单文件持续膨胀。
pub fn register(router: anytype) void {
    router.post("/api/connection/connect", connection_controller.connect, .{});
    router.post("/api/connection/disconnect", connection_controller.disconnect, .{});
}
