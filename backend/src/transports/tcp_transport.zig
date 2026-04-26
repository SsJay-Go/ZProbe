const std = @import("std");
const modbus = @import("modbus");

/// TCP 传输层的建连参数。
///
/// 这里故意只放“建立 TCP 连接真正需要的字段”，
/// 避免整个 HTTP 请求模型一路穿透到传输层。
pub const ConnectOptions = struct {
    host: []const u8,
    port: u16,
    slaveId: u8,
};

/// 创建一个稳定驻留在堆上的 Modbus TCP 客户端。
///
/// 传输层只负责“怎么连上目标设备”，
/// 不负责连接 ID、连接池写入、HTTP 错误映射等上层职责。
pub fn connect(allocator: std.mem.Allocator, options: ConnectOptions) !*modbus.tcp.Client {
    const client = try allocator.create(modbus.tcp.Client);
    errdefer allocator.destroy(client);

    client.* = try modbus.tcp.Client.connect(.{
        .allocator = allocator,
        .host = options.host,
        .port = options.port,
        .unit_id = options.slaveId,
    });

    return client;
}
