const std = @import("std");
const ErrorContext = @This();

errors: std.ArrayList([]const u8),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) ErrorContext {
    return .{
        .errors = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *ErrorContext) void {
    for (self.errors.items) |s| self.allocator.free(s);
    self.errors.deinit(self.allocator);
}

pub fn append(self: *ErrorContext, comptime fmt: []const u8, args: anytype) !void {
    try self.errors.append(self.allocator, try std.fmt.allocPrint(self.allocator, fmt, args));
}

pub fn printAll(self: ErrorContext, writer: *std.Io.Writer) !void {
    for (self.errors.items) |s| {
        try writer.writeAll(s);
    }
    try writer.flush();
}

pub fn hasErrors(self: ErrorContext) bool {
    return self.errors.items.len > 0;
}
