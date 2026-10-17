const std = @import("std");
const disassembleChunk = @import("debug.zig").disassembleChunk;
const ExitCode = @import("exit_code.zig").ExitCode;
const ByteCode = @import("bytecode.zig");
const OpCode = ByteCode.OpCode;
const Value = ByteCode.Value;
const VirtualMachine = @import("vm.zig");

comptime {
    if (@import("builtin").is_test) {
        _ = @import("box_chars.zig");
        _ = @import("bytecode.zig");
        _ = @import("debug.zig");
        _ = @import("scanner.zig");
        _ = @import("vm.zig");
    }
}

pub fn main(init: std.process.Init) !u8 {
    const arena: std.mem.Allocator = init.arena.allocator();

    // read in all args
    const args = try init.minimal.args.toSlice(arena);

    var vm: VirtualMachine = .init(init.io, arena);
    defer vm.deinit();

    // Ensure a single arg with a filepath
    if (args.len == 1) {
        try repl(&vm, init.io, arena);
    } else if (args.len == 2) {
        const path = try std.Io.Dir.realPathFileAlloc(std.Io.Dir.cwd(), init.io, args[1], arena);
        try runFile(path, &vm, init.io, arena);
    } else {
        // initialize a stdout writer
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        const writer = &stdout_writer.interface;

        // Print usage information
        try writer.print("Usage: {s} [path]\n", .{args[0]});
        try writer.flush();
        return @intFromEnum(ExitCode.EX_USAGE);
    }

    return @intFromEnum(ExitCode.SUCCESS);
}

fn repl(vm: *VirtualMachine, io: std.Io, allocator: std.mem.Allocator) !void {
    var read_buffer: [4_096]u8 = undefined;
    var write_buffer: [4_096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &read_buffer);
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &write_buffer);
    const reader = &stdin_reader.interface;
    const writer = &stdout_writer.interface;
    while (true) {
        try writer.print("> ", .{});
        try writer.flush();
        const input = try std.Io.Reader.takeDelimiter(reader, '\n') orelse return;
        if (input.len == 0) return;
        try interpret(input, vm, io, allocator);
    }
}

fn runFile(path: []u8, vm: *VirtualMachine, io: std.Io, allocator: std.mem.Allocator) !void {
    // Read the file contents all at once
    const source = try std.Io.Dir.readFileAlloc(
        std.Io.Dir.cwd(),
        io,
        path,
        allocator,
        .unlimited,
    );
    try interpret(source, vm, io, allocator);
}

fn interpret(source: []u8, vm: *VirtualMachine, _: std.Io, allocator: std.mem.Allocator) !void {
    var chunk = try compile(source, allocator);
    try vm.interpret(&chunk);
}
fn compile(_: []u8, allocator: std.mem.Allocator) !ByteCode {
    var chunk = ByteCode.init(allocator);
    try chunk.addOpCode(OpCode.OP_RETURN, 1);
    return chunk;
}
