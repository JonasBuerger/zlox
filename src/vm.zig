const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;
const Chunk = @import("chunk.zig").ManagedChunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("chunk.zig").Value;
const trace_execution = @import("build_options").trace_execution;
const stack_trace = @import("build_options").stack_trace;
const debug = @import("debug.zig");

pub const InterpretError = error{
    COMPILE_ERROR,
    STACK_OVERFLOW,
    STACK_UNDERFLOW,
    RUNTIME_ERROR,
    WRITER_ERROR,
};

pub const VirtualMachine = struct {
    chunk: ?*Chunk,
    ip: ?[*]u8,
    stack: std.ArrayList(Value),
    allocator: Allocator,
    io: std.Io,

    const Self = @This();

    pub fn init(allocator: Allocator, io: std.Io) Self {
        return .{
            .chunk = null,
            .ip = null,
            .stack = .empty,
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
    }

    pub fn interpret(self: *Self, chunk: *Chunk) InterpretError!void {
        self.chunk = chunk;
        self.chunk.?.code.lockPointers();
        defer self.chunk.?.code.unlockPointers();
        self.ip = self.chunk.?.code.items.ptr;
        self.stack.clearAndFree(self.allocator);
        try self.run();
    }

    fn run(self: *Self) InterpretError!void {
        var writer_buffer: [2048]u8 = undefined;
        var file_writer: std.Io.File.Writer = .init(.stdout(), self.io, &writer_buffer);
        const writer = &file_writer.interface;
        const starttime = std.Io.Clock.now(.cpu_thread, self.io);

        if (comptime trace_execution) {
            debug.printTableHead(writer) catch return error.WRITER_ERROR;
        }

        while (true) {
            if (comptime trace_execution) {
                if (comptime stack_trace) {
                    writer.print("│", .{}) catch return error.WRITER_ERROR;
                    for (self.stack.items) |stackValue| {
                        try printValue(writer, stackValue);

                        writer.print("│", .{}) catch return error.WRITER_ERROR;
                    }
                    writer.print("\n", .{}) catch return error.WRITER_ERROR;
                }
                _ = debug.disassembleInstruction(self.chunk.?, self.ip.? - self.chunk.?.code.items.ptr, writer) catch return error.WRITER_ERROR;
            }
            switch (self.readByte()) {
                @backingInt(OpCode.OP_CONSTANT) => try self.pushStack(self.readConstant()),
                @backingInt(OpCode.OP_CONSTANT_LONG) => try self.pushStack(self.readConstantLong()),
                @backingInt(OpCode.OP_NEGATE) => try self.pushStack(Value{ .number = -try self.popStackNumber() }),
                @backingInt(OpCode.OP_ADD),
                @backingInt(OpCode.OP_SUBTRACT),
                @backingInt(OpCode.OP_MULTIPLY),
                @backingInt(OpCode.OP_DIVIDE),
                => |opCode| {
                    const a = try self.popStackNumber();
                    const b = try self.popStackNumber();
                    try switch (opCode) {
                        @backingInt(OpCode.OP_ADD) => self.pushStack(Value{ .number = a + b }),
                        @backingInt(OpCode.OP_SUBTRACT) => self.pushStack(Value{ .number = a - b }),
                        @backingInt(OpCode.OP_MULTIPLY) => self.pushStack(Value{ .number = a * b }),
                        @backingInt(OpCode.OP_DIVIDE) => self.pushStack(Value{ .number = a / b }),
                        else => unreachable,
                    };
                },
                @backingInt(OpCode.OP_RETURN) => {
                    try printValue(writer, self.stack.pop() orelse .nil);
                    writer.print("\n", .{}) catch return error.WRITER_ERROR;
                    break;
                },
                else => return error.RUNTIME_ERROR,
            }

            if (writer.unusedCapacityLen() < 1024) {}
        }
        if (comptime trace_execution) {
            debug.printTableFoot(writer) catch return error.WRITER_ERROR;
            const runtime = @as(f64, @floatFromInt(starttime.untilNow(self.io, .cpu_thread).toMicroseconds())) / 1000.0;
            writer.print("Runtime: {d:.3}ms\n", .{runtime}) catch return error.WRITER_ERROR;
        }
        writer.flush() catch return error.WRITER_ERROR;
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

    fn popStack(self: *Self) InterpretError!Value {
        return self.stack.pop() orelse return InterpretError.STACK_UNDERFLOW;
    }

    fn popStackNumber(self: *Self) InterpretError!f64 {
        const number = switch (try self.popStack()) {
            .number => |value| value,
            else => return InterpretError.RUNTIME_ERROR,
        };
        return number;
    }

    fn pushStack(self: *Self, value: Value) InterpretError!void {
        return self.stack.append(self.allocator, value) catch return InterpretError.STACK_OVERFLOW;
    }

    fn printValue(writer: *std.Io.Writer, value: Value) InterpretError!void {
        switch (value) {
            .number => |v| {
                writer.print("{d}", .{v}) catch return error.WRITER_ERROR;
            },
            .nil => {
                writer.print("nil", .{}) catch return error.WRITER_ERROR;
            },
        }
    }
};
