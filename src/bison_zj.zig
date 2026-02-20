const std = @import("std");
const Bison = @import("bison_v2.zig");
const BisonFZF = @import("bison_fzf.zig");
const BisonPrint = @import("bison_print.zig");
const Allocator = std.mem.Allocator;

const TokenIterator = std.mem.SplitIterator(u8, .any);
const TokenSearch = struct { keySearch: []const u8, valueSearch: ?[]const u8 };

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
    var searchTokens = try std.ArrayList(TokenSearch).initCapacity(gpa, 5);
    while (searchTokensIter.next()) |searchToken| {
        var indexOfValueSpecifier: ?usize = null;
        for (searchToken, 0..) |char, index| {
            if (char == '=') {
                indexOfValueSpecifier = index;
                break;
            }
        }
        if (indexOfValueSpecifier) |_indexOfValueSpecifier| {
            try searchTokens.append(gpa, .{ .keySearch = searchToken[0.._indexOfValueSpecifier], .valueSearch = searchToken[_indexOfValueSpecifier + 1 ..] });
        } else {
            try searchTokens.append(gpa, .{ .keySearch = searchToken, .valueSearch = null });
        }
    }
    const searchTokensSlice = try searchTokens.toOwnedSlice(gpa);
    defer gpa.free(searchTokensSlice);
    const match = try findMatchingEntry2(gpa, json, searchTokensSlice);

    if (match) |value| {
        return BisonPrint.printValue(gpa, value, 0);
    } else {
        return "";
    }
}
fn findMatchingEntry2(gpa: Allocator, jsonType: Bison.JsonValueType, searchTokens: []TokenSearch) !?Bison.JsonValueType {
    var matchingType: ?Bison.JsonValueType = null;
    if (searchTokens[0].valueSearch != null) {
        matchingType = switch (jsonType) {
            .Array => blk: {
                for (jsonType.Array) |arrayEntry| {
                    if (try findMatchingEntry2(gpa, arrayEntry, searchTokens)) |match| {
                        if (searchTokens.len > 1) {
                            if (try findMatchingEntry2(gpa, arrayEntry, searchTokens[1..])) |nestedMatch| {
                                break :blk nestedMatch;
                            }
                        } else {
                            break :blk match;
                        }
                    }
                }
                break :blk null;
            },
            .Object => blk: {
                for (jsonType.Object.entries) |entry| {
                    const valueString: ?[]const u8 = switch (entry.value) {
                        .String => |string| string,
                        .Float => |float| try std.fmt.allocPrint(gpa, "{d}", .{float}),
                        .Int => |int| try std.fmt.allocPrint(gpa, "{d}", .{int}),
                        .Null => "null",
                        .Boolean => |boolean| boolString: {
                            if (boolean) {
                                break :boolString "true";
                            } else {
                                break :boolString "false";
                            }
                        },
                        else => null,
                    };
                    defer {
                        if (valueString != null and (entry.value == .Float or entry.value == .Int)) {
                            gpa.free(valueString.?);
                        }
                    }

                    if (valueString != null and
                        BisonFZF.matches(entry.name, searchTokens[0].keySearch, false) and
                        BisonFZF.matches(valueString.?, searchTokens[0].valueSearch.?, false))
                    {
                        if (searchTokens.len > 1) {
                            if (try findMatchingEntry2(gpa, jsonType, searchTokens[1..])) |nestedMatch| {
                                break :blk nestedMatch;
                            }
                        } else {
                            return jsonType;
                        }
                    }
                }
                break :blk null;
            },
            else => null,
        };
    } else {
        matchingType = switch (jsonType) {
            .Array => blk: {
                for (jsonType.Array) |arrayEntry| {
                    if (try findMatchingEntry2(gpa, arrayEntry, searchTokens)) |match| {
                        if (searchTokens.len > 1) {
                            break :blk try findMatchingEntry2(gpa, match, searchTokens[1..]);
                        } else {
                            break :blk match;
                        }
                    }
                }
                break :blk null;
            },
            .Object => blk: {
                for (jsonType.Object.entries) |entry| {
                    if (BisonFZF.matches(entry.name, searchTokens[0].keySearch, false)) {
                        if (searchTokens.len > 1) {
                            if (try findMatchingEntry2(gpa, entry.value, searchTokens[1..])) |nested| {
                                break :blk nested;
                            }
                        } else {
                            break :blk entry.value;
                        }
                    }
                }
                break :blk null;
            },
            .String => blk: {
                if (BisonFZF.matches(jsonType.String, searchTokens[0].keySearch, false)) {
                    break :blk jsonType;
                } else {
                    break :blk null;
                }
            },
            else => null,
        };
    }
    if (matchingType != null) {
        return matchingType;
    }
    switch (jsonType) {
        .Object => {
            for (jsonType.Object.entries) |entry| {
                if (try findMatchingEntry2(gpa, entry.value, searchTokens)) |nestedFound| {
                    return nestedFound;
                }
            }
        },
        else => {},
    }
    return null;
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

test "finds object in list" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "customer_name": "Alex Rivera",
        \\  "purchases": [
        \\    {
        \\      "purchase_id": "P-9001",
        \\      "timestamp": "2026-02-14T10:30:00Z",
        \\      "orders": [
        \\        {
        \\          "order_id": "ORD-101",
        \\          "payment_type": "CREDIT"
        \\        },
        \\        {
        \\          "order_id": "ORD-102",
        \\          "payment_type": "CASH"
        \\        }
        \\      ]
        \\    },
        \\    {
        \\      "purchase_id": "P-9002",
        \\      "timestamp": "2026-02-14T14:15:00Z",
        \\      "orders": [
        \\        {
        \\          "order_id": "ORD-205",
        \\          "payment_type": "CREDIT"
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;
    const search = "pur.or";

    const expected =
        \\[
        \\  {
        \\    "order_id": "ORD-101",
        \\    "payment_type": "CREDIT"
        \\  },
        \\  {
        \\    "order_id": "ORD-102",
        \\    "payment_type": "CASH"
        \\  }
        \\]
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "uses object key/val sytax" {
    const gpa = std.testing.allocator;
    const json =
        \\    {
        \\      "orders": [
        \\        {
        \\          "order_id": "ORD-101",
        \\          "payment_type": "CREDIT"
        \\        },
        \\        {
        \\          "order_id": "ORD-102",
        \\          "payment_type": "CASH"
        \\        }
        \\      ]
        \\    }
    ;
    const search = "or.pay=cas";

    const expected =
        \\{
        \\  "order_id": "ORD-102",
        \\  "payment_type": "CASH"
        \\}
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "uses object key/val for complicated key val pairs" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "customer_name": "Alex Rivera",
        \\  "purchases": [
        \\    {
        \\      "purchase_id": "P-9001",
        \\      "timestamp": "2026-02-14T10:30:00Z",
        \\      "orders": [
        \\        {
        \\          "order_id": "ORD-101",
        \\          "payment_type": "CREDIT"
        \\        },
        \\        {
        \\          "order_id": "ORD-102",
        \\          "payment_type": "CASH"
        \\        }
        \\      ]
        \\    },
        \\    {
        \\      "purchase_id": "P-9002",
        \\      "timestamp": "2026-02-14T14:15:00Z",
        \\      "orders": [
        \\        {
        \\          "order_id": "ORD-205",
        \\          "payment_type": "CREDIT"
        \\        },
        \\        {
        \\          "order_id": "ORD-206",
        \\          "payment_type": "CASH"
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;
    const search = "pur.purid=9002.or.pay=cas";

    const expected =
        \\{
        \\  "order_id": "ORD-206",
        \\  "payment_type": "CASH"
        \\}
    ;
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "can chain key/val searches to find nested field" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "name": "Jack",
        \\    "value": {
        \\      "age": 234
        \\    }
        \\  }
    ;
    const search = "id=abc.nam=jack.val.ag";

    const expected = "234";
    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
test "can filter by float" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "name": "Jack",
        \\    "value": {
        \\      "price": -9.231,
        \\      "name": "Jack"
        \\    }
        \\  }
    ;
    const search = "pr=-93";
    const expected =
        \\{
        \\  "price": -9.231,
        \\  "name": "Jack"
        \\}
    ;

    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
test "can filter by int" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "name": "Jack",
        \\    "value": {
        \\      "age": -123,
        \\      "name": "Jack"
        \\    }
        \\  }
    ;
    const search = "ag=-2";
    const expected =
        \\{
        \\  "age": -123,
        \\  "name": "Jack"
        \\}
    ;

    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
test "can filter by boolean" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "name": "Jack",
        \\    "value": {
        \\      "is_cool": true,
        \\      "name": "Jack"
        \\    }
        \\  }
    ;
    const search = "cool=rU";
    const expected =
        \\{
        \\  "is_cool": true,
        \\  "name": "Jack"
        \\}
    ;

    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
test "can filter by null" {
    const gpa = std.testing.allocator;
    const json =
        \\  {
        \\    "id": "abc123",
        \\    "name": "Jack",
        \\    "value": {
        \\      "missing": null,
        \\      "name": "Jack"
        \\    }
        \\  }
    ;
    const search = "miss=nll";
    const expected =
        \\{
        \\  "missing": null,
        \\  "name": "Jack"
        \\}
    ;

    const result = try findObject(gpa, json, search);
    defer gpa.free(result);
    try std.testing.expectEqualStrings(expected, result);
}
