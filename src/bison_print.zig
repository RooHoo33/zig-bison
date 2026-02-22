const std = @import("std");
const Bison = @import("bison_v2.zig");
const StringTestingUtils = @import("string_testing_utils.zig");
const indentSize = 2;
const nullValue = "null";

// zig fmt: off
pub const TermColorsStruct = struct { 
    BLACK: []const u8 = "\x1b[30m",
    RED: []const u8 = "\x1b[31m",
    GREEN: []const u8 = "\x1b[32m",
    YELLOW: []const u8 = "\x1b[33m",
    BLUE: []const u8 = "\x1b[34m",
    PURPLE: []const u8 = "\x1b[35m",
    CYAN: []const u8 = "\x1b[36m",
    WHITE: []const u8 = "\x1b[37m",
    RESET: []const u8 = "\x1b[0m",
// zig fmt: on
    fn getNestingColor(self: *const TermColorsStruct, nestingLevel: u32) []const u8 {
        return switch (@rem(nestingLevel, 6)) {
            0 => self.CYAN,
            1 => self.RED,
            2 => self.BLUE,
            3 => self.PURPLE,
            4 => self.YELLOW,
            5 => self.GREEN,
            else => self.RESET,
        };
    }
};

pub const TermColors: TermColorsStruct = .{};

fn getPad(gpa: std.mem.Allocator, indent: u8) ![]u8 {
    const pad: []u8 = try gpa.alloc(u8, indent);
    for (0..indent) |index| {
        pad[index] = ' ';
    }
    return pad;
}

fn printObject(gpa: std.mem.Allocator, object: Bison.Object, indent: u8, nestingLevel: u32) ![]u8 {
    const pad = try getPad(gpa, indent);
    const nestingColor = TermColors.getNestingColor(nestingLevel);
    defer gpa.free(pad);
    const braceString = try std.fmt.allocPrint(gpa, "{s}{{{s}\n", .{ nestingColor, TermColors.RESET });
    const backBraceString = try std.fmt.allocPrint(gpa, "{s}}}{s}", .{ nestingColor, TermColors.RESET });
    defer gpa.free(braceString);
    defer gpa.free(backBraceString);
    var stringResult = try std.ArrayList(u8)
        .initCapacity(gpa, 20);
    try stringResult.appendSlice(gpa, braceString);
    for (object.entries, 0..) |entry, index| {
        const entryString = try printRootObjectEntry(gpa, entry, indent + indentSize, nestingLevel + 1);
        defer gpa.free(entryString);
        try stringResult.appendSlice(gpa, entryString);
        if (index + 1 < object.entries.len) {
            try stringResult.append(gpa, ',');
        }
        try stringResult.append(gpa, '\n');
    }
    try stringResult.appendSlice(gpa, pad);
    try stringResult.appendSlice(gpa, backBraceString);
    return stringResult.toOwnedSlice(gpa);
}
fn printRootObject(gpa: std.mem.Allocator, object: Bison.Object, indent: u8, nestingLevel: u32) ![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    const objectString = try printObject(gpa, object, indent, nestingLevel + 1);
    defer gpa.free(objectString);
    return try std.mem.concat(gpa, u8, &.{ pad, objectString });
}

fn printRootObjectEntry(gpa: std.mem.Allocator, node: Bison.ObjectEntry, indent: u8, nestingLevel: u32) anyerror![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    const keyString = try std.fmt.allocPrint(gpa, "{s}\"{s}\"{s}: ", .{ TermColors.CYAN, node.name, TermColors.RESET });
    defer gpa.free(keyString);
    var stringResult = try std.ArrayList(u8)
        .initCapacity(gpa, keyString.len * 2);
    try stringResult.appendSlice(gpa, pad);
    try stringResult.appendSlice(gpa, keyString);
    const valueString = try printValue(gpa, node.value, indent, nestingLevel);
    defer gpa.free(valueString);
    try stringResult.appendSlice(gpa, valueString);
    return try stringResult.toOwnedSlice(gpa);
}

pub fn print(gpa: std.mem.Allocator, node: Bison.JsonValueType) anyerror![]u8 {
    return printValue(gpa, node, 0, 0);
}
fn printValue(gpa: std.mem.Allocator, node: Bison.JsonValueType, indent: u8, nestingLevel: u32) anyerror![]u8 {
    const pad = try getPad(gpa, indent);
    defer gpa.free(pad);
    if (nestingLevel == 99999) {}

    const nestingColor = TermColors.getNestingColor(nestingLevel);
    const bracketString = try std.fmt.allocPrint(gpa, "{s}[{s}\n", .{ nestingColor, TermColors.RESET });
    const backBracketString = try std.fmt.allocPrint(gpa, "{s}]{s}", .{ nestingColor, TermColors.RESET });
    defer gpa.free(bracketString);
    defer gpa.free(backBracketString);

    const result = try switch (node) {
        .Int => std.fmt.allocPrint(gpa, "{s}{d}{s}", .{ TermColors.BLUE, node.Int, TermColors.RESET }),
        .Float => std.fmt.allocPrint(gpa, "{s}{d}{s}", .{ TermColors.BLUE, node.Float, TermColors.RESET }),
        .Boolean => std.fmt.allocPrint(gpa, "{s}{}{s}", .{ TermColors.YELLOW, node.Boolean, TermColors.RESET }),
        .String => std.fmt.allocPrint(gpa, "{s}\"{s}\"{s}", .{ TermColors.GREEN, node.String, TermColors.RESET }),
        .Null => gpa.dupe(u8, nullValue),
        .Array => array: {
            var stringResult = try std.ArrayList(u8)
                .initCapacity(gpa, 20);
            try stringResult.appendSlice(gpa, bracketString);
            const innerPad = try getPad(gpa, indent + indentSize);
            defer gpa.free(innerPad);
            for (node.Array, 0..) |listValue, index| {
                const result = try printValue(gpa, listValue, indent + indentSize, nestingLevel + 1);
                defer gpa.free(result);
                if (index != 0) {
                    try stringResult.appendSlice(gpa, ",\n");
                }
                try stringResult.appendSlice(gpa, innerPad);
                try stringResult.appendSlice(gpa, result);
            }
            try stringResult.append(gpa, '\n');
            try stringResult.appendSlice(gpa, pad);
            try stringResult.appendSlice(gpa, backBracketString);
            break :array try stringResult.toOwnedSlice(gpa);
        },
        .Object => printObject(gpa, node.Object, indent, nestingLevel + 1),
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
    const result = try printRootObject(gpa, object, 2, 1);
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
    try StringTestingUtils.expectEqualsStringWithoutColor(gpa, expected, result);
}

test "can print a list of ints" {
    const intValueOne: Bison.JsonValueType = Bison.JsonValueType{ .Int = 5 };
    const intValueTwo: Bison.JsonValueType = Bison.JsonValueType{ .Int = 2 };
    const array: Bison.ObjectEntry = .{ .name = "ages", .value = Bison.JsonValueType{ .Array = &.{ intValueOne, intValueTwo } } };
    const object: Bison.Object = .{ .entries = &.{array} };
    const gpa = std.testing.allocator;
    const result = try printRootObject(gpa, object, 0, 0);
    defer gpa.free(result);
    const expected =
        \\{
        \\  "ages": [
        \\    5,
        \\    2
        \\  ]
        \\}
    ;
    try StringTestingUtils.expectEqualsStringWithoutColor(gpa, expected, result);
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

    const result = try printRootObject(gpa, rootObject, 2, 1);
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
    try StringTestingUtils.expectEqualsStringWithoutColor(gpa, expected, result);
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
//    try expectEqualsStringWithoutColor(expected, result);
//}
