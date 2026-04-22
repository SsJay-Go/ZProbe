const std = @import("std");
const app = @import("app.zig");

/// 程序入口仅保留启动职责，业务逻辑统一下沉到 app/router/handler/service。
pub fn main(init: std.process.Init) !void {
    try app.run(init);
}
