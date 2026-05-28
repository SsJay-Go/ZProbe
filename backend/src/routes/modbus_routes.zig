const modbus_controller = @import("../controllers/modbus_controller.zig");
const route_helpers = @import("./route_helpers.zig");

/// Modbus 域路由注册。
pub fn register(router: anytype) void {
    route_helpers.registerPostWithPreflight(router, "/api/modbus/read", modbus_controller.readRegisters);
    route_helpers.registerPostWithPreflight(router, "/api/modbus/write", modbus_controller.writeRegister);
    route_helpers.registerPostWithPreflight(router, "/api/modbus/write-read", modbus_controller.writeAndReadRegisters);
}
