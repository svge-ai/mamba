# Mamba

Zig CLI command framework, inspired by Go's [cobra](https://github.com/spf13/cobra).

## Features

- Command struct with subcommand routing
- Positional arg validators (NoArgs, ExactArgs, MinArgs, etc.)
- Flag parsing (bool, string, int)
- Run hooks (PreRun, Run, PostRun)
- Help/usage generation

## Usage

```zig
const mamba = @import("mamba");

const cmd = mamba.Command.init(.{
    .name = "greet",
    .short = "Say hello",
    .run = struct {
        fn run(_: *mamba.Command, _: []const []const u8) !void {
            std.debug.print("Hello!\n", .{});
        }
    }.run,
});
```

## License

Apache-2.0
