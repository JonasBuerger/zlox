const std = @import("std");
const Allocator = std.mem.Allocator;
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
        _ = @import("hash_table.zig");
        _ = @import("scanner.zig");
        _ = @import("vm.zig");
    }
}

pub fn main(init: std.process.Init) !u8 {
    // In debug mode use debug allocator for leak detection
    var gpa = if (comptime @import("builtin").mode == .debug) std.heap.DebugAllocator(.{}).init else init.arena;
    // Don`t call deinit on arena allocator
    defer _ = if (comptime @import("builtin").mode == .debug) gpa.deinit();
    const allocator: Allocator = gpa.allocator();

    // read in all args
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    // create bytecode vm
    var vm: VirtualMachine = .init(init.io, allocator);
    defer vm.deinit();

    // Ensure no args for repl or a single arg with a filepath to run
    if (args.len == 1) {
        repl(&vm, init.io, allocator) catch |err| {
            return if (err == error.WriteFailed) @backingInt(ExitCode.EX_IOERR) else @backingInt(ExitCode.EX_SOFTWARE);
        };
    } else if (args.len == 2) {
        const path = std.Io.Dir.realPathFileAlloc(std.Io.Dir.cwd(), init.io, args[1], allocator) catch |err| return @backingInt(mapFileReadError(err));
        runFile(path, &vm, init.io, allocator) catch |err| {
            return if (err == error.WriteFailed) @backingInt(ExitCode.EX_IOERR) else @backingInt(ExitCode.EX_SOFTWARE);
        };
    } else {
        // stderr writer for usage information
        var buffer: [1024]u8 = undefined;
        var stderr: std.Io.File.Writer = .init(.stderr(), init.io, &buffer);
        const writer = &stderr.interface;

        // Print usage information
        writer.print("Usage: {s} [path]\n", .{args[0]}) catch return @backingInt(ExitCode.EX_IOERR);
        writer.flush() catch return @backingInt(ExitCode.EX_IOERR);
        return @backingInt(ExitCode.EX_USAGE);
    }

    return @backingInt(ExitCode.SUCCESS);
}

inline fn mapFileReadError(err: std.Io.Dir.RealPathFileAllocError) ExitCode {
    return switch (err) {
        error.AccessDenied,
        error.DeviceBusy,
        error.FileBusy,
        error.FileNotFound,
        error.NetworkNotFound,
        error.NoDevice,
        error.PermissionDenied,
        error.UnrecognizedVolume,
        => .EX_NOINPUT,
        error.AntivirusInterference,
        error.FileSystem,
        error.ProcessFdQuotaExceeded,
        error.SystemFdQuotaExceeded,
        => .EX_UNAVAILABLE,
        error.BadPathName,
        error.FileTooBig,
        error.IsDir,
        error.NameTooLong,
        => .EX_DATAERR,
        else => .EX_SOFTWARE,
    };
}

fn repl(vm: *VirtualMachine, io: std.Io, allocator: Allocator) !void {
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

fn runFile(path: []u8, vm: *VirtualMachine, io: std.Io, allocator: Allocator) !void {
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

fn interpret(source: *[]u8, vm: *VirtualMachine, io: std.Io, allocator: Allocator) !void {
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
