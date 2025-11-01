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
    Float,
    Boolean,
    Object,
    Array,
};
const JsonValueType = enum { string, int, float, obj, array };
const JsonValueUnion = union(JsonValueType) { string: StringNode, int: IntNode, float: FloatNode, obj: ObjectNode, array: ArrayNode };

const JsonValue = union(JsonType) {
    String: JsonTypeDataType(JsonType.String),
    Int: JsonTypeDataType(JsonType.Int),
    Float: JsonTypeDataType(JsonType.Float),
    Boolean: JsonTypeDataType(JsonType.Boolean),
    Object: JsonTypeDataType(JsonType.Object),
    Array: JsonTypeDataType(JsonType.Array),
};

const JsonObject = struct { values: [*]const JsonValueUnion };

fn JsonTypeDataType(comptime T: JsonType) type {
    return switch (T) {
        .String => []const u8,
        .Boolean => bool,
        .Int => u64,
        .Float => f64,
        .Object => JsonObject,
        .Array => []const JsonValue,
    };
}

fn JsonObjectEntry(comptime T: JsonType) type {
    return struct {
        name: []const u8,
        value: JsonTypeDataType(T),
        fn entryType() JsonType {
            return T;
        }
    };
}

const StringNode = JsonObjectEntry(JsonType.String);
const IntNode = JsonObjectEntry(JsonType.Int);
const FloatNode = JsonObjectEntry(JsonType.Float);
const ObjectNode = JsonObjectEntry(JsonType.Object);
const ArrayNode = JsonObjectEntry(JsonType.Array);

pub fn parseObject(_: []const u8) JsonObject {
    return JsonObject{ .values = &[_]JsonValueUnion{JsonValueUnion{ .int = IntNode{ .name = "abc", .value = 23 } }} };
}

const KeyResult = struct {
    key: []const u8,
    keyEndIndex: usize,
};

fn parseEntry(jsonBlob: []const u8) JsonValueUnion {
    const keyResult = parseKey(jsonBlob);
    const value = parseValue(jsonBlob[keyResult.keyEndIndex + 1 ..]);

    // TODO there has to be a better way to do this
    return switch (value) {
        .Int => .{ .int = IntNode{ .name = keyResult.key, .value = value.Int } },
        .Float => .{ .float = FloatNode{ .name = keyResult.key, .value = value.Float } },
        .String => .{ .string = StringNode{ .name = keyResult.key, .value = value.String } },
        .Object => .{ .obj = ObjectNode{ .name = keyResult.key, .value = value.Object } },
        .Array => .{ .array = ArrayNode{ .name = keyResult.key, .value = value.Array } },
        .Boolean => unreachable,
    };
}
fn readListValues(gpa: std.mem.Allocator, jsonBlob: []const u8) ArrayNode {
    _ = jsonBlob;
    var valuesArray = try std.ArrayList(JsonValue)
        .initCapacity(gpa, 10);
    defer valuesArray.deinit(std.heap.page_allocator);

    //fo/r

}
fn parseValue(jsonBlob: []const u8) JsonValue {
    var readingValue = false;
    var startingValueIndex: usize = undefined;

    for (jsonBlob, 0..) |char, index| {
        if (readingValue == false and (char == ' ' or char == ':')) {
            continue;
        }

        startingValueIndex = index;
        readingValue = true;
        //if(char == '[') {

        //    const value = readListValues(jsonBlob[index..]);
        //}
        if (char >= '0' and char <= '9') {
            const value = readNumer(jsonBlob[index..]);
            return switch (value) {
                .int => JsonValue{ .Int = value.int.value },
                .float => JsonValue{ .Float = value.float.value },
            };
        }
    }
    unreachable;
}

const IntResult = struct { value: u64, endIndex: usize };
const FloatResult = struct { value: f64, endIndex: usize };
const NumericResultEnum = enum { int, float };
const NumericResult = union(NumericResultEnum) { int: IntResult, float: FloatResult };

fn readNumer(jsonBlob: []const u8) NumericResult {
    var isFloat = false;
    for (jsonBlob, 0..) |char, index| {
        if (char == '.') {
            isFloat = true;
            continue;
        }
        if (char > '9' or char < '0') {
            if (isFloat) {
                const floatVal = std.fmt.parseFloat(f64, jsonBlob[0..index]) catch 0;
                return .{ .float = FloatResult{ .value = floatVal, .endIndex = index - 1 } };
            } else {
                const intVal = std.fmt.parseInt(u64, jsonBlob[0..index], 10) catch 0;
                return .{ .int = IntResult{ .value = intVal, .endIndex = index - 1 } };
            }
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
test "can parse a int" {
    const testValue = "\"example\": 2 ";
    const jsonValue = parseEntry(testValue);

    const expectedValue = JsonValueUnion{ .int = .{ .name = "example", .value = 2 } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
test "can parse a float" {
    const testValue = "\"example\": 2.3 ";
    const jsonValue = parseEntry(testValue);

    const expectedValue = JsonValueUnion{ .float = .{ .name = "example", .value = 2.3 } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
test "can parse a list of ints" {
    const testValue = "\"example\": [2, 32, 54] ";
    const jsonValue = parseEntry(testValue);

    const expectedValuesList: []const JsonValue = &.{};

    const expectedValue = JsonValueUnion{ .array = .{ .name = "example", .value = expectedValuesList } };
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
