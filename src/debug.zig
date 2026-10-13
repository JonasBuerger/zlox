const print = @import("std").debug.print;
const OpCode = @import("root").OpCode;

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
        else => unknownOpCode(instruction, offset),
    };
}

fn simpleOpCode(instruction: OpCode, offset: usize) usize {
    print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}
fn unknownOpCode(instruction: u8, offset: usize) usize {
    print("Unknown opcode {d}\n", .{instruction});
    return offset + 1;
}
