const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;

/// Pings a machine given a FQDN using the system's ping command in a multithreaded context.
/// The is_alive pointer is shared between threads, a mutex is used to ensure thread safety.
/// If forever, run indefinitely with a 5 second sleep between pings.
pub fn ping_with_os_command_multithread(allocator: Allocator, io: Io, fqdn: []const u8, forever: bool, mutex: *Io.Mutex, is_alive: *bool) !void {
    while (true) {
        const ping_result = ping_with_os_command(allocator, io, fqdn) catch |err| {
            return err;
        };

        // lock the mutex while updating the shared is_alive variable
        mutex.lockUncancelable(io);
        is_alive.* = ping_result;
        mutex.unlock(io);

        if (!forever) break;
        try Io.sleep(io, .fromSeconds(5), .real); // do not spam too many pings if pinging forever
    }
}

/// Pings a machine given a FQDN using the system's ping command, returns true if the ping was successful, false otherwise.
pub fn ping_with_os_command(allocator: Allocator, io: Io, fqdn: []const u8) !bool {
    const args = switch (builtin.target.os.tag) {
        .linux, .macos => &[_][]const u8{ "ping", "-c", "1", "-W", "1", fqdn },
        .windows => &[_][]const u8{ "ping", "-n", "1", "-w", "1000", fqdn },
        else => @compileError("Unsupported OS"),
    };

    const result = try std.process.run(allocator, io, .{
        .argv = args,
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    if (result.term.exited == 0 and
        std.mem.find(u8, result.stdout, "unreachable") == null and
        std.mem.find(u8, result.stderr, "unreachable") == null)
    {
        return true;
    } else {
        return false;
    }
}

test "ping_with_os_command" {
    try testing.expectEqual(true, try ping_with_os_command(testing.allocator, testing.io, "127.0.0.1"));
    try testing.expectEqual(true, try ping_with_os_command(testing.allocator, testing.io, "localhost"));
    try testing.expectEqual(false, try ping_with_os_command(testing.allocator, testing.io, "256.256.256.256"));
}
