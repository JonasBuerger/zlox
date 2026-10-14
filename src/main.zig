const std = @import("std");
const disassembleChunk = @import("debug.zig").disassembleChunk;
const Chunk = @import("chunk.zig").ManagedChunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("chunk.zig").Value;
const VirtualMachine = @import("vm.zig").VirtualMachine;

comptime {
    _ = @import("chunk.zig");
    _ = @import("debug.zig");
    _ = @import("box_chars.zig");
    _ = @import("vm.zig");
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // read in all args
    // const args = try init.minimal.args.toSlice(arena);

    // initialize a stdout writer
    // var stderr_buffer: [1024]u8 = undefined;
    // var file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    // const writer = &file_writer.interface;

    // Ensure a single arg with a filepath
    // if (args.len != 2) {
    //     try stdout_writer.print("Usage {s} <lox file>\n", .{args[0]});
    //     try stdout_writer.flush();
    //     std.process.exit(2);
    // }
    // const path = try std.Io.Dir.realPathFileAlloc(std.Io.Dir.cwd(), io, args[1], arena);
    // try stdout_writer.print("File: {s}\n\n", .{path});

    // Read the file contents all at once
    //
    // const contents = std.Io.Dir.readFileAlloc(
    //     std.Io.Dir.cwd(),
    //     io,
    //     args[1],
    //     arena,
    //     .unlimited,
    // ) catch |err| switch (err) {
    //     error.FileNotFound => {
    //         try stdout_writer.print("Error: file not found: {s}\n", .{args[1]});
    //         try stdout_writer.flush();
    //         std.process.exit(line);
    //     },
    //     else => return err,
    // };
    // try stdout_writer.print("{s}\nEOF\n", .{contents});

    // Create our bytecode data structure
    var chunk = Chunk.init(arena);
    defer chunk.deinit();
    var line: usize = 1;

    // Assemble bytecode example chunk by hand
    try chunk.addOpCode(OpCode.OP_RETURN, line);
    line += 1;
    try chunk.addConstant(Value{ .number = 1.6 }, line);
    try chunk.addConstant(Value{ .number = 42 }, line);
    line += 1;
    try chunk.addOpCode(OpCode.OP_RETURN, line);
    try chunk.write(42, line);
    line += 1;
    try chunk.addOpCode(OpCode.OP_RETURN, line);
    line += 1;
    try chunk.addConstant(Value{ .number = 9e10 }, line);
    line += 1;
    try chunk.addConstant(Value{ .number = 1e-15 + 1 }, line);
    line += 1;
    try chunk.addConstant(Value{ .number = -1e10 }, line);

    // Cause OP_CONSTANT_LONG OpCode to be emitted
    // for (50..500) |idx| {
    //     try chunk.addConstant(Value{ .number = @floatFromInt(idx) }, line);
    // }

    // Debug print to stdout
    // try stdout_writer.print("{any}\n\n", .{chunk});
    // try stdout_writer.flush(); // Don't forget to flush!

    // Use the bytecode debug statement
    try disassembleChunk(chunk, "example chunk", init.io);
    try disassembleChunk(Chunk.init(arena), "empty chunk", init.io);

    var vm = VirtualMachine.init(arena, init.io);

    try vm.interpret(&chunk);
}
