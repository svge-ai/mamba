const std = @import("std");

/// Result of argument validation. Tagged union carrying diagnostic data
/// so the execute loop can format cobra-compatible error messages.
pub const ValidateResult = union(enum) {
    ok: void,
    wrong_count: struct { expected: usize, actual: usize },
    too_few: struct { min: usize, actual: usize },
    too_many: struct { max: usize, actual: usize },
    invalid_arg: struct { arg: []const u8 },
    unknown_command: struct { arg: []const u8 },
    range_error: struct { min: usize, max: usize, actual: usize },
};

/// Function pointer type for argument validators.
/// Takes valid_args (from the command) and the actual args to validate.
pub const ArgValidator = *const fn (valid_args: []const []const u8, a: []const []const u8) ValidateResult;

/// Accepts no arguments. If args are present, reports "unknown command".
pub fn noArgs(_: []const []const u8, a: []const []const u8) ValidateResult {
    if (a.len > 0) {
        return .{ .unknown_command = .{ .arg = a[0] } };
    }
    return .ok;
}

/// Accepts any arguments — always ok.
pub fn arbitraryArgs(_: []const []const u8, _: []const []const u8) ValidateResult {
    return .ok;
}

/// Accepts only arguments listed in valid_args.
pub fn onlyValidArgs(valid: []const []const u8, a: []const []const u8) ValidateResult {
    for (a) |arg| {
        var found = false;
        for (valid) |v| {
            if (std.mem.eql(u8, arg, v)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return .{ .invalid_arg = .{ .arg = arg } };
        }
    }
    return .ok;
}

/// Returns a validator that accepts exactly `n` args.
pub fn exactArgs(comptime n: usize) ArgValidator {
    return &struct {
        fn validate(_: []const []const u8, a: []const []const u8) ValidateResult {
            if (a.len != n) {
                return .{ .wrong_count = .{ .expected = n, .actual = a.len } };
            }
            return .ok;
        }
    }.validate;
}

/// Returns a validator that requires at least `n` args.
pub fn minimumNArgs(comptime n: usize) ArgValidator {
    return &struct {
        fn validate(_: []const []const u8, a: []const []const u8) ValidateResult {
            if (a.len < n) {
                return .{ .too_few = .{ .min = n, .actual = a.len } };
            }
            return .ok;
        }
    }.validate;
}

/// Returns a validator that accepts at most `n` args.
pub fn maximumNArgs(comptime n: usize) ArgValidator {
    return &struct {
        fn validate(_: []const []const u8, a: []const []const u8) ValidateResult {
            if (a.len > n) {
                return .{ .too_many = .{ .max = n, .actual = a.len } };
            }
            return .ok;
        }
    }.validate;
}

/// Returns a validator that accepts between `min` and `max` args (inclusive).
pub fn rangeArgs(comptime min: usize, comptime max: usize) ArgValidator {
    return &struct {
        fn validate(_: []const []const u8, a: []const []const u8) ValidateResult {
            if (a.len < min or a.len > max) {
                return .{ .range_error = .{ .min = min, .max = max, .actual = a.len } };
            }
            return .ok;
        }
    }.validate;
}

/// Returns a validator that runs all given validators in order,
/// returning the first non-ok result.
pub fn matchAll(comptime validators: []const ArgValidator) ArgValidator {
    return &struct {
        fn validate(valid: []const []const u8, a: []const []const u8) ValidateResult {
            inline for (validators) |v| {
                const result = v(valid, a);
                switch (result) {
                    .ok => {},
                    else => return result,
                }
            }
            return .ok;
        }
    }.validate;
}

/// Format a ValidateResult into a human-readable error message matching cobra's format.
/// Writes into the provided buffer and returns the slice.
pub fn formatError(result: ValidateResult, cmd_path: []const u8, buf: []u8) []const u8 {
    switch (result) {
        .ok => return "",
        .wrong_count => |v| {
            return std.fmt.bufPrint(buf, "accepts {d} arg(s), received {d}", .{ v.expected, v.actual }) catch "";
        },
        .too_few => |v| {
            return std.fmt.bufPrint(buf, "requires at least {d} arg(s), only received {d}", .{ v.min, v.actual }) catch "";
        },
        .too_many => |v| {
            return std.fmt.bufPrint(buf, "accepts at most {d} arg(s), received {d}", .{ v.max, v.actual }) catch "";
        },
        .range_error => |v| {
            return std.fmt.bufPrint(buf, "accepts between {d} and {d} arg(s), received {d}", .{ v.min, v.max, v.actual }) catch "";
        },
        .invalid_arg => |v| {
            return std.fmt.bufPrint(buf, "invalid argument \"{s}\" for \"{s}\"", .{ v.arg, cmd_path }) catch "";
        },
        .unknown_command => |v| {
            return std.fmt.bufPrint(buf, "unknown command \"{s}\" for \"{s}\"", .{ v.arg, cmd_path }) catch "";
        },
    }
}

// =============================================================================
// Unit tests — pure validator logic, no Command dependency
// =============================================================================

const testing = std.testing;

test "noArgs with no args" {
    const result = noArgs(&.{}, &.{});
    try testing.expect(result == .ok);
}

test "noArgs with args returns unknown_command" {
    const result = noArgs(&.{}, &.{"one"});
    switch (result) {
        .unknown_command => |v| try testing.expectEqualStrings("one", v.arg),
        else => return error.TestUnexpectedResult,
    }
}

test "arbitraryArgs always ok" {
    const result = arbitraryArgs(&.{}, &.{ "a", "b", "c" });
    try testing.expect(result == .ok);
}

test "onlyValidArgs with valid args" {
    const result = onlyValidArgs(&.{ "one", "two" }, &.{ "one", "two" });
    try testing.expect(result == .ok);
}

test "onlyValidArgs with invalid arg" {
    const result = onlyValidArgs(&.{ "one", "two" }, &.{"bad"});
    switch (result) {
        .invalid_arg => |v| try testing.expectEqualStrings("bad", v.arg),
        else => return error.TestUnexpectedResult,
    }
}

test "exactArgs with correct count" {
    const v = comptime exactArgs(2);
    const result = v(&.{}, &.{ "a", "b" });
    try testing.expect(result == .ok);
}

test "exactArgs with wrong count" {
    const v = comptime exactArgs(2);
    const result = v(&.{}, &.{ "a", "b", "c" });
    switch (result) {
        .wrong_count => |wc| {
            try testing.expectEqual(@as(usize, 2), wc.expected);
            try testing.expectEqual(@as(usize, 3), wc.actual);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "minimumNArgs satisfied" {
    const v = comptime minimumNArgs(2);
    const result = v(&.{}, &.{ "a", "b", "c" });
    try testing.expect(result == .ok);
}

test "minimumNArgs not satisfied" {
    const v = comptime minimumNArgs(2);
    const result = v(&.{}, &.{"a"});
    switch (result) {
        .too_few => |tf| {
            try testing.expectEqual(@as(usize, 2), tf.min);
            try testing.expectEqual(@as(usize, 1), tf.actual);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "maximumNArgs satisfied" {
    const v = comptime maximumNArgs(3);
    const result = v(&.{}, &.{ "a", "b" });
    try testing.expect(result == .ok);
}

test "maximumNArgs exceeded" {
    const v = comptime maximumNArgs(2);
    const result = v(&.{}, &.{ "a", "b", "c" });
    switch (result) {
        .too_many => |tm| {
            try testing.expectEqual(@as(usize, 2), tm.max);
            try testing.expectEqual(@as(usize, 3), tm.actual);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "rangeArgs within range" {
    const v = comptime rangeArgs(2, 4);
    const result = v(&.{}, &.{ "a", "b", "c" });
    try testing.expect(result == .ok);
}

test "rangeArgs below range" {
    const v = comptime rangeArgs(2, 4);
    const result = v(&.{}, &.{"a"});
    switch (result) {
        .range_error => |re| {
            try testing.expectEqual(@as(usize, 2), re.min);
            try testing.expectEqual(@as(usize, 4), re.max);
            try testing.expectEqual(@as(usize, 1), re.actual);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "matchAll runs all validators" {
    const v = comptime matchAll(&.{ &onlyValidArgs, exactArgs(2) });
    // Valid args and correct count
    const ok_result = v(&.{ "one", "two" }, &.{ "one", "two" });
    try testing.expect(ok_result == .ok);

    // Invalid arg — first validator fails
    const invalid_result = v(&.{ "one", "two" }, &.{ "one", "bad" });
    try testing.expect(invalid_result == .invalid_arg);
}

test "formatError wrong_count" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .wrong_count = .{ .expected = 2, .actual = 3 } };
    const msg = formatError(result, "root cmd", &buf);
    try testing.expectEqualStrings("accepts 2 arg(s), received 3", msg);
}

test "formatError too_few" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .too_few = .{ .min = 2, .actual = 1 } };
    const msg = formatError(result, "cmd", &buf);
    try testing.expectEqualStrings("requires at least 2 arg(s), only received 1", msg);
}

test "formatError too_many" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .too_many = .{ .max = 2, .actual = 3 } };
    const msg = formatError(result, "cmd", &buf);
    try testing.expectEqualStrings("accepts at most 2 arg(s), received 3", msg);
}

test "formatError range_error" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .range_error = .{ .min = 2, .max = 4, .actual = 1 } };
    const msg = formatError(result, "cmd", &buf);
    try testing.expectEqualStrings("accepts between 2 and 4 arg(s), received 1", msg);
}

test "formatError invalid_arg" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .invalid_arg = .{ .arg = "bad" } };
    const msg = formatError(result, "root cmd", &buf);
    try testing.expectEqualStrings("invalid argument \"bad\" for \"root cmd\"", msg);
}

test "formatError unknown_command" {
    var buf: [256]u8 = undefined;
    const result = ValidateResult{ .unknown_command = .{ .arg = "bad" } };
    const msg = formatError(result, "root", &buf);
    try testing.expectEqualStrings("unknown command \"bad\" for \"root\"", msg);
}
