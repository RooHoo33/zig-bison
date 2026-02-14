const std = @import("std");

fn isLetter(char: u8) bool {
    return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z');
}

pub fn matches(value: []const u8, search: []const u8, caseSensitive: bool) bool {
    var searchIndex: usize = 0;
    if (search.len == 0) {
        return true;
    }

    for (value) |char| {
        const searchChar = search[searchIndex];
        if (char == searchChar) {
            searchIndex += 1;
        } else if (caseSensitive == false and isLetter(char) and isLetter(searchChar)) {
            var lowerChar: u8 = char;
            if (char > 'Z') {
                lowerChar = char - 32;
            }
            var lowerSearchChar: u8 = searchChar;
            if (searchChar > 'Z') {
                lowerSearchChar = searchChar - 32;
            }
            if (lowerChar == lowerSearchChar) {
                searchIndex += 1;
            }
        }
        if (searchIndex == search.len) {
            return true;
        }
    }
    return false;
}

test "empty search string returns true" {
    const value = "test";
    const search = "";
    try std.testing.expect(matches(value, search, true));
}

test "match when strings match" {
    const value = "test";
    try std.testing.expect(matches(value, value, true));
}

test "match when string starts with expected" {
    const value = "test";
    const search = "te";
    try std.testing.expect(matches(value, search, true));
}
test "match when string ends with expected" {
    const value = "test";
    const search = "st";
    try std.testing.expect(matches(value, search, true));
}
test "match when char match in order but not next to each other" {
    const value = "test";
    const search = "ts";
    try std.testing.expect(matches(value, search, true));
}

test "if the search string is longer than the value false is returned" {
    const value = "test";
    const search = "test1";
    try std.testing.expect(!matches(value, search, true));
}
test "value missing middle char of search not match" {
    const value = "hllo";
    const search = "hel";
    try std.testing.expect(!matches(value, search, true));
}
test "if case sensitive is false strings match even when casing doest" {
    const value = "HEY how ARE YOU?![@";
    const search = "hey HOW are YOU![";
    try std.testing.expect(matches(value, search, false));
}
