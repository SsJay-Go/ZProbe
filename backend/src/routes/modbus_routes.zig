const modbus_controller = @import("../controllers/modbus_controller.zig");

/// Modbus 域路由注册。
pub fn register(router: anytype) void {
    router.post("/api/modbus/read", modbus_controller.readRegisters, .{});
    router.post("/api/modbus/write", modbus_controller.writeRegister, .{});
}
