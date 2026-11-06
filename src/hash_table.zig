const std = @import("std");
const Value = @import("bytecode.zig").Value;
const Object = @import("bytecode.zig").Object;

const HashTable = @This();
count: usize,
entries: []Entry,

const MAX_LOAD = 0.75;

const empty = HashTable{
    .count = 0,
    .entries = &.{},
};

const Entry = struct {
    key: ?*Object,
    value: Value,
};

pub fn set(self: *HashTable, allocator: std.mem.Allocator, key: *Object, value: Value) !void {
    if (self.count + 1 > @as(f64, @floatFromInt(self.entries.len)) * MAX_LOAD) {
        try self.growCapacity(allocator);
    }
    var entry = findEntry(self.entries, key);
    if (entry.key == null and entry.value == .nil) self.count += 1;
    entry.key = key;
    entry.value = value;
}

fn growCapacity(self: *HashTable, allocator: std.mem.Allocator) !void {
    const newCapacity = if (self.entries.len < 8) 8 else self.entries.len * 2;
    const entries = try allocator.alloc(Entry, newCapacity);
    for (0..entries.len) |index| {
        entries[index] = .{ .key = null, .value = .nil };
    }
    self.count = 0;
    for (0..self.entries.len) |index| {
        const entry = &self.entries[index];
        if (entry.key) |key| {
            const dest = findEntry(entries, key);
            dest.key = entry.key;
            dest.value = entry.value;
            self.count += 1;
        }
    }
    allocator.free(self.entries);
    self.entries = entries;
}

pub fn copyInto(self: *HashTable, allocator: std.mem.Allocator, other: *HashTable) !void {
    for (0..self.entries.len) |index| {
        const entry = &self.entries[index];
        if (entry.key) |key| {
            other.set(allocator, key, entry.value);
        }
    }
}

pub fn get(self: *HashTable, key: *Object) ?Value {
    if (self.count == 0) return null;
    const entry = findEntry(self.entries, key);
    return if (entry.key) entry.value else null;
}

pub fn remove(self: *HashTable, key: *Object) void {
    if (self.count == 0) return;
    const entry = findEntry(self.entries, key);
    if (entry.key == null) return;
    // Place a tombstone in the entry.
    entry.key = null;
    entry.value = .{ .bool = true };
}

fn findEntry(entries: *[]Entry, key: *Object) *Entry {
    var index = key.hash % entries.len;
    var tombstone: ?*Entry = null;
    while (true) : (index = (index + 1) % entries.len) {
        const entry = &entries[index];
        if (entry.key) |entryKey| {
            if (entryKey.equals(key)) return entry;
        } else {
            if (entry.value == .nil) {
                return if (tombstone) tombstone else entry;
            } else {
                if (tombstone == null) tombstone = entry;
            }
        }
    }
}

pub fn loadFactor(self: HashTable) f64 {
    if (self.entries.len == 0) return 1;
    return @as(f64, @floatFromInt(self.count)) / @as(f64, @floatFromInt(self.entries.len));
}

pub fn deinit(self: *HashTable, allocator: std.mem.Allocator) void {
    allocator.free(self.entries);
    self.* = undefined;
}

test "empty hashtable reports as full" {
    const table: HashTable = .empty;
    try std.testing.expectEqual(1.0, table.loadFactor());
}
