# FPS

A minimal first-person shooter in Zig. 227 lines. No dependencies beyond Sokol.

## What It Does

- Bitpacked voxel world (16³ blocks in 512 bytes)
- WASD movement with mouse look
- Physics: gravity, jumping, collision
- Mesh generation with face culling
- Crosshair rendering

## How It Works

The world is a single array of bits. Each bit represents a voxel. Collision detection samples the bitfield directly. Mesh generation creates faces only where needed.

```zig
const World = struct {
    blocks: [WORLD_SIZE * WORLD_SIZE * WORLD_SIZE / 8]u8,
    
    fn get(w: *const World, x: i32, y: i32, z: i32) bool {
        // Bit manipulation to check if voxel exists
    }
    
    fn collision(w: *const World, aabb: AABB) bool {
        // Direct sampling of voxel grid
    }
    
    fn mesh(w: *const World) MeshData {
        // Generate triangles for visible faces only
    }
};
```

## Running

```bash
zig build run
```

Requires Zig 0.15.2 or later.

## Controls

- **WASD**: Move
- **Mouse**: Look around  
- **Space**: Jump
- **Click**: Capture mouse
- **Escape**: Release mouse

## Architecture

The player is an AABB that moves through the world one axis at a time. Collision reverts position on contact. Mesh generation iterates every voxel and emits quads for exposed faces.