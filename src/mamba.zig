//! Mamba — Zig CLI Framework
//!
//! A Zig-idiomatic port of Go's spf13/cobra.
//! Provides command-tree routing, flag parsing, arg validation, and hook chains.

pub const command = @import("command.zig");
pub const args = @import("args.zig");
pub const flags = @import("flags.zig");

// Re-export primary types at the top level for convenience.
pub const Command = command.Command;
pub const CommandOpts = command.CommandOpts;
pub const RunFn = command.RunFn;
pub const ArgValidator = args.ArgValidator;
pub const ValidateResult = args.ValidateResult;
pub const FlagDef = flags.FlagDef;
pub const FlagKind = flags.FlagKind;
pub const FlagValue = flags.FlagValue;
pub const Flag = flags.Flag;

test {
    // Pull in tests from sub-modules (no circular deps).
    _ = @import("args.zig");
    _ = @import("flags.zig");
    _ = @import("command.zig");
    // Integration tests live in tests/ — run via build.zig test targets
}
