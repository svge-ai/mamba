const std = @import("std");
const args_mod = @import("args.zig");
const flags_mod = @import("flags.zig");
const help_mod = @import("help.zig");

pub const ValidateResult = args_mod.ValidateResult;
pub const ArgValidator = args_mod.ArgValidator;
pub const FlagDef = flags_mod.FlagDef;
pub const FlagValue = flags_mod.FlagValue;
pub const FlagKind = flags_mod.FlagKind;
pub const Flag = flags_mod.Flag;

/// Run function signature: receives the command and positional args.
pub const RunFn = *const fn (cmd: *Command, a: []const []const u8) anyerror!void;

/// Options for initializing a Command.
pub const CommandOpts = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    short: []const u8 = "",
    long: []const u8 = "",
    version: []const u8 = "",
    example: []const u8 = "",

    args: ?ArgValidator = null,
    valid_args: []const []const u8 = &.{},
    run: ?RunFn = null,
    pre_run: ?RunFn = null,
    post_run: ?RunFn = null,
    persistent_pre_run: ?RunFn = null,
    persistent_post_run: ?RunFn = null,

    flags: []const FlagDef = &.{},
    persistent_flags: []const FlagDef = &.{},
};

pub const Command = struct {
    // Identity
    name: []const u8,
    aliases: []const []const u8 = &.{},
    short: []const u8 = "",
    long: []const u8 = "",
    version: []const u8 = "",
    example: []const u8 = "",

    // Behavior
    args: ?ArgValidator = null,
    valid_args: []const []const u8 = &.{},
    run: ?RunFn = null,
    pre_run: ?RunFn = null,
    post_run: ?RunFn = null,
    persistent_pre_run: ?RunFn = null,
    persistent_post_run: ?RunFn = null,

    // Flags
    flags: []const FlagDef = &.{},
    persistent_flags: []const FlagDef = &.{},

    // Tree (mutable at runtime)
    parent: ?*Command = null,
    children: [MAX_CHILDREN]*Command = undefined,
    children_count: usize = 0,

    // State (populated during execute)
    parsed_flags: [MAX_FLAGS]FlagValue = undefined,
    parsed_flags_count: usize = 0,
    parsed_args: []const []const u8 = &.{},

    // IO (overridable for testing)
    out_buffer: ?[]u8 = null,
    out_len: usize = 0,
    err_buffer: ?[]u8 = null,
    err_len: usize = 0,

    // Constants
    pub const MAX_CHILDREN = 32;
    pub const MAX_FLAGS = 64;
    const MAX_ALL_FLAGS = 128;
    pub const PATH_BUF_SIZE = 256;

    /// Initialize a Command from CommandOpts.
    pub fn init(opts: CommandOpts) Command {
        return .{
            .name = opts.name,
            .aliases = opts.aliases,
            .short = opts.short,
            .long = opts.long,
            .version = opts.version,
            .example = opts.example,
            .args = opts.args,
            .valid_args = opts.valid_args,
            .run = opts.run,
            .pre_run = opts.pre_run,
            .post_run = opts.post_run,
            .persistent_pre_run = opts.persistent_pre_run,
            .persistent_post_run = opts.persistent_post_run,
            .flags = opts.flags,
            .persistent_flags = opts.persistent_flags,
        };
    }

    /// Add a child command, linking parent.
    pub fn addCommand(self: *Command, child: *Command) void {
        if (self.children_count >= MAX_CHILDREN) {
            @panic("mamba: too many child commands (MAX_CHILDREN exceeded)");
        }
        child.parent = self;
        self.children[self.children_count] = child;
        self.children_count += 1;
    }

    /// Print the help text for this command to its output.
    pub fn help(self: *Command) void {
        help_mod.writeHelp(self);
    }

    /// Execute using OS args (skipping argv[0]).
    /// Shows help if no arguments are provided (matches cobra behavior).
    pub fn execute(self: *Command) !void {
        const argv = std.os.argv;
        if (argv.len <= 1) {
            // No args: show help (like cobra)
            help_mod.writeHelp(self);
            return;
        }
        var args_buf: [128][]const u8 = undefined;
        const n = @min(argv.len - 1, args_buf.len);
        for (0..n) |i| {
            args_buf[i] = std.mem.sliceTo(argv[i + 1], 0);
        }
        try self.executeWithArgs(args_buf[0..n]);
    }

    /// Execute with the given args (for testing / programmatic use).
    pub fn executeWithArgs(self: *Command, exec_args: []const []const u8) !void {
        // 1. Walk command tree to find target, skipping flags so that
        //    persistent flags before subcommand names don't break traversal.
        //    Cobra does the same thing in Command.Traverse().
        var target: *Command = self;

        // Collect non-subcommand args (flags + positional) for the target.
        var remaining_buf: [256][]const u8 = undefined;
        var remaining_count: usize = 0;

        var i: usize = 0;
        while (i < exec_args.len) {
            const arg = exec_args[i];

            if (arg.len > 0 and arg[0] == '-') {
                // This is a flag — keep it in remaining for later parsing.
                if (remaining_count < remaining_buf.len) {
                    remaining_buf[remaining_count] = arg;
                    remaining_count += 1;
                }
                // If it's a non-boolean flag that expects a value in the next arg,
                // carry that value along too. We need flag defs to know this.
                if (!isBooleanOrSelfContainedFlag(target, arg)) {
                    i += 1;
                    if (i < exec_args.len) {
                        if (remaining_count < remaining_buf.len) {
                            remaining_buf[remaining_count] = exec_args[i];
                            remaining_count += 1;
                        }
                    }
                }
            } else if (target.findChild(arg)) |child| {
                target = child;
            } else {
                // Positional arg or unrecognized — keep in remaining.
                if (remaining_count < remaining_buf.len) {
                    remaining_buf[remaining_count] = arg;
                    remaining_count += 1;
                }
            }

            i += 1;
        }

        const remaining = remaining_buf[0..remaining_count];

        // 2. Handle help subcommand: "cmd help [target...]"
        if (remaining.len > 0 and std.mem.eql(u8, remaining[0], "help")) {
            var help_target: *Command = target;
            for (remaining[1..]) |arg| {
                if (help_target.findChild(arg)) |child| {
                    help_target = child;
                } else {
                    break;
                }
            }
            help_mod.writeHelp(help_target);
            return;
        }

        // 3. Handle --help / -h anywhere in remaining args
        for (remaining) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                help_mod.writeHelp(target);
                return;
            }
        }

        // 4. Handle --version if the target command has a version set
        if (target.version.len > 0) {
            for (remaining) |arg| {
                if (std.mem.eql(u8, arg, "--version")) {
                    var path_buf: [PATH_BUF_SIZE]u8 = undefined;
                    const cmd_path = target.commandPathBuf(&path_buf);
                    target.writeOut(cmd_path);
                    target.writeOut(" version ");
                    target.writeOut(target.version);
                    target.writeOut("\n");
                    return;
                }
            }
        }

        // 5. Parse flags from remaining args
        const all_defs = target.collectAllFlags();
        const parse_result = flags_mod.parseFlags(remaining, all_defs.defs[0..all_defs.count]) catch |e| {
            switch (e) {
                flags_mod.FlagError.UnknownFlag => {
                    target.writeErr("Error: unknown flag\n");
                    return error.FlagParseError;
                },
                flags_mod.FlagError.MissingFlagValue => {
                    target.writeErr("Error: missing flag value\n");
                    return error.FlagParseError;
                },
                flags_mod.FlagError.InvalidFlagValue => {
                    target.writeErr("Error: invalid flag value\n");
                    return error.FlagParseError;
                },
            }
        };

        // Store parsed flags on target
        const flag_vals = parse_result.flagValues();
        for (flag_vals, 0..) |fv, fi| {
            target.parsed_flags[fi] = fv;
        }
        target.parsed_flags_count = flag_vals.len;

        const positional = parse_result.positionalArgs();
        target.parsed_args = positional;

        // 3. Validate positional args
        if (target.args) |validator| {
            const result = validator(target.valid_args, positional);
            switch (result) {
                .ok => {},
                else => {
                    var path_buf: [PATH_BUF_SIZE]u8 = undefined;
                    const cmd_path = target.commandPathBuf(&path_buf);
                    var err_msg_buf: [512]u8 = undefined;
                    const err_msg = args_mod.formatError(result, cmd_path, &err_msg_buf);

                    target.writeErr("Error: ");
                    target.writeErr(err_msg);
                    target.writeErr("\n");

                    return error.ArgValidationFailed;
                },
            }
        } else {
            // Legacy behavior (matches cobra's legacyArgs):
            // - If command has no children: accept arbitrary args
            // - If root command (no parent) has children: reject unknown args
            // - If non-root command (has parent) has children: accept arbitrary args
            if (target.children_count > 0 and positional.len > 0 and target.parent == null) {
                var path_buf: [PATH_BUF_SIZE]u8 = undefined;
                const cmd_path = target.commandPathBuf(&path_buf);
                var err_msg_buf: [512]u8 = undefined;
                const err_msg = std.fmt.bufPrint(&err_msg_buf, "unknown command \"{s}\" for \"{s}\"", .{ positional[0], cmd_path }) catch "";

                target.writeErr("Error: ");
                target.writeErr(err_msg);
                target.writeErr("\n");

                // Also write usage hint
                var hint_buf: [256]u8 = undefined;
                const hint = std.fmt.bufPrint(&hint_buf, "Run '{s} --help' for usage.\n", .{cmd_path}) catch "";
                target.writeOut(hint);

                return error.ArgValidationFailed;
            }
        }

        // Show help for non-runnable commands (matches cobra)
        if (target.run == null) {
            help_mod.writeHelp(target);
            return;
        }

        // Run hook chain
        // persistent_pre_run: walk up parent chain, find first one
        if (target.findPersistentPreRun()) |hook| {
            try hook(target, positional);
        }

        // pre_run
        if (target.pre_run) |hook| {
            try hook(target, positional);
        }

        // run
        if (target.run) |run_fn| {
            try run_fn(target, positional);
        }

        // post_run
        if (target.post_run) |hook| {
            try hook(target, positional);
        }

        // persistent_post_run: walk up parent chain, find first one
        if (target.findPersistentPostRun()) |hook| {
            try hook(target, positional);
        }
    }

    /// Retrieve a typed flag value by name.
    /// Falls back to the default from the flag definition.
    /// Panics if the flag name is not found (programming error).
    pub fn getFlag(self: *const Command, comptime T: type, name: []const u8) T {
        // Check parsed flags first
        for (self.parsed_flags[0..self.parsed_flags_count]) |fv| {
            if (std.mem.eql(u8, fv.name, name)) {
                return convertFlag(T, fv.raw, fv.kind);
            }
        }

        // Fall back to default from flag definition
        for (self.flags) |def| {
            if (std.mem.eql(u8, def.name, name)) {
                return convertFlag(T, def.default_raw, def.kind);
            }
        }

        // Check persistent flags up the parent chain
        var current: ?*const Command = self;
        while (current) |cmd| {
            for (cmd.persistent_flags) |def| {
                if (std.mem.eql(u8, def.name, name)) {
                    return convertFlag(T, def.default_raw, def.kind);
                }
            }
            current = if (cmd.parent) |p| @as(*const Command, p) else null;
        }

        @panic("mamba: unknown flag name");
    }

    /// Returns the full command path (e.g., "root child grandchild").
    /// Uses a static buffer — not reentrant-safe, but fine for CLI use.
    pub fn commandPath(self: *const Command) []const u8 {
        const S = struct {
            var buf: [PATH_BUF_SIZE]u8 = undefined;
        };
        return self.commandPathBuf(&S.buf);
    }

    /// Returns the full command path into the provided buffer.
    pub fn commandPathBuf(self: *const Command, buf: []u8) []const u8 {
        // Build path by walking up to root, then reversing
        var parts: [32][]const u8 = undefined;
        var count: usize = 0;
        var current: ?*const Command = self;

        while (current) |cmd| {
            if (count < 32) {
                parts[count] = cmd.name;
                count += 1;
            }
            current = if (cmd.parent) |p| @as(*const Command, p) else null;
        }

        // Reverse and join with spaces
        var pos: usize = 0;
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            if (pos > 0 and pos < buf.len) {
                buf[pos] = ' ';
                pos += 1;
            }
            const part = parts[i];
            const copy_len = @min(part.len, buf.len - pos);
            @memcpy(buf[pos..][0..copy_len], part[0..copy_len]);
            pos += copy_len;
        }

        return buf[0..pos];
    }

    // -- IO --

    /// Set the output buffer for capturing stdout-like output.
    pub fn setOut(self: *Command, buf: []u8) void {
        self.out_buffer = buf;
        self.out_len = 0;
    }

    /// Set the error buffer for capturing stderr-like output.
    pub fn setErr(self: *Command, buf: []u8) void {
        self.err_buffer = buf;
        self.err_len = 0;
    }

    /// Write to the output buffer (or stdout if no buffer set).
    pub fn writeOut(self: *Command, msg: []const u8) void {
        // Walk up to root to find the output buffer
        var target: *Command = self;
        while (target.out_buffer == null) {
            if (target.parent) |p| {
                target = p;
            } else {
                break;
            }
        }
        if (target.out_buffer) |buf| {
            const copy_len = @min(msg.len, buf.len - target.out_len);
            @memcpy(buf[target.out_len..][0..copy_len], msg[0..copy_len]);
            target.out_len += copy_len;
        } else {
            const stdout = std.fs.File.stdout();
            stdout.writeAll(msg) catch {};
        }
    }

    /// Write to the error buffer (or stderr if no buffer set).
    pub fn writeErr(self: *Command, msg: []const u8) void {
        // Walk up to root to find the error buffer
        var target: *Command = self;
        while (target.err_buffer == null) {
            if (target.parent) |p| {
                target = p;
            } else {
                break;
            }
        }
        if (target.err_buffer) |buf| {
            const copy_len = @min(msg.len, buf.len - target.err_len);
            @memcpy(buf[target.err_len..][0..copy_len], msg[0..copy_len]);
            target.err_len += copy_len;
        } else {
            const stderr = std.fs.File.stderr();
            stderr.writeAll(msg) catch {};
        }
    }

    // -- Internal helpers --

    /// Find a child command by name or alias.
    fn findChild(self: *Command, name: []const u8) ?*Command {
        for (self.children[0..self.children_count]) |child| {
            if (std.mem.eql(u8, child.name, name)) {
                return child;
            }
            for (child.aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    return child;
                }
            }
        }
        return null;
    }

    /// Walk up parent chain to find the first persistent_pre_run.
    fn findPersistentPreRun(self: *Command) ?RunFn {
        var current: ?*Command = self;
        while (current) |cmd| {
            if (cmd.persistent_pre_run) |hook| {
                return hook;
            }
            current = cmd.parent;
        }
        return null;
    }

    /// Walk up parent chain to find the first persistent_post_run.
    fn findPersistentPostRun(self: *Command) ?RunFn {
        var current: ?*Command = self;
        while (current) |cmd| {
            if (cmd.persistent_post_run) |hook| {
                return hook;
            }
            current = cmd.parent;
        }
        return null;
    }

    /// Determine whether a flag argument is "self-contained" — i.e. it does
    /// NOT consume the next argument as its value. Returns true for:
    ///   - Boolean flags (--verbose, -v)
    ///   - Flags using = syntax (--output=foo, -o=foo)
    ///   - Negated booleans (--no-verbose)
    /// Returns false for non-boolean flags in space-separated form (--output foo).
    fn isBooleanOrSelfContainedFlag(cmd: *Command, arg: []const u8) bool {
        if (arg.len >= 2 and arg[0] == '-' and arg[1] == '-') {
            const rest = arg[2..];
            // --name=value is self-contained
            if (std.mem.indexOf(u8, rest, "=") != null) return true;
            // --no-name is self-contained (negated boolean)
            if (rest.len > 3 and std.mem.startsWith(u8, rest, "no-")) {
                return true;
            }
            // Look up flag definition to check if boolean
            const all = cmd.collectAllFlags();
            for (all.defs[0..all.count]) |def| {
                if (std.mem.eql(u8, def.name, rest)) {
                    return def.kind == .boolean;
                }
            }
            // Unknown flag — assume it takes a value (conservative)
            return false;
        } else if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
            // Short flag
            if (arg.len > 2) {
                // -o=value or -ovalue — self-contained
                return true;
            }
            // -o (len == 2) — look up if boolean
            const short_char = arg[1];
            const all = cmd.collectAllFlags();
            for (all.defs[0..all.count]) |def| {
                if (def.short) |s| {
                    if (s == short_char) {
                        return def.kind == .boolean;
                    }
                }
            }
            return false;
        }
        return true;
    }

    /// Collect all flag definitions: local flags + persistent flags from parent chain.
    const CollectedFlags = struct {
        defs: [MAX_ALL_FLAGS]FlagDef,
        count: usize,
    };

    fn collectAllFlags(self: *Command) CollectedFlags {
        var collected: CollectedFlags = .{
            .defs = undefined,
            .count = 0,
        };

        // Local flags
        for (self.flags) |def| {
            if (collected.count < MAX_ALL_FLAGS) {
                collected.defs[collected.count] = def;
                collected.count += 1;
            }
        }

        // Walk up parent chain for persistent flags
        var current: ?*Command = self;
        while (current) |cmd| {
            for (cmd.persistent_flags) |def| {
                if (collected.count < MAX_ALL_FLAGS) {
                    collected.defs[collected.count] = def;
                    collected.count += 1;
                }
            }
            current = cmd.parent;
        }

        return collected;
    }

    /// Convert a raw flag string to a typed value.
    fn convertFlag(comptime T: type, raw: []const u8, kind: FlagKind) T {
        _ = kind;
        if (T == []const u8) {
            return raw;
        } else if (T == bool) {
            return std.mem.eql(u8, raw, "true");
        } else if (T == i64) {
            return std.fmt.parseInt(i64, raw, 10) catch 0;
        } else if (T == f64) {
            return std.fmt.parseFloat(f64, raw) catch 0.0;
        } else {
            @compileError("mamba: unsupported flag type");
        }
    }
};

// =============================================================================
// Tests — command behavior ported from cobra/command_test.go
// =============================================================================

const testing = std.testing;

fn emptyRun(_: *Command, _: []const []const u8) anyerror!void {}

const ExecuteResult = struct {
    output: []const u8,
    err_output: []const u8,
    err: ?anyerror,
};

fn executeCommandTest(root: *Command, cmd_args: []const []const u8) ExecuteResult {
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

test "single command" {
    var root = Command.init(.{
        .name = "root",
        .args = args_mod.exactArgs(2),
        .run = &emptyRun,
    });
    var child_a = Command.init(.{ .name = "a", .args = &args_mod.noArgs, .run = &emptyRun });
    var child_b = Command.init(.{ .name = "b", .args = &args_mod.noArgs, .run = &emptyRun });
    root.addCommand(&child_a);
    root.addCommand(&child_b);

    const result = executeCommandTest(&root, &.{ "one", "two" });
    try testing.expect(result.err == null);
}

test "child command" {
    var root = Command.init(.{ .name = "root", .args = &args_mod.noArgs, .run = &emptyRun });
    var child1 = Command.init(.{
        .name = "child1",
        .args = args_mod.exactArgs(2),
        .run = &emptyRun,
    });
    var child2 = Command.init(.{ .name = "child2", .args = &args_mod.noArgs, .run = &emptyRun });
    root.addCommand(&child1);
    root.addCommand(&child2);

    const result = executeCommandTest(&root, &.{ "child1", "one", "two" });
    try testing.expect(result.err == null);
}

test "call command without subcommands" {
    var root = Command.init(.{ .name = "root", .args = &args_mod.noArgs, .run = &emptyRun });
    const result = executeCommandTest(&root, &.{});
    try testing.expect(result.err == null);
}

test "root execute unknown command" {
    var root = Command.init(.{ .name = "root", .run = &emptyRun });
    var child = Command.init(.{ .name = "child", .run = &emptyRun });
    root.addCommand(&child);

    const result = executeCommandTest(&root, &.{"unknown"});
    try testing.expect(result.err != null);
    try expectContains(result.err_output, "unknown command \"unknown\" for \"root\"");
}

test "command alias" {
    var root = Command.init(.{ .name = "root", .args = &args_mod.noArgs, .run = &emptyRun });
    var echo_cmd = Command.init(.{
        .name = "echo",
        .aliases = &.{ "say", "tell" },
        .args = &args_mod.noArgs,
        .run = &emptyRun,
    });
    var times_cmd = Command.init(.{
        .name = "times",
        .args = args_mod.exactArgs(2),
        .run = &emptyRun,
    });
    echo_cmd.addCommand(&times_cmd);
    root.addCommand(&echo_cmd);

    const result = executeCommandTest(&root, &.{ "tell", "times", "one", "two" });
    try testing.expect(result.err == null);
}

test "child same name" {
    var root = Command.init(.{ .name = "foo", .args = &args_mod.noArgs, .run = &emptyRun });
    var foo_cmd = Command.init(.{
        .name = "foo",
        .args = args_mod.exactArgs(2),
        .run = &emptyRun,
    });
    var bar_cmd = Command.init(.{ .name = "bar", .args = &args_mod.noArgs, .run = &emptyRun });
    root.addCommand(&foo_cmd);
    root.addCommand(&bar_cmd);

    const result = executeCommandTest(&root, &.{ "foo", "one", "two" });
    try testing.expect(result.err == null);
}

test "grandchild same name" {
    var root = Command.init(.{ .name = "foo", .args = &args_mod.noArgs, .run = &emptyRun });
    var bar_cmd = Command.init(.{ .name = "bar", .args = &args_mod.noArgs, .run = &emptyRun });
    var foo_cmd = Command.init(.{
        .name = "foo",
        .args = args_mod.exactArgs(2),
        .run = &emptyRun,
    });
    bar_cmd.addCommand(&foo_cmd);
    root.addCommand(&bar_cmd);

    const result = executeCommandTest(&root, &.{ "bar", "foo", "one", "two" });
    try testing.expect(result.err == null);
}

test "commandPath" {
    var root = Command.init(.{ .name = "root" });
    var child = Command.init(.{ .name = "child" });
    var grandchild = Command.init(.{ .name = "grandchild" });
    child.addCommand(&grandchild);
    root.addCommand(&child);

    try testing.expectEqualStrings("root", root.commandPath());
    try testing.expectEqualStrings("root child", child.commandPath());
    try testing.expectEqualStrings("root child grandchild", grandchild.commandPath());
}

test "setOut and writeOut" {
    var cmd = Command.init(.{ .name = "test" });
    var buf: [256]u8 = undefined;
    cmd.setOut(&buf);
    cmd.writeOut("hello ");
    cmd.writeOut("world");
    try testing.expectEqualStrings("hello world", buf[0..cmd.out_len]);
}

test "setErr and writeErr" {
    var cmd = Command.init(.{ .name = "test" });
    var buf: [256]u8 = undefined;
    cmd.setErr(&buf);
    cmd.writeErr("error msg");
    try testing.expectEqualStrings("error msg", buf[0..cmd.err_len]);
}

test "getFlag string" {
    var cmd = Command.init(.{
        .name = "test",
        .flags = &.{
            Flag.string("output", 'o', "Output file", "default.gem"),
        },
        .run = &emptyRun,
    });
    try testing.expectEqualStrings("default.gem", cmd.getFlag([]const u8, "output"));
}

test "getFlag boolean" {
    var cmd = Command.init(.{
        .name = "test",
        .flags = &.{
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });
    try testing.expect(!cmd.getFlag(bool, "verbose"));
}

test "flag parsing integration" {
    var cmd = Command.init(.{
        .name = "build",
        .flags = &.{
            Flag.string("output", 'o', "Output file", "out.gem"),
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });
    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    cmd.setOut(&out_buf);
    cmd.setErr(&err_buf);

    try cmd.executeWithArgs(&.{ "--output", "foo.gem", "--verbose" });
    try testing.expectEqualStrings("foo.gem", cmd.getFlag([]const u8, "output"));
    try testing.expect(cmd.getFlag(bool, "verbose"));
}

test "hook execution order" {
    const State = struct {
        var order: [10]u8 = undefined;
        var count: usize = 0;

        fn reset() void {
            count = 0;
        }
        fn record(c: u8) void {
            if (count < 10) {
                order[count] = c;
                count += 1;
            }
        }
        fn getOrder() []const u8 {
            return order[0..count];
        }
    };

    State.reset();

    const persistent_pre = struct {
        fn run(_: *Command, _: []const []const u8) anyerror!void {
            State.record('A');
        }
    }.run;
    const pre = struct {
        fn run(_: *Command, _: []const []const u8) anyerror!void {
            State.record('B');
        }
    }.run;
    const main_run = struct {
        fn run(_: *Command, _: []const []const u8) anyerror!void {
            State.record('C');
        }
    }.run;
    const post = struct {
        fn run(_: *Command, _: []const []const u8) anyerror!void {
            State.record('D');
        }
    }.run;
    const persistent_post = struct {
        fn run(_: *Command, _: []const []const u8) anyerror!void {
            State.record('E');
        }
    }.run;

    var cmd = Command.init(.{
        .name = "test",
        .persistent_pre_run = &persistent_pre,
        .pre_run = &pre,
        .run = &main_run,
        .post_run = &post,
        .persistent_post_run = &persistent_post,
    });
    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    cmd.setOut(&out_buf);
    cmd.setErr(&err_buf);

    try cmd.executeWithArgs(&.{});
    try testing.expectEqualStrings("ABCDE", State.getOrder());
}

test "child inherits IO buffers from root" {
    var root = Command.init(.{ .name = "root", .run = &emptyRun });
    const child_run = struct {
        fn run(cmd: *Command, _: []const []const u8) anyerror!void {
            cmd.writeOut("from child");
        }
    }.run;
    var child = Command.init(.{ .name = "child", .run = &child_run });
    root.addCommand(&child);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    root.setOut(&out_buf);
    root.setErr(&err_buf);

    try root.executeWithArgs(&.{"child"});
    try testing.expectEqualStrings("from child", out_buf[0..root.out_len]);
}

test "persistent flags from root are inherited by subcommands" {
    // Mirrors cobra behavior: persistent flags defined on the root command
    // are accessible from any descendant, even when specified before the
    // subcommand name (e.g., "grimoire --index example collection add").
    const child_run = struct {
        fn run(cmd: *Command, _: []const []const u8) anyerror!void {
            const index = cmd.getFlag([]const u8, "index");
            cmd.writeOut(index);
        }
    }.run;

    var root = Command.init(.{
        .name = "grimoire",
        .persistent_flags = &.{
            Flag.string("index", 'i', "Index name", "default"),
        },
        .run = &emptyRun,
    });
    var collection = Command.init(.{ .name = "collection" });
    var add = Command.init(.{
        .name = "add",
        .flags = &.{
            Flag.string("name", 'n', "Collection name", ""),
        },
        .run = &child_run,
    });
    collection.addCommand(&add);
    root.addCommand(&collection);

    // Test 1: persistent flag BEFORE subcommand names
    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    root.setOut(&out_buf);
    root.setErr(&err_buf);

    try root.executeWithArgs(&.{ "--index", "example", "collection", "add", "/tmp/foo", "--name", "docs" });
    try testing.expectEqualStrings("example", out_buf[0..root.out_len]);

    // Test 2: persistent flag AFTER subcommand names
    root.out_len = 0;
    try root.executeWithArgs(&.{ "collection", "add", "/tmp/foo", "--index", "myindex", "--name", "docs" });
    try testing.expectEqualStrings("myindex", out_buf[0..root.out_len]);

    // Test 3: persistent flag default when not specified
    root.out_len = 0;
    try root.executeWithArgs(&.{ "collection", "add", "/tmp/foo", "--name", "docs" });
    try testing.expectEqualStrings("default", out_buf[0..root.out_len]);
}

test "persistent flags with short form before subcommand" {
    const child_run = struct {
        fn run(cmd: *Command, _: []const []const u8) anyerror!void {
            const verbose = cmd.getFlag(bool, "verbose");
            if (verbose) {
                cmd.writeOut("verbose-on");
            } else {
                cmd.writeOut("verbose-off");
            }
        }
    }.run;

    var root = Command.init(.{
        .name = "app",
        .persistent_flags = &.{
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });
    var sub = Command.init(.{
        .name = "sub",
        .run = &child_run,
    });
    root.addCommand(&sub);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    root.setOut(&out_buf);
    root.setErr(&err_buf);

    // Short boolean flag before subcommand
    try root.executeWithArgs(&.{ "-v", "sub" });
    try testing.expectEqualStrings("verbose-on", out_buf[0..root.out_len]);
}
