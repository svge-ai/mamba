# Installation

## Add to your Zig project

Mamba requires Zig 0.15.2+.

### 1. Fetch the dependency

```bash
zig fetch --save https://github.com/svge-ai/mamba/archive/refs/heads/main.tar.gz
```

This adds mamba to your `build.zig.zon`.

### 2. Wire into build.zig

```zig
const mamba_dep = b.dependency("mamba", .{
    .target = target,
    .optimize = optimize,
});

// Add to your executable's imports:
const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mamba", .module = mamba_dep.module("mamba") },
        },
    }),
});
```

### 3. Import and use

```zig
const mamba = @import("mamba");
```

## Pin to a release

To pin to a specific version instead of `main`:

```bash
zig fetch --save https://github.com/svge-ai/mamba/archive/refs/tags/v0.1.5.tar.gz
```
