# ZProbe

ZProbe 是一个基于 Zig + Vue 构建的 Modbus 调试与联调工具，当前定位是本地使用的测试工具，而不是通用工业组态平台。

它支持 Modbus TCP 和 Modbus RTU，前端界面用于连接、读写、查看结果，后端负责协议通信与静态资源托管。当前版本已经可以覆盖常见的设备联调、寄存器验证、写入测试和报文排查场景。

## 当前能力

- 支持 Modbus TCP
- 支持 Modbus RTU
- 支持常用功能码读写
	- FC01 读线圈
	- FC02 读离散输入
	- FC03 读保持寄存器
	- FC04 读输入寄存器
	- FC05 写单线圈
	- FC06 写单寄存器
	- FC0F 写多线圈
	- FC10 写多寄存器
	- FC17 读写多寄存器
- 支持连接管理与断开
- 支持寄存器表格查看与格式切换
- 支持近实时通信日志查看
- 支持查看 libmodbus 收发的原始报文帧
- 支持后端直接托管前端打包后的 dist

## 技术栈

- 后端：Zig 0.16.0
- HTTP 框架：httpz
- Modbus 协议库：libmodbus
- 前端：Vue 3 + Vite + Element Plus
- 前后端通信：HTTP API

## 项目结构

- backend
	- Zig 后端服务
	- 负责 Modbus 通信、连接池、日志、前端 dist 托管
- front
	- Vue 前端界面
	- 负责连接配置、功能码操作、数据显示、日志展示
- third_party/libmodbus
	- vendored libmodbus 源码与平台生成头文件
- modbus-zig
	- 早期自研实验代码，当前主链路已切换到 libmodbus

## 开发环境要求

- Windows 为当前主要验证平台
- 已安装 Zig 0.16.0
- 已安装 Bun 或其他可运行 Vite 的 Node 兼容环境

## 本地开发

### 1. 安装前端依赖

在 front 目录执行：

```bash
bun install
```

### 2. 启动前端开发服务器

在 front 目录执行：

```bash
bun run dev
```

### 3. 启动后端

在 backend 目录执行：

```bash
zig build run
```

默认后端监听地址：

```text
http://localhost:8080
```

## 生产 / 本地交付使用方式

当前推荐的交付方式是：先打包前端，再构建后端，由后端直接托管前端 dist。

### 1. 构建前端

在 front 目录执行：

```bash
bun run build
```

构建完成后会生成：

```text
front/dist
```

### 2. 构建后端

在 backend 目录执行：

```bash
zig build
```

构建时，backend 会把前端 dist 一并安装进自己的输出目录。

### 3. 最终产物目录

主要使用下面这组产物：

```text
backend/zig-out/
	bin/
		backend.exe
		modbus.dll
	dist/
		index.html
		assets/
		...
```

也就是说，现在不再需要额外单独起一个前端静态文件服务。

### 4. 运行

可直接运行：

```text
backend/zig-out/bin/backend.exe
```

后端会优先尝试从自己的打包目录读取前端 dist。

## 通信日志说明

当前日志面板展示的是 libmodbus 收发的原始报文帧，主要用于联调排查。

- send：发送给设备的原始帧
- recv：设备返回的原始帧

日志保存在后端内存中，适合本地调试，不是长期归档日志系统。

## 已知边界

- 当前支持 TCP 和 RTU，不支持 ASCII
- 当前更适合本机联调，不是远程多用户平台
- RTU 是否可用还取决于本机串口权限、串口占用和驱动状态
- 当前 UI 以测试工具为目标，没有继续扩展为模板管理、历史数据库、趋势分析平台

## 常用命令

前端开发：

```bash
cd front
bun run dev
```

前端构建：

```bash
cd front
bun run build
```

后端运行：

```bash
cd backend
zig build run
```

后端测试：

```bash
cd backend
zig build test
```

后端构建：

```bash
cd backend
zig build
```

## 适用场景

- 设备寄存器映射验证
- TCP/RTU 联调
- 读写功能码验证
- 原始报文排查
- 设备接入前的通信层测试


但就当前定位来说，它已经可以作为一个可用的 Modbus 测试工具使用。

