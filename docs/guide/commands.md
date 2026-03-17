# Commands

Commands are the central building block of a mamba CLI. Each command has a name, description, optional flags, and an optional `run` function.

## Defining a command

```zig
var cmd = mamba.Command.init(.{
    .name = "serve",
    .short = "Start the server",
    .long = "Start the HTTP server on the given port.\nListens on all interfaces by default.",
    .run = &serveRun,
});
```

### CommandOpts fields

| Field | Type | Description |
|-------|------|-------------|
| `.name` | `[]const u8` | Command name (used in `Usage:` line and subcommand routing) |
| `.short` | `[]const u8` | One-line description (shown in parent's subcommand list) |
| `.long` | `[]const u8` | Multi-line description (shown at top of `--help`) |
| `.example` | `[]const u8` | Example usage text |
| `.version` | `[]const u8` | Version string (enables `--version` flag) |
| `.run` | `*const RunFn` | Main command function |
| `.pre_run` | `*const RunFn` | Runs before `run` |
| `.post_run` | `*const RunFn` | Runs after `run` |
| `.persistent_pre_run` | `*const RunFn` | Runs before `run` on this command and all children |
| `.persistent_post_run` | `*const RunFn` | Runs after `run` on this command and all children |
| `.flags` | `[]const FlagDef` | Local flags (only for this command) |
| `.persistent_flags` | `[]const FlagDef` | Flags inherited by all child commands |
| `.args` | `ArgValidator` | Positional argument validator |
| `.valid_args` | `[]const []const u8` | List of valid argument values (for `onlyValidArgs`) |
| `.aliases` | `[]const []const u8` | Alternative names for this command |

## The run function

```zig
fn serveRun(cmd: *mamba.Command, positional: []const []const u8) !void {
    const port = cmd.getFlag(i64, "port");
    // ...
}
```

The `run` function receives:

- `cmd` — the command instance, used to read flags and write output
- `positional` — positional arguments (everything that's not a flag)

## Subcommands

Build a command tree by adding children:

```zig
var root = mamba.Command.init(.{ .name = "app" });
var serve = mamba.Command.init(.{ .name = "serve", .run = &serveRun });
var migrate = mamba.Command.init(.{ .name = "migrate", .run = &migrateRun });

root.addCommand(&serve);
root.addCommand(&migrate);

try root.execute();
```

```bash
app serve --port 8080
app migrate --direction up
app help serve
```

## Command output

Use `cmd.writeOut()` for stdout and `cmd.writeErr()` for stderr:

```zig
fn run(cmd: *mamba.Command, _: []const []const u8) !void {
    cmd.writeOut("Success!\n");
    cmd.writeErr("Warning: something happened\n");
}
```

For testing, redirect output to buffers:

```zig
var out_buf: [4096]u8 = undefined;
var err_buf: [4096]u8 = undefined;
cmd.setOut(&out_buf);
cmd.setErr(&err_buf);
try cmd.executeWithArgs(&.{"--verbose"});
// out_buf now contains the output
```

## Limits

| Limit | Value |
|-------|-------|
| Max child commands | 32 per command |
| Max command path depth | 32 levels |
| Max parsed flags | 64 per command |
| Max flag definitions | 128 total (local + persistent) |
| Output buffer | Caller-provided, any size |
