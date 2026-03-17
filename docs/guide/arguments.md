# Arguments

Positional arguments are everything on the command line that isn't a flag. Mamba provides validators to enforce argument count and content.

## Validators

Set the `.args` field on your command:

```zig
var cmd = mamba.Command.init(.{
    .name = "copy",
    .args = mamba.args.exactArgs(2),  // requires exactly 2 args
    .run = &copyRun,
});
```

### Built-in validators

| Validator | Description |
|-----------|-------------|
| `args.noArgs` | Accept no positional arguments |
| `args.arbitraryArgs` | Accept any number of arguments |
| `args.exactArgs(n)` | Require exactly `n` arguments |
| `args.minimumNArgs(n)` | Require at least `n` arguments |
| `args.maximumNArgs(n)` | Require at most `n` arguments |
| `args.rangeArgs(min, max)` | Require between `min` and `max` arguments |
| `args.onlyValidArgs` | Only accept arguments listed in `.valid_args` |
| `args.matchAll(validators)` | All validators must pass |

### Examples

```zig
// File copy: exactly source and destination
.args = mamba.args.exactArgs(2),

// Grep: at least a pattern
.args = mamba.args.minimumNArgs(1),

// Optional output file
.args = mamba.args.rangeArgs(1, 2),

// Only specific values
.valid_args = &.{ "start", "stop", "restart" },
.args = mamba.args.onlyValidArgs,

// Combine: at least 1 arg, and only valid values
.args = mamba.args.matchAll(&.{
    mamba.args.minimumNArgs(1),
    mamba.args.onlyValidArgs,
}),
```

## Reading arguments

Positional arguments are the second parameter of the `run` function:

```zig
fn copyRun(cmd: *mamba.Command, positional: []const []const u8) !void {
    const source = positional[0];
    const dest = positional[1];
    cmd.writeOut("Copying ");
    cmd.writeOut(source);
    cmd.writeOut(" to ");
    cmd.writeOut(dest);
    cmd.writeOut("\n");
}
```

## Error messages

When validation fails, mamba prints a cobra-style error:

```
Error: accepts 2 arg(s), received 1
```
