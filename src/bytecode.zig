const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const ByteCode = @This();
code: ArrayList(u8),
constants: ArrayList(Value),
lines: ArrayList(usize),
allocator: Allocator,

pub const OpCode = enum(u8) {
    OP_CONSTANT_LONG,
    OP_CONSTANT,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NOT,
    OP_NEGATE,
    OP_RETURN,
};

pub const ObjectType = enum {
    string,
};

pub const Object = struct {
    value: union(ObjectType) {
        string: []const u8,
    },
    hash: u32,
    next: ?*Object,
    pub fn initString(allocator: std.mem.Allocator, string: []const u8) !*Object {
        const object = try allocator.create(Object);
        object.value.string = string;
        object.hash = hashString(string);
        object.next = null;
        return object;
    }
    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .string => |value| allocator.free(value),
        }
        allocator.destroy(self);
        self.* = undefined;
    }
    // FNV-1a hash https://www.isthe.com/chongo/tech/comp/fnv/
    pub fn hashString(string: []const u8) u32 {
        var hash: u32 = 2166136261;
        for (0..string.len) |index| {
            hash ^= string[index];
            hash = @mulWithOverflow(hash, 16777619)[0];
        }
        return hash;
    }
    pub fn equals(self: Object, other: Object) bool {
        if (@backingInt(self.value) != @backingInt(other.value)) {
            return false;
        }
        if (self.hash != other.hash) {
            return false;
        }
        return switch (self.value) {
            .string => std.mem.eql(u8, self.value.string, other.value.string),
        };
    }
};

pub const ValueType = enum(u8) {
    number,
    bool,
    nil,
    object,
};

pub const Value = union(ValueType) {
    number: f64,
    bool: bool,
    nil: void,
    object: *Object,

    pub fn is(self: Value, comptime valueType: ValueType) bool {
        return self == valueType;
    }
    pub fn equals(self: Value, other: Value) bool {
        if (@backingInt(self) != @backingInt(other)) {
            return false;
        }
        return switch (self) {
            .bool => self.bool == other.bool,
            .nil => true,
            .number => self.number == other.number,
            .object => self.object.equals(other.object.*),
        };
    }
    pub fn isObjectAnd(self: Value, comptime objectType: ObjectType) bool {
        return switch (self) {
            .object => |object| object.*.value == objectType,
            else => false,
        };
    }
    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .object => |object| object.deinit(allocator),
            else => {},
        }
    }
};

pub fn init(allocator: Allocator) ByteCode {
    return .{
        .code = .empty,
        .constants = .empty,
        .lines = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *ByteCode) void {
    // Free only the object pointer for constant strings, the string is held by the scanner
    for (self.constants.items) |value| switch (value) {
        .object => |object| self.allocator.destroy(object),
        else => {},
    };
    self.code.deinit(self.allocator);
    self.constants.deinit(self.allocator);
    self.lines.deinit(self.allocator);
}

/// Schreibt ungeprüft direkt in das bytecode array
pub fn write(self: *ByteCode, instruction: u8, line: usize) !void {
    try self.code.append(self.allocator, instruction);

    if (self.lines.items.len == 0 or self.lines.last() != line) {
        try self.lines.append(self.allocator, 1);
        try self.lines.append(self.allocator, line);
    } else {
        self.lines.items[self.lines.items.len - 2] += 1;
    }
}

pub fn getLine(self: ByteCode, offset: usize) usize {
    var position: usize = 0;
    var index: usize = 0;
    while (index < (self.lines.items.len - 1)) : (index += 2) {
        position += self.lines.items[index];
        if (position > offset) {
            return self.lines.items[index + 1];
        }
    }
    return 0;
}

pub fn addOpCode(self: *ByteCode, opCode: OpCode, line: usize) !void {
    try self.write(@backingInt(opCode), line);
}

pub fn addConstant(self: *ByteCode, constant: Value, line: usize) !void {
    if (self.constants.items.len <= std.math.maxInt(u8)) {
        try self.addOpCode(OpCode.OP_CONSTANT, line);
        try self.constants.append(self.allocator, constant);
        try self.write(@intCast(self.constants.items.len - 1), line);
    } else {
        try self.addOpCode(OpCode.OP_CONSTANT_LONG, line);
        try self.constants.append(self.allocator, constant);
        const index: [3]u8 = @bitCast(@as(u24, @intCast(self.constants.items.len - 1)));
        try self.write(index[0], line);
        try self.write(index[1], line);
        try self.write(index[2], line);
    }
}

test "size of value should no longer increase with further variants" {
    try std.testing.expectEqual(16, @sizeOf(Value));
}

test "after reaching the u8 integer limit constant opCode become OP_CONSTANT_LONG with 3 bytes of index" {
    var chunk = ByteCode.init(std.testing.allocator);
    defer chunk.deinit();
    for (0..(std.math.maxInt(u8) + 1)) |_| {
        try chunk.addConstant(.{ .number = 0 }, 1);
    }
    // First opCode
    try std.testing.expectEqualSlices(u8, &[_]u8{ @backingInt(OpCode.OP_CONSTANT), 0 }, chunk.code.items[0..2]);
    // Last OP_CONSTANT opCode
    try std.testing.expectEqualSlices(u8, &[_]u8{ @backingInt(OpCode.OP_CONSTANT), 255 }, chunk.code.items[(chunk.code.items.len - 2)..chunk.code.items.len]);
    try chunk.addConstant(.{ .number = 0 }, 1);
    // First OP_CONSTANT_LONG opCode
    try std.testing.expectEqualSlices(u8, &[_]u8{ @backingInt(OpCode.OP_CONSTANT_LONG), 0, 1, 0 }, chunk.code.items[(chunk.code.items.len - 4)..chunk.code.items.len]);
}

test "line information is compressed via run length encoding" {
    var chunk = ByteCode.init(std.testing.allocator);
    defer chunk.deinit();
    for (0..50) |_| {
        try chunk.addOpCode(OpCode.OP_NIL, 1);
    }
    for (0..50) |_| {
        try chunk.addOpCode(OpCode.OP_NIL, 2);
    }
    // Length should only be 4 because of encoding
    try std.testing.expectEqual(4, chunk.lines.items.len);
    try std.testing.expectEqual(50, chunk.lines.items[0]);
    try std.testing.expectEqual(1, chunk.lines.items[1]);
    // Check boundary values
    try std.testing.expectEqual(1, chunk.getLine(0));
    try std.testing.expectEqual(1, chunk.getLine(49));
    try std.testing.expectEqual(2, chunk.getLine(50));
    try std.testing.expectEqual(2, chunk.getLine(99));
    // Out of bounds access simply returns 0
    try std.testing.expectEqual(0, chunk.getLine(100));
}
