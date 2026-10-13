const print = @import("std").debug.print;
const OpCode = @import("chunk.zig").OpCode;

pub fn disassembleChunk(chunk: []u8, name: []const u8) void {
    print("== {s} ==\n", .{name});
    var offset: usize = 0;

    while (offset < chunk.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

fn disassembleInstruction(chunk: []u8, offset: usize) usize {
    print("{d:0>4} ", .{offset});

    const instruction = chunk[offset];
    return switch (instruction) {
        @backingInt(OpCode.OP_RETURN) => simpleOpCode(@fromBackingInt(instruction), offset),
        @backingInt(OpCode.OP_CONSTANT) => unaryOpCode(@fromBackingInt(instruction), chunk[offset+1], offset),
        else => unknownOpCode(instruction, offset),
    };
}

fn simpleOpCode(instruction: OpCode, offset: usize) usize {
    print("{s: <20}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn unaryOpCode(instruction: OpCode,operand: u8, offset: usize) usize {
    print("{s: <20}{x:0>2}\n", .{@tagName(instruction),operand});
    return offset + 2;
}

fn unknownOpCode(instruction: u8, offset: usize) usize {
    print("Unknown opcode      {x:0>2}\n", .{instruction});
    return offset + 1;
}
