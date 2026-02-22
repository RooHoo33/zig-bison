const std = @import("std");

const SearchTokenType = enum { FUZZY, EXACT, EXACT_WORD, START, END };
const SearchToken = struct {
    type: SearchTokenType,
    searchChars: []const u8,

    fn fromString(string: []const u8) SearchToken {
        if (string.len == 0) {
            return .{ .type = SearchTokenType.FUZZY, .searchChars = "" };
        }
        if (string[0] == '\'' and string.len > 1 and string[string.len - 1] == '\'') {
            return .{ .type = SearchTokenType.EXACT_WORD, .searchChars = string[1 .. string.len - 1] };
        } else if (string[0] == '\'') {
            return .{ .type = SearchTokenType.EXACT, .searchChars = string[1..] };
        } else if (string[0] == '^') {
            return .{ .type = SearchTokenType.START, .searchChars = string[1..] };
        } else if (string[0] == '$') {
            return .{ .type = SearchTokenType.END, .searchChars = string[1..] };
        } else {
            return .{ .type = SearchTokenType.FUZZY, .searchChars = string[0..] };
        }
    }

    fn matches(self: *const SearchToken, input: []const u8) bool {
        switch (self.type) {
            .FUZZY => return matchesExactWord(input, self.searchChars, false, false, false),
            .EXACT => return matchesExactWord(input, self.searchChars, true, false, false),
            .EXACT_WORD => return matchesExactWord(input, self.searchChars, true, true, true),
            .START => return matchesExactWord(input, self.searchChars, true, true, false),
            .END => return matchesExactWord(input, self.searchChars, true, false, true),
        }
    }

    fn toLowerCase(char: u8) u8 {
        if (char > 'Z') {
            return char - 32;
        } else {
            return char;
        }
    }

    fn matchesExactWord(input: []const u8, searchChars: []const u8, exact: bool, startWord: bool, endWord: bool) bool {
        outer: for (input, 0..) |_, inputIndex| {
            var searchIndex: usize = 0;
            if (startWord and inputIndex != 0 and input[inputIndex - 1] != ' ') {
                continue :outer;
            }
            for (input[inputIndex..], inputIndex..) |innerInputLoop, innerLoopIndex| {
                if (searchIndex == searchChars.len) {
                    return true;
                } else if (toLowerCase(innerInputLoop) == toLowerCase(searchChars[searchIndex])) {
                    searchIndex += 1;
                    if (searchIndex == searchChars.len) {
                        if (endWord == false or (innerLoopIndex == input.len - 1 or input[innerLoopIndex + 1] == ' ')) {
                            return true;
                        } else {
                            continue :outer;
                        }
                    }
                } else if (exact) {
                    continue :outer;
                }
            }
        }
        return false;
    }
};

pub const FzfSearch = struct {
    tokens: []const SearchToken,

    pub fn free(self: *const FzfSearch, gpa: std.mem.Allocator) void {
        gpa.free(self.tokens);
    }

    pub fn fromString(gpa: std.mem.Allocator, string: []const u8) !FzfSearch {
        if (string.len == 0) {
            return .{ .tokens = &.{} };
        }

        var lastIndex: usize = 0;
        var tokenList = try std.ArrayList(SearchToken)
            .initCapacity(gpa, 5);

        for (string, 0..) |char, index| {
            if (char == ' ') {
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
    pub fn matches(self: *const FzfSearch, input: []const u8) bool {
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

fn testTokenization(tokenString: []const u8, tokenType: SearchTokenType, resultToken: []const u8) !void {
    const token = SearchToken.fromString(tokenString);

    try std.testing.expectEqualStrings(resultToken, token.searchChars);
    try std.testing.expectEqual(tokenType, token.type);
}
fn testMatch(tokenString: []const u8, input: []const u8) !void {
    const token = SearchToken.fromString(tokenString);
    try std.testing.expect(token.matches(input));
}
fn testNotMatch(tokenString: []const u8, input: []const u8) !void {
    const token = SearchToken.fromString(tokenString);
    try std.testing.expect(!token.matches(input));
}
test "fuzzy match empty string" {
    const token = SearchToken.fromString("");
    try std.testing.expect(token.matches("Hello!"));
}

test "starting quote is considered exact match" {
    try testTokenization("'ell", SearchTokenType.EXACT, "ell");
}

test "if just a quote, its an exact match with no string" {
    try testTokenization("'", SearchTokenType.EXACT, "");
}

test "exact match matches in order" {
    try testMatch("'ell", "helo helelello");
    try testMatch("'ello", "hello");
}
test "exact match matches if just quote" {
    try testMatch("'", "hello");
}

test "doesnt match if a char is missing in the middle of the token" {
    try testNotMatch("'eel", "hello");
}

test "starting and ending quote is considered exact word match" {
    try testTokenization("'ell'", SearchTokenType.EXACT_WORD, "ell");
}

test "exact match matches if word is bordered by spaces or matches exactly" {
    try testMatch("'Hello'", "hey hello");
    try testMatch("'hello'", "a hello a");
    try testMatch("'hello'", "hello how are you");
}
test "exact match matches if just double quotes" {
    try testMatch("''", "hello");
}

test "doesnt match if a theres an extra char in the match thats not a space" {
    try testNotMatch("'bc'", " abcd ");
    try testNotMatch("'bc'", " abc ");
    try testNotMatch("'bc'", " bcd ");
}

test "matches start word" {
    try testMatch("^hel", "hey hello");
    try testMatch("^hEllo", "hey hello");
    try testMatch("^hello", "hello");
    try testMatch("^hello", "hello how are you?");
}
test "doesnt matches start word" {
    try testNotMatch("^hel", "hey hallo");
    try testNotMatch("^eLlo", "hello");
}

test "matches end word" {
    try testMatch("$eLlo", "hey hello");
    try testMatch("$hello", "hey hello hi");
    try testMatch("$hello", "hello");
    try testMatch("$hello", "hello how are you?");
}
test "doesnt matches end word" {
    try testNotMatch("$hello", "hey hallo");
    try testNotMatch("$hel", "hello");
}
