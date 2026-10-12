const std = @import("std");
const Io = std.Io;

const zlox = @import("zlox");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    if (args.len != 2) {
        try stdout_writer.print("Usage {s} <lox file>\n", .{args[0]});
        try stdout_writer.flush();
        std.process.exit(2);
    }

    const contents = std.Io.Dir.readFileAlloc(
        std.Io.Dir.cwd(),
        io,
        args[1],
        arena,
        .unlimited,
    ) catch |err| switch (err) {
        error.FileNotFound => {
            try stdout_writer.print("Error: file not found: {s}\n", .{args[1]});
            try stdout_writer.flush();
            std.process.exit(1);
        },
        else => return err,
    };

    const path = try std.Io.Dir.realPathFileAlloc(std.Io.Dir.cwd(), io, args[1], arena);
    try stdout_writer.print("File: '{s}'.\n", .{path});
    try stdout_writer.print("{s}\nEOF\n", .{contents});
    try stdout_writer.flush(); // Don't forget to flush!
}
