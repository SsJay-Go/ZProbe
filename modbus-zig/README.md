# modbus-zig

这是一个面向 Zig 0.16 的 Modbus TCP 主站库，目标不是“把所有协议分支一次做满”，而是先提供一个适合你当前通讯测试和后续数据采集软件复用的稳定骨架。

## 当前已实现

- Modbus TCP MBAP 头构造与解析
- 读取保持寄存器 `FC03`
- 读取输入寄存器 `FC04`
- 写单个保持寄存器 `FC06`
- 写多个保持寄存器 `FC16`
- 设备异常码到 Zig 错误的映射
- 独立包结构，适合作为本地依赖接入其他 Zig 项目

## 为什么单独做成包

把协议库直接塞进现有 backend 业务代码，会让“协议能力”和“接口/控制器/业务流程”耦合在一起。独立包的好处是：

- 当前通讯测试项目可以直接复用
- 以后做数据采集服务、轮询调度器、从站仿真器时还能继续复用
- 后续要补 RTU、线圈读写、自动重连、连接池时不会污染业务层

## 建议目录阅读顺序

1. `src/root.zig`
2. `src/errors.zig`
3. `src/codec.zig`
4. `src/tcp/client.zig`

## 作为依赖接入其他项目

在你的使用方项目 `build.zig.zon` 里增加本地依赖：

```zig
.dependencies = .{
    .modbus = .{
        .path = "../modbus-zig",
    },
},
```

然后在 `build.zig` 中导入模块：

```zig
const modbus_dep = b.dependency("modbus", .{
    .target = target,
    .optimize = optimize,
});
const modbus_mod = modbus_dep.module("modbus");
```

如果你的根模块或业务模块需要使用它，再把它加入 `.imports`：

```zig
.imports = &.{
    .{ .name = "modbus", .module = modbus_mod },
},
```

## 最小使用示例

```zig
const std = @import("std");
const modbus = @import("modbus");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try modbus.tcp.Client.connect(.{
        .allocator = allocator,
        .host = "127.0.0.1",
        .port = 502,
        .unit_id = 1,
    });
    defer client.deinit();

    const registers = try client.readHoldingRegistersAlloc(allocator, 0, 4);
    defer allocator.free(registers);

    for (registers, 0..) |value, index| {
        std.debug.print("reg[{d}] = 0x{X:0>4}\n", .{ index, value });
    }
}
```

## 这份库适合怎么继续学

- 先看 `codec.zig`，理解 Modbus TCP 报文到底是怎样拼起来的
- 再看 `tcp/client.zig`，理解一次请求是如何在 TCP 层往返的
- 最后自己补一个 `readCoils` 或 `writeSingleCoil`，这是最好的练习方式

## 后续最值得补的能力

- 串口 RTU 传输层
- 线圈 / 离散输入读写
- 超时、重连、轮询调度
- 自定义请求与原始帧调试接口
- 面向采集场景的批量轮询器