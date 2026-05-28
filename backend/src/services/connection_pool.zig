const std = @import("std");
const libmodbus = @import("../protocol_bindings/libmodbus.zig");
const connection_model = @import("../models/connection.zig");
const modbus_model = @import("../models/modbus.zig");
const rtu_transport = @import("../transports/rtu_transport.zig");
const ascii_transport = @import("../transports/ascii_transport.zig");

/// 统一连接句柄。
///
/// 这里不是走“虚函数表接口”那套抽象，而是直接用 Zig 最直观的 tagged union：
/// 当前持有的到底是 TCP、RTU 还是 ASCII，一眼就能看出来；
/// 调用读写时也显式 switch，不会把控制流藏到过深的抽象里。
pub const ConnectionHandle = union(connection_model.TransportKind) {
    tcp: *libmodbus.Client,
    rtu: *libmodbus.Client,
    ascii: *ascii_transport.Client,

    /// 统一释放底层连接。
    pub fn deinit(self: *ConnectionHandle, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tcp => |client| {
                client.deinit();
                allocator.destroy(client);
            },
            .rtu => |client| {
                client.deinit();
                allocator.destroy(client);
            },
            .ascii => |client| {
                client.deinit();
                allocator.destroy(client);
            },
        }
    }

    /// 统一读寄存器入口。
    ///
    /// 业务层不需要关心当前是哪个 transport；
    /// transport-specific 的差异都在这里集中分发。
    pub fn readValuesAlloc(
        self: *const ConnectionHandle,
        allocator: std.mem.Allocator,
        target: modbus_model.ReadTarget,
        start_address: u16,
        quantity: u16,
    ) ![]u16 {
        return switch (self.*) {
            .tcp, .rtu => |client| switch (target) {
                .read_coils => client.readCoilsAlloc(allocator, start_address, quantity),
                .read_discrete_inputs => client.readDiscreteInputsAlloc(allocator, start_address, quantity),
                .holding_registers => client.readHoldingRegistersAlloc(allocator, start_address, quantity),
                .input_registers => client.readInputRegistersAlloc(allocator, start_address, quantity),
            },
            .ascii => error.TransportNotSupported,
        };
    }

    /// 统一写寄存器入口。
    ///
    /// 返回实际写入的寄存器个数，方便上层直接回包给前端。
    pub fn writeValues(self: *const ConnectionHandle, allocator: std.mem.Allocator, request: modbus_model.WriteRequest) !u16 {
        return switch (self.*) {
            .tcp, .rtu => |client| switch (request.target) {
                .single_coil => {
                    try client.writeSingleCoil(request.startAddress, request.value.?);
                    return 1;
                },
                .single_register => {
                    try client.writeSingleRegister(request.startAddress, request.value.?);
                    return 1;
                },
                .multiple_coils => {
                    const values = request.values.?;
                    try client.writeMultipleCoils(allocator, request.startAddress, values);
                    return @as(u16, @intCast(values.len));
                },
                .multiple_registers => {
                    const values = request.values.?;
                    try client.writeMultipleRegisters(request.startAddress, values);
                    return @as(u16, @intCast(values.len));
                },
            },
            .ascii => error.TransportNotSupported,
        };
    }

    pub fn writeAndReadRegistersAlloc(
        self: *const ConnectionHandle,
        allocator: std.mem.Allocator,
        request: modbus_model.WriteReadRequest,
    ) ![]u16 {
        return switch (self.*) {
            .tcp, .rtu => |client| client.writeAndReadRegistersAlloc(
                allocator,
                request.writeStartAddress,
                request.values,
                request.readStartAddress,
                request.readQuantity,
            ),
            .ascii => error.TransportNotSupported,
        };
    }
};

/// 统一的连接记录。
///
/// 连接注册表里真正持有的是这份记录，
/// 它把“元数据”和“底层连接句柄”捆在一起，便于 connect / disconnect / read / write 共享。
pub const ConnectionRecord = struct {
    id: []const u8,
    name: []const u8,
    transport: connection_model.TransportKind,
    slave_id: u8,
    timeout_ms: u32,
    retry_count: u8,
    details: connection_model.ConnectionDetails,
    handle: ConnectionHandle,

    /// 统一释放记录持有的全部资源。
    ///
    /// 释放顺序：
    /// 1. 先销毁底层连接句柄
    /// 2. 再释放元数据字符串
    /// 3. 最后释放 id
    pub fn deinit(self: *ConnectionRecord, allocator: std.mem.Allocator) void {
        self.handle.deinit(allocator);
        allocator.free(self.name);

        switch (self.details) {
            .tcp => |details| allocator.free(details.host),
            .rtu => |details| allocator.free(details.serialPort),
            .ascii => |details| allocator.free(details.serialPort),
        }

        allocator.free(self.id);
    }

    /// 转成对外回包用的 ConnectionInfo。
    pub fn info(self: ConnectionRecord) connection_model.ConnectionInfo {
        return .{
            .id = self.id,
            .name = self.name,
            .transport = self.transport,
            .slaveId = self.slave_id,
            .timeoutMs = self.timeout_ms,
            .retryCount = self.retry_count,
            .details = self.details,
        };
    }
};

/// 连接注册表。
///
/// 旧版本这里叫 ConnectionPool，但存的是纯 TCP 指针；
/// 这次虽然沿用文件名，语义上已经更接近“registry”：
/// 它保存的是各类连接记录，而不是某一种 transport 的连接池。
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(ConnectionRecord),
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator) ConnectionPool {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ConnectionRecord).init(allocator),
        };
    }

    fn acquireLock(self: *ConnectionPool) void {
        while (!self.mutex.tryLock()) {}
    }

    fn releaseLock(self: *ConnectionPool) void {
        self.mutex.unlock();
    }

    /// 释放注册表中所有连接。
    ///
    /// 这里假设程序退出时不会再有新的业务线程向注册表发起读写。
    pub fn deinit(self: *ConnectionPool) void {
        self.acquireLock();
        defer self.releaseLock();

        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            var record = entry.value_ptr.*;
            record.deinit(self.allocator);
        }

        self.map.deinit();
    }

    /// 写入一条新连接记录。
    ///
    /// 注意这里不再重复复制 id；
    /// 我们要求 record.id 本身就是一段拥有所有权的稳定内存，
    /// 并让 map key 和 record.id 指向同一块内存，释放时只需要释放一次。
    pub fn insert(self: *ConnectionPool, record: ConnectionRecord) !void {
        self.acquireLock();
        defer self.releaseLock();
        try self.map.put(record.id, record);
    }

    /// 获取一份连接记录快照。
    ///
    /// 返回的是按值复制的记录，不转移所有权。
    /// 对于当前阶段的单窗口独占连接场景已经足够；
    /// 如果未来要支持“读写请求”和“断开请求”并发竞态，需要再加引用计数或 borrow 机制。
    pub fn get(self: *ConnectionPool, id: []const u8) ?ConnectionRecord {
        self.acquireLock();
        defer self.releaseLock();
        return self.map.get(id);
    }

    pub fn contains(self: *ConnectionPool, id: []const u8) bool {
        self.acquireLock();
        defer self.releaseLock();
        return self.map.contains(id);
    }

    /// 从注册表中移除一条连接记录，并把所有权交给调用方。
    ///
    /// 典型场景就是 disconnect：
    /// HTTP 线程先把记录快速移出注册表，后台线程再慢慢关闭底层资源。
    pub fn take(self: *ConnectionPool, id: []const u8) ?ConnectionRecord {
        self.acquireLock();
        defer self.releaseLock();

        const entry = self.map.fetchRemove(id) orelse return null;
        return entry.value;
    }
};
