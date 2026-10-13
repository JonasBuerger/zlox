const print = @import("std").debug.print;
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

pub fn disassembleChunk(chunk: Chunk, name: []const u8) void {
    print("{s:=^80}\n", .{name});
    print("INDEX\u{2502}OP_CODE            \u{2502}ARG 1\u{2502}ARG 2\u{2502}ARG 1 VALUE         \u{2502}ARG 2 VALUE         \u{2502}\n", .{});
    print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{253C}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2524}\n", .{});
    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: Chunk, offset: usize) usize {
    print("{d:0>4} ", .{offset});
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
    print("{s: <19}", .{@tagName(opCode)});
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
    print("Unknown opcode [{x:0>2}]", .{instruction});
    printVerticalConnector();
    printEmptyOperandCode();
    printEmptyOperandCode();
    printEmptyOperandValue();
    printEmptyOperandValue();
    print("\n", .{});
    return offset + 1;
}
