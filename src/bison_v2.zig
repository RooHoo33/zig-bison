const std = @import("std");
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;

const Index = u64;

pub const JsonValueEnum = enum { Int, Float, String, Boolean, Object, Array, Null };

pub const ObjectEntry = struct { name: []const u8, value: JsonValueType };
pub const Object = struct {
    entries: []const ObjectEntry,

    pub fn free(self: *const Object, gpa: Allocator) void {
        for (self.entries) |entry| {
            entry.value.free(gpa);
        }
        gpa.free(self.entries);
    }
};
pub const JsonValueType = union(JsonValueEnum) {
    Int: i64,
    Float: f64,
    String: []const u8,
    Boolean: bool,
    Object: Object,
    Array: []const JsonValueType,
    Null: void,
    pub fn free(self: *const JsonValueType, gpa: Allocator) void {
        switch (self.*) {
            .Object => {
                self.Object.free(gpa);
            },
            .Array => {
                for (self.Array) |arrayValue| {
                    switch(arrayValue) {
                        .Object => |objValue| {
                            objValue.free(gpa);
                        },
                        .Array => |arrayValues| {
                            for (arrayValues) |innerArrayValue| {
                            innerArrayValue.free(gpa);
                            }
                        },
                        else => {}
                }
                }
                gpa.free(self.Array);
            }
            ,
            else => {},
        }
    }
};

pub fn parseJson(gpa: Allocator, jsonBlob: []const u8) !JsonValueType {
    for (jsonBlob, 0..) |char, index| {
        if (char == '{') {
            const object, _ = try parseObject(gpa, jsonBlob[index..]);

            return JsonValueType{ .Object = object };
        }
    }
    unreachable;
}
fn parseObjectKey(jsonBlob: []const u8) struct { []const u8, Index } {
    var inKey: bool = false;
    var startIndex: usize = 0;

    for (jsonBlob[0..], 0..) |char, index| {
        if (char == '"' and !inKey) {
            inKey = true;
            startIndex = index + 1;
        } else if (char == '"' and jsonBlob[index - 1] != '\\' and inKey) {
            return .{ jsonBlob[startIndex..index], index };
        }
    }
    unreachable;
}
fn parseNumber(jsonBlob: []const u8) !struct { JsonValueType, Index } {
    var isInt = true;
    for (jsonBlob, 0..) |char, index| {
        if (char == '-') {
            continue;
        } else if (char == '.') {
            isInt = false;
        } else if (char < '0' or char > '9') {
            if (isInt) {
                const value = try std.fmt.parseInt(i64, jsonBlob[0..index], 10);
                return .{ JsonValueType{ .Int = value }, index };
            } else {
                const value = try std.fmt.parseFloat(f64, jsonBlob[0..index]);
                return .{ JsonValueType{ .Float = value }, index };
            }
        }
    }
    unreachable;
}
fn parseNull(jsonBlob: []const u8) struct { JsonValueType, Index } {
    if (std.mem.startsWith(u8, jsonBlob, "null")) {
        return .{ JsonValueType{ .Null = {} }, 4 };
    }
    unreachable;
}
fn parseBoolean(jsonBlob: []const u8) struct { JsonValueType, Index } {
    if (std.mem.startsWith(u8, jsonBlob, "true")) {
        return .{ JsonValueType{ .Boolean = true }, 4 };
    }
    if (std.mem.startsWith(u8, jsonBlob, "false")) {
        return .{ JsonValueType{ .Boolean = false }, 5 };
    }
    unreachable;
}
fn parseString(jsonBlob: []const u8) !struct { JsonValueType, Index } {
    var inString = false;
    for (jsonBlob, 0..) |char, index| {
        if (char == '"' and inString == false) {
            inString = true;
        } else if (char == '"') {
            const value = jsonBlob[0..index];
            return .{ JsonValueType{ .String = value }, index };
        }
    }
    unreachable;
}
fn parseValue(gpa: Allocator, jsonBlob: []const u8) anyerror!struct { JsonValueType, Index } {
    for (jsonBlob, 0..) |char, index| {
        if (char == ' ') {
            continue;
        } else if (char == '-' or (char >= '0' and char <= '9')) {
            const value: JsonValueType, const returnIndex: Index = try parseNumber(jsonBlob[index..]);
            return .{ value, index + returnIndex };
        } else if (char == '"') {
            const value: []const u8, const returnIndex: Index = parseObjectKey(jsonBlob[index..]);
            const jsonValueType = JsonValueType{ .String = value };
            return .{ jsonValueType, index + returnIndex };
        } else if (char == '[') {
            const value: JsonValueType, const returnIndex: Index = try parseList(gpa, jsonBlob[index..]);
            return .{ value, index + returnIndex };
        } else if (char == '{') {
            const value: Object, const returnIndex: Index = try parseObject(gpa, jsonBlob[index..]);
            const jsonValueType = JsonValueType{ .Object = value };
            return .{ jsonValueType, index + returnIndex };
        } else if (char == 't' or char == 'f') {
            const value: JsonValueType, const returnIndex: Index = parseBoolean(jsonBlob[index..]);
            return .{ value, index + returnIndex };
        } else if (char == 'n') {
            const value: JsonValueType, const returnIndex: Index = parseNull(jsonBlob[index..]);
            return .{ value, index + returnIndex };
        }
    }
    std.debug.print("Trying to read value {s}", .{jsonBlob});
    unreachable;
}

fn parseList(gpa: Allocator, jsonBlob: []const u8) anyerror!struct { JsonValueType, Index } {
    var values = try std.ArrayList(JsonValueType).initCapacity(gpa, 5);
    defer values.clearAndFree(gpa);
    var index: usize = 1; // skip 0 becsuase thats the [ char
    while (index < jsonBlob.len) {
        if (jsonBlob[index] == ',' or jsonBlob[index] == '\n' or jsonBlob[index] == ' ' or jsonBlob[index] == '}') {
            index += 1;
        } else if (jsonBlob[index] == ']') {
            return .{ JsonValueType{ .Array = try values.toOwnedSlice(gpa) }, index };
        } else {
            const value, const valueIndexOffset = try parseValue(gpa, jsonBlob[index..]);
            index += valueIndexOffset;
            try values.append(gpa, value);
        }
    }
    unreachable;
}

fn parseObject(gpa: Allocator, jsonBlob: []const u8) !struct { Object, Index } {
    var index: usize = 0;
    var entryList = try std.ArrayList(ObjectEntry).initCapacity(gpa, 5);
    defer entryList.clearAndFree(gpa);
    while (jsonBlob.len > index) {
        const char = jsonBlob[index];
        if (char == '"') {
            const key: []const u8, const nextIndex: Index = parseObjectKey(jsonBlob[index..]);
            index += nextIndex + 1;
            const value, const offsetFromVal = try parseValue(gpa, jsonBlob[index..]);
            index += offsetFromVal + 1;
            const entry = ObjectEntry{ .name = key, .value = value };
            try entryList.append(gpa, entry);
        } else if (char == '}') {
            return .{ Object{ .entries = try entryList.toOwnedSlice(gpa) }, index };
        } else {
            index += 1;
        }
    }
    return .{ Object{ .entries = try entryList.toOwnedSlice(gpa) }, index };
}

test "can parse an empty json object" {
    const json = "{}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const expected = JsonValueType{ .Object = Object{ .entries = &.{} } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}
test "can parse a json object" {
    const json = "{\"age\" : 234, \"name\": \"Jack \\\"Jack\\\" Me\", \"rand\": [1, 2,3]}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const numberEntry = ObjectEntry{ .name = "age", .value = JsonValueType{ .Int = 234 } };
    const nameEntry = ObjectEntry{ .name = "name", .value = JsonValueType{ .String = "Jack \\\"Jack\\\" Me" } };
    const randNumbers = JsonValueType{ .Array = &.{ JsonValueType{ .Int = 1 }, JsonValueType{ .Int = 2 }, JsonValueType{ .Int = 3 } } };
    const randEntry = ObjectEntry{ .name = "rand", .value = randNumbers };

    const expected = JsonValueType{ .Object = Object{ .entries = &.{ numberEntry, nameEntry, randEntry } } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}

test "can parse a nested json object" {
    const json = "{\"address\":{\"zip\":123}}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const nestedObjectZipEntry = ObjectEntry{ .name = "zip", .value = JsonValueType{ .Int = 123 } };
    const nestedObject = Object{ .entries = &.{nestedObjectZipEntry} };
    const nestedObjectEntry = ObjectEntry{ .name = "address", .value = JsonValueType{ .Object = nestedObject } };

    const expected = JsonValueType{ .Object = Object{ .entries = &.{nestedObjectEntry} } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}

test "can parse booleans" {
    const json = "{\"is_cool\" : true, \"is_lame\": false}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const isCoolEntry = ObjectEntry{ .name = "is_cool", .value = JsonValueType{ .Boolean = true } };
    const isLameEntry = ObjectEntry{ .name = "is_lame", .value = JsonValueType{ .Boolean = false } };
    const expected = JsonValueType{ .Object = Object{ .entries = &.{ isCoolEntry, isLameEntry } } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}
test "can parse ints" {
    const json = "{\"money\" : 12, \"debt\" : -43}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const moneyEntry = ObjectEntry{ .name = "money", .value = JsonValueType{ .Int = 12 } };
    const debtEntry = ObjectEntry{ .name = "debt", .value = JsonValueType{ .Int = -43 } };
    const expected = JsonValueType{ .Object = Object{ .entries = &.{ moneyEntry, debtEntry } } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}
test "can parse floats" {
    const json = "{\"money\" : 12.34, \"debt\" : -43.21}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const moneyEntry = ObjectEntry{ .name = "money", .value = JsonValueType{ .Float = 12.34 } };
    const debtEntry = ObjectEntry{ .name = "debt", .value = JsonValueType{ .Float = -43.21 } };
    const expected = JsonValueType{ .Object = Object{ .entries = &.{ moneyEntry, debtEntry } } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}
test "can parse nulls" {
    const json = "{\"missing\" : nulls}";
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const missingEntry = ObjectEntry{ .name = "missing", .value = JsonValueType{ .Null = {} } };
    const expected = JsonValueType{ .Object = Object{ .entries = &.{missingEntry} } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}

test "can parse a multiline list" {
    const json =
        \\  {
        \\      "rand": [
        \\        1,
        \\        2,
        \\        3
        \\      ]
        \\  }
    ;
    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);
    const randNumbers = JsonValueType{ .Array = &.{ JsonValueType{ .Int = 1 }, JsonValueType{ .Int = 2 }, JsonValueType{ .Int = 3 } } };
    const randEntry = ObjectEntry{ .name = "rand", .value = randNumbers };

    const expected = JsonValueType{ .Object = Object{ .entries = &.{ randEntry } } };
    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);

}

test "can parse complex list of objects" {
    const json =
        \\{
        \\  "name": "Alex",
        \\  "purchases": [
        \\    {
        \\      "orders": [
        \\        { "payment": "CREDIT", "id": 101 },
        \\        { "payment": "CASH", "id": 102 }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;

    const gpa = std.testing.allocator;
    var result = try parseJson(gpa, json);
    defer result.free(gpa);

    const order1Id = ObjectEntry{ .name = "id", .value = JsonValueType{ .Int = 101 } };
    const order1Pay = ObjectEntry{ .name = "payment", .value = JsonValueType{ .String = "CREDIT" } };
    const order1 = JsonValueType{ .Object = Object{ .entries = &.{ order1Pay, order1Id } } };

    const order2Id = ObjectEntry{ .name = "id", .value = JsonValueType{ .Int = 102 } };
    const order2Pay = ObjectEntry{ .name = "payment", .value = JsonValueType{ .String = "CASH" } };
    const order2 = JsonValueType{ .Object = Object{ .entries = &.{ order2Pay, order2Id } } };

    const ordersArray = JsonValueType{ .Array = &.{ order1, order2 } };
    const ordersEntry = ObjectEntry{ .name = "orders", .value = ordersArray };
    const purchase1 = JsonValueType{ .Object = Object{ .entries = &.{ordersEntry} } };

    const nameEntry = ObjectEntry{ .name = "name", .value = JsonValueType{ .String = "Alex" } };
    const purchasesArray = JsonValueType{ .Array = &.{purchase1} };
    const purchasesEntry = ObjectEntry{ .name = "purchases", .value = purchasesArray };

    const expected = JsonValueType{ .Object = Object{ .entries = &.{ nameEntry, purchasesEntry } } };

    try std.testing.expectEqualDeep(expected.Object.entries, result.Object.entries);
}
