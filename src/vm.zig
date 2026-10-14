const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const Chunk = @import("chunk.zig").ManagedChunk;
const OpCode = @import("chunk.zig").OpCode;

pub const InterpretError = error{
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

pub const VirtualMachine = struct {
    chunk: ?*Chunk,
    ip: ?[*]u8,
    allocator: Allocator,
    io: std.Io,

    const Self = @This();

    pub fn init(allocator: Allocator, io: std.Io) Self {
        return .{
            .chunk = null,
            .ip = null,
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn interpret(self: *Self, chunk: *Chunk) InterpretError!void {
        self.chunk = chunk;
        self.chunk.?.code.lockPointers();
        defer self.chunk.?.code.unlockPointers();
        self.ip = self.chunk.?.code.items.ptr;
        try run(self);
    }

    fn run(self: *Self) InterpretError!void {
        while (true) {
            switch (readByte(self)) {
                @backingInt(OpCode.OP_RETURN) => return,
                else => return InterpretError.RUNTIME_ERROR,
            }
        }
    }

    /// Demons, noses you know the spiel.
    /// Would love to just use array indexing, gonna stick with the book for now.
    /// Perf comparison later on would be cool.
    fn readByte(self: *Self) u8 {
        const instruction = self.ip.?[0];
        self.ip.? += 1;
        return instruction;
    }
};
