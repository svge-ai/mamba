# Mamba

A Zig CLI framework ported from Go's [spf13/cobra](https://github.com/spf13/cobra).

Mamba gives you command-tree routing, type-safe flag parsing, argument validation, lifecycle hooks, and auto-generated help text — all in idiomatic Zig with zero allocations.

## Features

- **Command tree** — nest subcommands arbitrarily deep, like `git remote add`
- **Flag parsing** — string, int, float, boolean flags with short (`-v`) and long (`--verbose`) forms
- **Argument validation** — exact count, min/max, range, custom validators
- **Lifecycle hooks** — PreRun, Run, PostRun with persistent variants that cascade to children
- **Auto help** — cobra-style `--help` and `help` subcommand generated automatically
- **Zero allocation** — all buffers are stack-allocated with static limits

## Quick example

```zig
const mamba = @import("mamba");

fn run(cmd: *mamba.Command, args: []const []const u8) !void {
    const name = cmd.getFlag([]const u8, "name");
    const count = cmd.getFlag(i64, "count");
    cmd.writeOut("Hello, ");
    cmd.writeOut(name);
    cmd.writeOut("!\n");
    _ = count;
    _ = args;
}

pub fn main() !void {
    var cmd = mamba.Command.init(.{
        .name = "greet",
        .short = "A friendly greeter",
        .flags = &.{
            mamba.Flag.string("name", 'n', "Who to greet", "world"),
            mamba.Flag.int("count", 'c', "How many times", 1),
        },
        .run = &run,
    });
    try cmd.execute();
}
```

```bash
$ greet --name Ada -c 3
Hello, Ada!

$ greet --help
A friendly greeter

Usage:
  greet [flags]

Flags:
  -n, --name string   Who to greet (default "world")
  -c, --count int     How many times (default "1")
  -h, --help          help for greet
```

## Cobra compatibility

Mamba mirrors cobra's API surface as closely as Zig's type system allows. If you've used cobra in Go, the patterns are the same: define commands with `init`, add flags, wire up `run` functions, and call `execute()`.

See the [Cobra Migration Guide](cobra-migration.md) for a side-by-side comparison.

## License

Apache 2.0 — same as the upstream cobra project.
