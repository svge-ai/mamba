# Cobra Migration Guide

Mamba mirrors cobra's API. This guide shows side-by-side equivalents.

## Command definition

=== "Cobra (Go)"

    ```go
    var rootCmd = &cobra.Command{
        Use:   "myapp",
        Short: "A brief description",
        Long:  "A longer description",
        Run: func(cmd *cobra.Command, args []string) {
            fmt.Println("Hello!")
        },
    }
    ```

=== "Mamba (Zig)"

    ```zig
    var root = mamba.Command.init(.{
        .name = "myapp",
        .short = "A brief description",
        .long = "A longer description",
        .run = &struct {
            fn run(cmd: *mamba.Command, args: []const []const u8) !void {
                _ = args;
                cmd.writeOut("Hello!\n");
            }
        }.run,
    });
    ```

## Flags

=== "Cobra (Go)"

    ```go
    rootCmd.Flags().StringP("config", "c", "app.yaml", "config file")
    rootCmd.Flags().IntP("port", "p", 8080, "server port")
    rootCmd.Flags().BoolP("verbose", "v", false, "verbose output")
    ```

=== "Mamba (Zig)"

    ```zig
    .flags = &.{
        mamba.Flag.string("config", 'c', "config file", "app.yaml"),
        mamba.Flag.int("port", 'p', "server port", 8080),
        mamba.Flag.boolean("verbose", 'v', "verbose output", false),
    },
    ```

## Reading flags

=== "Cobra (Go)"

    ```go
    config, _ := cmd.Flags().GetString("config")
    port, _ := cmd.Flags().GetInt("port")
    verbose, _ := cmd.Flags().GetBool("verbose")
    ```

=== "Mamba (Zig)"

    ```zig
    const config = cmd.getFlag([]const u8, "config");
    const port = cmd.getFlag(i64, "port");
    const verbose = cmd.getFlag(bool, "verbose");
    ```

## Subcommands

=== "Cobra (Go)"

    ```go
    rootCmd.AddCommand(serveCmd)
    rootCmd.AddCommand(migrateCmd)
    rootCmd.Execute()
    ```

=== "Mamba (Zig)"

    ```zig
    root.addCommand(&serve);
    root.addCommand(&migrate);
    try root.execute();
    ```

## Persistent flags

=== "Cobra (Go)"

    ```go
    rootCmd.PersistentFlags().BoolP("verbose", "v", false, "verbose output")
    ```

=== "Mamba (Zig)"

    ```zig
    .persistent_flags = &.{
        mamba.Flag.boolean("verbose", 'v', "verbose output", false),
    },
    ```

## Hooks

=== "Cobra (Go)"

    ```go
    &cobra.Command{
        PersistentPreRun:  func(cmd *cobra.Command, args []string) { ... },
        PreRun:            func(cmd *cobra.Command, args []string) { ... },
        Run:               func(cmd *cobra.Command, args []string) { ... },
        PostRun:           func(cmd *cobra.Command, args []string) { ... },
        PersistentPostRun: func(cmd *cobra.Command, args []string) { ... },
    }
    ```

=== "Mamba (Zig)"

    ```zig
    .persistent_pre_run = &persistentPreRun,
    .pre_run = &preRun,
    .run = &mainRun,
    .post_run = &postRun,
    .persistent_post_run = &persistentPostRun,
    ```

## Argument validation

=== "Cobra (Go)"

    ```go
    Args: cobra.ExactArgs(2),
    Args: cobra.MinimumNArgs(1),
    Args: cobra.RangeArgs(1, 3),
    Args: cobra.NoArgs,
    ```

=== "Mamba (Zig)"

    ```zig
    .args = mamba.args.exactArgs(2),
    .args = mamba.args.minimumNArgs(1),
    .args = mamba.args.rangeArgs(1, 3),
    .args = mamba.args.noArgs,
    ```

## Key differences

| Aspect | Cobra | Mamba |
|--------|-------|-------|
| Memory | Heap-allocated | Stack-allocated, zero alloc |
| Flag definition | Runtime method calls | Comptime struct literals |
| Error handling | Returns `error` | Returns Zig `error` union |
| Output | `fmt.Println` / `cmd.Println` | `cmd.writeOut()` |
| Int type | `int` (platform-sized) | `i64` |
| Generics | Interface-based | `comptime T: type` |
