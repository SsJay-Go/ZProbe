# httpz 实现与接口详解

这份文档面向当前项目里的 httpz 源码副本，目标不是介绍“怎么用一个黑盒 HTTP 框架”，而是帮助你从源码视角理解它的结构、请求流转路径、关键接口和当前这份包在 Zig 0.16 / Windows 下需要关注的兼容点。

## 1. 包的整体职责

httpz 是一个偏轻量、偏直接控制的 Zig HTTP 服务库。它主要做四件事：

1. 建立监听 socket，接收客户端连接。
2. 把原始字节流解析成 Request。
3. 根据 method + path 在 Router 中查到对应 action。
4. 把业务层写入的 Response 序列化回客户端。

和很多“大而全”的 Web 框架不同，httpz 更接近“高性能 HTTP 内核 + 路由 + 请求/响应辅助工具”的组合。它没有强制的 MVC，也没有过重的抽象层，所以很适合作为你这种设备通讯测试后端的基础壳层。

## 2. 推荐先看的源码入口

建议按下面顺序阅读：

1. src/httpz.zig
2. src/router.zig
3. src/request.zig
4. src/response.zig
5. src/worker.zig
6. src/posix.zig

原因：

- httpz.zig 负责把服务端生命周期串起来。
- router.zig 决定“请求怎么命中业务动作”。
- request.zig / response.zig 是业务层最直接接触的 API。
- worker.zig 负责把连接和请求处理真正跑起来。
- posix.zig 是平台兼容层，Windows 兼容问题大多会落在这里。

## 3. 核心对象分工

### 3.1 Server

定义位置主要在 src/httpz.zig。

职责：

- 初始化监听配置。
- 创建 router。
- 启动 worker。
- 接受连接。
- 协调 stop / deinit 生命周期。

你可以把 Server 理解成“框架的总控台”。

### 3.2 Router

定义位置在 src/router.zig。

职责：

- 按 method 维护多套路由树。
- 注册 GET / POST / PUT / DELETE 等路由。
- 在请求进入时根据路径做匹配。
- 提供 group、middleware、route config 等组织能力。

Router 的核心价值不是“把路径字符串存起来”，而是把“路径模式 + 参数提取 + 调度动作”组织成可快速查找的数据结构。

### 3.3 Request

定义位置在 src/request.zig。

职责：

- 暴露 URL、headers、params、query、body。
- 提供 header() / param() / body() / json() 等读取入口。
- 保存请求级 arena，减少碎片化分配。

对业务代码来说，Request 是读取输入的主入口。

### 3.4 Response

定义位置在 src/response.zig。

职责：

- 管理状态码、响应头、正文。
- 提供 json()、header()、setStatus() 等便捷接口。
- 支持 chunked 输出和 event stream。

对业务代码来说，Response 是写出结果的主入口。

## 4. 一次请求的流转路径

你可以按下面这条链去理解：

1. Server.listen 开始监听。
2. 底层 accept 到 socket 后交给 worker。
3. worker 从连接里读请求行、头、正文。
4. 请求被组装成 Request。
5. Router.route 根据 method + url 查找命中 action。
6. Dispatcher 调用你的业务 handler。
7. handler 通过 Response 写回状态、头和 body。
8. 框架把 Response 序列化成 HTTP 报文发回客户端。
9. 根据 keep-alive 决定复用连接还是关闭。

如果你后面要改性能、加日志、加 tracing 或接入 Modbus 连接池，通常就是在这条链上选一个切入点。

## 5. 你当前项目最相关的接口

### 5.1 路由注册

你在业务项目里用到的就是 Router 提供的：

- get(path, action, config)
- post(path, action, config)
- put(path, action, config)
- delete(path, action, config)
- group(prefix, config)

你的 backend 里 routes/*.zig 最终就是在调用这套接口。

### 5.2 读取请求

在 handler 里常用：

- req.header(name)
- req.param(name)
- req.body()
- req.json(T)

这对你的 TCP 连接创建接口最关键，因为它直接决定前端 JSON payload 怎样被反序列化成 Zig 结构。

### 5.3 写响应

在 handler 里常用：

- res.json(value, options)
- res.setStatus(status)
- res.header(name, value)
- res.chunk(data)

你当前后端控制器主要就是在用 res.json。

## 6. 这套实现的优点

1. 结构相对直接，适合阅读和二次修改。
2. 抽象层不厚，出问题时比较容易顺着源码往下追。
3. Request / Response API 对业务层友好。
4. Router 能满足中小型接口服务的组织需求。
5. 比较适合做“协议网关 / 工具型 HTTP 壳层”。

## 7. 这套实现的代价

1. 平台兼容要自己兜，尤其是 Zig 未稳定时期。
2. Windows 适配面会比较敏感，很多 socket 细节会暴露出来。
3. 依赖的 websocket / metrics 也会把兼容压力传递进来。
4. 版本升级时，你需要读源码而不是只看 README。

这也是你这次碰到 Zig 0.16 / Windows break 的根本原因：
框架不是不能用，而是它把系统层细节留得比较“真”。

## 8. 当前这份副本里已经重点加注释的地方

我本次已经在这些文件中补了中文注释，方便你继续顺着看：

- src/httpz.zig
- src/posix.zig
- src/request.zig
- src/response.zig
- src/router.zig
- websocket 依赖里的 src/posix.zig
- websocket 依赖里的 src/server/server.zig

建议阅读顺序：

1. 先看 src/httpz.zig 里的 Server.listen。
2. 再看 src/router.zig 的 Router.init / route / group。
3. 然后看 src/request.zig 和 src/response.zig。
4. 最后回到 src/posix.zig，看平台兼容层到底做了什么。

## 9. 对你这个项目的实际建议

如果你后续继续用 Zig 做 Modbus 测试后端，建议把 httpz 当成“可修改的内嵌依赖”而不是“完全信任的外部黑盒”。

更具体地说：

1. 把当前可用 Zig 版本固定住。
2. 把已验证过的 httpz 副本连同补丁一起保存在仓库里。
3. 把你自己真正依赖的接口缩到最小：路由注册、读取 JSON、写 JSON、健康检查。
4. 尽量不要过早依赖 websocket、复杂 middleware 和高级流式特性。
5. 每次升级 Zig 前，先跑一轮 socket / request / response 的最小回归验证。

## 10. 如果你要继续深挖源码，重点看这几个问题

1. Request 的 body 是什么时候读满的，什么时候惰性读取？
2. Router 的路径匹配是怎么组织静态段和参数段的？
3. Response 的 writer / json / chunk 三套输出模式有什么差别？
4. worker 在 keep-alive 和连接回收上怎么做？
5. posix.zig 为什么会成为 Zig 升级时最脆弱的一层？

把这五个问题吃透，你基本就能把 httpz 当成自己能维护的代码，而不只是一个第三方包。