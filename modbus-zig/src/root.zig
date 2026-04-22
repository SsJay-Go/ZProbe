// root.zig 是包的对外入口。
// 使用方只需要 `@import("modbus")`，然后从这里拿到客户端、协议类型和错误集合。

pub const errors = @import("errors.zig");
pub const codec = @import("codec.zig");
pub const tcp = struct {
    pub const Client = @import("tcp/client.zig").TcpClient;
    pub const ConnectOptions = @import("tcp/client.zig").ConnectOptions;
};

pub const ModbusError = errors.ModbusError;
pub const FunctionCode = codec.FunctionCode;
pub const Limits = codec.Limits;
pub const MbapHeader = codec.MbapHeader;

test {
    _ = @import("errors.zig");
    _ = @import("codec.zig");
    _ = @import("tcp/client.zig");
}
