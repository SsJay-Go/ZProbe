const connection_routes = @import("./connection_routes.zig");
const modbus_routes = @import("./modbus_routes.zig");
const system_routes = @import("./system_routes.zig");

/// 路由总入口。
/// app 层只依赖这一个入口，便于后续按业务域扩展。
pub fn registerAll(router: anytype) void {
    system_routes.register(router);
    connection_routes.register(router);
    modbus_routes.register(router);
}
