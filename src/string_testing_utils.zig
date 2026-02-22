const std = @import("std");
const BisonPrint = @import("bison_print.zig");

pub fn expectEqualsStringWithoutColor(gpa: std.mem.Allocator, expected: []const u8, actual: []const u8) !void {
    var actualWithoutColors = actual;
    inline for (std.meta.fields(BisonPrint.TermColorsStruct), 0..) |field, index| {
        const colorValue = @as([]const u8, @field(BisonPrint.TermColors, field.name));
        const size = std.mem.replacementSize(u8, actualWithoutColors, colorValue, "");
        const output = try gpa.alloc(u8, size);
        _ = std.mem.replace(u8, actualWithoutColors, colorValue, "", output);
        if (index != 0) {
            // dont free the passed param
            gpa.free(actualWithoutColors);
        }
        actualWithoutColors = output;
    }
    defer gpa.free(actualWithoutColors);

    try std.testing.expectEqualStrings(expected, actualWithoutColors);
}
