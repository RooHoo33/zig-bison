const std = @import("std");

const SearchTokenType = enum { FUZZY, EXACT, EXACT_WORD, START, END };
const SearchToken = struct {
    type: SearchTokenType,
    searchChars: []const u8,

    fn fromString(string: []const u8) SearchToken {
        if (string.len == 0) {
            return .{ .type = SearchTokenType.FUZZY, .searchChars = "" };
        }

        return .{ .type = SearchTokenType.FUZZY, .searchChars = string[0..] };
    }

    fn matches(self: *const SearchToken, input: []const u8) bool {
        switch (self.type) {
            .FUZZY => {
                return fuzzyMatches(input, self.searchChars, false);
            },
            else => unreachable,
        }
    }
};

const FzfSearch = struct {
    tokens: []const SearchToken,

    fn free(self: *const FzfSearch, gpa: std.mem.Allocator) void {
        gpa.free(self.tokens);
    }

    fn fromString(gpa: std.mem.Allocator, string: []const u8) !FzfSearch {
        std.debug.print("We are starting with string {s}<eof>\n", .{string});
        if (string.len == 0) {
            return .{ .tokens = &.{} };
        }

        var lastIndex: usize = 0;
        var tokenList = try std.ArrayList(SearchToken)
            .initCapacity(gpa, 5);

        for (string, 0..) |char, index| {
            if (char == ' ') {
                std.debug.print("We got string {s}<eof>\n", .{string[lastIndex..index]});
                try tokenList.append(gpa, SearchToken.fromString(string[lastIndex..index]));
                lastIndex = index + 1;
            }
        }

        // if there are still dangling chars after the last space, add them back
        if (lastIndex != string.len - 1) {
            try tokenList.append(gpa, SearchToken.fromString(string[lastIndex..]));
        }

        return FzfSearch{ .tokens = try tokenList.toOwnedSlice(gpa) };
    }
    fn matches(self: *const FzfSearch, input: []const u8) bool {
        for (self.tokens) |token| {
            if (token.matches(input) == false) {
                return false;
            }
        }
        return true;
    }
};

test "can create FzfSearch from empty string" {
    const gpa = std.testing.allocator;
    const search = try FzfSearch.fromString(gpa, "");
    try std.testing.expectEqualSlices(SearchToken, &.{}, search.tokens);
}
test "can create FzfSearch from simple string" {
    const gpa = std.testing.allocator;
    const search = try FzfSearch.fromString(gpa, "hello");
    defer search.free(gpa);
    const expected = &.{SearchToken{ .type = SearchTokenType.FUZZY, .searchChars = "hello" }};
    try std.testing.expectEqualSlices(SearchToken, expected, search.tokens);
}
test "can create FzfSearch from mutiple tokens" {
    const gpa = std.testing.allocator;
    const search = try FzfSearch.fromString(gpa, "hi jack");
    defer search.free(gpa);
    const expected = FzfSearch{ .tokens = &.{
        SearchToken{ .type = SearchTokenType.FUZZY, .searchChars = "hi" },
        SearchToken{ .type = SearchTokenType.FUZZY, .searchChars = "jack" },
    } };
    try std.testing.expectEqualDeep(expected, search);
}
test "if a fzf searchs token doesnt match the input false is returned" {
    const gpa = std.testing.allocator;
    const search = try FzfSearch.fromString(gpa, "appl pie");
    defer search.free(gpa);
    try std.testing.expect(search.matches("apple tart") == false);
    try std.testing.expect(search.matches("blueberry pie") == false);
}
test "if all fzf search tokens  match the input true is returned" {
    const gpa = std.testing.allocator;
    const search = try FzfSearch.fromString(gpa, "appl pie");
    defer search.free(gpa);
    try std.testing.expect(search.matches("apple pie, yum!"));
}

test "empty string is considered a FUZZY" {
    const token = SearchToken.fromString("");

    try std.testing.expectEqualStrings("", token.searchChars);
    try std.testing.expectEqual(SearchTokenType.FUZZY, token.type);
}

test "normal string returns a fuzzy token" {
    const token = SearchToken.fromString("baaaah");

    try std.testing.expectEqualStrings("baaaah", token.searchChars);
    try std.testing.expectEqual(SearchTokenType.FUZZY, token.type);
}
test "fuzzy match" {
    const token = SearchToken.fromString("hlo");
    try std.testing.expect(token.matches("Hello!"));
}
test "fuzzy match empty string" {
    const token = SearchToken.fromString("");
    try std.testing.expect(token.matches("Hello!"));
}

fn isLetter(char: u8) bool {
    return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z');
}

pub fn fuzzyMatches(value: []const u8, search: []const u8, caseSensitive: bool) bool {
    return matches(value, search, caseSensitive);
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
