const Scanner = @This();
const std = @import("std");

source: *[]u8,
start: usize,
current: usize,
line: usize,

const Token = struct {
    type: TokenType,
    lexeme: []u8,
    line: usize,
};

pub const TokenType = enum {
    // Single character tokens
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,

    // One or two character tokens
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // Literals
    IDENTIFIER,
    STRING,
    NUMBER,

    // Keywords
    AND,
    CLASS,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    // Special
    EOF,
    ERROR,
};

pub fn init(source: *[]u8) Scanner {
    return .{
        .source = source,
        .start = 0,
        .current = 0,
        .line = 1,
    };
}

pub fn getToken(self: *Scanner) Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) return self.makeToken(TokenType.EOF);

    const c = self.advance();
    if (isAlpha(c)) return self.identifier();
    if (isDigit(c)) return self.number();
    return switch (c) {
        '(' => self.makeToken(TokenType.LEFT_PAREN),
        ')' => self.makeToken(TokenType.RIGHT_PAREN),
        '{' => self.makeToken(TokenType.LEFT_BRACE),
        '}' => self.makeToken(TokenType.RIGHT_BRACE),
        ';' => self.makeToken(TokenType.SEMICOLON),
        ',' => self.makeToken(TokenType.COMMA),
        '.' => self.makeToken(TokenType.DOT),
        '-' => self.makeToken(TokenType.MINUS),
        '+' => self.makeToken(TokenType.PLUS),
        '/' => self.makeToken(TokenType.SLASH),
        '*' => self.makeToken(TokenType.STAR),
        '!' => if (self.match('=')) self.makeToken(TokenType.BANG_EQUAL) else self.makeToken(TokenType.BANG),
        '=' => if (self.match('=')) self.makeToken(TokenType.EQUAL_EQUAL) else self.makeToken(TokenType.EQUAL),
        '<' => if (self.match('=')) self.makeToken(TokenType.LESS_EQUAL) else self.makeToken(TokenType.LESS),
        '>' => if (self.match('=')) self.makeToken(TokenType.GREATER_EQUAL) else self.makeToken(TokenType.GREATER),
        '"' => self.string(),
        else => self.errorToken(@constCast("Unexpected character.")),
    };
}

fn makeToken(self: *Scanner, tokenType: TokenType) Token {
    return .{
        .type = tokenType,
        .lexeme = self.source.*[self.start..self.current],
        .line = self.line,
    };
}
fn errorToken(self: *Scanner, message: []u8) Token {
    return .{
        .type = TokenType.ERROR,
        .lexeme = message,
        .line = self.line,
    };
}
fn advance(self: *Scanner) u8 {
    self.current += 1;
    return self.source.*[self.current - 1];
}
fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (expected != self.source.*[self.current]) return false;
    self.current += 1;
    return true;
}
fn peek(self: *Scanner) u8 {
    return self.source.*[self.current];
}
fn peekNext(self: *Scanner) u8 {
    if (self.isAtEnd()) return '\x00';
    return self.source.*[self.current + 1];
}
fn skipWhitespace(self: *Scanner) void {
    while (true) {
        if (self.isAtEnd()) break;
        const c = self.peek();
        switch (c) {
            ' ', '\r', '\t' => _ = self.advance(),
            '\n' => {
                self.line += 1;
                _ = self.advance();
            },
            '/' => {
                if (self.peekNext() == '/') {
                    while (self.peek() != '\n' and !self.isAtEnd()) _ = self.advance();
                } else {
                    break;
                }
            },
            else => break,
        }
    }
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn string(self: *Scanner) Token {
    while (self.peek() != '"' and !self.isAtEnd()) {
        if (self.peek() == '\n') self.line += 1;
        _ = self.advance();
    }
    if (self.isAtEnd()) return self.errorToken(@constCast("Unterminated string."));
    _ = self.advance();
    return self.makeToken(TokenType.STRING);
}
fn number(self: *Scanner) Token {
    while (isDigit(self.peek())) _ = self.advance();
    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        while (isDigit(self.peek())) _ = self.advance();
    }
    return self.makeToken(TokenType.NUMBER);
}
fn identifier(self: *Scanner) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();

    return self.makeToken(self.identifierType());
}
fn identifierType(self: *Scanner) TokenType {
    return switch (self.source.*[self.start]) {
        'a' => self.checkKeyword(1, "nd", TokenType.AND),
        'c' => self.checkKeyword(1, "lass", TokenType.CLASS),
        'e' => self.checkKeyword(1, "lse", TokenType.ELSE),
        'f' => {
            if (self.current - self.start > 1) {
                return switch (self.source.*[self.start + 1]) {
                    'a' => self.checkKeyword(2, "lse", TokenType.FALSE),
                    'o' => self.checkKeyword(2, "r", TokenType.FOR),
                    'u' => self.checkKeyword(2, "n", TokenType.FUN),
                    else => TokenType.IDENTIFIER,
                };
            }
            return TokenType.IDENTIFIER;
        },
        'i' => self.checkKeyword(1, "f", TokenType.IF),
        'n' => self.checkKeyword(1, "il", TokenType.NIL),
        'o' => self.checkKeyword(1, "r", TokenType.OR),
        'p' => self.checkKeyword(1, "rint", TokenType.PRINT),
        'r' => self.checkKeyword(1, "eturn", TokenType.RETURN),
        's' => self.checkKeyword(1, "uper", TokenType.SUPER),
        't' => {
            if (self.current - self.start > 1) {
                return switch (self.source.*[self.start + 1]) {
                    'h' => self.checkKeyword(2, "is", TokenType.FALSE),
                    'r' => self.checkKeyword(2, "ue", TokenType.FOR),
                    else => TokenType.IDENTIFIER,
                };
            }
            return TokenType.IDENTIFIER;
        },
        'v' => self.checkKeyword(1, "ar", TokenType.VAR),
        'w' => self.checkKeyword(1, "hile", TokenType.WHILE),
        else => TokenType.IDENTIFIER,
    };
}
fn checkKeyword(self: *Scanner, start: usize, rest: []const u8, tokenType: TokenType) TokenType {
    return if (std.mem.eql(u8, rest, self.source.*[(self.start + start)..self.current])) tokenType else TokenType.IDENTIFIER;
}

fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}
fn isAlpha(c: u8) bool {
    return ('a' <= c and c <= 'z') or ('A' <= c and c <= 'Z') or c == '_';
}
