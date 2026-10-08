# xiom.opengl -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.0 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- bridge resolves opengl32/user32/gdi32 |
| G2 pin (soname + symbol set + PFD layout) | Done -- `SPEC.md` §2 |
| Staged probe + classification | Done -- ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL |
| Suite | Done -- 8/8 x2 on a GPU host + deterministic SKIP test |
| Extension loading (`wglGetProcAddress`) | Phase 2 |
| Context attributes/versions | Phase 2 |
| Modern GL function table | Phase 2 |
| POSIX / EGL path | Phase 2 |

## Phase 2 (next touches)

1. Extension loading: resolve `wglGetProcAddress` in the bridge and expose a
   `gl_proc_address(name)`-style API; build a lazily-populated function table
   for GL 2.0+ entry points (shader/buffer/VAO/texture calls).
2. Context control: `wglCreateContextAttribsARB` (core profile, version
   request, debug flag) with a fallback to the classic path; report the
   negotiated version.
3. Capability report: `glGetString(GL_EXTENSIONS)`/`GL_NUM_EXTENSIONS` +
   `glGetStringi` for GL 3.0+, and `GL_MAX_TEXTURE_SIZE`-class limits.
4. POSIX path: `libGL.so.1`/EGL (`eglGetDisplay`/`eglCreateContext`) behind
   the same classification API when a Linux CI target exists.
5. Loader fallback to `opengl32sw.dll` (Mesa llvmpipe) for headless hosts
   before returning NO_CONTEXT, so more CI machines get the string stage.
6. Re-test the pure-XIOM context shape at the next compiler pin (finding
   B-09); drop the bridge only if the shape becomes reliable.
