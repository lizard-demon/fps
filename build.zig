const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target, const optimize = .{ b.standardTargetOptions(.{}), b.standardOptimizeOption(.{}) };

    // Dependencies
    const sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize, .with_sokol_imgui = true });
    const cimgui = b.dependency("cimgui", .{ .target = target, .optimize = optimize });
    const shdc = b.dependency("shdc", .{});

    // Bind ImGui to Sokol
    sokol.artifact("sokol_clib").addIncludePath(cimgui.path(@import("cimgui").getConfig(false).include_dir));

    // Shader compilation
    const shader = try @import("shdc").createSourceFile(b, .{ .shdc_dep = shdc, .input = "src/shader/cube.glsl", .output = "src/shader/cube.glsl.zig", .slang = .{ .glsl410 = true, .glsl300es = true, .metal_macos = true, .wgsl = true } });

    // The executable
    const exe = b.addExecutable(.{
        .name = "fps",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("sokol", sokol.module("sokol"));
    exe.root_module.addImport("cimgui", cimgui.module("cimgui"));
    exe.step.dependOn(shader);

    b.installArtifact(exe);

    // Run the code
    const run = b.step("run", "Launch the ultraminimal FPS experience");
    run.dependOn(&b.addRunArtifact(exe).step);
}
