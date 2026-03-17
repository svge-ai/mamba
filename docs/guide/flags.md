# Flags

Mamba supports four flag types: string, int, float, and boolean. Each flag has a long name, optional short name, description, and default value.

## Defining flags

```zig
var cmd = mamba.Command.init(.{
    .name = "serve",
    .flags = &.{
        mamba.Flag.string("host", 'h', "Bind address", "0.0.0.0"),
        mamba.Flag.int("port", 'p', "Listen port", 8080),
        mamba.Flag.float("timeout", 't', "Request timeout in seconds", 30.0),
        mamba.Flag.boolean("verbose", 'v', "Enable verbose logging", false),
    },
    .run = &run,
});
```

## Flag types

| Constructor | Zig type | CLI syntax |
|-------------|----------|-----------|
| `Flag.string(name, short, desc, default)` | `[]const u8` | `--name value`, `--name=value`, `-n value` |
| `Flag.int(name, short, desc, default)` | `i64` | `--name 42`, `--name=42` |
| `Flag.float(name, short, desc, default)` | `f64` | `--name 3.14`, `--name=3.14` |
| `Flag.boolean(name, short, desc, default)` | `bool` | `--name` (true), `--no-name` (false) |

## Reading flag values

Inside a `run` function, use `cmd.getFlag()`:

```zig
fn run(cmd: *mamba.Command, _: []const []const u8) !void {
    const host = cmd.getFlag([]const u8, "host");   // "0.0.0.0" if not set
    const port = cmd.getFlag(i64, "port");           // 8080 if not set
    const timeout = cmd.getFlag(f64, "timeout");     // 30.0 if not set
    const verbose = cmd.getFlag(bool, "verbose");    // false if not set
    _ = .{ host, timeout, verbose };

    var buf: [32]u8 = undefined;
    const port_str = std.fmt.bufPrint(&buf, "Listening on port {d}\n", .{port}) catch return;
    cmd.writeOut(port_str);
}
```

If a flag isn't set on the command line, `getFlag` returns the default value from the flag definition.

## CLI syntax

All of these are equivalent:

```bash
myapp --port 8080
myapp --port=8080
myapp -p 8080
myapp -p8080
```

Boolean flags:

```bash
myapp --verbose          # sets verbose = true
myapp --no-verbose       # sets verbose = false
myapp -v                 # sets verbose = true (short form)
```

## Persistent flags

Persistent flags are inherited by all child commands:

```zig
var root = mamba.Command.init(.{
    .name = "app",
    .persistent_flags = &.{
        mamba.Flag.boolean("verbose", 'v', "Enable verbose output", false),
    },
});

var serve = mamba.Command.init(.{
    .name = "serve",
    .flags = &.{
        mamba.Flag.int("port", 'p', "Listen port", 8080),
    },
    .run = &serveRun,
});

root.addCommand(&serve);
```

```bash
app serve --verbose --port 8080  # --verbose inherited from root
```

In `serveRun`, both flags are accessible via `cmd.getFlag()`.

## Help text

Defaults are shown automatically in help output:

```
Flags:
  -h, --host string      Bind address (default "0.0.0.0")
  -p, --port int         Listen port (default "8080")
  -t, --timeout float    Request timeout in seconds (default "30")
  -v, --verbose          Enable verbose logging
  -h, --help             help for serve
```

Boolean flags don't show a default (they're `false` by convention).
