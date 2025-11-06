@header const math = @import("../lib/math.zig")
@ctype mat4 math.Mat4

@vs vs
layout(binding = 0) uniform vs_params { mat4 mvp; };
in vec4 position; in vec4 color0;
out vec4 color; out vec3 world_pos;
void main() {
    gl_Position = mvp * position;
    world_pos = position.xyz;
    color = color0;
}
@end

@fs fs
in vec4 color; in vec3 world_pos;
out vec4 frag_color;

void main() {
    vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
    
    // Get UV coordinates for the current face
    vec2 uv = (abs(n.x) > 0.5) ? world_pos.yz : (abs(n.y) > 0.5) ? world_pos.xz : world_pos.xy;
    
    // Create thick sharp voxel outline
    vec2 grid = fract(uv);
    float outline = min(min(grid.x, 1.0 - grid.x), min(grid.y, 1.0 - grid.y));
    float edge = smoothstep(0.05, 0.06, outline);
    
    // Simple lighting from above
    float light = dot(n, vec3(0.0, -1.0, 0.0)) * 0.4 + 0.6;
    
    frag_color = vec4(color.rgb * edge * light, color.a);
}
@end

@program cube vs fs
