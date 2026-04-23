const std = @import("std");

// 这个函数本身不会立刻执行构建，而是负责描述并修改 Zig 的构建图。
// 真正执行时由外部 runner 按依赖关系调度，因此这里更像是在声明“如何构建”。
pub fn build(b: *std.Build) void {
    // 标准目标选项：允许执行 `zig build` 的人自行指定目标平台。
    // 这里保持默认行为，即默认构建本机平台，也允许显式切换目标。
    const target = b.standardTargetOptions(.{});
    // 标准优化选项：支持 Debug、ReleaseSafe、ReleaseFast、ReleaseSmall 等模式。
    // 当前不强行指定优化级别，交给调用方按场景选择。
    const optimize = b.standardOptimizeOption(.{});
    // 如有需要，也可以通过 `b.option()` 给这个构建脚本追加自定义开关。
    // 这些开关会和 target / optimize 一起出现在 `zig build --help` 中。

    // 先把 httpz 依赖接入构建图，再导出为可导入模块。
    // 这样业务源码里的 `@import("httpz")` 才能在编译时被解析到。
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const httpz_mod = httpz_dep.module("httpz");
    const modbus_dep = b.dependency("modbus", .{
        .target = target,
        .optimize = optimize,
    });
    const modbus_mod = modbus_dep.module("modbus");

    // backend 模块承载共享业务代码，供测试和可执行程序共同复用。
    const mod = b.addModule("backend", .{
        // 模块根文件相当于对外暴露 API 的入口。
        // 如果其他文件里有想公开的声明，需要在 root.zig 中重新导出。
        .root_source_file = b.path("src/root.zig"),
        // 因为后面会把它作为测试目标的根模块，所以这里要明确挂上 target。
        .target = target,
        .imports = &.{
            .{ .name = "httpz", .module = httpz_mod },
            .{ .name = "modbus", .module = modbus_mod },
        },
    });

    // 定义最终可执行程序。
    // 这里单独使用 main.zig 作为入口，把 CLI / 启动逻辑和业务逻辑分开。
    const exe = b.addExecutable(.{
        .name = "backend",
        .root_module = b.createModule(.{
            // createModule 与 addModule 类似，但不会把该模块暴露给包外消费者。
            // 这里正适合只给当前可执行程序使用的根模块。
            .root_source_file = b.path("src/main.zig"),
            // 可执行程序的根模块需要显式绑定 target 和 optimize。
            .target = target,
            .optimize = optimize,
            // 这里声明 main.zig 及其子依赖可以直接导入的模块列表。
            .imports = &.{
                .{ .name = "backend", .module = mod },
                .{ .name = "httpz", .module = httpz_mod },
                .{ .name = "modbus", .module = modbus_mod },
            },
        }),
    });

    // Windows 下 httpz / websocket 最终都会落到 Winsock 符号，
    // 因此这里显式链接 ws2_32，补齐 socket / bind / listen / recv / send 等导入。
    if (target.result.os.tag == .windows) {
        exe.root_module.linkSystemLibrary("ws2_32", .{});
    }

    // 把可执行文件挂到默认安装步骤，执行 `zig build` 时会输出到 zig-out。
    b.installArtifact(exe);

    // 定义顶层 run 步骤，允许通过 `zig build run` 直接启动程序。
    const run_step = b.step("run", "Run the app");

    // RunArtifact 表示“先编译，再运行这个产物”。
    // 这里把它挂到 run_step 下，使 `zig build run` 生效。
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // 让运行步骤依赖安装步骤，这样程序会从安装目录启动，而不是直接从缓存目录启动。
    run_cmd.step.dependOn(b.getInstallStep());

    // 允许透传命令行参数，例如 `zig build run -- arg1 arg2`。
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // 为 backend 模块生成测试可执行程序，运行其中的 test 块。
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // 该步骤用于执行上面的模块测试产物。
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // main.zig 也单独生成一份测试产物。
    // Zig 的测试可执行程序一次只针对一个根模块，因此这里拆成两份。
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // 执行 main 根模块测试的步骤。
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // 顶层 test 步骤统一串起两组测试。
    // 两者之间没有依赖关系，因此 Zig 可以并行运行。
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // 顶层步骤和参数一样，都会出现在 `zig build --help` 中。
    // Zig 的构建系统本质上是在用户态描述编译图，再由编译器按图执行具体子命令。
}
