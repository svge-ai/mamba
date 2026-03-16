const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mamba_mod = b.addModule("mamba", .{
        .root_source_file = b.path("src/mamba.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mamba.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Integration tests
    const args_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/args_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    args_tests.root_module.addImport("mamba", mamba_mod);
    const run_args_tests = b.addRunArtifact(args_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_args_tests.step);
}
