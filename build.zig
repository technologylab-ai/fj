const std = @import("std");

const build_zig_zon = @embedFile("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addCSourceFile(.{ .file = b.path("src/pdf/pdfgen.c") });
    exe_mod.addCSourceFile(.{ .file = b.path("src/stb/stb_image.c") });
    exe_mod.addCSourceFile(.{ .file = b.path("src/stb/stb_image_resize.c") });
    exe_mod.addCSourceFile(.{ .file = b.path("src/stb/stb_image_write.c") });
    exe_mod.addIncludePath(b.path("src/pdf"));
    exe_mod.addIncludePath(b.path("src/stb"));
    exe_mod.addIncludePath(b.path("src/miniz"));

    // Add miniz as a C source file (no extra flags needed)
    exe_mod.addCSourceFile(.{ .file = b.path("src/miniz/miniz.c") });

    const exe = b.addExecutable(.{
        .name = "fj",
        .root_module = exe_mod,
    });

    // 3rd party deps:
    //
    const zli = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zli", zli.module("zli"));

    // Make build.zig.zon accessible in module
    var my_options = std.Build.Step.Options.create(b);
    my_options.addOption([]const u8, "contents", build_zig_zon);
    exe.root_module.addOptions("build.zig.zon", my_options);

    const zeit = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zeit", zeit.module("zeit"));

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false, // set to true to enable TLS support
    });

    exe.root_module.addImport("zap", zap.module("zap"));
    //
    // End of 3rd party deps

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
