# Quick Start

Build a CLI tool in 5 minutes.

## Step 1: Define your command

Every mamba app starts with a root command. The command specifies its name, description, flags, and a `run` function.

```zig
const mamba = @import("mamba");

fn run(cmd: *mamba.Command, positional: []const []const u8) !void {
    const verbose = cmd.getFlag(bool, "verbose");
    if (verbose) {
        cmd.writeOut("Running in verbose mode\n");
    }
    for (positional) |arg| {
        cmd.writeOut(arg);
        cmd.writeOut("\n");
    }
}

pub fn main() !void {
    var cmd = mamba.Command.init(.{
        .name = "myapp",
        .short = "Does something useful",
        .long = "A longer description of what myapp does.\nSpans multiple lines.",
        .flags = &.{
            mamba.Flag.boolean("verbose", 'v', "Enable verbose output", false),
            mamba.Flag.string("output", 'o', "Output file path", "stdout"),
        },
        .run = &run,
    });
    try cmd.execute();
}
```

## Step 2: Build and run

```bash
zig build
./zig-out/bin/myapp --help
```

Output:

```
A longer description of what myapp does.
Spans multiple lines.

Usage:
  myapp [flags]

Flags:
  -v, --verbose           Enable verbose output
  -o, --output string     Output file path (default "stdout")
  -h, --help              help for myapp
```

## Step 3: Use it

```bash
# Boolean flags
./zig-out/bin/myapp -v file1.txt file2.txt

# String flags with = syntax
./zig-out/bin/myapp --output=result.json file.txt

# Short flags combined
./zig-out/bin/myapp -v -o result.json file.txt
```

## Adding subcommands

```zig
pub fn main() !void {
    var root = mamba.Command.init(.{
        .name = "git",
        .short = "A version control system",
    });

    var clone = mamba.Command.init(.{
        .name = "clone",
        .short = "Clone a repository",
        .args = mamba.args.exactArgs(1),
        .run = &cloneRun,
    });

    root.addCommand(&clone);
    try root.execute();
}
```

```bash
$ git clone https://github.com/user/repo
$ git clone --help
$ git help clone
```
