# xiom.opengl -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- bridge resolves opengl32/user32/gdi32 |
| G2 pin (soname + symbol set + PFD/attribs) | Done -- `SPEC.md` §2 |
| Staged classic probe + classification | Done -- ABSENT/NO_CONTEXT -> SKIP, ABI -> FAIL |
| Contextless safety check | Done |
| Core-profile probe (version negotiation) | Done -- 0.3.0 (`wglCreateContextAttribsARB`) |
| Extension loading (`wglGetProcAddress`) + scan | Done -- 0.3.0 (`glGetStringi`, exact-match) |
| Session-based modern function table | Next |
| `opengl32sw.dll` (Mesa) fallback | Phase 2 |
| POSIX / EGL path | Phase 2 |

## Phase 2 (remaining)

1. **Session API**: `opengl_session_open(soname, major, minor)` keeps the
   window + context + libraries alive and exposes
   `opengl_session_get_proc(name) -> Int` (valid while the session lives) so
   consumers can call modern GL entry points through fn-pointer casts; plus
   `opengl_session_close`. This is the "modern GL function table" seam.
2. Harden the extension scan: binary-search over sorted names (the GL spec
   does not guarantee order) or expose `opengl_extension_at(index)` so
   consumers can build their own lookup; keep `opengl_has_extension` as the
   convenience path.
3. Loader fallback to `opengl32sw.dll` (Mesa llvmpipe) for headless hosts
   before returning NO_CONTEXT, so more CI machines get the string stage.
4. POSIX path: `libGL.so.1`/EGL behind the same classification API when a
   Linux CI target exists.
5. Re-evaluate the C bridge vs a pure-XIOM implementation at the next
   compiler pin (B-09 is fixed at v0.64.1; the bridge stays until the
   session API lands).
