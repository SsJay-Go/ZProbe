const std = @import("std");

pub const Direction = enum {
    send,
    recv,
};

const Entry = struct {
    id: u64,
    timestamp_ms: i64,
    direction: Direction,
    category: []u8,
    message: []u8,
};

pub const EntryView = struct {
    id: u64,
    timestampMs: i64,
    direction: Direction,
    category: []const u8,
    message: []const u8,
};

pub const TrafficLogResponse = struct {
    entries: []const EntryView,
};

/// 应用内存中的轻量通信日志。
///
/// 这里刻意只保留一个有限长度环形缓冲，
/// 目标是让前端能看到最近一次“发了什么、收到了什么”，
/// 而不是把后端变成长期日志系统。
pub const TrafficLog = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    next_id: u64 = 1,
    max_entries: usize = 200,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator) TrafficLog {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *TrafficLog) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *TrafficLog, category: []const u8, direction: Direction, message: []const u8) void {
        self.acquireLock();
        defer self.releaseLock();

        if (self.entries.items.len >= self.max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.category);
            self.allocator.free(removed.message);
        }

        const owned_category = self.allocator.dupe(u8, category) catch return;
        errdefer self.allocator.free(owned_category);

        const owned_message = self.allocator.dupe(u8, message) catch return;
        errdefer self.allocator.free(owned_message);

        const entry_id = self.next_id;

        self.entries.append(self.allocator, .{
            .id = entry_id,
            .timestamp_ms = @as(i64, @intCast(entry_id)),
            .direction = direction,
            .category = owned_category,
            .message = owned_message,
        }) catch {
            self.allocator.free(owned_category);
            self.allocator.free(owned_message);
            return;
        };
        self.next_id += 1;
    }

    pub fn appendJson(self: *TrafficLog, temp_allocator: std.mem.Allocator, category: []const u8, direction: Direction, value: anytype) void {
        var out: std.Io.Writer.Allocating = .init(temp_allocator);
        defer out.deinit();

        std.json.Stringify.value(value, .{}, &out.writer) catch return;
        self.append(category, direction, out.written());
    }

    pub fn snapshotAlloc(self: *TrafficLog, allocator: std.mem.Allocator) ![]EntryView {
        self.acquireLock();
        defer self.releaseLock();

        const result = try allocator.alloc(EntryView, self.entries.items.len);
        errdefer allocator.free(result);

        for (self.entries.items, 0..) |entry, index| {
            const category = try allocator.dupe(u8, entry.category);
            errdefer allocator.free(category);

            const message = try allocator.dupe(u8, entry.message);
            errdefer allocator.free(message);

            result[index] = .{
                .id = entry.id,
                .timestampMs = entry.timestamp_ms,
                .direction = entry.direction,
                .category = category,
                .message = message,
            };
        }

        return result;
    }

    pub fn clear(self: *TrafficLog) void {
        self.acquireLock();
        defer self.releaseLock();

        for (self.entries.items) |entry| {
            self.allocator.free(entry.category);
            self.allocator.free(entry.message);
        }
        self.entries.clearRetainingCapacity();
    }

    fn acquireLock(self: *TrafficLog) void {
        while (!self.mutex.tryLock()) {}
    }

    fn releaseLock(self: *TrafficLog) void {
        self.mutex.unlock();
    }
};
