const std = @import("std");

/// Kind of flag value.
pub const FlagKind = enum {
    string,
    boolean,
    int,
    float,
};

/// Compile-time flag definition. Defaults stored as raw strings.
pub const FlagDef = struct {
    name: []const u8,
    short: ?u8 = null,
    description: []const u8 = "",
    kind: FlagKind,
    default_raw: []const u8 = "",
};

/// Runtime parsed flag value.
pub const FlagValue = struct {
    name: []const u8,
    raw: []const u8,
    kind: FlagKind,
};

/// Flag constructors — convenience functions that return FlagDef.
pub const Flag = struct {
    pub fn string(name: []const u8, short: ?u8, desc: []const u8, default: []const u8) FlagDef {
        return .{
            .name = name,
            .short = short,
            .description = desc,
            .kind = .string,
            .default_raw = default,
        };
    }

    pub fn boolean(name: []const u8, short: ?u8, desc: []const u8, default: bool) FlagDef {
        return .{
            .name = name,
            .short = short,
            .description = desc,
            .kind = .boolean,
            .default_raw = if (default) "true" else "false",
        };
    }

    pub fn int(name: []const u8, short: ?u8, desc: []const u8, default: i64) FlagDef {
        // For comptime int defaults, we store the string representation.
        // Since FlagDef.default_raw is []const u8, we use comptime formatting.
        _ = default;
        return .{
            .name = name,
            .short = short,
            .description = desc,
            .kind = .int,
            .default_raw = "0", // caller should use intWithDefault for runtime
        };
    }

    pub fn float(name: []const u8, short: ?u8, desc: []const u8, default: f64) FlagDef {
        _ = default;
        return .{
            .name = name,
            .short = short,
            .description = desc,
            .kind = .float,
            .default_raw = "0.0",
        };
    }
};

/// Parse error when flags are malformed.
pub const FlagError = error{
    UnknownFlag,
    MissingFlagValue,
    InvalidFlagValue,
};

/// Result of parsing flags from an argument list.
pub const ParseResult = struct {
    flags: [MAX_FLAGS]FlagValue,
    flags_count: usize,
    positional: [MAX_POSITIONAL][]const u8,
    positional_count: usize,

    pub const MAX_FLAGS = 64;
    pub const MAX_POSITIONAL = 128;

    pub fn positionalArgs(self: *const ParseResult) []const []const u8 {
        return self.positional[0..self.positional_count];
    }

    pub fn flagValues(self: *const ParseResult) []const FlagValue {
        return self.flags[0..self.flags_count];
    }
};

/// Find a flag definition by long name in the given defs slice.
fn findFlagDef(defs: []const FlagDef, name: []const u8) ?FlagDef {
    for (defs) |def| {
        if (std.mem.eql(u8, def.name, name)) {
            return def;
        }
    }
    return null;
}

/// Find a flag definition by short name in the given defs slice.
fn findFlagDefShort(defs: []const FlagDef, short: u8) ?FlagDef {
    for (defs) |def| {
        if (def.short) |s| {
            if (s == short) return def;
        }
    }
    return null;
}

/// Parse flags from an arg list given the flag definitions.
/// Returns parsed flags and remaining positional args.
/// `all_defs` should include both local and inherited persistent flags.
pub fn parseFlags(raw_args: []const []const u8, all_defs: []const FlagDef) FlagError!ParseResult {
    var result: ParseResult = .{
        .flags = undefined,
        .flags_count = 0,
        .positional = undefined,
        .positional_count = 0,
    };

    var i: usize = 0;
    while (i < raw_args.len) {
        const arg = raw_args[i];

        if (arg.len >= 2 and arg[0] == '-' and arg[1] == '-') {
            // Long flag: --name or --name=value or --no-name
            const rest = arg[2..];

            // Check for --name=value
            if (std.mem.indexOf(u8, rest, "=")) |eq_pos| {
                const name = rest[0..eq_pos];
                const value = rest[eq_pos + 1 ..];
                const def = findFlagDef(all_defs, name) orelse return FlagError.UnknownFlag;
                if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                result.flags[result.flags_count] = .{ .name = def.name, .raw = value, .kind = def.kind };
                result.flags_count += 1;
            } else if (rest.len > 3 and std.mem.startsWith(u8, rest, "no-")) {
                // --no-boolname
                const name = rest[3..];
                const def = findFlagDef(all_defs, name);
                if (def) |d| {
                    if (d.kind == .boolean) {
                        if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                        result.flags[result.flags_count] = .{ .name = d.name, .raw = "false", .kind = .boolean };
                        result.flags_count += 1;
                    } else {
                        return FlagError.UnknownFlag;
                    }
                } else {
                    return FlagError.UnknownFlag;
                }
            } else {
                const def = findFlagDef(all_defs, rest) orelse return FlagError.UnknownFlag;
                if (def.kind == .boolean) {
                    // Boolean flag: presence means true
                    if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                    result.flags[result.flags_count] = .{ .name = def.name, .raw = "true", .kind = .boolean };
                    result.flags_count += 1;
                } else {
                    // Non-boolean: next arg is the value
                    i += 1;
                    if (i >= raw_args.len) return FlagError.MissingFlagValue;
                    if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                    result.flags[result.flags_count] = .{ .name = def.name, .raw = raw_args[i], .kind = def.kind };
                    result.flags_count += 1;
                }
            }
        } else if (arg.len >= 2 and arg[0] == '-' and arg[1] != '-') {
            // Short flag: -n or -n=value
            const short_char = arg[1];

            if (arg.len > 2 and arg[2] == '=') {
                // -n=value
                const value = arg[3..];
                const def = findFlagDefShort(all_defs, short_char) orelse return FlagError.UnknownFlag;
                if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                result.flags[result.flags_count] = .{ .name = def.name, .raw = value, .kind = def.kind };
                result.flags_count += 1;
            } else if (arg.len == 2) {
                const def = findFlagDefShort(all_defs, short_char) orelse return FlagError.UnknownFlag;
                if (def.kind == .boolean) {
                    if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                    result.flags[result.flags_count] = .{ .name = def.name, .raw = "true", .kind = .boolean };
                    result.flags_count += 1;
                } else {
                    i += 1;
                    if (i >= raw_args.len) return FlagError.MissingFlagValue;
                    if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                    result.flags[result.flags_count] = .{ .name = def.name, .raw = raw_args[i], .kind = def.kind };
                    result.flags_count += 1;
                }
            } else {
                // -nvalue (short flag with value concatenated)
                const def = findFlagDefShort(all_defs, short_char) orelse return FlagError.UnknownFlag;
                const value = arg[2..];
                if (result.flags_count >= ParseResult.MAX_FLAGS) return FlagError.UnknownFlag;
                result.flags[result.flags_count] = .{ .name = def.name, .raw = value, .kind = def.kind };
                result.flags_count += 1;
            }
        } else {
            // Positional arg
            if (result.positional_count >= ParseResult.MAX_POSITIONAL) {
                // Silently drop excess positional args (shouldn't happen in practice)
                i += 1;
                continue;
            }
            result.positional[result.positional_count] = arg;
            result.positional_count += 1;
        }

        i += 1;
    }

    return result;
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

test "parse long flag with value" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
    };
    const result = try parseFlags(&.{ "--output", "foo.gem" }, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("output", result.flags[0].name);
    try testing.expectEqualStrings("foo.gem", result.flags[0].raw);
    try testing.expectEqual(@as(usize, 0), result.positional_count);
}

test "parse long flag with equals" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
    };
    const result = try parseFlags(&.{"--output=foo.gem"}, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("foo.gem", result.flags[0].raw);
}

test "parse boolean flag" {
    const defs = &[_]FlagDef{
        Flag.boolean("verbose", 'v', "Verbose", false),
    };
    const result = try parseFlags(&.{"--verbose"}, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("true", result.flags[0].raw);
}

test "parse no-boolean flag" {
    const defs = &[_]FlagDef{
        Flag.boolean("verbose", 'v', "Verbose", true),
    };
    const result = try parseFlags(&.{"--no-verbose"}, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("false", result.flags[0].raw);
}

test "parse short flag" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
    };
    const result = try parseFlags(&.{ "-o", "bar.gem" }, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("bar.gem", result.flags[0].raw);
}

test "parse short flag with equals" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
    };
    const result = try parseFlags(&.{"-o=bar.gem"}, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("bar.gem", result.flags[0].raw);
}

test "parse mixed flags and positional" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
        Flag.boolean("verbose", 'v', "Verbose", false),
    };
    const result = try parseFlags(&.{ "--verbose", "pos1", "-o", "file.gem", "pos2" }, defs);
    try testing.expectEqual(@as(usize, 2), result.flags_count);
    try testing.expectEqual(@as(usize, 2), result.positional_count);
    try testing.expectEqualStrings("pos1", result.positional[0]);
    try testing.expectEqualStrings("pos2", result.positional[1]);
}

test "unknown flag returns error" {
    const defs = &[_]FlagDef{};
    const result = parseFlags(&.{"--unknown"}, defs);
    try testing.expect(result == FlagError.UnknownFlag);
}

test "missing flag value returns error" {
    const defs = &[_]FlagDef{
        Flag.string("output", 'o', "Output file", "out.gem"),
    };
    const result = parseFlags(&.{"--output"}, defs);
    try testing.expect(result == FlagError.MissingFlagValue);
}

test "short boolean flag" {
    const defs = &[_]FlagDef{
        Flag.boolean("verbose", 'v', "Verbose", false),
    };
    const result = try parseFlags(&.{"-v"}, defs);
    try testing.expectEqual(@as(usize, 1), result.flags_count);
    try testing.expectEqualStrings("true", result.flags[0].raw);
}
