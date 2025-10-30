const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const simgui = sokol.imgui;
const ig = @import("cimgui");
const math = @import("lib/math.zig");
const shader = @import("shader/cube.glsl.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const Vertex = extern struct { pos: [3]f32, col: [4]f32 };
const WORLD_SIZE = 16;
const AABB = struct { min: Vec3, max: Vec3 };

const Player = struct {
    pos: Vec3 = Vec3.new(2, 3, 2),
    vel: Vec3 = Vec3.zero(),
    yaw: f32 = 0,
    pitch: f32 = 0,
    on_ground: bool = false,
    mouse_dx: f32 = 0,
    mouse_dy: f32 = 0,
    keys: packed struct { w: bool = false, a: bool = false, s: bool = false, d: bool = false, space: bool = false } = .{},

    fn bbox(p: *const Player) AABB {
        const hull = Vec3.new(0.4, 0.8, 0.4);
        return .{ .min = Vec3.sub(p.pos, hull), .max = Vec3.add(p.pos, hull) };
    }

    fn update(p: *Player, w: *const World, dt: f32) void {
        p.yaw += p.mouse_dx * 0.002;
        p.pitch = std.math.clamp(p.pitch + p.mouse_dy * 0.002, -1.5, 1.5);
        p.mouse_dx = 0;
        p.mouse_dy = 0;

        const sy, const cy = .{ @sin(p.yaw), @cos(p.yaw) };
        const fw: f32 = if (p.keys.w) 1.0 else if (p.keys.s) -1.0 else 0.0;
        const st: f32 = if (p.keys.d) 1.0 else if (p.keys.a) -1.0 else 0.0;

        p.vel = Vec3.new((sy * fw + cy * st) * 6.0, p.vel.data[1] - 15.0 * dt, (-cy * fw + sy * st) * 6.0);
        if (p.keys.space and p.on_ground) p.vel.data[1] = 8.0;

        const old = p.pos;
        inline for (.{ 0, 2, 1 }) |axis| {
            p.pos.data[axis] += p.vel.data[axis] * dt;
            if (w.collision(p.bbox())) {
                p.pos.data[axis] = old.data[axis];
                if (axis == 1) {
                    if (p.vel.data[1] <= 0) p.on_ground = true;
                    p.vel.data[1] = 0;
                }
            } else if (axis == 1) p.on_ground = false;
        }

        if (p.pos.data[1] < 1.0) {
            p.pos.data[1] = 1.0;
            p.vel.data[1] = 0;
            p.on_ground = true;
        }
    }

    fn view(p: *const Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -p.pos.data[0] * cy - p.pos.data[2] * sy, -p.pos.data[0] * sy * sp - p.pos.data[1] * cp + p.pos.data[2] * cy * sp, p.pos.data[0] * sy * cp - p.pos.data[1] * sp - p.pos.data[2] * cy * cp, 1 } };
    }
};

const World = struct {
    blocks: [WORLD_SIZE * WORLD_SIZE * WORLD_SIZE / 8]u8 = std.mem.zeroes([WORLD_SIZE * WORLD_SIZE * WORLD_SIZE / 8]u8),

    fn init() World {
        var w = World{};
        for (0..WORLD_SIZE) |x| for (0..WORLD_SIZE) |y| for (0..WORLD_SIZE) |z| {
            if (y == 0 or x == 0 or x == WORLD_SIZE - 1 or z == 0 or z == WORLD_SIZE - 1 or (x % 4 == 0 and z % 4 == 0 and y < 3)) {
                const idx = x + y * WORLD_SIZE + z * WORLD_SIZE * WORLD_SIZE;
                w.blocks[idx / 8] |= @as(u8, 1) << @intCast(idx % 8);
            }
        };
        return w;
    }

    fn get(w: *const World, x: i32, y: i32, z: i32) bool {
        if (@as(u32, @bitCast(x)) >= WORLD_SIZE or @as(u32, @bitCast(y)) >= WORLD_SIZE or @as(u32, @bitCast(z)) >= WORLD_SIZE) return false;
        const idx = @as(usize, @intCast(x)) + @as(usize, @intCast(y)) * WORLD_SIZE + @as(usize, @intCast(z)) * WORLD_SIZE * WORLD_SIZE;
        return (w.blocks[idx / 8] & (@as(u8, 1) << @intCast(idx % 8))) != 0;
    }

    fn collision(w: *const World, aabb: AABB) bool {
        const bounds = [3][2]i32{
            .{ @max(0, @as(i32, @intFromFloat(@floor(aabb.min.data[0])))), @min(WORLD_SIZE - 1, @as(i32, @intFromFloat(@floor(aabb.max.data[0])))) },
            .{ @max(0, @as(i32, @intFromFloat(@floor(aabb.min.data[1])))), @min(WORLD_SIZE - 1, @as(i32, @intFromFloat(@floor(aabb.max.data[1])))) },
            .{ @max(0, @as(i32, @intFromFloat(@floor(aabb.min.data[2])))), @min(WORLD_SIZE - 1, @as(i32, @intFromFloat(@floor(aabb.max.data[2])))) },
        };
        for (@intCast(bounds[0][0])..@intCast(bounds[0][1] + 1)) |x| {
            for (@intCast(bounds[1][0])..@intCast(bounds[1][1] + 1)) |y| {
                for (@intCast(bounds[2][0])..@intCast(bounds[2][1] + 1)) |z| {
                    if (w.get(@intCast(x), @intCast(y), @intCast(z))) return true;
                }
            }
        }
        return false;
    }

    fn mesh(w: *const World) struct { pipeline: sg.Pipeline, bindings: sg.Bindings, pass_action: sg.PassAction, vertex_count: u32 } {
        var vertices: [32768]Vertex = undefined;
        var indices: [49152]u16 = undefined;
        var vert_count: usize = 0;
        var idx_count: usize = 0;

        const dirs = [_][3]i32{ .{ 1, 0, 0 }, .{ -1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, -1, 0 }, .{ 0, 0, 1 }, .{ 0, 0, -1 } };
        const quads = [_][4][3]f32{ .{ .{ 1, 0, 0 }, .{ 1, 0, 1 }, .{ 1, 1, 1 }, .{ 1, 1, 0 } }, .{ .{ 0, 0, 1 }, .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 1, 1 } }, .{ .{ 0, 1, 0 }, .{ 1, 1, 0 }, .{ 1, 1, 1 }, .{ 0, 1, 1 } }, .{ .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 0, 0 }, .{ 0, 0, 0 } }, .{ .{ 1, 0, 1 }, .{ 0, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } }, .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 } } };
        const colors = [_][4]f32{ .{ 0.8, 0.3, 0.3, 1.0 }, .{ 0.3, 0.8, 0.3, 1.0 }, .{ 0.6, 0.6, 0.6, 1.0 }, .{ 0.4, 0.4, 0.4, 1.0 }, .{ 0.3, 0.3, 0.8, 1.0 }, .{ 0.8, 0.8, 0.3, 1.0 } };

        for (0..WORLD_SIZE) |x| for (0..WORLD_SIZE) |y| for (0..WORLD_SIZE) |z| {
            if (!w.get(@intCast(x), @intCast(y), @intCast(z))) continue;
            const pos = @Vector(3, f32){ @floatFromInt(x), @floatFromInt(y), @floatFromInt(z) };

            for (dirs, quads, colors) |dir, quad, color| {
                if (!w.get(@as(i32, @intCast(x)) + dir[0], @as(i32, @intCast(y)) + dir[1], @as(i32, @intCast(z)) + dir[2])) {
                    if (vert_count + 4 > vertices.len or idx_count + 6 > indices.len) break;
                    const base_idx = @as(u16, @intCast(vert_count));

                    for (quad) |v| {
                        vertices[vert_count] = .{ .pos = pos + v, .col = color };
                        vert_count += 1;
                    }

                    for ([_]u16{ 0, 1, 2, 0, 2, 3 }) |idx| {
                        indices[idx_count] = base_idx + idx;
                        idx_count += 1;
                    }
                }
            }
        };

        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;

        return .{ .pipeline = sg.makePipeline(.{ .shader = sg.makeShader(shader.cubeShaderDesc(sg.queryBackend())), .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK }), .bindings = .{ .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(vertices[0..vert_count]) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} }, .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(indices[0..idx_count]) }) }, .pass_action = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } }, .vertex_count = @intCast(idx_count) };
    }
};

var world: World = undefined;
var player = Player{};
var pipeline: sg.Pipeline = undefined;
var bindings: sg.Bindings = undefined;
var pass_action: sg.PassAction = undefined;
var vertex_count: u32 = undefined;
var proj: Mat4 = undefined;
var mouse_locked = false;

export fn init() void {
    sg.setup(.{ .environment = sokol.glue.environment() });
    simgui.setup(.{});
    world = World.init();
    const mesh = world.mesh();
    pipeline = mesh.pipeline;
    bindings = mesh.bindings;
    pass_action = mesh.pass_action;
    vertex_count = mesh.vertex_count;
    proj = math.perspective(90, 1.33, 0.1, 100);
}

export fn frame() void {
    player.update(&world, @floatCast(sapp.frameDuration()));
    simgui.newFrame(.{ .width = sapp.width(), .height = sapp.height(), .delta_time = sapp.frameDuration() });

    const mvp = Mat4.mul(proj, player.view());
    sg.beginPass(.{ .action = pass_action, .swapchain = sokol.glue.swapchain() });
    sg.applyPipeline(pipeline);
    sg.applyBindings(bindings);
    sg.applyUniforms(0, sg.asRange(&mvp));
    sg.draw(0, vertex_count, 1);

    const cx, const cy = .{ @as(f32, @floatFromInt(sapp.width())) * 0.5, @as(f32, @floatFromInt(sapp.height())) * 0.5 };
    ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
    ig.igSetNextWindowSize(.{ .x = @floatFromInt(sapp.width()), .y = @floatFromInt(sapp.height()) }, ig.ImGuiCond_Always);
    _ = ig.igBegin("##crosshair", null, ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs);
    const draw_list = ig.igGetWindowDrawList();
    ig.ImDrawList_AddLine(draw_list, .{ .x = cx - 10, .y = cy }, .{ .x = cx + 10, .y = cy }, 0xFFFFFFFF);
    ig.ImDrawList_AddLine(draw_list, .{ .x = cx, .y = cy - 10 }, .{ .x = cx, .y = cy + 10 }, 0xFFFFFFFF);
    ig.igEnd();
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();
}

export fn event(e: [*c]const sapp.Event) void {
    _ = simgui.handleEvent(e.*);
    const state = e.*.type == .KEY_DOWN;
    switch (e.*.type) {
        .KEY_DOWN, .KEY_UP => switch (e.*.key_code) {
            .W => player.keys.w = state,
            .A => player.keys.a = state,
            .S => player.keys.s = state,
            .D => player.keys.d = state,
            .SPACE => player.keys.space = state,
            .ESCAPE => if (state and mouse_locked) {
                mouse_locked = false;
                sapp.showMouse(true);
                sapp.lockMouse(false);
            },
            else => {},
        },
        .MOUSE_DOWN => if (e.*.mouse_button == .LEFT and !mouse_locked) {
            mouse_locked = true;
            sapp.showMouse(false);
            sapp.lockMouse(true);
        },
        .MOUSE_MOVE => if (mouse_locked) {
            player.mouse_dx += e.*.mouse_dx;
            player.mouse_dy += e.*.mouse_dy;
        },
        else => {},
    }
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .event_cb = event, .width = 800, .height = 600, .window_title = "Simple Educational FPS" });
}
