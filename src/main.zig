const std = @import("std");
const disassembleChunk = @import("debug.zig").disassembleChunk;
const ExitCode = @import("exit_code.zig").ExitCode;
const ByteCode = @import("bytecode.zig");
const ErrorContext = @import("error_context.zig");
const OpCode = ByteCode.OpCode;
const Value = ByteCode.Value;
const VirtualMachine = @import("vm.zig");
const Scanner = @import("scanner.zig");
const Compiler = @import("compiler.zig");
const opt = @import("build_options");

comptime {
    if (@import("builtin").is_test) {
        _ = @import("box_chars.zig");
        _ = @import("bytecode.zig");
        _ = @import("compiler.zig");
        _ = @import("debug.zig");
        _ = @import("error_context.zig");
        _ = @import("exit_code.zig");
        _ = @import("scanner.zig");
        _ = @import("vm.zig");
    }
}

pub fn main(init: std.process.Init) !u8 {
    //const allocator: std.mem.Allocator = init.arena.allocator();

    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    const allocator: std.mem.Allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    // read in all args
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    var vm: VirtualMachine = .init(init.io, allocator);
    defer vm.deinit();

    // Ensure a single arg with a filepath
    if (args.len == 1) {
        try repl(&vm, init.io, allocator);
    } else if (args.len == 2) {
        const path = try std.Io.Dir.realPathFileAlloc(std.Io.Dir.cwd(), init.io, args[1], allocator);
        try runFile(path, &vm, init.io, allocator);
    } else {
        // initialize a stdout writer
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        const writer = &stdout_writer.interface;

        // Print usage information
        try writer.print("Usage: {s} [path]\n", .{args[0]});
        try writer.flush();
        return @backingInt(ExitCode.EX_USAGE);
    }

    return @backingInt(ExitCode.SUCCESS);
}

fn repl(vm: *VirtualMachine, io: std.Io, allocator: std.mem.Allocator) !void {
    var read_buffer: [4_096]u8 = undefined;
    var write_buffer: [8]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &read_buffer);
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &write_buffer);
    const reader = &stdin_reader.interface;
    const writer = &stdout_writer.interface;
    while (true) {
        try writer.writeAll("> ");
        try writer.flush();
        var input = try std.Io.Reader.takeDelimiter(reader, '\n') orelse return;
        //defer allocator.free(input);
        if (input.len == 0) return;
        try interpret(&input, vm, io, allocator);
    }
}

fn runFile(path: []u8, vm: *VirtualMachine, io: std.Io, allocator: std.mem.Allocator) !void {
    // Read the file contents all at once
    var source = try std.Io.Dir.readFileAlloc(
        std.Io.Dir.cwd(),
        io,
        path,
        allocator,
        .unlimited,
    );
    defer allocator.free(source);
    try interpret(&source, vm, io, allocator);
}

fn interpret(source: *[]u8, vm: *VirtualMachine, io: std.Io, allocator: std.mem.Allocator) !void {
    var chunk = ByteCode.init(allocator);
    defer chunk.deinit();
    var errors = ErrorContext.init(allocator);
    defer errors.deinit();
    var scanner = Scanner.init(source);
    var compiler: Compiler = .{ .compilingChunk = &chunk, .scanner = &scanner, .errors = &errors, .allocator = allocator };
    try compiler.compile();
    if (errors.hasErrors()) {
        var writer_buffer: [1024]u8 = undefined;
        var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &writer_buffer);
        try errors.printAll(&stderr_writer.interface);
    } else {
        if (comptime opt.print_code) {
            try disassembleChunk(chunk, "compiler output", io);
        }
        vm.interpret(&chunk) catch {};
    }
}
