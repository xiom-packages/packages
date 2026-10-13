# xiom.opengl -- Roadmap

**Version**: v0.5.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- bridge resolves opengl32/user32/gdi32 |
| G2 pin (soname + symbol set + PFD/attribs) | Done -- `SPEC.md` sec. 2 |
| Staged classic probe + classification | Done -- ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL |
| Contextless safety check | Done |
| Core-profile probe (version negotiation) | Done -- 0.3.0 (`wglCreateContextAttribsARB`) |
| Extension loading (`wglGetProcAddress`) + scan | Done -- 0.3.0 (`glGetStringi`, exact-match) |
| Full core-4.6 surface (generated) | Done -- 0.4.0 (656 commands + 1358 consts from the pinned registry; 656/656 resolved live) |
| Session-based modern function table | Done -- 0.4.0 (`opengl_session_open`; wrappers resolve per call) |
| Full WGL surface (generated) | Done -- 0.5.0 (146 commands + 298 consts from the pinned `wgl.xml`; 24/24 resolvable core-1.0 commands live; session dc/hglrc handles) |
| `opengl32sw.dll` (Mesa) fallback | Phase 2 |
| GLES/EGL (ANGLE) path | Phase 2 (next wave) |

## Phase 2 (remaining)

1. ~~Session API~~ Done in 0.4.0; the raw HDC/HGLRC accessors landed in
   0.5.0 (`opengl_session_dc`/`opengl_session_hglrc`).
2. Harden the extension scan: binary-search over sorted names (the GL spec
   does not guarantee order) or expose `opengl_extension_at(index)` so
   consumers can build their own lookup; keep `opengl_has_extension` as the
   convenience path.
3. Loader fallback to `opengl32sw.dll` (Mesa llvmpipe) for headless hosts
   before returning NO_CONTEXT, so more CI machines get the string stage.
4. GLES/EGL via ANGLE: runtime `libEGL.dll`/`libGLESv2.dll` +
   `eglGetProcAddress`; GLES2/GLES3 surfaces generated from the same pinned
   registry (`api/GLES2`, `api/GLES3`), the EGL surface from the Khronos
   EGL-Registry (clone + pin pending per the upstream-first policy).  POSIX
   loading stays behind the same classification API when a Linux CI target
   exists.
5. Re-evaluate the C bridge vs a pure-XIOM implementation at the next
   compiler pin (B-09 is fixed at v0.64.1; the bridge stays until the
   GLES/EGL wave lands).
