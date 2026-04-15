const std = @import("std");

pub const FunctionCode = enum(u8) {
    read_coils = 0x01,
    read_discrete_inputs = 0x02,
    read_holding_registers = 0x03,
    read_input_registers = 0x04,
    write_single_coil = 0x05,
    write_single_register = 0x06,
    write_multiple_coils = 0x0F,
    write_multiple_registers = 0x10,
};

pub const ExceptionCode = enum(u8) {
    illegal_function = 0x01,
    illegal_data_address = 0x02,
    illegal_data_value = 0x03,
    server_device_failure = 0x04,
    acknowledge = 0x05,
    server_device_busy = 0x06,
    memory_parity_error = 0x08,
    gateway_path_unavailable = 0x0A,
    gateway_target_failed = 0x0B,
    _,

    pub fn description(self: ExceptionCode) []const u8 {
        return switch (self) {
            .illegal_function => "Illegal Function",
            .illegal_data_address => "Illegal Data Address",
            .illegal_data_value => "Illegal Data Value",
            .server_device_failure => "Server Device Failure",
            .acknowledge => "Acknowledge",
            .server_device_busy => "Server Device Busy",
            .memory_parity_error => "Memory Parity Error",
            .gateway_path_unavailable => "Gateway Path Unavailable",
            .gateway_target_failed => "Gateway Target Failed",
            else => "Unknown Exception",
        };
    }
};

pub const MBAP_HEADER_SIZE: usize = 7; // 报文头长度
pub const MAX_PDU_SIZE: usize = 253; // 最大PDU长度
pub const MAX_ADU_SIZE: usize = MBAP_HEADER_SIZE + MAX_PDU_SIZE; // 最大ADU长度

pub const MbapHeader = struct {
    transaction_id: u16, //
    protocol_id: u16,
    length: u16,
    unit_id: u8,
};
