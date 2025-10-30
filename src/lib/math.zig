// Math utilities for TinyCode FPS
const std = @import("std");

pub const Vec3 = struct {
    data: @Vector(3, f32),
    pub inline fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .data = .{ x, y, z } };
    }
    pub inline fn zero() Vec3 {
        return .{ .data = @splat(0) };
    }
    pub inline fn add(v: Vec3, o: Vec3) Vec3 {
        return .{ .data = v.data + o.data };
    }
    pub inline fn sub(v: Vec3, o: Vec3) Vec3 {
        return .{ .data = v.data - o.data };
    }
    pub inline fn scale(v: Vec3, s: f32) Vec3 {
        return .{ .data = v.data * @as(@Vector(3, f32), @splat(s)) };
    }
    pub inline fn dot(v: Vec3, o: Vec3) f32 {
        return @reduce(.Add, v.data * o.data);
    }
    pub inline fn length(v: Vec3) f32 {
        return @sqrt(v.dot(v));
    }
    pub inline fn normalize(v: Vec3) Vec3 {
        const l = v.length();
        return if (l > 0) v.scale(1.0 / l) else v;
    }
    pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
        return Vec3.new(a.data[1] * b.data[2] - a.data[2] * b.data[1], a.data[2] * b.data[0] - a.data[0] * b.data[2], a.data[0] * b.data[1] - a.data[1] * b.data[0]);
    }
};

pub const Mat4 = struct {
    data: [16]f32,
    pub inline fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        inline for (0..4) |c| {
            inline for (0..4) |row| {
                var s: f32 = 0;
                inline for (0..4) |k| s += a.data[k * 4 + row] * b.data[c * 4 + k];
                r.data[c * 4 + row] = s;
            }
        }
        return r;
    }
    pub inline fn mulVec(m: Mat4, v: Vec3) @Vector(4, f32) {
        const x = m.data[0] * v.data[0] + m.data[4] * v.data[1] + m.data[8] * v.data[2] + m.data[12];
        const y = m.data[1] * v.data[0] + m.data[5] * v.data[1] + m.data[9] * v.data[2] + m.data[13];
        const z = m.data[2] * v.data[0] + m.data[6] * v.data[1] + m.data[10] * v.data[2] + m.data[14];
        const w = m.data[3] * v.data[0] + m.data[7] * v.data[1] + m.data[11] * v.data[2] + m.data[15];
        return .{ x, y, z, w };
    }
};

pub inline fn perspective(fov: f32, asp: f32, n: f32, f: f32) Mat4 {
    const t = @tan(fov * std.math.pi / 360) * n;
    const r = t * asp;
    return .{ .data = .{ n / r, 0, 0, 0, 0, n / t, 0, 0, 0, 0, -(f + n) / (f - n), -1, 0, 0, -(2 * f * n) / (f - n), 0 } };
}
