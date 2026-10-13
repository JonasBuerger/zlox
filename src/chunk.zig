const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const OpCode = enum(u8) {
    OP_CONSTANT,
    OP_RETURN,
};

pub const Value = union {
    number: f64
};

pub fn ManagedChunk() type {
    return struct {
        code: ArrayList(u8),
        constants: ArrayList(Value),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .code = .empty,
                .constants = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.code.deinit(self.allocator);
            self.constants.deinit(self.allocator);
        }

        pub fn addOpCode(self: *Self, opCode: OpCode) !void {
            try self.addInstruction(@backingInt(opCode));
        }

        pub fn addInstruction(self: *Self, instruction: u8) !void {
            try self.code.append(self.allocator, instruction);
        }

        pub fn addConstant(self: *Self, constant: Value) !u8 {
            try self.constants.append(self.allocator, constant);
            return @intCast(self.constants.items.len - 1);
        }
    };
}
