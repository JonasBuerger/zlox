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

pub const CompilerError = error{COMPILER_ERROR};

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

pub fn compile(self: *Compiler) !void {
    try self.advance();
    try self.expression();
    try self.consume(TokenType.EOF, "Expect end of expression.");

    try self.end();
    if (self.hadError) return CompilerError.COMPILER_ERROR;
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
        self.advance();
        return;
    }

    self.errorAt(self.current, message);
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

fn emitByte(self: *Compiler, byte: u8) !void {
    try self.currentChunk().write(byte, self.previous.line);
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
fn parsePrecedence(precedence: Precedence) void {}
fn expression(_: *Compiler) void {
    parsePrecedence(.ASSIGNEMENT);
}
fn number(self: *Compiler) !void {
    const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
    try self.emitConstant(.{ .number = value });
}
fn grouping(self: *Compiler) !void {
    try self.expression();
    try self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.");
}
fn unary(self: *Compiler) !void {
    const operatorType = self.previous.type;

    parsePrecedence(.UNARY);

    switch (operatorType) {
        TokenType.MINUS => self.emitOpCode(.OP_NEGATE),
        else => unreachable,
    }
}

fn binary(self: *Compiler) !void {
    const operatorType = self.previous.type;
    const rule = getRule(operatorType);

    parsePrecedence(rule.precedence + 1);

    switch (operatorType) {
        TokenType.MINUS => self.emitOpCode(.OP_NEGATE),
        else => unreachable,
    }
}
