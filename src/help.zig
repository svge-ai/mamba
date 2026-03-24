const std = @import("std");
const Command = @import("command.zig").Command;
const FlagDef = @import("flags.zig").FlagDef;
const FlagKind = @import("flags.zig").FlagKind;

const LINE_BUF_SIZE = 512;

/// Write the full help text for a command to its output.
/// Mirrors cobra's default help template: description, then full usage.
pub fn writeHelp(cmd: *Command) void {
    // Description: Long takes precedence, fall back to Short
    const desc = if (cmd.long.len > 0) cmd.long else cmd.short;
    if (desc.len > 0) {
        cmd.writeOut(desc);
        cmd.writeOut("\n");
    }

    writeUsage(cmd);
}

/// Write the usage section for a command (cobra's default usage template).
/// Called by writeHelp, and can also be used standalone for error context.
pub fn writeUsage(cmd: *Command) void {
    var path_buf: [Command.PATH_BUF_SIZE]u8 = undefined;
    const cmd_path = cmd.commandPathBuf(&path_buf);
    const has_subcmds = cmd.children_count > 0;
    const is_runnable = cmd.run != null;

    if (is_runnable or has_subcmds) {
        cmd.writeOut("\nUsage:\n");

        if (is_runnable) {
            var buf: [LINE_BUF_SIZE]u8 = undefined;
            const has_any_flags = cmd.flags.len > 0 or hasPersistentFlagsInChain(cmd);
            if (has_any_flags) {
                const line = std.fmt.bufPrint(&buf, "  {s} [flags]\n", .{cmd_path}) catch return;
                cmd.writeOut(line);
            } else {
                const line = std.fmt.bufPrint(&buf, "  {s}\n", .{cmd_path}) catch return;
                cmd.writeOut(line);
            }
        }

        if (has_subcmds) {
            var buf: [LINE_BUF_SIZE]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "  {s} [command]\n", .{cmd_path}) catch return;
            cmd.writeOut(line);
        }
    }

    // Aliases
    if (cmd.aliases.len > 0) {
        cmd.writeOut("\nAliases:\n  ");
        cmd.writeOut(cmd.name);
        for (cmd.aliases) |alias| {
            cmd.writeOut(", ");
            cmd.writeOut(alias);
        }
        cmd.writeOut("\n");
    }

    // Examples
    if (cmd.example.len > 0) {
        cmd.writeOut("\nExamples:\n");
        cmd.writeOut(cmd.example);
        cmd.writeOut("\n");
    }

    // Available Commands
    if (has_subcmds) {
        // Compute max name length for right-padding (minimum 4)
        var max_name_len: usize = 4;
        for (cmd.children[0..cmd.children_count]) |child| {
            if (child.name.len > max_name_len) max_name_len = child.name.len;
        }
        // Account for the synthetic "help" entry
        if (!hasChildNamed(cmd, "help") and 4 > max_name_len) {
            max_name_len = 4; // "help".len
        }

        cmd.writeOut("\nAvailable Commands:\n");

        // Display children in insertion order, plus synthetic "help"
        for (cmd.children[0..cmd.children_count]) |child| {
            writeCommandEntry(cmd, child.name, child.short, max_name_len);
        }
        // Add synthetic "help" entry if user hasn't registered one
        if (!hasChildNamed(cmd, "help")) {
            writeCommandEntry(cmd, "help", "Help about any command", max_name_len);
        }
    }

    // Flags (local + own persistent)
    const local_count = cmd.flags.len + cmd.persistent_flags.len;
    if (local_count > 0 or true) {
        // Always show Flags section (at minimum, --help is always present)
        cmd.writeOut("\nFlags:\n");

        // Compute max left width across local flags + help flag + version flag
        var max_left: usize = helpFlagLeftWidth(cmd);

        for (cmd.flags) |def| {
            const w = flagLeftWidth(def);
            if (w > max_left) max_left = w;
        }
        for (cmd.persistent_flags) |def| {
            const w = flagLeftWidth(def);
            if (w > max_left) max_left = w;
        }
        if (cmd.version.len > 0) {
            const vw = versionFlagLeftWidth();
            if (vw > max_left) max_left = vw;
        }

        // Write flag lines
        for (cmd.flags) |def| {
            writeFlagLine(cmd, def, max_left);
        }
        for (cmd.persistent_flags) |def| {
            writeFlagLine(cmd, def, max_left);
        }
        // Synthetic --help flag
        writeHelpFlagLine(cmd, max_left);
        // Synthetic --version flag (if version set)
        if (cmd.version.len > 0) {
            writeVersionFlagLine(cmd, max_left);
        }
    }

    // Global Flags (inherited persistent flags from parent chain)
    const inherited = collectInheritedFlags(cmd);
    if (inherited.count > 0) {
        cmd.writeOut("\nGlobal Flags:\n");
        var max_left: usize = 0;
        for (inherited.defs[0..inherited.count]) |def| {
            const w = flagLeftWidth(def);
            if (w > max_left) max_left = w;
        }
        for (inherited.defs[0..inherited.count]) |def| {
            writeFlagLine(cmd, def, max_left);
        }
    }

    // Footer hint
    if (has_subcmds) {
        var buf: [LINE_BUF_SIZE]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "\nUse \"{s} [command] --help\" for more information about a command.\n", .{cmd_path}) catch return;
        cmd.writeOut(line);
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn writeCommandEntry(cmd: *Command, name: []const u8, short: []const u8, max_name_len: usize) void {
    var buf: [LINE_BUF_SIZE]u8 = undefined;
    var pos: usize = 0;

    // "  "
    @memcpy(buf[pos..][0..2], "  ");
    pos += 2;

    // name
    @memcpy(buf[pos..][0..name.len], name);
    pos += name.len;

    // right-pad to max_name_len + gap
    const pad = (max_name_len + 4) -| name.len;
    if (pad > 0 and pos + pad <= buf.len) {
        @memset(buf[pos..][0..pad], ' ');
        pos += pad;
    }

    // short description
    const copy_len = @min(short.len, buf.len - pos - 1);
    @memcpy(buf[pos..][0..copy_len], short[0..copy_len]);
    pos += copy_len;

    buf[pos] = '\n';
    pos += 1;
    cmd.writeOut(buf[0..pos]);
}

/// Compute the left-column width for a flag definition.
fn flagLeftWidth(def: FlagDef) usize {
    // Format: "  -s, --name type" or "      --name type"
    // Prefix is always 6 chars: "  -s, " or "      "
    var w: usize = 6 + 2 + def.name.len; // prefix + "--" + name
    if (def.kind != .boolean) {
        w += 1 + flagTypeName(def.kind).len; // " type"
    }
    return w;
}

/// Left width for the synthetic --help flag.
fn helpFlagLeftWidth(cmd: *const Command) usize {
    _ = cmd;
    // "  -h, --help" = 6 + 2 + 4 = 12 (boolean, no type)
    return 12;
}

/// Left width for the synthetic --version flag.
fn versionFlagLeftWidth() usize {
    // "      --version" = 6 + 2 + 7 = 15 (boolean, no type)
    return 15;
}

fn writeFlagLine(cmd: *Command, def: FlagDef, max_left: usize) void {
    var buf: [LINE_BUF_SIZE]u8 = undefined;
    var pos: usize = 0;

    // Short flag prefix (short code 0 means "no short code")
    if (def.short) |s| {
        if (s != 0) {
            @memcpy(buf[pos..][0..2], "  ");
            pos += 2;
            buf[pos] = '-';
            pos += 1;
            buf[pos] = s;
            pos += 1;
            @memcpy(buf[pos..][0..2], ", ");
            pos += 2;
        } else {
            @memset(buf[pos..][0..6], ' ');
            pos += 6;
        }
    } else {
        @memset(buf[pos..][0..6], ' ');
        pos += 6;
    }

    // "--name"
    @memcpy(buf[pos..][0..2], "--");
    pos += 2;
    @memcpy(buf[pos..][0..def.name.len], def.name);
    pos += def.name.len;

    // " type" (skip for booleans)
    if (def.kind != .boolean) {
        buf[pos] = ' ';
        pos += 1;
        const tn = flagTypeName(def.kind);
        @memcpy(buf[pos..][0..tn.len], tn);
        pos += tn.len;
    }

    // Pad to alignment
    const target_col = max_left + 3;
    while (pos < target_col and pos < buf.len - 1) {
        buf[pos] = ' ';
        pos += 1;
    }

    // Description
    const desc_len = @min(def.description.len, buf.len - pos - 30);
    @memcpy(buf[pos..][0..desc_len], def.description[0..desc_len]);
    pos += desc_len;

    // Default value (shown for non-boolean flags with non-empty defaults)
    if (def.kind != .boolean and def.default_raw.len > 0) {
        const prefix = " (default \"";
        const suffix = "\")";
        const needed = prefix.len + def.default_raw.len + suffix.len;
        if (pos + needed + 1 < buf.len) {
            @memcpy(buf[pos..][0..prefix.len], prefix);
            pos += prefix.len;
            @memcpy(buf[pos..][0..def.default_raw.len], def.default_raw);
            pos += def.default_raw.len;
            @memcpy(buf[pos..][0..suffix.len], suffix);
            pos += suffix.len;
        }
    }

    buf[pos] = '\n';
    pos += 1;
    cmd.writeOut(buf[0..pos]);
}

fn writeHelpFlagLine(cmd: *Command, max_left: usize) void {
    var buf: [LINE_BUF_SIZE]u8 = undefined;
    var pos: usize = 0;

    const prefix = "  -h, --help";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    const target_col = max_left + 3;
    while (pos < target_col and pos < buf.len - 1) {
        buf[pos] = ' ';
        pos += 1;
    }

    const desc_prefix = "help for ";
    @memcpy(buf[pos..][0..desc_prefix.len], desc_prefix);
    pos += desc_prefix.len;

    const name_len = @min(cmd.name.len, buf.len - pos - 1);
    @memcpy(buf[pos..][0..name_len], cmd.name[0..name_len]);
    pos += name_len;

    buf[pos] = '\n';
    pos += 1;
    cmd.writeOut(buf[0..pos]);
}

fn writeVersionFlagLine(cmd: *Command, max_left: usize) void {
    var buf: [LINE_BUF_SIZE]u8 = undefined;
    var pos: usize = 0;

    const prefix = "      --version";
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    const target_col = max_left + 3;
    while (pos < target_col and pos < buf.len - 1) {
        buf[pos] = ' ';
        pos += 1;
    }

    const desc_prefix = "version for ";
    @memcpy(buf[pos..][0..desc_prefix.len], desc_prefix);
    pos += desc_prefix.len;

    const name_len = @min(cmd.name.len, buf.len - pos - 1);
    @memcpy(buf[pos..][0..name_len], cmd.name[0..name_len]);
    pos += name_len;

    buf[pos] = '\n';
    pos += 1;
    cmd.writeOut(buf[0..pos]);
}

fn flagTypeName(kind: FlagKind) []const u8 {
    return switch (kind) {
        .string => "string",
        .int => "int",
        .float => "float",
        .boolean => "",
    };
}

fn hasPersistentFlagsInChain(cmd: *const Command) bool {
    var current: ?*const Command = cmd;
    while (current) |c| {
        if (c.persistent_flags.len > 0) return true;
        current = if (c.parent) |p| @as(*const Command, p) else null;
    }
    return false;
}

fn hasChildNamed(cmd: *const Command, name: []const u8) bool {
    for (cmd.children[0..cmd.children_count]) |child| {
        if (std.mem.eql(u8, child.name, name)) return true;
    }
    return false;
}

const CollectedFlags = struct {
    defs: [128]FlagDef,
    count: usize,
};

/// Collect persistent flags inherited from parent chain (not including own).
fn collectInheritedFlags(cmd: *const Command) CollectedFlags {
    var collected: CollectedFlags = .{
        .defs = undefined,
        .count = 0,
    };
    var current: ?*const Command = if (cmd.parent) |p| @as(*const Command, p) else null;
    while (current) |c| {
        for (c.persistent_flags) |def| {
            if (collected.count < 128) {
                collected.defs[collected.count] = def;
                collected.count += 1;
            }
        }
        current = if (c.parent) |p| @as(*const Command, p) else null;
    }
    return collected;
}
