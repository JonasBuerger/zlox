const std = @import("std");
const disassembleChunk = @import("debug.zig").disassembleChunk;
const ByteCode = @import("bytecode.zig");
const OpCode = ByteCode.OpCode;
const Value = ByteCode.Value;
const VirtualMachine = @import("vm.zig");
const Scanner = @import("scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;

const Compiler = @This();
previous: Token = .empty,
current: Token = .empty,
hadError: bool = false,
panicMode: bool = false,
compilingChunk: *ByteCode,
scanner: *Scanner,

pub const CompilerError = error{ COMPILER_ERROR, OutOfMemory, InvalidCharacter };

const Precedence = enum(u8) {
    NONE,
    ASSIGNEMENT,
    OR,
    AND,
    EQUALITY,
    COMPARISON,
    TERM,
    FACTOR,
    UNARY,
    CALL,
    PRIMARY,
};

const ParseFn = *const fn (self: *Compiler) CompilerError!void;
const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};
const rules: std.EnumArray(TokenType, ParseRule) = .init(.{
    .LEFT_PAREN = .{ .prefix = grouping, .infix = null, .precedence = .NONE },
    .RIGHT_PAREN = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .LEFT_BRACE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .RIGHT_BRACE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .COMMA = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .DOT = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .MINUS = .{ .prefix = unary, .infix = binary, .precedence = .TERM },
    .PLUS = .{ .prefix = null, .infix = binary, .precedence = .TERM },
    .SEMICOLON = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .STAR = .{ .prefix = null, .infix = binary, .precedence = .FACTOR },
    .SLASH = .{ .prefix = null, .infix = binary, .precedence = .FACTOR },
    .BANG = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .BANG_EQUAL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .EQUAL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .EQUAL_EQUAL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .GREATER = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .GREATER_EQUAL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .LESS = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .LESS_EQUAL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .IDENTIFIER = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .STRING = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .NUMBER = .{ .prefix = number, .infix = null, .precedence = .NONE },
    .AND = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .CLASS = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .ELSE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .FALSE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .FOR = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .FUN = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .IF = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .NIL = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .OR = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .PRINT = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .RETURN = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .SUPER = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .THIS = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .TRUE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .VAR = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .WHILE = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .ERROR = .{ .prefix = null, .infix = null, .precedence = .NONE },
    .EOF = .{ .prefix = null, .infix = null, .precedence = .NONE },
});

pub fn compile(self: *Compiler) !bool {
    try self.advance();
    try self.expression();
    try self.consume(TokenType.EOF, "Expect end of expression.");

    try self.end();
    return !self.hadError;
}

fn advance(self: *Compiler) !void {
    self.previous = self.current;
    while (true) {
        self.current = self.scanner.getToken();
        if (self.current.type != TokenType.ERROR) break;

        self.errorAt(&self.current, self.current.lexeme);
    }
}

fn consume(self: *Compiler, tokenType: TokenType, message: []const u8) !void {
    if (self.current.type == tokenType) {
        try self.advance();
        return;
    }

    self.errorAt(&self.current, message);
}

fn currentChunk(self: *Compiler) *ByteCode {
    return self.compilingChunk;
}

fn emitConstant(self: *Compiler, value: Value) !void {
    try self.currentChunk().addConstant(value, self.previous.line);
}

fn emitOpCode(self: *Compiler, opCode: OpCode) !void {
    try self.currentChunk().addOpCode(opCode, self.previous.line);
}

fn end(self: *Compiler) !void {
    try self.emitOpCode(OpCode.OP_RETURN);
}

fn errorAt(self: *Compiler, token: *Token, message: []const u8) void {
    if (self.panicMode) return;
    self.panicMode = true;
    std.debug.print("[line {d}] Error", .{token.line});
    if (token.type == TokenType.EOF) {
        std.debug.print(" at end", .{});
    } else if (token.type != TokenType.ERROR) {
        std.debug.print(" at '{s}'", .{token.lexeme});
    }
    std.debug.print(": {s}\n", .{message});
    self.hadError = true;
}
fn expression(self: *Compiler) !void {
    try self.parsePrecedence(.ASSIGNEMENT);
}
fn number(self: *Compiler) CompilerError!void {
    const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
    try self.emitConstant(.{ .number = value });
}
fn grouping(self: *Compiler) CompilerError!void {
    try self.expression();
    try self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.");
}
fn unary(self: *Compiler) CompilerError!void {
    const operatorType = self.previous.type;

    try self.parsePrecedence(.UNARY);

    switch (operatorType) {
        TokenType.MINUS => try self.emitOpCode(.OP_NEGATE),
        else => unreachable,
    }
}

fn binary(self: *Compiler) CompilerError!void {
    const operatorType = self.previous.type;
    const rule = rules.get(operatorType);

    try self.parsePrecedence(@fromBackingInt(@backingInt(rule.precedence) + 1));

    switch (operatorType) {
        TokenType.PLUS => try self.emitOpCode(.OP_ADD),
        TokenType.MINUS => try self.emitOpCode(.OP_SUBTRACT),
        TokenType.STAR => try self.emitOpCode(.OP_MULTIPLY),
        TokenType.SLASH => try self.emitOpCode(.OP_DIVIDE),
        else => unreachable,
    }
}

fn parsePrecedence(self: *Compiler, precedence: Precedence) !void {
    try self.advance();
    const prefixRule = rules.get(self.previous.type).prefix;
    if (prefixRule) |rule| {
        try rule(self);
    } else {
        self.errorAt(&self.previous, "Expect expression.");
        return;
    }

    while (@backingInt(precedence) <= @backingInt(rules.get(self.current.type).precedence)) {
        try self.advance();
        const infixRule = rules.get(self.previous.type).infix;
        try infixRule.?(self);
    }
}
