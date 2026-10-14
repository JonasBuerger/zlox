const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const OpCode = enum(u8) {
    OP_CONSTANT_LONG,
    OP_CONSTANT,
    OP_RETURN,
};

pub const ValueType = enum {
    number,
};

pub const Value = union(ValueType) {
    number: f64,
};

pub fn ManagedChunk() type {
    return struct {
        code: ArrayList(u8),
        constants: ArrayList(Value),
        lines: ArrayList(usize),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .code = .empty,
                .constants = .empty,
                .lines = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.code.deinit(self.allocator);
            self.constants.deinit(self.allocator);
            self.lines.deinit(self.allocator);
        }

        /// Schreibt ungeprüft direkt in das bytecode array
        pub fn write(self: *Self, instruction: u8, line: usize) !void {
            try self.code.append(self.allocator, instruction);
            try self.lines.append(self.allocator, line);
        }

        pub fn addOpCode(self: *Self, opCode: OpCode, line: usize) !void {
            try self.write(@backingInt(opCode), line);
        }

        pub fn addConstant(self: *Self, constant: Value, line: usize) !void {
            if (self.constants.items.len < 256) {
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
    };
}
