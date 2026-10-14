const std = @import("std");
const print = std.debug.print;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("chunk.zig").Value;
const Chunk = @import("chunk.zig").ManagedChunk();

// https://en.wikipedia.org/wiki/Box-drawing_characters
const CrossConnector = 0x253C;
const BranchRightConnector = 0x251C;
const BranchLeftConnector = 0x2524;
const LeafConnector = 0x2514;
const HorizontalConnector = 0x2500;
const VerticalConnector = 0x2502;
const DoubleHorizontalConnector = 0x2550;
const TableHeader = "\u{2502}IDX \u{2502}LINE\u{2502}OP_CODE       \u{2502}ARG 1\u{2502}ARG 2\u{2502}ARG 1 VALUE         \u{2502}ARG 2 VALUE         \u{2502}\n";
const TableHeaderSeparator = "\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n";

pub fn disassembleChunk(chunk: Chunk, name: []const u8) void {
    print("{s:=^80}\n", .{name});
    print(TableHeader, .{});
    print(TableHeaderSeparator, .{});
    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: Chunk, offset: usize) usize {
    printVerticalConnector();
    print("{d:0>4}", .{offset});
    printVerticalConnector();
    print("{d:0>4}", .{chunk.lines.items[offset]});
    printVerticalConnector();

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        @backingInt(OpCode.OP_RETURN) => simpleOpCode(@fromBackingInt(instruction), offset),
        @backingInt(OpCode.OP_CONSTANT) => constantOpCode(@fromBackingInt(instruction), chunk, offset),
        else => unknownOpCode(instruction, offset),
    };
}

fn printVerticalConnector() void {
    print("{u}", .{VerticalConnector});
}
fn printOpCode(opCode: OpCode) void {
    print("{s: <14}", .{@tagName(opCode)});
    printVerticalConnector();
}
fn printOperandCode(operand: u8) void {
    print("{x:0>2}   ", .{operand});
    printVerticalConnector();
}
fn printValue(value: Value) void {
    switch (value) {
        .number => |v| {
            if (v > 1e-9 and v < 1e9 or v < -1e-9 and v > -1e9) {
                print("{d: <20}", .{v});
            } else {
                print("{e: <20}", .{v});
            }
        },
    }
    printVerticalConnector();
}
fn printEmptyOperandCode() void {
    print("     ", .{});
    printVerticalConnector();
}
fn printEmptyOperandValue() void {
    print("                    ", .{});
    printVerticalConnector();
}

fn simpleOpCode(instruction: OpCode, offset: usize) usize {
    printOpCode(instruction);
    printEmptyOperandCode();
    printEmptyOperandCode();
    printEmptyOperandValue();
    printEmptyOperandValue();
    print("\n", .{});
    return offset + 1;
}

fn unaryOpCode(instruction: OpCode, operand: u8, offset: usize) usize {
    printOpCode(instruction);
    printOperandCode(operand);
    printEmptyOperandCode();
    printEmptyOperandValue();
    printEmptyOperandValue();
    print("\n", .{});
    return offset + 2;
}

fn constantOpCode(instruction: OpCode, chunk: Chunk, offset: usize) usize {
    const valueIndex = chunk.code.items[offset + 1];
    printOpCode(instruction);
    printOperandCode(valueIndex);
    printEmptyOperandCode();
    printValue(chunk.constants.items[valueIndex]);
    printEmptyOperandValue();
    print("\n", .{});
    return offset + 2;
}

fn unknownOpCode(instruction: u8, offset: usize) usize {
    print("Unknown [{x:0>2}]  ", .{instruction});
    printVerticalConnector();
    printEmptyOperandCode();
    printEmptyOperandCode();
    printEmptyOperandValue();
    printEmptyOperandValue();
    print("\n", .{});
    return offset + 1;
}

pub fn disassembleChunkBuffered(chunk: Chunk, name: []const u8, io: std.Io) !void {
    // initialize a stderr writer
    var writer_buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stderr(), io, &writer_buffer);
    const writer = &file_writer.interface;

    try writer.print("{s:=^80}\n", .{name});
    try writer.print(TableHeader, .{});
    try writer.print(TableHeaderSeparator, .{});
    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset = try disassembleInstructionBuffered(chunk, offset, writer);
        if (writer.unusedCapacityLen() < 255) {
            try writer.flush();
        }
    }
    try writer.flush();
}

fn disassembleInstructionBuffered(chunk: Chunk, offset: usize, writer: *std.Io.Writer) !usize {
    try printVerticalConnectorBuffered(writer);
    try writer.print("{d:0>4}", .{offset});
    try printVerticalConnectorBuffered(writer);
    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        try writer.print("    ", .{});
    } else {
        try writer.print("{d:0>4}", .{chunk.lines.items[offset]});
    }
    try printVerticalConnectorBuffered(writer);

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        @backingInt(OpCode.OP_RETURN) => simpleOpCodeBuffered(@fromBackingInt(instruction), offset, writer),
        @backingInt(OpCode.OP_CONSTANT) => constantOpCodeBuffered(@fromBackingInt(instruction), chunk, offset, writer),
        else => unknownOpCodeBuffered(instruction, offset, writer),
    };
}

fn printVerticalConnectorBuffered(writer: *std.Io.Writer) !void {
    try writer.print("{u}", .{VerticalConnector});
}
fn printOpCodeBuffered(opCode: OpCode, writer: *std.Io.Writer) !void {
    try writer.print("{s: <14}", .{@tagName(opCode)});
    try printVerticalConnectorBuffered(writer);
}
fn printOperandCodeBuffered(operand: u8, writer: *std.Io.Writer) !void {
    try writer.print("{x:0>2}   ", .{operand});
    try printVerticalConnectorBuffered(writer);
}
fn printValueBuffered(value: Value, writer: *std.Io.Writer) !void {
    switch (value) {
        .number => |v| {
            if (v > 1e-9 and v < 1e9 or v < -1e-9 and v > -1e9) {
                try writer.print("{d: <20}", .{v});
            } else {
                try writer.print("{e: <20}", .{v});
            }
        },
    }
    try printVerticalConnectorBuffered(writer);
}
fn printEmptyOperandCodeBuffered(writer: *std.Io.Writer) !void {
    try writer.print("     ", .{});
    try printVerticalConnectorBuffered(writer);
}
fn printEmptyOperandValueBuffered(writer: *std.Io.Writer) !void {
    try writer.print("                    ", .{});
    try printVerticalConnectorBuffered(writer);
}

fn simpleOpCodeBuffered(instruction: OpCode, offset: usize, writer: *std.Io.Writer) !usize {
    try printOpCodeBuffered(instruction, writer);
    try printEmptyOperandCodeBuffered(writer);
    try printEmptyOperandCodeBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try writer.print("\n", .{});
    return offset + 1;
}

fn unaryOpCodeBuffered(instruction: OpCode, operand: u8, offset: usize, writer: *std.Io.Writer) !usize {
    try printOpCodeBuffered(instruction);
    try printOperandCodeBuffered(operand);
    try printEmptyOperandCodeBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try writer.print("\n", .{});
    return offset + 2;
}

fn constantOpCodeBuffered(instruction: OpCode, chunk: Chunk, offset: usize, writer: *std.Io.Writer) !usize {
    const valueIndex = chunk.code.items[offset + 1];
    try printOpCodeBuffered(instruction, writer);
    try printOperandCodeBuffered(valueIndex, writer);
    try printEmptyOperandCodeBuffered(writer);
    try printValueBuffered(chunk.constants.items[valueIndex], writer);
    try printEmptyOperandValueBuffered(writer);
    try writer.print("\n", .{});
    return offset + 2;
}

fn unknownOpCodeBuffered(instruction: u8, offset: usize, writer: *std.Io.Writer) !usize {
    try writer.print("Unknown [{x:0>2}]  ", .{instruction});
    try printVerticalConnectorBuffered(writer);
    try printEmptyOperandCodeBuffered(writer);
    try printEmptyOperandCodeBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try printEmptyOperandValueBuffered(writer);
    try writer.print("\n", .{});
    return offset + 1;
}
