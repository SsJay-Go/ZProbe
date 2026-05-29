const std = @import("std");
const httpz = @import("httpz");

pub fn serveDist(req: *httpz.Request, res: *httpz.Response) !void {
    if (std.mem.startsWith(u8, req.url.path, "/api/")) {
        res.setStatus(.not_found);
        try res.json(.{ .success = false, .message = "接口不存在" }, .{});
        return;
    }

    const dist_roots = [_][]const u8{
        "zig-out/dist",
        "../dist",
        "../front/dist",
    };
    const requested_path = sanitizePath(req.url.path) orelse {
        res.setStatus(.bad_request);
        res.body = "Bad request";
        return;
    };

    const should_fallback = requested_path.len == 0 or std.fs.path.extension(requested_path).len == 0;
    const exact_target = if (requested_path.len == 0) "index.html" else requested_path;

    for (dist_roots) |dist_root| {
        if (try tryServeFile(req.arena, req.conn.io, res, dist_root, exact_target)) {
            return;
        }

        if (should_fallback and try tryServeFile(req.arena, req.conn.io, res, dist_root, "index.html")) {
            return;
        }
    }

    res.setStatus(.not_found);
    res.body = "Not found";
}

fn tryServeFile(arena: std.mem.Allocator, io: std.Io, res: *httpz.Response, dist_root: []const u8, relative_path: []const u8) !bool {
    const cwd = std.Io.Dir.cwd();
    const full_path = try std.fs.path.join(arena, &.{ dist_root, relative_path });
    var file = cwd.openFile(io, full_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.kind != .file) {
        return false;
    }

    const body = try arena.alloc(u8, @intCast(stat.size));
    const content = try cwd.readFile(io, full_path, body);
    const content_type = httpz.ContentType.forFile(relative_path);
    if (content_type != .UNKNOWN) {
        res.content_type = content_type;
    }
    res.body = content;
    return true;
}

fn sanitizePath(raw_path: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, raw_path, "/");
    if (trimmed.len == 0) return "";
    if (std.mem.containsAtLeast(u8, trimmed, 1, "\\")) return null;

    var segments = std.mem.splitScalar(u8, trimmed, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0) continue;
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) {
            return null;
        }
    }

    return trimmed;
}
