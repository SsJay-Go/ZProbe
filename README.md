# ZProbe
基于zig编写的串口测试工具

当前 Modbus TCP 已改为通过 Zig 的 protocol_bindings 适配层复用 vendored libmodbus（C 开源库）。
现阶段保留 Zig 侧的连接池、HTTP 接口和调度逻辑，只把协议实现下沉到 C 库边界层。
libmodbus 的生成头文件已移出上游 src/，改为 third_party/libmodbus/generated/<platform>，用于同时兼容 Windows 和 Linux 的构建结构。
当前 backend 不再把 libmodbus 的 C 源码直接编进 backend.exe，而是单独构建为动态库；Windows 下产物为 backend/zig-out/bin/modbus.dll，backend.exe 通过该 DLL 链接运行。

选库时至少满足这 6 条：
有明确 C API，不依赖 C++ ABI。
Windows 编译和运行被验证过。
对 TCP 和串口支持边界清楚。
文档明确说明内存所有权和线程安全。
协议覆盖面符合你后续规划，不只是 Modbus 一点点功能。
许可证能接受。

复用 C 库时，强制遵守这几条：
Zig 里单独做一层 c_adapter 或 protocol_bindings，不要让业务层直接碰 @cImport 的类型。
所有 C 返回的指针，默认先怀疑是借用，必要时立即复制到 Zig 自己拥有的内存。
所有资源都包成明确的 init/deinit。
回调边界上不要传临时 slice，不要把 Zig 栈内存借给 C 长期持有。
先做最小冒烟测试：建连、单次读、异常响应、断开重连、超时。
先接 Modbus TCP，再评估 RTU/ASCII，再扩到电力协议，不要一口气全接。

当前仓库里与这些约束对应的落地点：
- C 库边界集中在 backend/src/protocol_bindings。
- 业务层不直接接触 @cImport 或 libmodbus 的裸类型。
- Modbus TCP 的 timeoutMs 已直接下沉到 libmodbus response timeout。
- 现阶段只替换 Modbus TCP；RTU/ASCII 保持原占位实现，避免一次切太大。
- vendor 目录里保留 upstream src/ 原样，平台相关生成头放在 third_party/libmodbus/generated。