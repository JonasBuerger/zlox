const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ByteCode = @import("bytecode.zig");
const OpCode = ByteCode.OpCode;
const Value = ByteCode.Value;
const Object = ByteCode.Object;
const opt = @import("build_options");
const debug = @import("debug.zig");

const VirtualMachine = @This();
chunk: ?*ByteCode,
ip: ?[*]u8,
stack: std.ArrayList(Value),
allocator: Allocator,
io: std.Io,
objects: ?*Object = null,

pub const InterpretError = error{
    COMPILE_ERROR,
    STACK_OVERFLOW,
    STACK_UNDERFLOW,
    RUNTIME_ERROR,
    WriteFailed,
    OutOfMemory,
};

pub fn init(io: std.Io, allocator: Allocator) VirtualMachine {
    return .{
        .chunk = null,
        .ip = null,
        .stack = .empty,
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *VirtualMachine) void {
    self.stack.deinit(self.allocator);
    while (self.objects) |object| {
        const next = object.next;
        object.deinit(self.allocator);
        self.objects = next;
    }
}

pub fn interpret(self: *VirtualMachine, chunk: *ByteCode) InterpretError!void {
    self.chunk = chunk;
    self.chunk.?.code.lockPointers();
    defer self.chunk.?.code.unlockPointers();
    self.ip = self.chunk.?.code.items.ptr;
    self.stack.clearAndFree(self.allocator);
    try self.run();
}

fn run(self: *VirtualMachine) InterpretError!void {
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), self.io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), self.io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};
    const starttime = std.Io.Clock.now(.cpu_thread, self.io);

    if (comptime opt.trace_execution) {
        try debug.printTableHead(stdout);
    }

    while (true) {
        if (comptime opt.trace_stack) {
            try stderr.print("│", .{});
            for (self.stack.items) |stackValue| {
                try printValue(stderr, stackValue);

                try stderr.print("│", .{});
            }
            try stderr.print("\n", .{});
        }
        if (comptime opt.trace_execution) {
            _ = try debug.disassembleInstruction(self.chunk.?, self.ip.? - self.chunk.?.code.items.ptr, stderr);
        }
        code: switch (self.readByte()) {
            @backingInt(OpCode.OP_CONSTANT) => try self.pushStack(self.readConstant()),
            @backingInt(OpCode.OP_CONSTANT_LONG) => try self.pushStack(self.readConstantLong()),
            @backingInt(OpCode.OP_NIL) => try self.pushStack(.nil),
            @backingInt(OpCode.OP_TRUE) => try self.pushStack(.{ .bool = true }),
            @backingInt(OpCode.OP_FALSE) => try self.pushStack(.{ .bool = false }),
            @backingInt(OpCode.OP_EQUAL) => try self.pushStack(.{ .bool = valuesEqual(try self.popStack(), try self.popStack()) }),
            @backingInt(OpCode.OP_NEGATE) => {
                switch (self.peek(0)) {
                    .number => self.stack.lastPtr().?.*.number = -self.stack.last().?.number,
                    else => try self.runtimeError(stderr, "Operand must be a number.", .{}),
                }
            },
            @backingInt(OpCode.OP_ADD),
            @backingInt(OpCode.OP_SUBTRACT),
            @backingInt(OpCode.OP_MULTIPLY),
            @backingInt(OpCode.OP_DIVIDE),
            @backingInt(OpCode.OP_LESS),
            @backingInt(OpCode.OP_GREATER),
            => |opCode| {
                if ((self.peek(0).isObjectAnd(.string) and self.peek(1).isObjectAnd(.string))) {
                    try self.concatenate();
                    break :code;
                }
                if (!(self.peek(0).is(.number) and self.peek(1).is(.number))) {
                    try self.runtimeError(stderr, "Operands must be numbers.", .{});
                }
                const operand = (try self.popStack()).number;
                switch (opCode) {
                    @backingInt(OpCode.OP_ADD) => self.stack.lastPtr().?.*.number += operand,
                    @backingInt(OpCode.OP_SUBTRACT) => self.stack.lastPtr().?.*.number -= operand,
                    @backingInt(OpCode.OP_MULTIPLY) => self.stack.lastPtr().?.*.number *= operand,
                    @backingInt(OpCode.OP_DIVIDE) => self.stack.lastPtr().?.*.number /= operand,
                    @backingInt(OpCode.OP_LESS) => try self.pushStack(.{ .bool = operand > (try self.popStack()).number }),
                    @backingInt(OpCode.OP_GREATER) => try self.pushStack(.{ .bool = operand < (try self.popStack()).number }),
                    else => unreachable,
                }
            },
            @backingInt(OpCode.OP_NOT) => try self.pushStack(.{ .bool = isFalsey(try self.popStack()) }),
            @backingInt(OpCode.OP_RETURN) => {
                try printValue(stdout, self.stack.pop() orelse .nil);
                try stdout.print("\n", .{});
                break;
            },
            else => unreachable,
        }
    }
    if (comptime opt.trace_execution) {
        try debug.printTableFoot(stdout);
    }
    if (comptime opt.run_duration) {
        const runDuration = starttime.untilNow(self.io, .cpu_thread);
        const runTimeMilliseconds = @as(f64, @floatFromInt(runDuration.toMicroseconds())) / 1000.0;
        try stdout.print("Runtime: {d:.3}ms\n", .{runTimeMilliseconds});
    }
}

/// Demons, noses you know the spiel.
/// Would love to just use array indexing, gonna stick with the book for now.
/// Perf comparison later on would be cool.
fn readByte(self: *VirtualMachine) u8 {
    const instruction = self.ip.?[0];
    self.ip = self.ip.? + 1;
    return instruction;
}

fn readConstant(self: *VirtualMachine) Value {
    const valueIndex = self.readByte();
    return self.chunk.?.constants.items[valueIndex];
}

fn readConstantLong(self: *VirtualMachine) Value {
    const valueIndex = @as(u24, self.readByte()) | (@as(u24, self.readByte()) << 8) | (@as(u24, self.readByte()) << 16);
    return self.chunk.?.constants.items[valueIndex];
}

fn popStack(self: *VirtualMachine) InterpretError!Value {
    return self.stack.pop() orelse return InterpretError.STACK_UNDERFLOW;
}

fn pushStack(self: *VirtualMachine, value: Value) InterpretError!void {
    return self.stack.append(self.allocator, value) catch return InterpretError.STACK_OVERFLOW;
}

fn peek(self: *VirtualMachine, distance: usize) Value {
    return self.stack.items[(self.stack.items.len - 1) - distance];
}

fn isFalsey(value: Value) bool {
    return value.is(.nil) or (value.is(.bool) and !value.bool);
}

fn concatenate(self: *VirtualMachine) !void {
    const right = try self.popStack();
    const left = try self.popStack();
    const concatenated = try std.mem.concat(self.allocator, u8, &[_][]const u8{ left.object.*.value.string, right.object.*.value.string });
    const value = try self.allocateObject();
    value.*.value.string = concatenated;
    try self.pushStack(.{ .object = value });
}

fn allocateObject(self: *VirtualMachine) !*Object {
    const value = try self.allocator.create(Object);
    value.next = self.objects;
    self.objects = value;
    return value;
}

fn valuesEqual(left: Value, right: Value) bool {
    if (@backingInt(left) != @backingInt(right)) {
        return false;
    }
    return switch (left) {
        .bool => left.bool == right.bool,
        .nil => true,
        .number => left.number == right.number,
        .object => {
            if (@backingInt(left.object.*.value) != @backingInt(right.object.*.value)) {
                return false;
            }
            return switch (left.object.*.value) {
                .string => std.mem.eql(u8, left.object.*.value.string, right.object.*.value.string),
            };
        },
    };
}

fn runtimeError(self: *VirtualMachine, writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) InterpretError!void {
    try writer.print(fmt, args);
    try writer.print("\n[line {d}] in script\n", .{self.chunk.?.getLine(self.ip.? - self.chunk.?.code.items.ptr)});
    try self.resetStack();
    return InterpretError.RUNTIME_ERROR;
}

fn resetStack(self: *VirtualMachine) !void {
    self.stack.shrinkAndFree(self.allocator, 0);
}

fn printValue(writer: *std.Io.Writer, value: Value) InterpretError!void {
    switch (value) {
        .number => |v| {
            try writer.print("{d}", .{v});
        },
        .bool => |v| {
            try writer.print("{s}", .{if (v) "true" else "false"});
        },
        .object => |object| switch (object.*.value) {
            .string => |v| try writer.print("{s}", .{v}),
        },
        .nil => {
            try writer.print("nil", .{});
        },
    }
}
