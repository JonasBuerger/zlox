const std = @import("std");
const print = std.debug.print;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("chunk.zig").Value;
const Chunk = @import("chunk.zig").ManagedChunk;

const TableHeaderTop = "┌────┬────┬───────────────────┬─────────┬─────────┬────────────────────────────┐\n";
const TableHeader = "│IDX │LINE│OP_CODE            │OPERAND 1│OPERAND 2│EXTRA                       │\n";
const TableHeaderSeparator = "├────┼────┼───────────────────┼─────────┼─────────┼────────────────────────────┤\n";
const TableFooter = "└────┴────┴───────────────────┴─────────┴─────────┴────────────────────────────┘\n";

pub fn disassembleChunk(chunk: *Chunk, name: []const u8, io: std.Io) !void {
    // initialize a stderr writer
    var writer_buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stderr(), io, &writer_buffer);
    const writer = &file_writer.interface;
    try writer.print("{s: ^80}\n", .{name});
    try printTableHead(writer);
    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset = try disassembleInstruction(chunk, offset, writer);
        if (writer.unusedCapacityLen() < 255) {
            try writer.flush();
        }
    }
    try printTableFoot(writer);
    try writer.flush();
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize, writer: *std.Io.Writer) !usize {
    try writer.print("│{d:0>4}│", .{offset});
    if (offset > 0 and chunk.getLine(offset) == chunk.getLine(offset - 1)) {
        try writer.print("    │", .{});
    } else {
        try writer.print("{d:0>4}│", .{chunk.getLine(offset)});
    }

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        @backingInt(OpCode.OP_RETURN),
        @backingInt(OpCode.OP_NEGATE),
        @backingInt(OpCode.OP_ADD),
        @backingInt(OpCode.OP_SUBTRACT),
        @backingInt(OpCode.OP_MULTIPLY),
        @backingInt(OpCode.OP_DIVIDE),
        => {
            try printOpCode(@fromBackingInt(instruction), writer);
            try printEmptyOperandField(writer);
            try printEmptyOperandField(writer);
            try printEmptyExtraField(writer);
            try printNewline(writer);
            return offset + 1;
        },
        @backingInt(OpCode.OP_CONSTANT) => {
            const valueIndex = chunk.code.items[offset + 1];
            try printOpCode(@fromBackingInt(instruction), writer);
            try printOperandCode(valueIndex, writer);
            try printEmptyOperandField(writer);
            try printValue(chunk.constants.items[valueIndex], writer);
            try printNewline(writer);
            return offset + 2;
        },
        @backingInt(OpCode.OP_CONSTANT_LONG) => {
            const b = chunk.code.items;
            const valueIndex = @as(u24, b[offset + 1]) | (@as(u24, b[offset + 2]) << 8) | (@as(u24, b[offset + 3]) << 16);
            try printOpCode(@fromBackingInt(instruction), writer);
            try printLongOperandCode(valueIndex, writer);
            try printEmptyOperandField(writer);
            try printValue(chunk.constants.items[valueIndex], writer);
            try printNewline(writer);
            return offset + 4;
        },
        else => {
            try writer.print("Unknown opcode [{x:0>2}]│", .{instruction});
            try printEmptyOperandField(writer);
            try printEmptyOperandField(writer);
            try printEmptyExtraField(writer);
            try printNewline(writer);
            return offset + 1;
        },
    };
}

pub fn printTableHead(writer: *std.Io.Writer) !void {
    try writer.print(TableHeaderTop, .{});
    try writer.print(TableHeader, .{});
    try writer.print(TableHeaderSeparator, .{});
}

pub fn printTableFoot(writer: *std.Io.Writer) !void {
    try writer.print(TableFooter, .{});
}

fn printNewline(writer: *std.Io.Writer) !void {
    try writer.print("\n", .{});
}

fn printOpCode(opCode: OpCode, writer: *std.Io.Writer) !void {
    try writer.print("{s: <19}│", .{@tagName(opCode)});
}

fn printOperandCode(operand: u8, writer: *std.Io.Writer) !void {
    try writer.print("{x:0>2}       │", .{operand});
}

fn printLongOperandCode(operand: u24, writer: *std.Io.Writer) !void {
    try writer.print("{x:0>6}   │", .{operand});
}

fn printValue(value: Value, writer: *std.Io.Writer) !void {
    switch (value) {
        .number => |v| {
            if (v > 1e-9 and v < 1e9 or v < -1e-9 and v > -1e9) {
                try writer.print("{d: <28}│", .{v});
            } else {
                try writer.print("{e: <28}│", .{v});
            }
        },
        .nil => {
            try writer.print("{s: <28}│", .{"nil"});
        },
    }
}

fn printEmptyOperandField(writer: *std.Io.Writer) !void {
    try writer.print("         │", .{});
}

fn printEmptyExtraField(writer: *std.Io.Writer) !void {
    try writer.print("                            │", .{});
}
