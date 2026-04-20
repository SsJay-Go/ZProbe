const std = @import("std");
const httpz = @import("httpz");

pub fn main(init: std.process.Init) !void {
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

    var router = try server.router(.{});

    // API routes
    router.get("/api/health", health, .{});
    router.post("/api/connection/connect", connectDevice, .{});
    router.post("/api/connection/disconnect", disconnectDevice, .{});
    router.post("/api/modbus/read", readRegisters, .{});
    router.post("/api/modbus/write", writeRegister, .{});

    std.debug.print("Server listening on http://localhost:8080\n", .{});
    try server.listen();
}

fn health(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .status = "ok" }, .{});
}

fn connectDevice(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    // TODO: implement actual Modbus TCP/RTU connection
    try res.json(.{ .success = true, .message = "connected" }, .{});
}

fn disconnectDevice(_: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .success = true, .message = "disconnected" }, .{});
}

fn readRegisters(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    // TODO: implement actual Modbus read (FC 01-04)
    try res.json(.{ .success = true, .data = &[_]u16{ 0, 0, 0, 0, 0 } }, .{});
}

fn writeRegister(req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    // TODO: implement actual Modbus write (FC 05,06,15,16)
    try res.json(.{ .success = true }, .{});
}
