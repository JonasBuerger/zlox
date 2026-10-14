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
const TableHeader = "\u{2502}IDX \u{2502}LINE\u{2502}OP_CODE            \u{2502}OPERAND 1\u{2502}OPERAND 2\u{2502}EXTRA                       \u{2502}\n";
const TableHeaderSeparator = "\u{251C}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n";

pub fn disassembleChunk(chunk: Chunk, name: []const u8, io: std.Io) !void {
    // initialize a stderr writer
    var writer_buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stderr(), io, &writer_buffer);
    const writer = &file_writer.interface;

    try writer.print("{s:=^80}\n", .{name});
    try writer.print(TableHeader, .{});
    try writer.print(TableHeaderSeparator, .{});
    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset = try disassembleInstruction(chunk, offset, writer);
        if (writer.unusedCapacityLen() < 255) {
            try writer.flush();
        }
    }
    try writer.flush();
}

fn disassembleInstruction(chunk: Chunk, offset: usize, writer: *std.Io.Writer) !usize {
    try printVerticalConnector(writer);
    try writer.print("{d:0>4}", .{offset});
    try printVerticalConnector(writer);
    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        try writer.print("    ", .{});
    } else {
        try writer.print("{d:0>4}", .{chunk.lines.items[offset]});
    }
    try printVerticalConnector(writer);

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        @backingInt(OpCode.OP_RETURN) => {
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
            try writer.print("Unknown opcode [{x:0>2}]", .{instruction});
            try printVerticalConnector(writer);
            try printEmptyOperandField(writer);
            try printEmptyOperandField(writer);
            try printEmptyExtraField(writer);
            try printNewline(writer);
            return offset + 1;
        },
    };
}

fn printVerticalConnector(writer: *std.Io.Writer) !void {
    try writer.print("{u}", .{VerticalConnector});
}

fn printNewline(writer: *std.Io.Writer) !void {
    try writer.print("\n", .{});
}

fn printOpCode(opCode: OpCode, writer: *std.Io.Writer) !void {
    try writer.print("{s: <19}", .{@tagName(opCode)});
    try printVerticalConnector(writer);
}

fn printOperandCode(operand: u8, writer: *std.Io.Writer) !void {
    try writer.print("{x:0>2}       ", .{operand});
    try printVerticalConnector(writer);
}

fn printLongOperandCode(operand: u24, writer: *std.Io.Writer) !void {
    try writer.print("{x:0>6}   ", .{operand});
    try printVerticalConnector(writer);
}

fn printValue(value: Value, writer: *std.Io.Writer) !void {
    switch (value) {
        .number => |v| {
            if (v > 1e-9 and v < 1e9 or v < -1e-9 and v > -1e9) {
                try writer.print("{d: <28}", .{v});
            } else {
                try writer.print("{e: <28}", .{v});
            }
        },
    }
    try printVerticalConnector(writer);
}

fn printEmptyOperandField(writer: *std.Io.Writer) !void {
    try writer.print("         ", .{});
    try printVerticalConnector(writer);
}

fn printEmptyExtraField(writer: *std.Io.Writer) !void {
    try writer.print("                            ", .{});
    try printVerticalConnector(writer);
}
