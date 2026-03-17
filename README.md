# Mamba

A Zig CLI framework ported from Go's [spf13/cobra](https://github.com/spf13/cobra).

Command-tree routing, flag parsing, argument validation, lifecycle hooks, and auto-generated help — in idiomatic Zig with zero allocations.

## Quick start

```zig
const mamba = @import("mamba");

fn run(cmd: *mamba.Command, args: []const []const u8) !void {
    const name = cmd.getFlag([]const u8, "name");
    cmd.writeOut("Hello, ");
    cmd.writeOut(name);
    cmd.writeOut("!\n");
    _ = args;
}

pub fn main() !void {
    var cmd = mamba.Command.init(.{
        .name = "greet",
        .short = "A friendly greeter",
        .flags = &.{
            mamba.Flag.string("name", 'n', "Who to greet", "world"),
            mamba.Flag.int("count", 'c', "How many times", 1),
            mamba.Flag.boolean("loud", 'l', "Shout it", false),
        },
        .run = &run,
    });
    try cmd.execute();
}
```

```bash
$ greet --name Ada
Hello, Ada!

$ greet --help
A friendly greeter

Usage:
  greet [flags]

Flags:
  -n, --name string   Who to greet (default "world")
  -c, --count int     How many times (default "1")
  -l, --loud          Shout it
  -h, --help          help for greet
```

## Install

```bash
zig fetch --save https://github.com/svge-ai/mamba/archive/refs/heads/main.tar.gz
```

Then in `build.zig`:

```zig
const mamba_dep = b.dependency("mamba", .{ .target = target, .optimize = optimize });
// Add to your executable's imports:
.imports = &.{
    .{ .name = "mamba", .module = mamba_dep.module("mamba") },
},
```

Requires Zig 0.15.2+.

## Features

- **Commands** — root command + nested subcommands, like `git remote add`
- **Flags** — string, int, float, bool with `-s` short and `--long` forms
- **Arguments** — exact, min, max, range, and custom validators
- **Hooks** — PreRun/PostRun with persistent variants that cascade to children
- **Help** — auto-generated cobra-style `--help`, `-h`, and `help` subcommand
- **Zero alloc** — stack-allocated buffers, no heap, no allocator required

## Documentation

Full docs at the [Mamba documentation site](https://svge-ai.github.io/mamba/).

## Development

```bash
task build      # Build library
task test       # Run tests
task doc:build  # Build docs site
task doc:serve  # Serve docs locally
```

## License

Apache 2.0 — same as the upstream cobra project.
