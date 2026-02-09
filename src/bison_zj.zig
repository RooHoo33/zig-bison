const std = @import("std");
const Bison = @import("bison_v2.zig");
const BisonFZF = @import("bison_fzf.zig");
const BisonPrint = @import("bison_print.zig");
const Allocator = std.mem.Allocator;

const TokenIterator = std.mem.SplitIterator(u8, .any);

const BadArgError = error{
    EXTRA_ARG,
    MISSING_ARG,
};

fn readStdIn(gpa: Allocator) ![]const u8 {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    if (std.fs.File.stdin().isTty()) {
        return &.{};
    }
    const stdin = &stdin_reader.interface;
    var stdInArray = try std.ArrayList(u8).initCapacity(gpa, 100);

    while (stdin.takeByte()) |char| {
        try stdInArray.append(gpa, char);
    } else |_| {}
    return try stdInArray.toOwnedSlice(gpa);
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const stdReadBytes = try readStdIn(gpa);
    defer gpa.free(stdReadBytes);

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    var token: []const u8 = "";
    var index: usize = 0;

    var json: ?[]const u8 = null;
    while (args.next()) |arg| {
        switch (index) {
            0 => {},
            1 => {
                json = arg;
            },
            2 => {
                token = arg;
            },
            else => {
                std.log.err("Too many arguments, {s} unknown", .{arg});
                return BadArgError.EXTRA_ARG;
            },
        }
        index += 1;
    }
    if (stdReadBytes.len > 0) {
        if (json) |_json| {
            token = _json;
        }
        json = stdReadBytes;
    } else if (index < 2) {
        std.log.err("Missing arguments, must pass json", .{});
        return BadArgError.MISSING_ARG;
    }
    const result = try findObject(gpa, json.?, token);
    defer gpa.free(result);
    _ = try std.fs.File.stdout().write(result);
    _ = try std.fs.File.stdout().write("\n");
    return;
}

fn findObject(gpa: Allocator, jsonBlobl: []const u8, search: []const u8) ![]u8 {
    var json = try Bison.parseJson(gpa, jsonBlobl);
    defer json.free(gpa);
    if (search.len == 0) {
        return BisonPrint.printValue(gpa, json, 0);
    }
    var searchTokensIter = std.mem.splitScalar(u8, search, '.');
    var searchTokens = try std.ArrayList([]const u8).initCapacity(gpa, 5);
    while (searchTokensIter.next()) |searchToken| {
        try searchTokens.append(gpa, searchToken);
    }
    const searchTokensSlice = try searchTokens.toOwnedSlice(gpa);
    defer gpa.free(searchTokensSlice);
    const match = findMatchingEntry(json.Object, searchTokensSlice);

    if (match) |value| {
        return BisonPrint.printValue(gpa, value.value, 0);
    } else {
        return "";
    }
}
fn findMatchingEntry(object: Bison.Object, searchTokens: [][]const u8) ?Bison.ObjectEntry {
    if (searchTokens.len > 0) {
        for (object.entries) |entry| {
            const matches = BisonFZF.matches(entry.name, searchTokens[0]);
            if (matches == false) {
                continue;
            } else if (searchTokens.len > 1 and entry.value != .Object) {
                continue;
            } else if (searchTokens.len > 1) {
                return findMatchingEntry(entry.value.Object, searchTokens[1..]);
            } else {
                return entry;
            }
        }
        for (object.entries) |entry| {
            switch (entry.value) {
                .Object => {
                    if (findMatchingEntry(entry.value.Object, searchTokens)) |nextedMatch| {
                        return nextedMatch;
                    }
                },
                else => {},
            }
        }

        return null;
    } else {
        return null;
    }
}

test "if no search is passed the object is printed" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "id": "abc123",
        \\  "value": {
        \\    "age": 234,
        \\    "name": "Jack \"Jack\" Me",
        \\    "rand": [
        \\      1,
        \\      2,
        \\      3
        \\    ]
        \\  }
        \\}
    ;
    const search = "";

    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(json, result);
}

test "can find nested object" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "value": {
        \\      "age": 234,
        \\      "name": "Jack \"Jack\" Me",
        \\      "rand": [
        \\        1,
        \\        2,
        \\        3
        \\      ]
        \\    }
        \\  }
    ;
    const search = "val";

    const expected =
        \\{
        \\  "age": 234,
        \\  "name": "Jack \"Jack\" Me",
        \\  "rand": [
        \\    1,
        \\    2,
        \\    3
        \\  ]
        \\}
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "if key doesnt match root, children are checked" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "value": {
        \\      "age": 234,
        \\      "name": "Jack \"Jack\" Me",
        \\      "rand": [
        \\        1,
        \\        2,
        \\        3
        \\      ]
        \\    }
        \\  }
    ;
    const search = "nam";

    const expected = "\"Jack \\\"Jack\\\" Me\"";
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
test "can find double nested object" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "value": {
        \\      "age": 234,
        \\      "name": "Jack \"Jack\" Me",
        \\      "rand": [
        \\        1,
        \\        2,
        \\        3
        \\      ]
        \\    }
        \\  }
    ;
    const search = "val.ra";

    const expected =
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "non object nodes are discarded if there are more tokens to search though" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "value_id": "abc123",
        \\    "value": {
        \\      "age": 234,
        \\      "name": "Jack \"Jack\" Me",
        \\      "rand": [
        \\        1,
        \\        2,
        \\        3
        \\      ]
        \\    }
        \\  }
    ;
    const search = "val.ra";

    const expected =
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
