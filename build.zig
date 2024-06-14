const std = @import("std");

const name = "m349wm";
const source = "src/" ++ name ++ ".zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
        .use_llvm = optimize != .Debug,
        .use_lld = optimize != .Debug,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("xcb");
    exe.linkSystemLibrary("xcb-keysyms");
    exe.linkSystemLibrary("xcb-util");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
        .use_llvm = optimize != .Debug,
        .use_lld = optimize != .Debug,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
