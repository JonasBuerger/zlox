const Scanner = @This();
const std = @import("std");

start: ?[*]u8,
current: ?[*]u8,
line: usize,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Scanner {
    return .{
        .start = null,
        .current = null,
        .line = 1,
        .allocator = allocator,
    };
}
