const std = @import("std");

fn matches(value: []const u8, search: []const u8) bool {
    var searchIndex:usize = 0;
    if (search.len == 0) {
        return true;
    }

    for (value) |char| {
        if (char == search[searchIndex]) {
            searchIndex += 1;
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
    try std.testing.expect(matches(value, search));
}

test "match when strings match" {
    const value = "test";
    try std.testing.expect(matches(value, value));
}

test "match when string starts with expected" {
    const value = "test";
    const search = "te";
    try std.testing.expect(matches(value, search));
}
test "match when string ends with expected" {
    const value = "test";
    const search = "st";
    try std.testing.expect(matches(value, search));
}
test "match when char match in order but not next to each other" {
    const value = "test";
    const search = "ts";
    try std.testing.expect(matches(value, search));
}

test "if the search string is longer than the value false is returned" {
    const value = "test";
    const search = "test1";
    try std.testing.expect(!matches(value, search));
}
test "value missing middle char of search not match" {
    const value = "hllo";
    const search = "hel";
    try std.testing.expect(!matches(value, search));
}
