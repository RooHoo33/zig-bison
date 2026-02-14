const std = @import("std");
const Bison = @import("bison_v2.zig");
const indentSize = 2;
const nullValue = "null";

fn getPad(gpa: std.mem.Allocator, indent: u8) ![]u8 {
    const pad: []u8 = try gpa.alloc(u8, indent);
    for (0..indent) |index| {
        pad[index] = ' ';
    }
    return pad;
}

fn printObject(gpa: std.mem.Allocator, object: Bison.Object, indent: u8) ![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    var stringResult = try std.ArrayList(u8)
        .initCapacity(gpa, 20);
    try stringResult.append(gpa, '{');
    try stringResult.append(gpa, '\n');
    for (object.entries, 0..) |entry, index| {
        const entryString = try printRootObjectEntry(gpa, entry, indent + indentSize);
        defer gpa.free(entryString);
        try stringResult.appendSlice(gpa, entryString);
        if (index + 1 < object.entries.len) {
            try stringResult.append(gpa, ',');
        }
        try stringResult.append(gpa, '\n');
    }
    try stringResult.appendSlice(gpa, pad);
    try stringResult.append(gpa, '}');
    return stringResult.toOwnedSlice(gpa);
}
fn printRootObject(gpa: std.mem.Allocator, object: Bison.Object, indent: u8) ![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    const objectString = try printObject(gpa, object, indent);
    defer gpa.free(objectString);
    return try std.mem.concat(gpa, u8, &.{ pad, objectString });
}

fn printRootObjectEntry(gpa: std.mem.Allocator, node: Bison.ObjectEntry, indent: u8) anyerror![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    const keyString = try std.fmt.allocPrint(gpa, "\"{s}\": ", .{node.name});
    defer gpa.free(keyString);
    var stringResult = try std.ArrayList(u8)
        .initCapacity(gpa, keyString.len * 2);
    try stringResult.appendSlice(gpa, pad);
    try stringResult.appendSlice(gpa, keyString);
    const valueString = try printValue(gpa, node.value, indent);
    defer gpa.free(valueString);
    try stringResult.appendSlice(gpa, valueString);
    return try stringResult.toOwnedSlice(gpa);
}

pub fn printValue(gpa: std.mem.Allocator, node: Bison.JsonValueType, indent: u8) anyerror![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);

    const result = try switch (node) {
        .Int => std.fmt.allocPrint(gpa, "{d}", .{node.Int}),
        .Float => std.fmt.allocPrint(gpa, "{d}", .{node.Float}),
        .Boolean => std.fmt.allocPrint(gpa, "{}", .{node.Boolean}),
        .String => std.fmt.allocPrint(gpa, "\"{s}\"", .{node.String}),
        .Null => gpa.dupe(u8, nullValue),
        .Array => array: {
            var stringResult = try std.ArrayList(u8)
                .initCapacity(gpa, 20);
            try stringResult.appendSlice(gpa, "[\n");
            const innerPad = try getPad(gpa, indent + indentSize);
            defer gpa.free(innerPad);
            for (node.Array, 0..) |listValue, index| {
                const result = try printValue(gpa, listValue, indent + indentSize);
                defer gpa.free(result);
                if (index != 0) {
                    try stringResult.appendSlice(gpa, ",\n");
                }
                try stringResult.appendSlice(gpa, innerPad);
                try stringResult.appendSlice(gpa, result);
            }
            try stringResult.append(gpa, '\n');
            try stringResult.appendSlice(gpa, pad);
            try stringResult.append(gpa, ']');
            break :array try stringResult.toOwnedSlice(gpa);
        },
        .Object => printObject(gpa, node.Object, indent),
        //.Object => blk: {
        //    var stringResult = try std.ArrayList(u8)
        //        .initCapacity(gpa, 20);
        //    //defer gpa.free(stringResult);

        //    try stringResult.appendSlice(gpa, "{\n");
        //    for (node.obj.value.values, 0..) |objValue, index| {
        //        const result = try printNode(gpa, objValue, indent + indentSize);
        //        defer gpa.free(result);
        //        if (index != 0) {
        //            try stringResult.appendSlice(gpa, ",\n");
        //        }
        //        //try stringResult.appendSlice(gpa, pad);
        //        try stringResult.appendSlice(gpa, result);
        //    }
        //    try stringResult.appendSlice(gpa, "\n");
        //    try stringResult.appendSlice(gpa, pad);
        //    try stringResult.appendSlice(gpa, "}");
        //    break :blk try stringResult.toOwnedSlice(gpa);
        //},
    };
    return result;
    //defer gpa.free(result);
    //return std.mem.concat(gpa, u8, &.{ pad, result });
}

test "can print object with primitives" {
    const intEntry: Bison.ObjectEntry = .{ .name = "age", .value = Bison.JsonValueType{ .Int = 20 } };
    const stringEntry: Bison.ObjectEntry = .{ .name = "name", .value = Bison.JsonValueType{ .String = "Jack" } };
    const isCoolEntry: Bison.ObjectEntry = .{ .name = "is_cool", .value = Bison.JsonValueType{ .Boolean = true } };
    const debtEntry: Bison.ObjectEntry = .{ .name = "debt", .value = Bison.JsonValueType{ .Float = -987.65 } };
    const nullEntry: Bison.ObjectEntry = .{ .name = "nothing", .value = Bison.JsonValueType{ .Null = {} } };
    const object = Bison.Object{ .entries = &.{ intEntry, stringEntry, isCoolEntry, debtEntry, nullEntry } };
    const gpa = std.testing.allocator;
    const result = try printRootObject(gpa, object, 2);
    defer gpa.free(result);
    const expected =
        \\  {
        \\    "age": 20,
        \\    "name": "Jack",
        \\    "is_cool": true,
        \\    "debt": -987.65,
        \\    "nothing": null
        \\  }
    ;
    try std.testing.expectEqualStrings(expected, result);
}

test "can print a list of ints" {
    const intValueOne: Bison.JsonValueType = Bison.JsonValueType{ .Int = 5 };
    const intValueTwo: Bison.JsonValueType = Bison.JsonValueType{ .Int = 2 };
    const array: Bison.ObjectEntry = .{ .name = "ages", .value = Bison.JsonValueType{ .Array = &.{ intValueOne, intValueTwo } } };
    const object: Bison.Object = .{ .entries = &.{array} };
    const gpa = std.testing.allocator;
    const result = try printRootObject(gpa, object, 0);
    defer gpa.free(result);
    const expected =
        \\{
        \\  "ages": [
        \\    5,
        \\    2
        \\  ]
        \\}
    ;
    try std.testing.expectEqualStrings(expected, result);
}

test "can print a complex object node" {
    const gpa = std.testing.allocator;
    const numberEntry = Bison.ObjectEntry{ .name = "age", .value = Bison.JsonValueType{ .Int = 234 } };
    const nameEntry = Bison.ObjectEntry{ .name = "name", .value = Bison.JsonValueType{ .String = "Jack \\\"Jack\\\" Me" } };
    const randNumbers = Bison.JsonValueType{ .Array = &.{ Bison.JsonValueType{ .Int = 1 }, Bison.JsonValueType{ .Int = 2 }, Bison.JsonValueType{ .Int = 3 } } };
    const randEntry = Bison.ObjectEntry{ .name = "rand", .value = randNumbers };
    const nestedObjectValue = Bison.Object{ .entries = &.{ numberEntry, nameEntry, randEntry } };

    const nestedObject = Bison.ObjectEntry{ .name = "value", .value = Bison.JsonValueType{ .Object = nestedObjectValue } };
    const idEntry = Bison.ObjectEntry{ .name = "id", .value = Bison.JsonValueType{ .String = "abc123" } };
    const rootObject = Bison.Object{ .entries = &.{ idEntry, nestedObject } };

    const result = try printRootObject(gpa, rootObject, 2);
    defer gpa.free(result);
    const expected =
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
    try std.testing.expectEqualStrings(expected, result);
}

//test "can print an object node" {
//    const int: IntNode = .{ .name = "age", .value = 20 };
//
//    const obj: JsonObject = .{ .values = &.{JsonValueUnion{
//        .int = int,
//    }} };
//    const objectNode: ObjectNode = .{ .name = "person", .value = obj };
//    const gpa = std.testing.allocator;
//    const result = try printNode(gpa, .{ .obj = objectNode }, 2);
//    defer gpa.free(result);
//    const expected =
//        \\  {
//        \\    "age": 20
//        \\  }
//    ;
//    try std.testing.expectEqualStrings(expected, result);
//}
