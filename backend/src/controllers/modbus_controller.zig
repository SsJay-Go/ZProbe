const httpz = @import("httpz");
const context = @import("../context.zig");
const connection_model = @import("../models/connection.zig");
const model = @import("../models/modbus.zig");
const service = @import("../services/modbus_service.zig");
const controller_helpers = @import("./controller_helpers.zig");

/// Modbus 读控制器。
///
/// 当前统一承载 FC01 / FC02 / FC03 / FC04 四类读取，
/// 具体读的是 bit 还是寄存器，由请求里的 target 决定。
pub fn readRegisters(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_payload = try req.json(model.ReadRequest);
    if (maybe_payload == null) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    service.validateReadRequest(payload) catch |err| {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    const registers = service.read(&app.pool, req.arena, payload) catch |err| {
        controller_helpers.closeAfterResponse(res);

        switch (err) {
            error.ConnectionNotFound => res.setStatus(.not_found),
            error.TransportNotSupported => res.setStatus(.not_implemented),
            error.ModbusOperationFailed => res.setStatus(.bad_gateway),
            else => res.setStatus(.bad_request),
        }

        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    controller_helpers.closeAfterResponse(res);
    try res.json(model.makeReadSuccessForTarget(payload.target, registers), .{});
}

/// Modbus 写控制器。
///
/// 当前统一承载 FC05 / FC06 / FC0F / FC10 四类写入。
pub fn writeRegister(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_payload = try req.json(model.WriteRequest);
    if (maybe_payload == null) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    service.validateWriteRequest(payload) catch |err| {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    const written_count = service.write(&app.pool, req.arena, payload) catch |err| {
        controller_helpers.closeAfterResponse(res);

        switch (err) {
            error.ConnectionNotFound => res.setStatus(.not_found),
            error.TransportNotSupported => res.setStatus(.not_implemented),
            error.ModbusOperationFailed => res.setStatus(.bad_gateway),
            else => res.setStatus(.bad_request),
        }

        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    controller_helpers.closeAfterResponse(res);
    try res.json(model.makeWriteSuccess(written_count), .{});
}

/// FC17 读写多寄存器控制器。
pub fn writeAndReadRegisters(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_payload = try req.json(model.WriteReadRequest);
    if (maybe_payload == null) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    service.validateWriteReadRequest(payload) catch |err| {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    const values = service.writeAndRead(&app.pool, req.arena, payload) catch |err| {
        controller_helpers.closeAfterResponse(res);

        switch (err) {
            error.ConnectionNotFound => res.setStatus(.not_found),
            error.TransportNotSupported => res.setStatus(.not_implemented),
            error.ModbusOperationFailed => res.setStatus(.bad_gateway),
            else => res.setStatus(.bad_request),
        }

        try res.json(connection_model.makeError(service.errorMessage(err)), .{});
        return;
    };

    controller_helpers.closeAfterResponse(res);
    try res.json(model.makeWriteReadSuccess(values), .{});
}
