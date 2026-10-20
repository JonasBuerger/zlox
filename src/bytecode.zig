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
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NEGATE,
    OP_RETURN,
};

pub const ValueType = enum {
    number,
    nil,
};

pub const Value = union(ValueType) {
    number: f64,
    nil: void,
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
