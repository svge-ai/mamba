# API Reference

## Types

### Command

```zig
const Command = struct {
    // Initialize a new command
    pub fn init(opts: CommandOpts) Command

    // Execute using OS arguments (reads std.os.argv)
    pub fn execute(self: *Command) !void

    // Execute with specific arguments (for testing)
    pub fn executeWithArgs(self: *Command, args: []const []const u8) !void

    // Add a child subcommand
    pub fn addCommand(self: *Command, child: *Command) void

    // Get a parsed flag value (returns default if not set)
    pub fn getFlag(self: *const Command, comptime T: type, name: []const u8) T
    // T must be one of: []const u8, bool, i64, f64

    // Write to command's stdout/stderr
    pub fn writeOut(self: *Command, msg: []const u8) void
    pub fn writeErr(self: *Command, msg: []const u8) void

    // Redirect output (for testing)
    pub fn setOut(self: *Command, buf: []u8) void
    pub fn setErr(self: *Command, buf: []u8) void

    // Show help text
    pub fn help(self: *Command) void
};
```

### Flag

```zig
const Flag = struct {
    pub fn string(name, short, desc, default) FlagDef
    pub fn int(name, short, desc, default) FlagDef
    pub fn float(name, short, desc, default) FlagDef
    pub fn boolean(name, short, desc, default) FlagDef
};
```

All parameters are `comptime`. The `short` parameter is `?u8` — pass `null` for no short flag, or a character like `'v'`.

### RunFn

```zig
const RunFn = fn (cmd: *Command, args: []const []const u8) anyerror!void;
```

### ArgValidator

```zig
const args = struct {
    pub const noArgs: ArgValidator;
    pub const arbitraryArgs: ArgValidator;
    pub fn exactArgs(comptime n: usize) ArgValidator;
    pub fn minimumNArgs(comptime n: usize) ArgValidator;
    pub fn maximumNArgs(comptime n: usize) ArgValidator;
    pub fn rangeArgs(comptime min: usize, comptime max: usize) ArgValidator;
    pub const onlyValidArgs: ArgValidator;
    pub fn matchAll(validators: []const ArgValidator) ArgValidator;
};
```

## Static limits

| Resource | Limit |
|----------|-------|
| Child commands per command | 32 |
| Command path depth | 32 |
| Parsed flags per command | 64 |
| Total flag definitions (local + persistent chain) | 128 |
| Args buffer for `execute()` | 128 |
