const std = @import("std");
const disassembleChunk = @import("debug.zig").disassembleChunk;

comptime {
    _ = @import("debug.zig");
}

pub const OpCode = enum(u8) { OP_RETURN };

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // read in all args
    // const args = try init.minimal.args.toSlice(arena);

    // initialize a stdout writer
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

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
    //         std.process.exit(1);
    //     },
    //     else => return err,
    // };
    // try stdout_writer.print("{s}\nEOF\n", .{contents});

    // Create our bytecode data structure
    var chunk: std.ArrayList(u8) = .empty;
    defer chunk.deinit(arena);
    try chunk.append(arena, @backingInt(OpCode.OP_RETURN));

    // Debug print to stdout
    try stdout_writer.print("{any}\n\n", .{chunk});
    try stdout_writer.flush(); // Don't forget to flush!

    // Use the bytecode debug statement
    disassembleChunk(chunk.items, "test chunk");
}
