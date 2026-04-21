const httpz = @import("httpz");

/// Modbus 读取控制器（占位）。
/// 后续将在 service 层补齐 FC01~FC04 的真实协议处理。
pub fn readRegisters(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .success = true, .data = &[_]u16{ 0, 0, 0, 0, 0 } }, .{});
}

/// Modbus 写入控制器（占位）。
/// 后续将在 service 层补齐 FC05/FC06/FC0F/FC10 的真实协议处理。
pub fn writeRegister(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .success = true }, .{});
}
