const std = @import("std");
const httpz = @import("httpz");
const model = @import("../models/connection.zig");
const service = @import("../services/connection_service.zig");
const context = @import("../context.zig");
const controller_helpers = @import("./controller_helpers.zig");
const connection_pool = @import("../services/connection_pool.zig");

/// 新建连接控制器。
///
/// 参数 app: *context.App 由 httpz 框架注入，携带全局连接池。
/// 每次 HTTP 请求到来时，框架自动把 &app 传入，无需手动传参。
pub fn connect(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    // req.arena 用于解析请求体等短生命周期分配；
    // 长连接记录会跨请求存活，因此真正持久化的数据仍然要放到全局 allocator 上。
    const long_alloc = app.pool.allocator;
    // maybe_payload代表 optional 包装值 因为 req.json返回的类型是!?T （可能的 T 或错误），需要先 try 解包，再检查 null。
    const maybe_payload = try req.json(model.ConnectRequest);
    if (maybe_payload == null) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    service.validateConnectRequest(payload) catch |err| {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(model.makeError(service.validationErrorMessage(err)), .{});
        return;
    };

    // 先计算连接 ID，再检查冲突，避免建立连接后才发现 ID 已存在而泄漏资源。
    // buildConnectionId 用 Wyhash 对参数组合做哈希，结果写入调用方提供的栈缓冲区。
    // 缓冲区 40 字节，格式 "tcp-{hex16}"（最长 20 字节），不会溢出，catch unreachable 安全。
    // catch unreachable 告诉编译器：「我确信此处不会出错，若出错即是编程 bug，直接 panic」。
    var id_buf: [40]u8 = undefined;
    const connection_id = service.buildConnectionId(payload, &id_buf) catch unreachable;

    // 连接 ID 已存在 → 返回 409 Conflict，避免同参数连接被重复建立。
    if (app.pool.contains(connection_id)) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.conflict);
        try res.json(model.makeError("该连接已存在，请先断开再重新连接"), .{});
        return;
    }

    // 创建“完整连接记录”：
    // 里面既包含真实 TCP 客户端，也包含名字、连接 ID、传输细节等长生命周期元数据。
    const record = service.createConnectionRecord(long_alloc, connection_id, payload) catch |err| {
        controller_helpers.closeAfterResponse(res);

        switch (err) {
            error.OutOfMemory => res.setStatus(.internal_server_error),
            error.TcpConnectFailed, error.RtuConnectFailed => res.setStatus(.bad_gateway),
            error.TransportNotImplemented => res.setStatus(.not_implemented),
        }

        try res.json(model.makeError(service.createErrorMessage(err)), .{});
        return;
    };

    const connection = record.info();

    // insert 失败时，说明连接注册表并未接管 record 的所有权，
    // 所以需要在这里手动释放。
    app.pool.insert(record) catch {
        var cleanup_record = record;
        cleanup_record.deinit(long_alloc);
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.internal_server_error);
        try res.json(model.makeError("连接池写入失败，请稍后重试"), .{});
        return;
    };

    controller_helpers.closeAfterResponse(res);
    try res.json(model.makeConnectSuccess(connection), .{});
}

/// 后台清理任务的参数包。
/// deinit + destroy 可能耗时（关闭 socket、停止 IO 运行时线程），
/// 放到后台线程执行，避免阻塞 HTTP 请求处理线程。
const CleanupArgs = struct {
    record: connection_pool.ConnectionRecord,
    allocator: std.mem.Allocator,
};

/// 后台线程入口：安全地销毁 TcpClient。
/// 1. deinit()：关闭 socket + 停止 Io.Threaded 后台线程池
/// 2. destroy()：释放堆上的 TcpClient 结构体内存
fn cleanupTask(args: CleanupArgs) void {
    var record = args.record;
    record.deinit(args.allocator);
}

/// 断开连接控制器：从连接池中移除并关闭指定连接。
pub fn disconnect(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const maybe_payload = try req.json(model.DisconnectRequest);
    if (maybe_payload == null) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(model.makeError("请求体不能为空"), .{});
        return;
    }

    const payload = maybe_payload.?;
    if (payload.connectionId.len == 0) {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(model.makeError("connectionId 不能为空"), .{});
        return;
    }

    // 从注册表快速拿走一整条连接记录，
    // 后续真正关闭底层 transport 的动作放到后台线程处理。
    const record = app.pool.take(payload.connectionId) orelse {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.not_found);
        try res.json(model.makeError("连接不存在或已断开"), .{});
        return;
    };

    // 先发送 HTTP 200，再在后台线程做耗时的清理工作。
    // 若线程创建失败（极少见，通常是资源耗尽），退化为同步清理。
    const args = CleanupArgs{ .record = record, .allocator = app.pool.allocator };
    const thread = std.Thread.spawn(.{}, cleanupTask, .{args}) catch {
        var cleanup_record = record;
        cleanup_record.deinit(app.pool.allocator);
        controller_helpers.closeAfterResponse(res);
        try res.json(.{ .success = true, .message = "连接已断开" }, .{});
        return;
    };
    thread.detach(); // 后台运行，不需要等待结果

    controller_helpers.closeAfterResponse(res);
    try res.json(.{ .success = true, .message = "连接已断开" }, .{});
}

pub fn status(app: *context.App, req: *httpz.Request, res: *httpz.Response) !void {
    const connection_id = req.param("id") orelse {
        controller_helpers.closeAfterResponse(res);
        res.setStatus(.bad_request);
        try res.json(model.makeError("connectionId 不能为空"), .{});
        return;
    };

    const connection = if (app.pool.get(connection_id)) |record| record.info() else null;
    controller_helpers.closeAfterResponse(res);
    try res.json(model.makeConnectionStatus(connection), .{});
}
