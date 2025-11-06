const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");
const cimgui = @import("cimgui");

const Opts = struct { mod: *Build.Module, dep_sokol: *Build.Dependency, dep_cimgui: *Build.Dependency, cimgui_clib_name: []const u8, shader: *Build.Step };

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cimgui_conf = cimgui.getConfig(false);

    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize, .with_sokol_imgui = true });
    const dep_cimgui = b.dependency("cimgui", .{ .target = target, .optimize = optimize });
    const shdc = b.dependency("shdc", .{});

    dep_sokol.artifact("sokol_clib").addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    const shader = try @import("shdc").createSourceFile(b, .{ .shdc_dep = shdc, .input = "src/shader/cube.glsl", .output = "src/shader/cube.glsl.zig", .slang = .{ .glsl410 = true, .glsl300es = true, .metal_macos = true, .wgsl = true } });

    const mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "sokol", .module = dep_sokol.module("sokol") },
        .{ .name = cimgui_conf.module_name, .module = dep_cimgui.module(cimgui_conf.module_name) },
    } });

    const opts = Opts{ .mod = mod, .dep_sokol = dep_sokol, .dep_cimgui = dep_cimgui, .cimgui_clib_name = cimgui_conf.clib_name, .shader = shader };

    if (target.result.cpu.arch.isWasm()) try buildWeb(b, opts) else try buildNative(b, opts);
}

fn buildNative(b: *Build, opts: Opts) !void {
    const exe = b.addExecutable(.{ .name = "fps", .root_module = opts.mod });
    exe.step.dependOn(opts.shader);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run fps").dependOn(&run.step);
}

fn buildWeb(b: *Build, opts: Opts) !void {
    const lib = b.addLibrary(.{ .name = "fps", .root_module = opts.mod });
    lib.step.dependOn(opts.shader);

    const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
    const emsdk_incl_path = emsdk.path("upstream/emscripten/cache/sysroot/include");
    opts.dep_cimgui.artifact(opts.cimgui_clib_name).addSystemIncludePath(emsdk_incl_path);
    opts.dep_cimgui.artifact(opts.cimgui_clib_name).step.dependOn(&opts.dep_sokol.artifact("sokol_clib").step);

    const link_step = try sokol.emLinkStep(b, .{ .lib_main = lib, .target = opts.mod.resolved_target.?, .optimize = opts.mod.optimize.?, .emsdk = emsdk, .use_webgl2 = true, .use_emmalloc = false, .use_filesystem = true, .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"), .extra_args = &.{ "-sEXPORTED_RUNTIME_METHODS=['FS']", "-sEXPORTED_FUNCTIONS=['_main']", "-sFORCE_FILESYSTEM=1" } });
    b.getInstallStep().dependOn(&link_step.step);

    const run = sokol.emRunStep(b, .{ .name = "fps", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run fps").dependOn(&run.step);
}
