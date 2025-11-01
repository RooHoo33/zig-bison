const std = @import("std");
const zig_bison = @import("zig_bison");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try zig_bison.bufferedPrint();
}

const JsonType = enum {
    String,
    Int,
    Boolean,
    Object,
};
const JsonValueType = enum { string, int, obj };
const JsonValueUnion = union(JsonValueType) { string: StringNode, int: IntNode, obj: ObjectNode };

const JsonObject = struct { values: [*]const JsonValueUnion };

fn JsonObjectEntry(comptime T: JsonType) type {
    return struct {
        name: []const u8,
        value: switch (T) {
            .String => []const u8,
            .Boolean => bool,
            .Int => u64,
            .Object => JsonObject,
        },
        fn entryType() JsonType {
            return T;
        }
    };
}

const StringNode = JsonObjectEntry(JsonType.String);
const IntNode = JsonObjectEntry(JsonType.Int);
const ObjectNode = JsonObjectEntry(JsonType.Object);

pub fn parseObject(_: []const u8) JsonObject {
    return JsonObject{ .values = &[_]JsonValueUnion{JsonValueUnion{ .int = IntNode{ .name = "abc", .value = 23 } }} };
}

const KeyResult = struct {
    key: []const u8,
    keyEndIndex: usize,
};

fn parseEntry(jsonBlob: []const u8) JsonValueUnion {
    const keyResult = parseKey(jsonBlob);
    return parseValue(jsonBlob[keyResult.keyEndIndex + 1 ..], keyResult.key);
}
fn parseValue(jsonBlob: []const u8, key: []const u8) JsonValueUnion {
    var readingValue = false;
    var startingValueIndex: usize = undefined;

    for (jsonBlob, 0..) |char, index| {
        if (readingValue == false and (char == ' ' or char == ':')) {
            continue;
        }
        startingValueIndex = index;
        readingValue = true;
        if (char >= '0' and char <= '9') {
            const value = readInt(jsonBlob[index..]);
            return JsonValueUnion{ .int = .{ .name = key, .value = value.value } };
        }
    }
    unreachable;
}


const IntResult = struct { value: u64, endIndex: usize };
const FloatResult = struct { value: f64, endIndex: usize };
const NumericResult  = union {
    int: IntResult,
    float: FloatResult
};

fn readInt(jsonBlob: []const u8) IntResult {
    for (jsonBlob, 0..) |char, index| {
        if (char > '9' or char < '0') {
            const intVal = std.fmt.parseInt(u64, jsonBlob[0..index], 10) catch 0;
            return IntResult{ .value = intVal, .endIndex = index - 1 };
        }
    }
    unreachable;
}
fn parseKey(jsonBlob: []const u8) KeyResult {

    // TODO add error checking here and return an error
    var beginingOfKey = false;
    var startingKeyIndex: usize = undefined;
    for (jsonBlob, 0..) |char, index| {
        if (char == '"' and beginingOfKey == false) {
            beginingOfKey = true;
            startingKeyIndex = index + 1;
            continue;
        }
        if (char == '"') {
            return .{ .key = jsonBlob[startingKeyIndex..(index)], .keyEndIndex = index + 1 };
        }
    }
    unreachable;
}
test "can parse a string" {
    const testValue = "\"example\": 2 ";
    const jsonValue = parseEntry(testValue);

    const expectedValue = JsonValueUnion{ .int = .{ .name = "example", .value = 2 } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
//pub fn parse(jsonBlob: []const u8) !JsonObject {
//    //const jsontNodeType = StringNode{ .value = "hello", .name = "name" };
//    var valuesArray = try std.ArrayList(JsonObject)
//        .initCapacity(std.heap.page_allocator, 19);
//    defer valuesArray.deinit(std.heap.page_allocator);
//
//    var i = 0;
//    while(i < jsonBlob.len) {
//        //switch(jsonBlob[i]) {
//        //    '"' =>
//        //
//        //}
//        i+=1;
//        try valuesArray.append(std.testing.allocator, parseObject(jsonBlob));
//    }
//
//    for (jsonBlob) |char| {
//        if (char == '{') {
//        }
//    }
//    return JsonObject{ .values = valuesArray.items };
//}

test "can parse a simple json object" {
    //const string: []const u8 = "{}";
    //const result = parse(string);

    //try std.testing.expectEqualDeep(StringNode{
    //    .value = "hello",
    //    .name = "name",
    //}, result);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
