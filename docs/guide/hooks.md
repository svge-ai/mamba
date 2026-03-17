# Hooks

Mamba supports lifecycle hooks that run before and after the main `run` function. This matches cobra's hook chain exactly.

## Hook types

| Hook | When it runs | Scope |
|------|-------------|-------|
| `persistent_pre_run` | Before `pre_run` | This command and all children |
| `pre_run` | Before `run` | This command only |
| `run` | Main command logic | This command only |
| `post_run` | After `run` | This command only |
| `persistent_post_run` | After `post_run` | This command and all children |

## Execution order

For a command with all hooks defined:

```
persistent_pre_run  →  pre_run  →  run  →  post_run  →  persistent_post_run
```

## Example

```zig
const mamba = @import("mamba");

fn setupLogging(_: *mamba.Command, _: []const []const u8) !void {
    // Runs before every command in the tree
}

fn validateConfig(_: *mamba.Command, _: []const []const u8) !void {
    // Runs before this specific command
}

fn serve(cmd: *mamba.Command, _: []const []const u8) !void {
    cmd.writeOut("Server started\n");
}

fn cleanup(_: *mamba.Command, _: []const []const u8) !void {
    // Runs after this specific command
}

pub fn main() !void {
    var cmd = mamba.Command.init(.{
        .name = "serve",
        .persistent_pre_run = &setupLogging,
        .pre_run = &validateConfig,
        .run = &serve,
        .post_run = &cleanup,
    });
    try cmd.execute();
}
```

## Persistent hooks

Persistent hooks cascade to all child commands. This is useful for cross-cutting concerns like logging or authentication:

```zig
var root = mamba.Command.init(.{
    .name = "app",
    .persistent_pre_run = &initLogger,      // runs for ALL commands
    .persistent_post_run = &flushMetrics,   // runs for ALL commands
});

var serve = mamba.Command.init(.{
    .name = "serve",
    .pre_run = &loadConfig,  // only for serve
    .run = &serveRun,
});

root.addCommand(&serve);
```

When running `app serve`:
1. `initLogger` (persistent, from root)
2. `loadConfig` (local, from serve)
3. `serveRun` (local, from serve)
4. `flushMetrics` (persistent, from root)

## Error handling

If any hook returns an error, execution stops. The error propagates to the `execute()` caller.
