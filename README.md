# Simple Educational FPS

A simple fps base in 227 lines of Zig.

## What It Is

- First-person movement with physics and collision.

Player movement uses axis-separated collision detection. 
Audio is synthesized in real-time.

## Running

```bash
zig build run
```

Requires Zig 0.15.2+

## Controls

- **WASD**: Move
- **Mouse**: Look around  
- **Space**: Jump (with audio)
- **Click**: Capture mouse
- **Escape**: Release mouse
