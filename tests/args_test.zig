/// Integration tests ported from cobra/args_test.go.
/// This file imports both command and args, breaking the cycle
/// by being a leaf in the dependency graph.
const std = @import("std");
const testing = std.testing;
const mamba = @import("mamba");
const Command = mamba.Command;
const args = mamba.args;

fn emptyRun(_: *Command, _: []const []const u8) anyerror!void {}

fn getCommand(validator: args.ArgValidator, with_valid: bool) Command {
    var cmd = Command.init(.{
        .name = "c",
        .args = validator,
        .run = &emptyRun,
    });
    if (with_valid) {
        cmd.valid_args = &.{ "one", "two", "three" };
    }
    return cmd;
}

const ExecuteResult = struct {
    output: []const u8,
    err_output: []const u8,
    err: ?anyerror,
};

fn executeCommand(root: *Command, cmd_args: []const []const u8) ExecuteResult {
    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    root.setOut(&out_buf);
    root.setErr(&err_buf);

    root.executeWithArgs(cmd_args) catch |e| {
        return .{
            .output = out_buf[0..root.out_len],
            .err_output = err_buf[0..root.err_len],
            .err = e,
        };
    };
    return .{
        .output = out_buf[0..root.out_len],
        .err_output = err_buf[0..root.err_len],
        .err = null,
    };
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("Expected to contain: \"{s}\"\nGot: \"{s}\"\n", .{ needle, haystack });
        return error.TestExpectedContains;
    }
}

// -- NoArgs tests --

test "NoArgs" {
    var cmd = getCommand(&args.noArgs, false);
    const result = executeCommand(&cmd, &.{});
    try testing.expect(result.err == null);
}

test "NoArgs with args" {
    var cmd = getCommand(&args.noArgs, false);
    const result = executeCommand(&cmd, &.{"one"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"one\" for \"c\"");
}

test "NoArgs with valid with args" {
    var cmd = getCommand(&args.noArgs, true);
    const result = executeCommand(&cmd, &.{"one"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"one\" for \"c\"");
}

test "NoArgs with valid with invalid args" {
    var cmd = getCommand(&args.noArgs, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"a\" for \"c\"");
}

test "NoArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, &args.noArgs });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- OnlyValidArgs tests --

test "OnlyValidArgs" {
    var cmd = getCommand(&args.onlyValidArgs, true);
    const result = executeCommand(&cmd, &.{ "one", "two" });
    try testing.expect(result.err == null);
}

test "OnlyValidArgs with invalid args" {
    var cmd = getCommand(&args.onlyValidArgs, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- ArbitraryArgs tests --

test "ArbitraryArgs" {
    var cmd = getCommand(&args.arbitraryArgs, false);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err == null);
}

test "ArbitraryArgs with valid" {
    var cmd = getCommand(&args.arbitraryArgs, true);
    const result = executeCommand(&cmd, &.{ "one", "two" });
    try testing.expect(result.err == null);
}

test "ArbitraryArgs with valid with invalid args" {
    var cmd = getCommand(&args.arbitraryArgs, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err == null);
}

test "ArbitraryArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, &args.arbitraryArgs });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- MinimumNArgs tests --

test "MinimumNArgs" {
    var cmd = getCommand(comptime args.minimumNArgs(2), false);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err == null);
}

test "MinimumNArgs with valid" {
    var cmd = getCommand(comptime args.minimumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "one", "three" });
    try testing.expect(result.err == null);
}

test "MinimumNArgs with valid with invalid args" {
    var cmd = getCommand(comptime args.minimumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err == null);
}

test "MinimumNArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.minimumNArgs(2) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

test "MinimumNArgs with less args" {
    var cmd = getCommand(comptime args.minimumNArgs(2), false);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "requires at least 2 arg(s), only received 1");
}

test "MinimumNArgs with less args with valid" {
    var cmd = getCommand(comptime args.minimumNArgs(2), true);
    const result = executeCommand(&cmd, &.{"one"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "requires at least 2 arg(s), only received 1");
}

test "MinimumNArgs with less args with valid with invalid args" {
    var cmd = getCommand(comptime args.minimumNArgs(2), true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "requires at least 2 arg(s), only received 1");
}

test "MinimumNArgs with less args with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.minimumNArgs(2) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- MaximumNArgs tests --

test "MaximumNArgs" {
    var cmd = getCommand(comptime args.maximumNArgs(3), false);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err == null);
}

test "MaximumNArgs with valid" {
    var cmd = getCommand(comptime args.maximumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "one", "three" });
    try testing.expect(result.err == null);
}

test "MaximumNArgs with valid with invalid args" {
    var cmd = getCommand(comptime args.maximumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err == null);
}

test "MaximumNArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.maximumNArgs(2) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "a", "b" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

test "MaximumNArgs with more args" {
    var cmd = getCommand(comptime args.maximumNArgs(2), false);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts at most 2 arg(s), received 3");
}

test "MaximumNArgs with more args with valid" {
    var cmd = getCommand(comptime args.maximumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "one", "three", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts at most 2 arg(s), received 3");
}

test "MaximumNArgs with more args with valid with invalid args" {
    var cmd = getCommand(comptime args.maximumNArgs(2), true);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts at most 2 arg(s), received 3");
}

test "MaximumNArgs with more args with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.maximumNArgs(2) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- ExactArgs tests --

test "ExactArgs" {
    var cmd = getCommand(comptime args.exactArgs(3), false);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err == null);
}

test "ExactArgs with valid" {
    var cmd = getCommand(comptime args.exactArgs(3), true);
    const result = executeCommand(&cmd, &.{ "three", "one", "two" });
    try testing.expect(result.err == null);
}

test "ExactArgs with valid with invalid args" {
    var cmd = getCommand(comptime args.exactArgs(3), true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err == null);
}

test "ExactArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.exactArgs(3) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

test "ExactArgs with invalid count" {
    var cmd = getCommand(comptime args.exactArgs(2), false);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts 2 arg(s), received 3");
}

test "ExactArgs with invalid count with valid" {
    var cmd = getCommand(comptime args.exactArgs(2), true);
    const result = executeCommand(&cmd, &.{ "three", "one", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts 2 arg(s), received 3");
}

test "ExactArgs with invalid count with valid with invalid args" {
    var cmd = getCommand(comptime args.exactArgs(2), true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts 2 arg(s), received 3");
}

test "ExactArgs with invalid count with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.exactArgs(2) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- RangeArgs tests --

test "RangeArgs" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), false);
    const result = executeCommand(&cmd, &.{ "a", "b", "c" });
    try testing.expect(result.err == null);
}

test "RangeArgs with valid" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), true);
    const result = executeCommand(&cmd, &.{ "three", "one", "two" });
    try testing.expect(result.err == null);
}

test "RangeArgs with valid with invalid args" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err == null);
}

test "RangeArgs with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.rangeArgs(2, 4) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{ "three", "a", "two" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

test "RangeArgs with invalid count" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), false);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts between 2 and 4 arg(s), received 1");
}

test "RangeArgs with invalid count with valid" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), true);
    const result = executeCommand(&cmd, &.{"two"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts between 2 and 4 arg(s), received 1");
}

test "RangeArgs with invalid count with valid with invalid args" {
    var cmd = getCommand(comptime args.rangeArgs(2, 4), true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "accepts between 2 and 4 arg(s), received 1");
}

test "RangeArgs with invalid count with validOnly with invalid args" {
    const v = comptime args.matchAll(&.{ &args.onlyValidArgs, args.rangeArgs(2, 4) });
    var cmd = getCommand(v, true);
    const result = executeCommand(&cmd, &.{"a"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "invalid argument \"a\" for \"c\"");
}

// -- Root/Child takes args tests --

test "RootTakesNoArgs" {
    var root_cmd = Command.init(.{ .name = "root", .run = &emptyRun });
    var child_cmd = Command.init(.{ .name = "child", .run = &emptyRun });
    root_cmd.addCommand(&child_cmd);

    const result = executeCommand(&root_cmd, &.{ "illegal", "args" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"illegal\" for \"root\"");
}

test "RootTakesArgs" {
    var root_cmd = Command.init(.{ .name = "root", .args = &args.arbitraryArgs, .run = &emptyRun });
    var child_cmd = Command.init(.{ .name = "child", .run = &emptyRun });
    root_cmd.addCommand(&child_cmd);

    const result = executeCommand(&root_cmd, &.{ "legal", "args" });
    try testing.expect(result.err == null);
}

test "ChildTakesNoArgs" {
    var root_cmd = Command.init(.{ .name = "root", .run = &emptyRun });
    var child_cmd = Command.init(.{ .name = "child", .args = &args.noArgs, .run = &emptyRun });
    root_cmd.addCommand(&child_cmd);

    const result = executeCommand(&root_cmd, &.{ "child", "illegal", "args" });
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"illegal\" for \"root child\"");
}

test "ChildTakesArgs" {
    var root_cmd = Command.init(.{ .name = "root", .run = &emptyRun });
    var child_cmd = Command.init(.{ .name = "child", .args = &args.arbitraryArgs, .run = &emptyRun });
    root_cmd.addCommand(&child_cmd);

    const result = executeCommand(&root_cmd, &.{ "child", "legal", "args" });
    try testing.expect(result.err == null);
}

// -- Legacy args tests --

test "LegacyArgsRootAcceptsArgs" {
    var root_cmd = Command.init(.{ .name = "root", .run = &emptyRun });
    const result = executeCommand(&root_cmd, &.{"somearg"});
    try testing.expect(result.err == null);
}

test "LegacyArgsSubcmdAcceptsArgs" {
    var root_cmd = Command.init(.{ .name = "root", .run = &emptyRun });
    var child_cmd = Command.init(.{ .name = "child", .run = &emptyRun });
    var grandchild_cmd = Command.init(.{ .name = "grandchild", .run = &emptyRun });
    child_cmd.addCommand(&grandchild_cmd);
    root_cmd.addCommand(&child_cmd);

    const result = executeCommand(&root_cmd, &.{ "child", "somearg" });
    try testing.expect(result.err == null);
}
