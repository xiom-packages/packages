# xiom.opengl -- ROADMAP

**Phase 2 (Scientific)** | **Priority: HIGH**
**Depends on**: xiom.ffi (stdlib), xiom.glfw (window creation)
**Platform**: Cross-platform (Windows, Linux, macOS)

## Current Status: SPEC Implementation (v0.1.0)

The package currently contains a full XIOM specification layer:
- All 5 type definitions (GlShader, GlProgram, GlBuffer, GlVao, GlTexture)
- All 100+ GLenum constants (shader types, buffer targets, draw modes, texture formats, etc.)
- 36 extern "C" raw OpenGL 4.6 Core Profile function declarations
- 30 safe wrapper functions with requires contracts
- 54 conformance tests (25+ test functions) covering types, constants, and stub behavior

All FFI calls return `Err(...)` or stub defaults -- no C bridge is linked yet.

## Phased Roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | **SPEC phase** -- Full API surface, contracts, constants, stub tests | Weekend | **DONE** |
| 2 | **C bridge** -- Link glad loader, implement extern functions, context creation via GLFW | Weekend | TODO |
| 3 | **Hello Triangle** -- End-to-end VAO/VBO/shader/program/draw pipeline integration test | 1 day | TODO |
| 4 | **Textures & Uniforms** -- Texture loading, uniform management, matrix passing | Weekend | TODO |
| 5 | **Framebuffers & Depth/Stencil** -- Render-to-texture, depth testing, stencil ops | Weekend | TODO |
| 6 | **Compute Shaders** -- Compute pipeline, SSBO, image load/store | Weekend | TODO |
| 7 | **Instancing & Multi-pass** -- Draw instanced, render passes, blending modes | Weekend | TODO |
| 8 | **OpenGL ES 3.0** -- Mobile/WebGL compatibility layer | Weekend | TODO |

## Phase 2 (C Bridge) Checkpoints

- [ ] Create `glad.c` bundling (single-file extension loader, ~500KB)
- [ ] Create `opengl_bridge.c` with extern "C" wrappers for the 36 OpenGL functions
- [ ] Implement context creation via GLFW bridge (`glfw_bridge_*` in xiom.glfw)
- [ ] Wire up shader compilation with info log retrieval
- [ ] Wire up program linking with info log retrieval
- [ ] Wire up buffer, VAO, texture generation
- [ ] Implement `gl_get_error()` relay

## Phase 3 (Hello Triangle) Checkpoints

- [ ] Load GLAD via bridge init
- [ ] Create window via xiom.glfw
- [ ] Compile vertex + fragment shaders
- [ ] Link program
- [ ] Create VAO + VBO with triangle vertices
- [ ] Draw and swap buffers
- [ ] Screenshot verification

## Contract Coverage

- Shader compilation: `Result` with info log on failure
- Program linking: `Result` with info log
- Buffer size: `requires: data.len() > 0`
- Context: `requires: ctx != 0`
- Shader type validation: `requires: typ` must be valid enum
- Buffer target validation: `requires: target` must be valid enum
- Uniform location: `requires: location >= 0`
- Texture dimensions: `requires: w > 0 && h > 0`
- Viewport dimensions: `requires: w >= 0 && h >= 0`
- Color component range: `requires: r/g/b/a >= 0.0 && <= 1.0`

## File Inventory

| File | Lines | Description |
|------|-------|-------------|
| `opengl.xi` | 350+ | Main module: types, constants, extern block, safe wrappers |
| `tests/test_conformance.xi` | 390+ | 54 unit tests across 17 sections |
| `SPEC.md` | 86 | Original specification (Phase 2) |
| `ROADMAP.md` | this | Implementation roadmap and checkpoints |
