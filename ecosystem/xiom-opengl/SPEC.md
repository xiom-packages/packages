# xiom-opengl — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: SPEC layer implemented (v0.1.0) — C bridge pending
**Depends on**: xiom.ffi (stdlib), xiom-glfw (window creation)
**Platform**: Cross-platform (Windows, Linux, macOS)

## What it wraps
OpenGL 4.6 — cross-platform graphics API.
Legacy support for Linux/macOS, embedded systems (OpenGL ES), WebGL transpilation target.
Used alongside Vulkan for compatibility fallback.

## Dependencies

| What | How | Size |
|------|-----|------|
| OpenGL | System-installed. GPU drivers include it. Windows: `opengl32.lib`. Linux: `libGL.so`. | — |
| GLAD or GLEW | Extension loader. **Bundle glad.c** (single file, 500KB). | ~500KB |
| C compiler | For building bridge | — |

## Bundling strategy
**OpenGL is system-installed** (part of GPU drivers). Extension loader (glad) is **bundled** as a single .c file (tiny). GLFW provides the window context (via xiom-glfw).

## API surface

```xiom
module xiom.opengl

// Context
pub fn gl_create_context(win: Window, major: Int, minor: Int) -> Result[GLContext, Str]
pub fn gl_make_current(ctx: &GLContext)
pub fn gl_swap_buffers(win: Window)

// Shaders
pub fn gl_create_shader(typ: Int) -> Result[Shader, Str]
pub fn gl_shader_source(shader: Shader, source: Str)
pub fn gl_compile_shader(shader: Shader) -> Result[Unit, Str]
pub fn gl_create_program() -> Result[Program, Str]
pub fn gl_attach_shader(prog: Program, shader: Shader)
pub fn gl_link_program(prog: Program) -> Result[Unit, Str]
pub fn gl_use_program(prog: Program)

// Buffers
pub fn gl_gen_vertex_array() -> Result[VAO, Str]
pub fn gl_bind_vertex_array(vao: VAO)
pub fn gl_gen_buffer() -> Result[Buffer, Str]
pub fn gl_bind_buffer(target: Int, buf: Buffer)
pub fn gl_buffer_data(target: Int, data: &Vec[Float32], usage: Int)

// Drawing
pub fn gl_clear(r: Float32, g: Float32, b: Float32, a: Float32)
pub fn gl_clear_color(r: Float32, g: Float32, b: Float32, a: Float32)
pub fn gl_draw_arrays(mode: Int, first: Int, count: Int)
pub fn gl_draw_elements(mode: Int, count: Int, typ: Int, offset: Int)
pub fn gl_viewport(x: Int, y: Int, w: Int, h: Int)

// Textures
pub fn gl_gen_texture() -> Result[Texture, Str]
pub fn gl_bind_texture(target: Int, tex: Texture)
pub fn gl_tex_image2d(target: Int, level: Int, internal_fmt: Int, w: Int, h: Int, fmt: Int, typ: Int, data: &Vec[UInt8])

// Uniforms
pub fn gl_uniform1i(location: Int, val: Int)
pub fn gl_uniform1f(location: Int, val: Float32)
pub fn gl_uniform_matrix4fv(location: Int, count: Int, transpose: Bool, data: &Vec[Float32])
pub fn gl_get_uniform_location(prog: Program, name: Str) -> Int
```

## Contract coverage target
- Shader compilation: `Result` with info log on failure
- Program linking: `Result` with info log
- Buffer size: `requires: data.len() > 0`
- Context: `requires: ctx != 0`

## Implementation Status

| File | Lines | Description |
|------|-------|-------------|
| `opengl.xi` | 354 | Types (5), GLenum constants (100+), extern "C" block (36 fns), safe wrappers (30 fns) |
| `tests/test_conformance.xi` | 393 | 54 test functions across 17 sections covering types, constants, stub behavior |
| `ROADMAP.md` | 87 | Detailed implementation roadmap with checkpoints |
| `SPEC.md` | this | Updated specification |

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | SPEC phase: Full API surface, contracts, constants, stub tests | Weekend | **DONE** |
| 2 | C bridge: Link glad loader, implement extern functions, context via GLFW | Weekend | TODO |
| 3 | Hello Triangle: End-to-end VAO/VBO/shader/program/draw | 1 day | TODO |
| 4 | Textures, uniforms, framebuffers, depth/stencil | Weekend | TODO |
| 5 | Compute shaders, instancing, multi-pass, OpenGL ES 3.0 | Weekend | TODO |

## Relationship to other packages
- `xiom-glfw`: Creates the window and OpenGL context.
- `xiom-vulkan`: Vulkan is the modern alternative. OpenGL is for compatibility.
- `xiom-directx11/12`: Windows-only alternatives.
