const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const Chunk = @import("chunk.zig").ManagedChunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("chunk.zig").Value;
const trace_execution = @import("build_options").trace_execution;
const debug = @import("debug.zig");

pub const InterpretError = error{
    COMPILE_ERROR,
    RUNTIME_ERROR,
    RUNTIME_CRASH,
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
        try self.run();
    }

    fn run(self: *Self) InterpretError!void {
        var writer_buffer: [2048]u8 = undefined;
        var file_writer: std.Io.File.Writer = .init(.stdout(), self.io, &writer_buffer);
        const writer = &file_writer.interface;

        if(comptime trace_execution){
            debug.printTableHead(writer) catch return InterpretError.RUNTIME_CRASH;
        }

        while (true) {
            if(comptime trace_execution){
                _ = debug.disassembleInstruction(self.chunk.?,self.ip.?-self.chunk.?.code.items.ptr,writer) catch return InterpretError.RUNTIME_CRASH;
            }
            switch (self.readByte()) {
                @backingInt(OpCode.OP_RETURN) => break,
                @backingInt(OpCode.OP_CONSTANT) => {
                    printValue(writer, self.readConstant()) catch return InterpretError.RUNTIME_CRASH;
                    writer.print("\n",.{}) catch return InterpretError.RUNTIME_CRASH;
                    writer.flush() catch return InterpretError.RUNTIME_CRASH;
                },
                @backingInt(OpCode.OP_CONSTANT_LONG) => {
                    printValue(writer, self.readConstantLong()) catch return InterpretError.RUNTIME_CRASH;
                    writer.print("\n",.{}) catch return InterpretError.RUNTIME_CRASH;
                    writer.flush() catch return InterpretError.RUNTIME_CRASH;
                },
                else => return InterpretError.RUNTIME_ERROR,
            }

            if (writer.unusedCapacityLen() < 1024) {
            }
        }
        if(comptime trace_execution){
           debug.printTableFoot(writer) catch return InterpretError.RUNTIME_CRASH;
        }
        writer.flush() catch return InterpretError.RUNTIME_CRASH;
    }

    /// Demons, noses you know the spiel.
    /// Would love to just use array indexing, gonna stick with the book for now.
    /// Perf comparison later on would be cool.
    fn readByte(self: *Self) u8 {
        const instruction = self.ip.?[0];
        self.ip = self.ip.? + 1;
        return instruction;
    }

    fn readConstant(self: *Self) Value {
        const valueIndex = self.readByte();
        return self.chunk.?.constants.items[valueIndex];
    }
    fn readConstantLong(self: *Self) Value {
        const valueIndex = @as(u24, self.readByte()) | (@as(u24, self.readByte()) << 8) | (@as(u24, self.readByte()) << 16);
        return self.chunk.?.constants.items[valueIndex];
    }

    fn printValue(writer: *std.Io.Writer,value:Value) !void {
            switch (value) {
                .number => |v| {
                     try writer.print("{d}", .{v});
                },
            }
    }
};
