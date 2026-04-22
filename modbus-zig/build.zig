const std = @import("std");

// 独立 Modbus 库的构建脚本。
// 当前先导出 modbus 模块，并提供 `zig build test` 用于验证协议编解码和客户端接口能正常编译。
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("modbus", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const tests = b.addTest(.{
        .root_module = mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run modbus library tests");
    test_step.dependOn(&run_tests.step);

    _ = optimize;
}
