/// Integration tests for automatic help text generation.
/// Mirrors cobra's help behavior: --help, -h, help subcommand, --version.
const std = @import("std");
const testing = std.testing;
const mamba = @import("mamba");
const Command = mamba.Command;
const Flag = mamba.Flag;
const args = mamba.args;

fn emptyRun(_: *Command, _: []const []const u8) anyerror!void {}

const ExecuteResult = struct {
    output: []const u8,
    err_output: []const u8,
    err: ?anyerror,
};

fn executeCommand(root: *Command, cmd_args: []const []const u8) ExecuteResult {
    var out_buf: [8192]u8 = undefined;
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

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("Expected NOT to contain: \"{s}\"\nGot: \"{s}\"\n", .{ needle, haystack });
        return error.TestUnexpectedContains;
    }
}

// =============================================================================
// --help flag tests
// =============================================================================

test "--help on root shows help" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My application",
        .long = "A longer description of myapp.",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "A longer description of myapp.");
    try expectContains(result.output, "Usage:");
    try expectContains(result.output, "myapp");
    try expectContains(result.output, "--help");
}

test "-h on root shows help" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My application",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"-h"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "My application");
    try expectContains(result.output, "Usage:");
}

test "--help on child command" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var serve = Command.init(.{
        .name = "serve",
        .short = "Start the server",
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{ "serve", "--help" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "Start the server");
    try expectContains(result.output, "myapp serve");
}

test "--help bypasses flag parsing errors" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .run = &emptyRun,
    });

    // --unknown would normally error, but --help takes priority
    const result = executeCommand(&root, &.{ "--unknown", "--help" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "My app");
}

test "--help bypasses arg validation" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .args = args.exactArgs(3),
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "My app");
}

// =============================================================================
// help subcommand tests
// =============================================================================

test "help subcommand shows root help" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My application",
        .run = &emptyRun,
    });
    var serve = Command.init(.{ .name = "serve", .short = "Start server", .run = &emptyRun });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{"help"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "My application");
    try expectContains(result.output, "serve");
}

test "help subcommand targets child" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var serve = Command.init(.{
        .name = "serve",
        .short = "Start the server",
        .long = "Start the server with the given configuration.",
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{ "help", "serve" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "Start the server with the given configuration.");
}

test "help subcommand targets grandchild" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var config = Command.init(.{ .name = "config", .short = "Configuration", .run = &emptyRun });
    var config_set = Command.init(.{
        .name = "set",
        .short = "Set a config value",
        .run = &emptyRun,
    });
    config.addCommand(&config_set);
    root.addCommand(&config);

    const result = executeCommand(&root, &.{ "help", "config", "set" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "Set a config value");
    try expectContains(result.output, "myapp config set");
}

test "child help subcommand" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var serve = Command.init(.{
        .name = "serve",
        .short = "Start the server",
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    // "serve help" shows help for serve
    const result = executeCommand(&root, &.{ "serve", "help" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "Start the server");
}

// =============================================================================
// --version tests
// =============================================================================

test "--version shows version" {
    var root = Command.init(.{
        .name = "myapp",
        .version = "1.2.3",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--version"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "myapp version 1.2.3");
}

test "--version on child with version" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var serve = Command.init(.{
        .name = "serve",
        .version = "2.0.0",
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{ "serve", "--version" });
    try testing.expect(result.err == null);
    try expectContains(result.output, "myapp serve version 2.0.0");
}

test "--version not available without version" {
    var root = Command.init(.{
        .name = "myapp",
        .run = &emptyRun,
    });

    // --version with no version set should be an unknown flag
    const result = executeCommand(&root, &.{"--version"});
    try testing.expect(result.err != null);
}

// =============================================================================
// Help content tests
// =============================================================================

test "help shows long description over short" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "Short desc",
        .long = "Long description here",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Long description here");
}

test "help falls back to short when no long" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "Short desc",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Short desc");
}

test "help shows available commands" {
    var root = Command.init(.{ .name = "myapp", .short = "My app", .run = &emptyRun });
    var serve = Command.init(.{ .name = "serve", .short = "Start server", .run = &emptyRun });
    var build_cmd = Command.init(.{ .name = "build", .short = "Build project", .run = &emptyRun });
    root.addCommand(&serve);
    root.addCommand(&build_cmd);

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Available Commands:");
    try expectContains(result.output, "serve");
    try expectContains(result.output, "Start server");
    try expectContains(result.output, "build");
    try expectContains(result.output, "Build project");
    // Synthetic help entry
    try expectContains(result.output, "help");
    try expectContains(result.output, "Help about any command");
}

test "help shows aliases" {
    var root = Command.init(.{ .name = "myapp", .run = &emptyRun });
    var serve = Command.init(.{
        .name = "serve",
        .aliases = &.{ "s", "server" },
        .short = "Start server",
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{ "serve", "--help" });
    try expectContains(result.output, "Aliases:");
    try expectContains(result.output, "serve, s, server");
}

test "help shows examples" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .example = "  myapp serve --port 8080\n  myapp build -o out.gem",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Examples:");
    try expectContains(result.output, "myapp serve --port 8080");
}

test "help shows local flags" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .flags = &.{
            Flag.string("output", 'o', "Output file", "out.gem"),
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Flags:");
    try expectContains(result.output, "-o, --output string");
    try expectContains(result.output, "Output file");
    try expectContains(result.output, "(default \"out.gem\")");
    try expectContains(result.output, "-v, --verbose");
    try expectContains(result.output, "Verbose output");
    try expectContains(result.output, "-h, --help");
}

test "help shows global flags from parent" {
    var root = Command.init(.{
        .name = "myapp",
        .persistent_flags = &.{
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });
    var serve = Command.init(.{
        .name = "serve",
        .short = "Start server",
        .flags = &.{
            Flag.string("port", 'p', "Port number", "8080"),
        },
        .run = &emptyRun,
    });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{ "serve", "--help" });
    try expectContains(result.output, "Flags:");
    try expectContains(result.output, "-p, --port");
    try expectContains(result.output, "Global Flags:");
    try expectContains(result.output, "-v, --verbose");
}

test "help shows [flags] in usage for runnable command" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .flags = &.{
            Flag.boolean("verbose", 'v', "Verbose", false),
        },
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "myapp [flags]");
}

test "help shows [command] in usage for parent command" {
    var root = Command.init(.{ .name = "myapp", .short = "My app", .run = &emptyRun });
    var serve = Command.init(.{ .name = "serve", .short = "Serve", .run = &emptyRun });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "myapp [command]");
}

test "help shows footer hint for commands with subcommands" {
    var root = Command.init(.{ .name = "myapp", .short = "My app", .run = &emptyRun });
    var serve = Command.init(.{ .name = "serve", .short = "Serve", .run = &emptyRun });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Use \"myapp [command] --help\" for more information about a command.");
}

test "help shows version flag when version is set" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .version = "1.0.0",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "--version");
    try expectContains(result.output, "version for myapp");
}

// =============================================================================
// Non-runnable command shows help
// =============================================================================

test "non-runnable command with children shows help" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My application",
    });
    var serve = Command.init(.{ .name = "serve", .short = "Start server", .run = &emptyRun });
    root.addCommand(&serve);

    const result = executeCommand(&root, &.{});
    try testing.expect(result.err == null);
    try expectContains(result.output, "My application");
    try expectContains(result.output, "Available Commands:");
    try expectContains(result.output, "serve");
}

// =============================================================================
// help() method tests
// =============================================================================

test "help() method writes help to output" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My application",
        .long = "A detailed description.",
    });
    var serve = Command.init(.{ .name = "serve", .short = "Start server", .run = &emptyRun });
    root.addCommand(&serve);

    var out_buf: [8192]u8 = undefined;
    root.setOut(&out_buf);
    root.help();

    const output = out_buf[0..root.out_len];
    try expectContains(output, "A detailed description.");
    try expectContains(output, "Available Commands:");
    try expectContains(output, "serve");
    try expectContains(output, "--help");
}

// =============================================================================
// Edge cases
// =============================================================================

test "help with no description still shows usage" {
    var root = Command.init(.{
        .name = "myapp",
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try testing.expect(result.err == null);
    try expectContains(result.output, "Usage:");
    try expectContains(result.output, "myapp");
}

test "help with persistent flags shows them in own Flags section" {
    var root = Command.init(.{
        .name = "myapp",
        .short = "My app",
        .persistent_flags = &.{
            Flag.boolean("verbose", 'v', "Verbose output", false),
        },
        .run = &emptyRun,
    });

    const result = executeCommand(&root, &.{"--help"});
    try expectContains(result.output, "Flags:");
    try expectContains(result.output, "-v, --verbose");
}
