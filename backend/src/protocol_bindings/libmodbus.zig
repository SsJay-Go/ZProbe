const std = @import("std");
const traffic_log = @import("../services/traffic_log.zig");

pub const c = @cImport({
    @cDefine("FD_SETSIZE", "1024");
    @cInclude("modbus.h");
    @cInclude("modbus-rtu.h");
    @cInclude("modbus-tcp.h");
});

var trace_log: ?*traffic_log.TrafficLog = null;

pub fn installTraceLog(log: *traffic_log.TrafficLog) void {
    trace_log = log;
    c.modbus_set_trace_hook(zprobeModbusTraceHook);
}

pub fn uninstallTraceLog() void {
    trace_log = null;
    c.modbus_set_trace_hook(null);
}

export fn zprobeModbusTraceHook(direction: c_int, backend_type: c_int, frame: [*c]const u8, frame_length: c_int) callconv(.c) void {
    const log = trace_log orelse return;
    if (frame == null or frame_length <= 0) return;

    const trace_direction: traffic_log.Direction = if (direction == c.MODBUS_TRACE_SEND) .send else .recv;
    const category = if (backend_type == 0) "rtu.frame" else "tcp.frame";

    var buffer: [1536]u8 = undefined;
    const bytes = frame[0..@intCast(frame_length)];
    const rendered = renderFrameHex(&buffer, bytes) catch return;
    log.append(category, trace_direction, rendered);
}

fn renderFrameHex(buffer: []u8, frame: []const u8) ![]const u8 {
    var used: usize = 0;

    for (frame, 0..) |byte, index| {
        if (index != 0) {
            buffer[used] = ' ';
            used += 1;
        }
        const written = try std.fmt.bufPrint(buffer[used..], "{X:0>2}", .{byte});
        used += written.len;
    }

    return buffer[0..used];
}

pub const ConnectError = error{
    OutOfMemory,
    InvalidUnitId,
    InvalidSerialConfig,
    ConnectFailed,
};

pub const ModbusError = error{
    OutOfMemory,
    InvalidQuantity,
    InvalidValue,
    ReadFailed,
    WriteFailed,
};

pub const Client = struct {
    ctx: *c.modbus_t,

    pub const TcpConnectOptions = struct {
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16 = c.MODBUS_TCP_DEFAULT_PORT,
        unit_id: u8 = 1,
        timeout_ms: u32 = 1000,
    };

    pub const RtuConnectOptions = struct {
        allocator: std.mem.Allocator,
        device: []const u8,
        baud_rate: u32,
        parity: u8,
        data_bits: u8,
        stop_bits: u8,
        unit_id: u8 = 1,
        timeout_ms: u32 = 1000,
    };

    pub fn connectTcp(options: TcpConnectOptions) ConnectError!Client {
        if (options.unit_id == 0 or options.unit_id > 247) {
            return error.InvalidUnitId;
        }

        const host_z = try options.allocator.dupeZ(u8, options.host);
        defer options.allocator.free(host_z);

        var service_buf: [6:0]u8 = undefined;
        const service_z = std.fmt.bufPrintZ(&service_buf, "{d}", .{options.port}) catch unreachable;

        const maybe_ctx = if (isIpv4Literal(options.host))
            c.modbus_new_tcp(host_z.ptr, options.port)
        else
            c.modbus_new_tcp_pi(host_z.ptr, service_z.ptr);
        const ctx = maybe_ctx orelse {
            logLibmodbusFailure("new_tcp_context");
            return error.ConnectFailed;
        };
        errdefer c.modbus_free(ctx);

        if (c.modbus_set_slave(ctx, options.unit_id) == -1) {
            logLibmodbusFailure("set_slave");
            return error.ConnectFailed;
        }

        const timeout_sec = options.timeout_ms / 1000;
        const timeout_usec = (options.timeout_ms % 1000) * 1000;
        if (c.modbus_set_response_timeout(ctx, timeout_sec, timeout_usec) == -1) {
            logLibmodbusFailure("set_response_timeout");
            return error.ConnectFailed;
        }

        if (c.modbus_connect(ctx) == -1) {
            logLibmodbusFailure("connect");
            return error.ConnectFailed;
        }

        return .{ .ctx = ctx };
    }

    pub fn connectRtu(options: RtuConnectOptions) ConnectError!Client {
        if (options.unit_id == 0 or options.unit_id > 247) {
            return error.InvalidUnitId;
        }
        if (options.device.len == 0 or options.baud_rate == 0) {
            return error.InvalidSerialConfig;
        }

        const device_z = try options.allocator.dupeZ(u8, options.device);
        defer options.allocator.free(device_z);

        const maybe_ctx = c.modbus_new_rtu(
            device_z.ptr,
            @intCast(options.baud_rate),
            @intCast(options.parity),
            @intCast(options.data_bits),
            @intCast(options.stop_bits),
        );
        const ctx = maybe_ctx orelse {
            logLibmodbusFailure("new_rtu_context");
            return error.ConnectFailed;
        };
        errdefer c.modbus_free(ctx);

        if (c.modbus_set_slave(ctx, options.unit_id) == -1) {
            logLibmodbusFailure("rtu_set_slave");
            return error.ConnectFailed;
        }

        const timeout_sec = options.timeout_ms / 1000;
        const timeout_usec = (options.timeout_ms % 1000) * 1000;
        if (c.modbus_set_response_timeout(ctx, timeout_sec, timeout_usec) == -1) {
            logLibmodbusFailure("rtu_set_response_timeout");
            return error.ConnectFailed;
        }

        if (c.modbus_connect(ctx) == -1) {
            logLibmodbusFailure("rtu_connect");
            return error.ConnectFailed;
        }

        return .{ .ctx = ctx };
    }

    pub fn deinit(self: *Client) void {
        c.modbus_close(self.ctx);
        c.modbus_free(self.ctx);
    }

    pub fn readHoldingRegistersAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
    ) ModbusError![]u16 {
        return self.readRegistersAlloc(allocator, start_address, quantity, c.modbus_read_registers);
    }

    pub fn readInputRegistersAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
    ) ModbusError![]u16 {
        return self.readRegistersAlloc(allocator, start_address, quantity, c.modbus_read_input_registers);
    }

    pub fn readCoilsAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
    ) ModbusError![]u16 {
        return self.readBitValuesAlloc(allocator, start_address, quantity, c.modbus_read_bits);
    }

    pub fn readDiscreteInputsAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
    ) ModbusError![]u16 {
        return self.readBitValuesAlloc(allocator, start_address, quantity, c.modbus_read_input_bits);
    }

    pub fn writeSingleCoil(self: *Client, address: u16, value: u16) ModbusError!void {
        if (value > 1) {
            return error.InvalidValue;
        }

        const rc = c.modbus_write_bit(self.ctx, address, if (value == 0) c.FALSE else c.TRUE);
        if (rc != 1) {
            logLibmodbusFailure("write_bit");
            return error.WriteFailed;
        }
    }

    pub fn writeSingleRegister(self: *Client, address: u16, value: u16) ModbusError!void {
        const rc = c.modbus_write_register(self.ctx, address, value);
        if (rc != 1) {
            logLibmodbusFailure("write_register");
            return error.WriteFailed;
        }
    }

    pub fn writeMultipleCoils(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        values: []const u16,
    ) ModbusError!void {
        if (values.len == 0 or values.len > c.MODBUS_MAX_WRITE_BITS) {
            return error.InvalidQuantity;
        }

        const bit_values = try allocator.alloc(u8, values.len);
        defer allocator.free(bit_values);

        for (values, bit_values) |value, *target| {
            if (value > 1) {
                return error.InvalidValue;
            }
            target.* = @intCast(value);
        }

        const expected: c_int = @intCast(values.len);
        const rc = c.modbus_write_bits(self.ctx, start_address, expected, bit_values.ptr);
        if (rc != expected) {
            logLibmodbusFailure("write_bits");
            return error.WriteFailed;
        }
    }

    pub fn writeMultipleRegisters(self: *Client, start_address: u16, values: []const u16) ModbusError!void {
        if (values.len == 0 or values.len > c.MODBUS_MAX_WRITE_REGISTERS) {
            return error.InvalidQuantity;
        }

        const expected: c_int = @intCast(values.len);
        const rc = c.modbus_write_registers(self.ctx, start_address, expected, @ptrCast(values.ptr));
        if (rc != expected) {
            logLibmodbusFailure("write_registers");
            return error.WriteFailed;
        }
    }

    pub fn writeAndReadRegistersAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        write_start_address: u16,
        write_values: []const u16,
        read_start_address: u16,
        read_quantity: u16,
    ) ModbusError![]u16 {
        if (write_values.len == 0 or write_values.len > c.MODBUS_MAX_WR_WRITE_REGISTERS) {
            return error.InvalidQuantity;
        }
        if (read_quantity == 0 or read_quantity > c.MODBUS_MAX_WR_READ_REGISTERS) {
            return error.InvalidQuantity;
        }

        const registers = try allocator.alloc(u16, read_quantity);
        errdefer allocator.free(registers);

        const write_count: c_int = @intCast(write_values.len);
        const read_count: c_int = @intCast(read_quantity);
        const rc = c.modbus_write_and_read_registers(
            self.ctx,
            write_start_address,
            write_count,
            @ptrCast(write_values.ptr),
            read_start_address,
            read_count,
            @ptrCast(registers.ptr),
        );
        if (rc == -1) {
            logLibmodbusFailure("write_and_read_registers");
            return error.ReadFailed;
        }

        return registers[0..@intCast(rc)];
    }

    fn readRegistersAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
        read_fn: *const fn (?*c.modbus_t, c_int, c_int, [*c]u16) callconv(.c) c_int,
    ) ModbusError![]u16 {
        if (quantity == 0 or quantity > c.MODBUS_MAX_READ_REGISTERS) {
            return error.InvalidQuantity;
        }

        const registers = try allocator.alloc(u16, quantity);
        errdefer allocator.free(registers);

        const count = read_fn(self.ctx, start_address, quantity, @ptrCast(registers.ptr));
        if (count == -1) {
            logLibmodbusFailure("read_registers");
            return error.ReadFailed;
        }

        return registers[0..@intCast(count)];
    }

    fn readBitValuesAlloc(
        self: *Client,
        allocator: std.mem.Allocator,
        start_address: u16,
        quantity: u16,
        read_fn: *const fn (?*c.modbus_t, c_int, c_int, [*c]u8) callconv(.c) c_int,
    ) ModbusError![]u16 {
        if (quantity == 0 or quantity > c.MODBUS_MAX_READ_BITS) {
            return error.InvalidQuantity;
        }

        const raw_bits = try allocator.alloc(u8, quantity);
        defer allocator.free(raw_bits);

        const count = read_fn(self.ctx, start_address, quantity, raw_bits.ptr);
        if (count == -1) {
            logLibmodbusFailure("read_bits");
            return error.ReadFailed;
        }

        const values = try allocator.alloc(u16, @intCast(count));
        errdefer allocator.free(values);
        for (values, 0..) |*value, index| {
            value.* = raw_bits[index];
        }

        return values;
    }

    fn isIpv4Literal(host: []const u8) bool {
        if (host.len == 0 or host.len > 15) {
            return false;
        }

        var dot_count: usize = 0;
        for (host) |char| {
            switch (char) {
                '.' => dot_count += 1,
                '0'...'9' => {},
                else => return false,
            }
        }

        return dot_count == 3;
    }

    fn logLibmodbusFailure(step: []const u8) void {
        const errnum = std.c._errno().*;
        const message = std.mem.span(c.modbus_strerror(errnum));
        std.log.err("libmodbus {s} failed: errno={d} message={s}", .{ step, errnum, message });
    }
};

pub const TcpClient = Client;
pub const RtuClient = Client;
