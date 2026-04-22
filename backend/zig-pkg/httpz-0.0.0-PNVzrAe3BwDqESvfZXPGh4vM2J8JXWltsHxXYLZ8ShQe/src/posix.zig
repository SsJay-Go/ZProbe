const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
// Zig 0.16 将 Windows API 命名空间稳定在 std.os.windows，
// 旧代码里的 std.io.windows 在新版本中已经不存在。
const windows = std.os.windows;
pub const system = posix.system;

pub const O = system.O;
pub const F = system.F;
pub const AF = posix.AF;
pub const SO = posix.SO;
pub const SOL = posix.SOL;
// 这层兼容常量的目的，是让上层继续沿用 `posix.SOCK.*` 这套接口，
// 同时把 Zig 0.16 / Windows 缺失的 NONBLOCK、CLOEXEC 收口在一个地方处理。
pub const SOCK = struct {
    pub const STREAM = posix.SOCK.STREAM;
    pub const DGRAM = posix.SOCK.DGRAM;
    pub const RAW = posix.SOCK.RAW;
    pub const RDM = if (@hasDecl(posix.SOCK, "RDM")) posix.SOCK.RDM else 4;
    pub const SEQPACKET = if (@hasDecl(posix.SOCK, "SEQPACKET")) posix.SOCK.SEQPACKET else 5;
    pub const NONBLOCK: u32 = if (builtin.os.tag == .windows) 0x4000_0000 else posix.SOCK.NONBLOCK;
    pub const CLOEXEC: u32 = if (builtin.os.tag == .windows) 0x2000_0000 else posix.SOCK.CLOEXEC;
};
pub const fd_t = posix.fd_t;
pub const socket_t = posix.socket_t;
pub const timeval = posix.timeval;
pub const IPPROTO = posix.IPPROTO;
pub const sockaddr = posix.sockaddr;
pub const timespec = posix.timespec;
pub const socklen_t = posix.socklen_t;
pub const Kevent = system.Kevent;

const native_os = builtin.os.tag;

const WSAData = extern struct {
    wVersion: windows.WORD,
    wHighVersion: windows.WORD,
    szDescription: [257]u8,
    szSystemStatus: [129]u8,
    iMaxSockets: windows.WORD,
    iMaxUdpDg: windows.WORD,
    lpVendorInfo: ?[*:0]u8,
};

extern "ws2_32" fn WSAStartup(wVersionRequired: windows.WORD, lpWSAData: *WSAData) callconv(.winapi) c_int;

var winsock_initialized = false;

fn ensureWindowsSocketsInitialized() !void {
    if (!winsock_initialized) {
        var wsa_data: WSAData = undefined;
        const rc = WSAStartup(0x0202, &wsa_data);
        if (rc != 0) return error.Unexpected;
        winsock_initialized = true;
    }
}

pub fn socket(domain: u32, socket_type: u32, protocol: u32) !socket_t {
    if (native_os == .windows) {
        // Windows 下这里仍然走 libc socket，但必须先显式拦截失败返回值。
        // 否则 rc 为 -1 时，后续整数到句柄的转换会在 @intCast 处直接 panic。
        try ensureWindowsSocketsInitialized();
        const filtered_sock_type = socket_type & ~@as(u32, SOCK.NONBLOCK | SOCK.CLOEXEC);
        const rc = system.socket(domain, filtered_sock_type, protocol);
        if (rc == -1) {
            return error.Unexpected;
        }

        const fd: fd_t = @ptrFromInt(@as(usize, @intCast(rc)));
        errdefer close(fd);
        try setSockFlags(fd, socket_type);
        return fd;
    }

    const have_sock_flags = !builtin.target.os.tag.isDarwin() and native_os != .haiku;
    const filtered_sock_type = if (!have_sock_flags)
        socket_type & ~@as(u32, SOCK.NONBLOCK | SOCK.CLOEXEC)
    else
        socket_type;
    const rc = posix.system.socket(domain, filtered_sock_type, protocol);
    switch (posix.errno(rc)) {
        .SUCCESS => {
            const fd: fd_t = @intCast(rc);
            errdefer close(fd);
            if (!have_sock_flags) {
                try setSockFlags(fd, socket_type);
            }
            return fd;
        },
        .ACCES => return error.AccessDenied,
        .AFNOSUPPORT => return error.AddressFamilyNotSupported,
        .INVAL => return error.ProtocolFamilyNotAvailable,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOBUFS => return error.SystemResources,
        .NOMEM => return error.SystemResources,
        .PROTONOSUPPORT => return error.ProtocolNotSupported,
        .PROTOTYPE => return error.SocketTypeNotSupported,
        else => return error.Unexpected,
    }
}

fn setSockFlags(sock: socket_t, flags: u32) !void {
    if ((flags & SOCK.CLOEXEC) != 0) {
        if (native_os == .windows) {
            // TODO: Find out if this is supported for sockets
        } else {
            var fd_flags = fcntl(sock, F.GETFD, 0) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                error.DeadLock => unreachable,
                error.LockedRegionLimitExceeded => unreachable,
                else => |e| return e,
            };
            fd_flags |= system.FD_CLOEXEC;
            _ = fcntl(sock, F.SETFD, fd_flags) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                error.DeadLock => unreachable,
                error.LockedRegionLimitExceeded => unreachable,
                else => |e| return e,
            };
        }
    }
    if ((flags & SOCK.NONBLOCK) != 0) {
        if (native_os == .windows) {
            // Zig 0.16 当前标准库未提供旧版 ioctlsocket 包装。
            // 在当前项目里 Windows 主路径并不依赖这里切到非阻塞，
            // 因此先安全退化为保持阻塞模式，避免为了兼容补丁继续引入更深的 Winsock 绑定。
        } else {
            var fl_flags = fcntl(sock, F.GETFL, 0) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                error.DeadLock => unreachable,
                error.LockedRegionLimitExceeded => unreachable,
                else => |e| return e,
            };
            fl_flags |= 1 << @bitOffsetOf(O, "NONBLOCK");
            _ = fcntl(sock, F.SETFL, fl_flags) catch |err| switch (err) {
                error.FileBusy => unreachable,
                error.Locked => unreachable,
                error.PermissionDenied => unreachable,
                error.DeadLock => unreachable,
                error.LockedRegionLimitExceeded => unreachable,
                else => |e| return e,
            };
        }
    }
}

pub fn fcntl(fd: fd_t, cmd: i32, arg: usize) !usize {
    while (true) {
        const rc = posix.system.fcntl(fd, cmd, arg);
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .AGAIN, .ACCES => return error.Locked,
            .BADF => unreachable,
            .BUSY => return error.FileBusy,
            .INVAL => unreachable, // invalid parameters
            .PERM => return error.PermissionDenied,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NOTDIR => unreachable, // invalid parameter
            .DEADLK => return error.DeadLock,
            .NOLCK => return error.LockedRegionLimitExceeded,
            else => return error.Unexpected,
        }
    }
}

pub fn close(fd: fd_t) void {
    if (native_os == .windows) {
        _ = system.close(fd);
        return;
    }
    switch (posix.errno(system.close(fd))) {
        .BADF => unreachable, // Always a race condition.
        .INTR => return, // This is still a success. See https://github.com/ziglang/zig/issues/2425
        else => return,
    }
}

pub fn setsockopt(fd: socket_t, level: i32, optname: u32, opt: []const u8) !void {
    if (native_os == .windows) {
        // 这里直接回落到 libc 的 setsockopt，避免继续依赖 Zig 0.16 已移除的 ws2_32 包装函数。
        if (system.setsockopt(fd, level, optname, opt.ptr, @intCast(opt.len)) != 0) return error.Unexpected;
        return;
    } else {
        switch (posix.errno(system.setsockopt(fd, level, optname, opt.ptr, @intCast(opt.len)))) {
            .SUCCESS => {},
            .BADF => unreachable, // always a race condition
            .NOTSOCK => unreachable, // always a race condition
            .INVAL => unreachable,
            .FAULT => unreachable,
            .DOM => return error.TimeoutTooBig,
            .ISCONN => return error.AlreadyConnected,
            .NOPROTOOPT => return error.InvalidProtocolOption,
            .NOMEM => return error.SystemResources,
            .NOBUFS => return error.SystemResources,
            .PERM => return error.PermissionDenied,
            .NODEV => return error.NoDevice,
            .OPNOTSUPP => return error.OperationNotSupported,
            else => return error.Unexpected,
        }
    }
}

pub fn bind(sock: socket_t, addr: *const sockaddr, len: socklen_t) !void {
    if (native_os == .windows) {
        // Zig 0.16 不再暴露旧的 windows.bind 包装，这里直接退回 libc bind。
        if (system.bind(sock, addr, len) != 0) return error.Unexpected;
        return;
    } else {
        const rc = system.bind(sock, addr, len);
        switch (posix.errno(rc)) {
            .SUCCESS => return,
            .ACCES, .PERM => return error.AccessDenied,
            .ADDRINUSE => return error.AddressInUse,
            .BADF => unreachable, // always a race condition if this error is returned
            .INVAL => unreachable, // invalid parameters
            .NOTSOCK => unreachable, // invalid `sockfd`
            .AFNOSUPPORT => return error.AddressFamilyNotSupported,
            .ADDRNOTAVAIL => return error.AddressNotAvailable,
            .FAULT => unreachable, // invalid `addr` pointer
            .LOOP => return error.SymLinkLoop,
            .NAMETOOLONG => return error.NameTooLong,
            .NOENT => return error.FileNotFound,
            .NOMEM => return error.SystemResources,
            .NOTDIR => return error.NotDir,
            .ROFS => return error.ReadOnlyFileSystem,
            else => return error.Unexpected,
        }
    }
    unreachable;
}

pub const Address = extern union {
    any: posix.sockaddr,
    in: posix.sockaddr.in,
    in6: posix.sockaddr.in6,
    un: if (@hasDecl(posix.sockaddr, "un")) posix.sockaddr.un else posix.sockaddr,

    pub fn initUnix(path: []const u8) !Address {
        var sock_addr = posix.sockaddr.un{
            .family = AF.UNIX,
            .path = undefined,
        };

        // Add 1 to ensure a terminating 0 is present in the path array for maximum portability.
        if (path.len + 1 > sock_addr.path.len) {
            return error.NameTooLong;
        }

        @memset(&sock_addr.path, 0);
        @memcpy(sock_addr.path[0..path.len], path);

        return .{ .un = sock_addr };
    }

    pub fn initIp4(addr: [4]u8, port: u16) !Address {
        return .{ .in = .{
            .port = std.mem.nativeToBig(u16, port),
            .addr = @as(*align(1) const u32, @ptrCast(&addr)).*,
        } };
    }

    pub fn initIp6(addr: [16]u8, port: u16, flowinfo: u32, scope_id: u32) !Address {
        return .{ .in6 = .{
            .addr = addr,
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = flowinfo,
            .scope_id = scope_id,
        } };
    }

    pub fn getOsSockLen(self: Address) posix.socklen_t {
        return switch (self.any.family) {
            posix.AF.INET => @sizeOf(posix.sockaddr.in),
            posix.AF.INET6 => @sizeOf(posix.sockaddr.in6),
            posix.AF.UNIX => if (@hasDecl(posix.sockaddr, "un"))
                @intCast(@offsetOf(posix.sockaddr.un, "path") + std.mem.indexOfScalar(u8, &self.un.path, 0).? + 1)
            else
                @sizeOf(posix.sockaddr),
            else => @sizeOf(posix.sockaddr),
        };
    }

    pub fn toIOAddress(self: Address) std.Io.net.IpAddress {
        return switch (self.any.family) {
            posix.AF.INET => {
                const bytes: *const [4]u8 = @ptrCast(&self.in.addr);
                return .{ .ip4 = .{ .bytes = bytes.*, .port = std.mem.bigToNative(u16, self.in.port) } };
            },
            posix.AF.INET6 => {
                // @ZIG016 I don't think this is correct
                const bytes: *const [16]u8 = @ptrCast(&self.in.addr);
                return .{ .ip6 = .{ .bytes = bytes.*, .port = std.mem.bigToNative(u16, self.in.port) } };
            },
            else => .{ .ip4 = .unspecified(0) },
        };
    }

    // Zig 0.16 的 Writer 格式化协议会优先找自定义 format 方法。
    // 这里补一个最小实现，让 httpz 现有的地址日志输出继续可用。
    pub fn format(self: Address, writer: *std.Io.Writer) !void {
        switch (self.any.family) {
            posix.AF.INET, posix.AF.INET6 => {
                try writer.print("{}", .{self.toIOAddress()});
            },
            posix.AF.UNIX => {
                if (@hasDecl(posix.sockaddr, "un")) {
                    const end = std.mem.indexOfScalar(u8, &self.un.path, 0) orelse self.un.path.len;
                    try writer.print("unix:{s}", .{self.un.path[0..end]});
                } else {
                    try writer.writeAll("unix");
                }
            },
            else => {
                try writer.writeAll("unknown-address");
            },
        }
    }
};

pub fn listen(sock: socket_t, backlog: u31) !void {
    if (native_os == .windows) {
        if (system.listen(sock, backlog) != 0) return error.Unexpected;
        return;
    } else {
        const rc = system.listen(sock, backlog);
        switch (posix.errno(rc)) {
            .SUCCESS => return,
            .ADDRINUSE => return error.AddressInUse,
            .BADF => unreachable,
            .NOTSOCK => return error.FileDescriptorNotASocket,
            .OPNOTSUPP => return error.OperationNotSupported,
            else => return error.Unexpected,
        }
    }
}

pub fn accept(
    /// This argument is a socket that has been created with `socket`, bound to a local address
    /// with `bind`, and is listening for connections after a `listen`.
    sock: socket_t,
    /// This argument is a pointer to a sockaddr structure.  This structure is filled in with  the
    /// address  of  the  peer  socket, as known to the communications layer.  The exact format of the
    /// address returned addr is determined by the socket's address  family  (see  `socket`  and  the
    /// respective  protocol  man  pages).
    addr: ?*sockaddr,
    /// This argument is a value-result argument: the caller must initialize it to contain  the
    /// size (in bytes) of the structure pointed to by addr; on return it will contain the actual size
    /// of the peer address.
    ///
    /// The returned address is truncated if the buffer provided is too small; in this  case,  `addr_size`
    /// will return a value greater than was supplied to the call.
    addr_size: ?*socklen_t,
    /// The following values can be bitwise ORed in flags to obtain different behavior:
    /// * `SOCK.NONBLOCK` - Set the `NONBLOCK` file status flag on the open file description (see `open`)
    ///   referred  to by the new file descriptor.  Using this flag saves extra calls to `fcntl` to achieve
    ///   the same result.
    /// * `SOCK.CLOEXEC`  - Set the close-on-exec (`FD_CLOEXEC`) flag on the new file descriptor.   See  the
    ///   description  of the `CLOEXEC` flag in `open` for reasons why this may be useful.
    flags: u32,
) !socket_t {
    const have_accept4 = !(builtin.target.os.tag.isDarwin() or native_os == .windows or native_os == .haiku);
    std.debug.assert(0 == (flags & ~@as(u32, SOCK.NONBLOCK | SOCK.CLOEXEC))); // Unsupported flag(s)

    const accepted_sock: socket_t = while (true) {
        const rc = if (have_accept4)
            system.accept4(sock, addr, addr_size, flags)
        else
            system.accept(sock, addr, addr_size);

        if (native_os == .windows) {
            if (rc == -1) return error.Unexpected;
            break @ptrFromInt(@as(usize, @intCast(rc)));
        } else {
            switch (posix.errno(rc)) {
                .SUCCESS => break @intCast(rc),
                .INTR => continue,
                .AGAIN => return error.WouldBlock,
                .BADF => {
                    // ZIG016 This is not right. If we hit this, it's always certainly
                    // an error - we're trying to read from a socket after it's been closed
                    // which is not safe. But, the code around this worked in 0.15 and I
                    // consider this entire 0.16 transition experimental.
                    return error.SocketNotListening;
                },
                .CONNABORTED => return error.ConnectionAborted,
                .FAULT => unreachable,
                .INVAL => return error.SocketNotListening,
                .NOTSOCK => unreachable,
                .MFILE => return error.ProcessFdQuotaExceeded,
                .NFILE => return error.SystemFdQuotaExceeded,
                .NOBUFS => return error.SystemResources,
                .NOMEM => return error.SystemResources,
                .OPNOTSUPP => unreachable,
                .PROTO => return error.ProtocolFailure,
                .PERM => return error.BlockedByFirewall,
                else => return error.Unexpected,
            }
        }
    };

    errdefer switch (native_os) {
        .windows => windows.closesocket(accepted_sock) catch unreachable,
        else => close(accepted_sock),
    };
    if (!have_accept4) {
        try setSockFlags(accepted_sock, flags);
    }
    return accepted_sock;
}

const iovec_const = extern struct {
    base: [*]const u8,
    len: usize,
};

pub fn write(fd: fd_t, bytes: []const u8) !usize {
    if (bytes.len == 0) return 0;
    if (native_os == .windows) {
        const rc = system.send(fd, bytes.ptr, bytes.len, 0);
        if (rc < 0) return error.WouldBlock;
        return @intCast(rc);
    }

    const max_count = switch (native_os) {
        .linux => 0x7ffff000,
        .macos, .ios, .watchos, .tvos, .visionos => std.math.maxInt(i32),
        else => std.math.maxInt(isize),
    };
    while (true) {
        const rc = system.write(fd, bytes.ptr, @min(bytes.len, max_count));
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .INVAL => return error.InvalidArgument,
            .FAULT => unreachable,
            .SRCH => return error.ProcessNotFound,
            .AGAIN => return error.WouldBlock,
            .BADF => return error.NotOpenForWriting, // can be a race condition.
            .DESTADDRREQ => unreachable, // `connect` was never called.
            .DQUOT => return error.DiskQuota,
            .FBIG => return error.FileTooBig,
            .IO => return error.InputOutput,
            .NOSPC => return error.NoSpaceLeft,
            .ACCES => return error.AccessDenied,
            .PERM => return error.PermissionDenied,
            .PIPE => return error.BrokenPipe,
            .CONNRESET => return error.ConnectionResetByPeer,
            .BUSY => return error.DeviceBusy,
            .NXIO => return error.NoDevice,
            .MSGSIZE => return error.MessageTooBig,
            else => return error.Unexpected,
        }
    }
}

pub fn read(fd: fd_t, buf: []u8) !usize {
    if (buf.len == 0) return 0;
    if (native_os == .windows) {
        const rc = system.recv(fd, buf.ptr, buf.len, 0);
        if (rc < 0) return error.WouldBlock;
        return @intCast(rc);
    }

    // Prevents EINVAL.
    const max_count = switch (native_os) {
        .linux => 0x7ffff000,
        .macos, .ios, .watchos, .tvos, .visionos => std.math.maxInt(i32),
        else => std.math.maxInt(isize),
    };
    while (true) {
        const rc = system.read(fd, buf.ptr, @min(buf.len, max_count));
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .INVAL => unreachable,
            .FAULT => unreachable,
            .SRCH => return error.ProcessNotFound,
            .AGAIN => return error.WouldBlock,
            .CANCELED => return error.Canceled,
            .BADF => return error.NotOpenForReading, // Can be a race condition.
            .IO => return error.InputOutput,
            .ISDIR => return error.IsDir,
            .NOBUFS => return error.SystemResources,
            .NOMEM => return error.SystemResources,
            .NOTCONN => return error.SocketNotConnected,
            .CONNRESET => return error.ConnectionResetByPeer,
            .TIMEDOUT => return error.ConnectionTimedOut,
            else => return error.Unexpected,
        }
    }
}

pub const ShutdownHow = enum { recv, send, both };

/// Shutdown socket send/receive operations
pub fn shutdown(sock: socket_t, how: ShutdownHow) !void {
    if (native_os == .windows) {
        // Zig 0.16 的 ws2_32 模块只保留常量和结构体，
        // 实际的 libc socket 符号需要从 std.c 走，才能在 Windows 下继续调用 shutdown。
        const result = std.c.shutdown(sock, switch (how) {
            // Winsock 的 shutdown 参数本质上就是 0/1/2，
            // Zig 0.16 的 ws2_32 模块不再导出这组常量，因此在兼容层显式写明。
            .recv => 0,
            .send => 1,
            .both => 2,
        });
        if (0 != result) return error.Unexpected;
    } else {
        const rc = system.shutdown(sock, switch (how) {
            .recv => posix.SHUT.RD,
            .send => posix.SHUT.WR,
            .both => posix.SHUT.RDWR,
        });
        switch (posix.errno(rc)) {
            .SUCCESS => return,
            .BADF => unreachable,
            .INVAL => unreachable,
            .NOTCONN => return error.SocketNotConnected,
            .NOTSOCK => unreachable,
            .NOBUFS => return error.SystemResources,
            else => return error.Unexpected,
        }
    }
}

pub fn kevent(
    kq: i32,
    changelist: []const Kevent,
    eventlist: []Kevent,
    timeout: ?*const timespec,
) !usize {
    while (true) {
        const rc = system.kevent(
            kq,
            changelist.ptr,
            std.math.cast(c_int, changelist.len) orelse return error.Overflow,
            eventlist.ptr,
            std.math.cast(c_int, eventlist.len) orelse return error.Overflow,
            timeout,
        );
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .ACCES => return error.AccessDenied,
            .FAULT => unreachable,
            .BADF => unreachable, // Always a race condition.
            .INTR => continue,
            .INVAL => unreachable,
            .NOENT => return error.EventNotFound,
            .NOMEM => return error.SystemResources,
            .SRCH => return error.ProcessNotFound,
            else => unreachable,
        }
    }
}

pub fn kqueue() !i32 {
    const rc = system.kqueue();
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        else => return error.Unexpected,
    }
}

pub fn eventfd(initval: u32, flags: u32) !i32 {
    const rc = system.eventfd(initval, flags);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .INVAL => unreachable, // invalid parameters
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NODEV => return error.SystemResources,
        .NOMEM => return error.SystemResources,
        else => return error.Unexpected,
    }
}

pub fn epoll_create1(flags: u32) !i32 {
    const rc = system.epoll_create1(flags);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .INVAL => unreachable,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOMEM => return error.SystemResources,
        else => return error.Unexpected,
    }
}

pub fn epoll_ctl(epfd: i32, op: u32, fd: i32, event: ?*system.epoll_event) !void {
    const rc = system.epoll_ctl(epfd, op, fd, event);
    switch (posix.errno(rc)) {
        .SUCCESS => return,
        .BADF => unreachable, // always a race condition if this happens
        .EXIST => return error.FileDescriptorAlreadyPresentInSet,
        .INVAL => unreachable,
        .LOOP => return error.OperationCausesCircularLoop,
        .NOENT => return error.FileDescriptorNotRegistered,
        .NOMEM => return error.SystemResources,
        .NOSPC => return error.UserResourceLimitReached,
        .PERM => return error.FileDescriptorIncompatibleWithEpoll,
        else => return error.Unexpected,
    }
}

/// Waits for an I/O event on an epoll file descriptor.
/// Returns the number of file descriptors ready for the requested I/O,
/// or zero if no file descriptor became ready during the requested timeout milliseconds.
pub fn epoll_wait(epfd: i32, events: []system.epoll_event, timeout: i32) usize {
    while (true) {
        // TODO get rid of the @intCast
        const rc = system.epoll_wait(epfd, events.ptr, @intCast(events.len), timeout);
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .BADF => unreachable,
            .FAULT => unreachable,
            .INVAL => unreachable,
            else => unreachable,
        }
    }
}
