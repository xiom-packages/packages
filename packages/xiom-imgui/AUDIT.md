# AUDIT: xiom.imgui

## Status (2026-10-09)

Vendored-C++ implementation at 0.2.0. The pre-pilot tree (a 90-extern
surface with precompiled bridge objects, GLFW + Vulkan backends, and a
demo) is preserved in git history only; it required the Vulkan SDK and
prebuilt `.obj` files at build time, which breaks the binding gate. The
0.2.0 probe is headless and SDK-free.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | Dear ImGui v1.92.9b (tag), vendored unmodified (MIT) |
| Link model | `--c-source` (4 core sources + bridge via `port.args.json`) |
| FFI confinement | all `unsafe`/`extern` in the root module `imgui.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 4 checks (real headless frames) |
| Runs | 4/4 on the pin (see the session relay for the recorded matrix) |

## Design notes

- **Headless probe**: upstream's null backends (`imgui_impl_null`) plus two
  `NewFrame`/`Begin`/`Text`/`End`/`Render` cycles; the second frame's
  `ImDrawData` stats are reported (ImGui hides a newly created window on its
  first frame). No platform or renderer backend, so the suite runs on any CI
  machine.
- **Flat vendor layout**: every core include is same-directory quoted; no
  `-I` passthrough needed and the vendored bytes stay unmodified (per-file
  SHA256 table in `SPEC.md` §2).
- Integer-only bridge ABI (same pattern as `xiom.box2d`): floats and
  ImVec2/ImDrawData stay inside the bridge; counts cross as C `int`s.
- Out-param slots are XIOM-owned `Vec[UInt8]` buffers (no malloc/free;
  finding B-05).
- Compiles under the link line's default C++ standard (C++14): the vendored
  core is C++11-compatible. (Larger C++17 libraries need the standard-flag
  passthrough request recorded in the session ledger -- see `xiom.jolt`.)

## Known limitations

- Pilot scope: version + frame lifecycle + tessellation stats; widget
  wrappers and backends are Phase 2 (`ROADMAP.md`).
- The probe creates and destroys a fresh context per call -- sufficient for
  assertions, not a long-lived UI loop (Phase 2 will own a context handle).
- Windows x64 primary; the vendored path is portable, no other platform has
  been run yet.
