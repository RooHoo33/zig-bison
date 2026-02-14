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

const JsonObject = struct { values: []const JsonValueUnion };

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

const KeyResult = struct {
    key: []const u8,
    keyEndIndex: usize,
};

const indentSize = 2;

fn printNode(gpa: std.mem.Allocator, node: JsonValueUnion, indent: u8) anyerror![]u8 {
    const pad: []u8 = try gpa.alloc(u8, indent);
    defer gpa.free(pad);
    for (0..indent) |index| {
        pad[index] = ' ';
    }
    const result = try switch (node) {
        .int => std.fmt.allocPrint(gpa, "\"{s}\": {d}", .{ node.int.name, node.int.value }),
        .array => {
            var stringResult = try std.ArrayList(u8)
                .initCapacity(gpa, 20);
            try stringResult.appendSlice(gpa, "[\n");
            for (node.array.value, 0..) |listValue, index| {
                const result = try printNode(gpa, listValue, indent + indentSize);
                defer gpa.free(result);
                if (index != 0) {
                    try stringResult.appendSlice(gpa, ",\n");
                }
                //try stringResult.appendSlice(gpa, pad);
                try stringResult.appendSlice(gpa, result);
            }
            try stringResult.appendSlice(gpa, "\n");
            try stringResult.appendSlice(gpa, pad);
            try stringResult.appendSlice(gpa, "}");
        },
        .obj => blk: {
            var stringResult = try std.ArrayList(u8)
                .initCapacity(gpa, 20);
            //defer gpa.free(stringResult);

            try stringResult.appendSlice(gpa, "{\n");
            for (node.obj.value.values, 0..) |objValue, index| {
                const result = try printNode(gpa, objValue, indent + indentSize);
                defer gpa.free(result);
                if (index != 0) {
                    try stringResult.appendSlice(gpa, ",\n");
                }
                //try stringResult.appendSlice(gpa, pad);
                try stringResult.appendSlice(gpa, result);
            }
            try stringResult.appendSlice(gpa, "\n");
            try stringResult.appendSlice(gpa, pad);
            try stringResult.appendSlice(gpa, "}");
            break :blk try stringResult.toOwnedSlice(gpa);
        },
        else => unreachable,
    };
    defer gpa.free(result);
    return std.mem.concat(gpa, u8, &.{ pad, result });
}

test "can print a int node" {
    const int: IntNode = .{ .name = "age", .value = 20 };
    const gpa = std.testing.allocator;
    const result = try printNode(gpa, .{ .int = int }, 2);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("  \"age\": 20", result);
}

test "can print a list of ints" {
    const intValueOne: JsonValue = JsonValue{ .Int = 5 };
    const intValueTwo: JsonValue = JsonValue{ .Int = 2 };
    const array: ArrayNode = .{ .name = "ages", .value = &.{ intValueOne, intValueTwo } };
    const gpa = std.testing.allocator;
    const result = try printNode(gpa, .{ .array = array }, 2);
    defer gpa.free(result);
    try std.testing.expectEqualStrings("  \"age\": 20", result);
}

test "can print an object node" {
    const int: IntNode = .{ .name = "age", .value = 20 };

    const obj: JsonObject = .{ .values = &.{JsonValueUnion{
        .int = int,
    }} };
    const objectNode: ObjectNode = .{ .name = "person", .value = obj };
    const gpa = std.testing.allocator;
    const result = try printNode(gpa, .{ .obj = objectNode }, 2);
    defer gpa.free(result);
    const expected =
        \\  {
        \\    "age": 20
        \\  }
    ;
    try std.testing.expectEqualStrings(expected, result);
}

const EntryResult = struct { entry: JsonValueUnion, endIndex: usize };

fn parseEntry(gpa: std.mem.Allocator, jsonBlob: []const u8) !EntryResult {
    const keyResult = parseKey(jsonBlob);
    const value = try parseJsonValue(gpa, jsonBlob[keyResult.keyEndIndex + 1 ..]);

    // TODO there has to be a better way to do this
    const entry: JsonValueUnion = switch (value.value) {
        .Int => .{ .int = IntNode{ .name = keyResult.key, .value = value.value.Int } },
        .Float => .{ .float = FloatNode{ .name = keyResult.key, .value = value.value.Float } },
        .String => .{ .string = StringNode{ .name = keyResult.key, .value = value.value.String } },
        .Object => .{ .obj = ObjectNode{ .name = keyResult.key, .value = value.value.Object } },
        .Array => .{ .array = ArrayNode{ .name = keyResult.key, .value = value.value.Array } },
        .Boolean => unreachable,
    };
    return .{ .entry = entry, .endIndex = keyResult.keyEndIndex + value.endIndex + 1 };
}
fn readListValues(gpa: std.mem.Allocator, jsonBlob: []const u8) std.mem.Allocator.Error!ValueResult {
    var valuesArray = std.ArrayList(JsonValue)
        .initCapacity(gpa, 10) catch unreachable;
    errdefer valuesArray.deinit(gpa);
    var index: usize = 0;
    while (index < jsonBlob.len) {
        if (jsonBlob[index] == ' ' or jsonBlob[index] == '[') {
            index += 1;
            continue;
        }
        if (jsonBlob[index] == ']') {
            const slice: []const JsonValue = try valuesArray.toOwnedSlice(gpa);
            return ValueResult{ .value = JsonValue{ .Array = slice }, .endIndex = index };
        }
        const valueResult = try parseJsonValue(gpa, jsonBlob[index..]);
        valuesArray.append(gpa, valueResult.value) catch unreachable;
        index += valueResult.endIndex + 1;
    }
    unreachable;
}

test "can parse a list value of ints" {
    const str = "[1,2,3]";
    const gpa = std.testing.allocator;
    const result = try readListValues(gpa, str);
    defer gpa.free(result.value.Array);
    const expectedValue = ValueResult{ .endIndex = 6, .value = JsonValue{ .Array = &.{ JsonValue{ .Int = 1 }, JsonValue{ .Int = 2 }, JsonValue{ .Int = 3 } } } };
    try std.testing.expectEqualDeep(expectedValue, result);
}

const ValueResult = struct { value: JsonValue, endIndex: usize };
fn parseJsonValue(gpa: std.mem.Allocator, jsonBlob: []const u8) !ValueResult {
    var readingValue = false;
    var startingValueIndex: usize = undefined;

    for (jsonBlob, 0..) |char, index| {
        if (readingValue == false and (char == ' ' or char == ':' or char == ',')) {
            continue;
        }

        startingValueIndex = index;
        readingValue = true;
        if (char == '[') {
            const valueResult = try readListValues(gpa, jsonBlob[index..]);
            return ValueResult{ .value = JsonValue{ .Array = valueResult.value.Array }, .endIndex = index + valueResult.endIndex };
        }
        if (char == '{') {
            const valueResult = try parseObject(gpa, jsonBlob[index..]);
            return ValueResult{ .value = JsonValue{ .Object = valueResult.value }, .endIndex = index + valueResult.endIndex };
        }
        if (char >= '0' and char <= '9') {
            const value = readNumer(jsonBlob[index..]);
            return switch (value) {
                .int => ValueResult{ .value = JsonValue{ .Int = value.int.value }, .endIndex = index + value.int.endIndex },
                .float => ValueResult{ .value = JsonValue{ .Float = value.float.value }, .endIndex = index + value.float.endIndex },
            };
        }
        if (char == '"') {
            const value = readstring(jsonBlob[index..]);
            return ValueResult{ .value = JsonValue{ .String = value.value }, .endIndex = index + value.endIndex };
        }
    }
    unreachable;
}

const IntResult = struct { value: u64, endIndex: usize };
const BooleanResult = struct { value: bool, endIndex: usize }; // TODO we need boolean  support
const FloatResult = struct { value: f64, endIndex: usize };
const NumericResultEnum = enum { int, float };
const NumericResult = union(NumericResultEnum) { int: IntResult, float: FloatResult };
const StringResult = struct { value: []const u8, endIndex: usize };
const ObjectResult = struct { value: JsonObject, endIndex: usize };

fn readstring(jsonBlob: []const u8) StringResult {
    var readingString = false;
    var startingIndex: usize = undefined;
    for (jsonBlob, 0..) |char, index| {
        if (readingString == false and char == '"') {
            readingString = true;
            startingIndex = index + 1;
            continue;
        }
        if (readingString == true and char == '"' and jsonBlob[index - 1] != '\\') {
            return .{ .value = jsonBlob[startingIndex..index], .endIndex = index };
        }
    }
    unreachable;
}

fn parseObject(gpa: std.mem.Allocator, jsonBlob: []const u8) std.mem.Allocator.Error!ObjectResult {
    var index: usize = 0;
    var valuesArray = std.ArrayList(JsonValueUnion)
        .initCapacity(gpa, 10) catch unreachable;
    errdefer valuesArray.deinit(gpa);
    while (index < jsonBlob.len) {
        if (jsonBlob[index] == '}') {
            const values = try valuesArray.toOwnedSlice(gpa);
            const result = JsonObject{ .values = values };
            return .{ .endIndex = index + 1, .value = result };
        }
        if (jsonBlob[index] == '{' or jsonBlob[index] == ' ' or jsonBlob[index] == '\n') {
            index += 1;
            continue;
        }
        const entryResult = try parseEntry(gpa, jsonBlob[index..]);
        try valuesArray.append(gpa, entryResult.entry);
        index += entryResult.endIndex + 1;
    }
    unreachable;
}

test "can read a json object" {
    const testString =
        \\ {
        \\   "name":"Jack",
        \\   "age": 12
        \\ }
    ;
    const gpa = std.testing.allocator;
    const result = try parseObject(gpa, testString);
    defer gpa.free(result.value.values);

    const expectedStringValue: StringNode = .{ .name = "name", .value = "Jack" };
    try std.testing.expectEqualDeep(expectedStringValue, result.value.values[0].string);

    const expectedIntValue: IntNode = .{ .name = "age", .value = 12 };
    try std.testing.expectEqualDeep(expectedIntValue, result.value.values[1].int);
}
test "can read a complex json object" {
    const testString =
        \\ {"name":"Jack", "age": 12, "address": { "street": "123 west ave", "zipcode": 12345 } }
    ;
    const gpa = std.testing.allocator;
    const result = try parseObject(gpa, testString);
    defer gpa.free(result.value.values);
    defer gpa.free(result.value.values[2].obj.value.values);

    const expectedStringValue: StringNode = .{ .name = "name", .value = "Jack" };
    try std.testing.expectEqualDeep(expectedStringValue, result.value.values[0].string);

    const expectedIntValue: IntNode = .{ .name = "age", .value = 12 };
    try std.testing.expectEqualDeep(expectedIntValue, result.value.values[1].int);

    const ob: JsonObject = .{ .values = &.{ JsonValueUnion{
        .string = StringNode{ .name = "street", .value = "123 west ave" },
    }, JsonValueUnion{
        .int = IntNode{ .name = "zipcode", .value = 12345 },
    } } };

    const expectedObject = ObjectNode{ .name = "address", .value = ob };
    try std.testing.expectEqualDeep(expectedObject, result.value.values[2].obj);
}

test "can read a simple string properly" {
    const testString = " : \"hello\" ";

    const result = readstring(testString);
    try std.testing.expectEqual('"', testString[result.endIndex]);
    try std.testing.expectEqualStrings("hello", result.value);
}
test "can read a complex string properly" {
    const testString = " : \"hello \\\" world\" ";

    const result = readstring(testString);
    try std.testing.expectEqual(18, result.endIndex);
    try std.testing.expectEqualStrings("hello \\\" world", result.value);
}

fn readNumer(jsonBlob: []const u8) NumericResult {
    var isFloat = false;
    var foundNumber = false;
    var startingIndex: usize = 0;
    for (jsonBlob, 0..) |char, index| {
        if (foundNumber == false and (char > '9' or char < '0')) {
            continue;
        } else if (foundNumber == false) {
            foundNumber = true;
            startingIndex = index;
        }

        if (char == '.') {
            isFloat = true;
            continue;
        }
        if (char > '9' or char < '0') {
            if (isFloat) {
                const floatVal = std.fmt.parseFloat(f64, jsonBlob[startingIndex..index]) catch 0;
                return .{ .float = FloatResult{ .value = floatVal, .endIndex = index - 1 } };
            } else {
                const intVal = std.fmt.parseInt(u64, jsonBlob[startingIndex..index], 10) catch 0;
                return .{ .int = IntResult{ .value = intVal, .endIndex = index - 1 } };
            }
        }
        if (index == jsonBlob.len - 1) {
            if (isFloat) {
                const floatVal = std.fmt.parseFloat(f64, jsonBlob[startingIndex..]) catch 0;
                return .{ .float = FloatResult{ .value = floatVal, .endIndex = index } };
            } else {
                const intVal = std.fmt.parseInt(u64, jsonBlob[startingIndex..], 10) catch 0;
                return .{ .int = IntResult{ .value = intVal, .endIndex = index } };
            }
        }
    }
    unreachable;
}

test "can read a number and get the expected index back" {
    const input = " : 12345";
    const result = readNumer(input);

    try std.testing.expectEqual(7, result.int.endIndex);
    try std.testing.expectEqual(12345, result.int.value);
}
test "can read last number in array" {
    const input = "12345]";
    const result = readNumer(input);

    try std.testing.expectEqual(4, result.int.endIndex);
    try std.testing.expectEqual(12345, result.int.value);
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
    const testValue = "\"example\": \"hello \\\"world\\\"\" ";
    const gpa = std.testing.allocator;
    const entryResult = try parseEntry(gpa, testValue);
    const jsonValue = entryResult.entry;
    const expectedValue = JsonValueUnion{ .string = .{ .name = "example", .value = "hello \\\"world\\\"" } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
test "can parse a int" {
    const testValue = "\"example\": 2 ";
    const gpa = std.testing.allocator;
    const entryResult = try parseEntry(gpa, testValue);
    const jsonValue = entryResult.entry;

    const expectedValue = JsonValueUnion{ .int = .{ .name = "example", .value = 2 } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
test "can parse a float" {
    const testValue = "\"example\": 2.3 ";
    const gpa = std.testing.allocator;
    const entryResult = try parseEntry(gpa, testValue);
    const jsonValue = entryResult.entry;

    const expectedValue = JsonValueUnion{ .float = .{ .name = "example", .value = 2.3 } };
    try std.testing.expectEqualDeep(expectedValue, jsonValue);
}
test "can parse a list of ints" {
    const testValue = "\"example\": [2, 32, 54] ";
    const gpa = std.heap.page_allocator;
    const entryResult = try parseEntry(gpa, testValue);
    const jsonValue = entryResult.entry;
    defer gpa.free(jsonValue.array.value);

    //const expectedValuesList: []const sonValue = &.{};

    //const expectedValue = JsonValueUnion{ .array = .{ .name = "example", .value = expectedValuesList } };
    //try std.testing.expectEqualDeep(expectedValue, jsonValue);
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
