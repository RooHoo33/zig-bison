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

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    var token: []const u8 = "";
    var json: []const u8 = undefined;
    var index: usize = 0;
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
    if (index < 2) {
        std.log.err("Missing arguments, must pass json", .{});
        return BadArgError.MISSING_ARG;
    }
    const result = try findObject(gpa, json, token);
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
    var searchTokens = std.mem.splitAny(u8, search, ".");
    const match = findMatchingEntry(json.Object, &searchTokens);

    if (match) |value| {
        return BisonPrint.printValue(gpa, value.value, 0);
    } else {
        return "";
    }
}
fn findMatchingEntry(object: Bison.Object, searchTokens: *TokenIterator) ?Bison.ObjectEntry {
    if (searchTokens.next()) |token| {
        for (object.entries) |entry| {
            const matches = BisonFZF.matches(entry.name, token);
            if (matches == false) {
                continue;
            } else if (searchTokens.peek() != null and entry.value != .Object) {
                continue;
            } else if (searchTokens.peek() != null) {
                return findMatchingEntry(entry.value.Object, searchTokens);
            } else {
                return entry;
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
