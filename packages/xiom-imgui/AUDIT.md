# AUDIT: xiom.imgui

## Status (2026-10-27)

Vendored-C++ implementation at 0.4.0. The pre-pilot tree (a 90-extern
surface with precompiled bridge objects, GLFW + Vulkan backends, and a
demo) is preserved in git history only; it required prebuilt `.obj` files
at build time, which breaks the binding gate. The 0.4.0 turn-vendors the
upstream SDL3 + Vulkan backends together with their SDK headers and import
libs, so the package is self-contained at build time (runtime needs
`SDL3.dll` / `vulkan-1.dll`).

| Item | State |
|------|-------|
| Compiler | xiom v0.65.2 |
| Upstream | Dear ImGui v1.92.9b (tag), vendored unmodified (MIT) |
| SDK | Vulkan SDK 1.4.350.0 (SDL3 3.4.8 headers + SDL3.lib; Vulkan-Headers 1.4.350 + vulkan-1.lib) |
| Link model | `--c-source` (4 core + SDL3/Vulkan/null backends + bridge) + `--link-path vendor/lib --link SDL3 --link vulkan-1` |
| FFI confinement | all `unsafe`/`extern` in the root module `imgui.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 11 checks (headless frames, contexts, real SDL3 backend, backend guards) |
| Runs | **11/11 x2** on the pin (`scripts/port.ps1`) |

## Design notes

- **Headless probe**: upstream's null backends (`imgui_impl_null`) plus two
  `NewFrame`/`Begin`/`Text`/`End`/`Render` cycles; the second frame's
  `ImDrawData` stats are reported (ImGui hides a newly created window on its
  first frame). No platform or renderer backend, so the suite runs on any CI
  machine.
- **Long-lived context handles (0.3.0)**: a 4-slot registry of
  `ImGuiContext*` with 1-based handles; create/frame/destroy cross as ints
  and window state persists across separate XIOM calls (frames 4/5 of the
  settled window are identical). Two gotchas: `ImGui::CreateContext`
  returns the new context but only makes it current when none is -- bind
  and store the RETURN value (GetCurrentContext() aliases every slot to the
  first context, surfacing as a NewFrame assertion); and windows settle
  over ~4 frames (first hidden, auto-size adjusts), which is why the
  steadiness check uses frames 4 and 5.
- **Side-effect-free runs**: all probes set `io.IniFilename = 0` /
  `io.LogFilename = 0`; previously every run rewrote a tracked `imgui.ini`
  (LastUsed timestamps). The artifact was removed from the repo and is now
  ignored.
- **Flat vendor layout**: every core include is same-directory quoted; no
  `-I` passthrough needed and the vendored bytes stay unmodified (per-file
  SHA256 table in `SPEC.md` §2).
- Integer-only bridge ABI (same pattern as `xiom.box2d`): floats and
  ImVec2/ImDrawData stay inside the bridge; counts cross as C `int`s.
- Out-param slots are XIOM-owned `Vec[UInt8]` buffers (no malloc/free;
  finding B-05).
- **SDL3 + Vulkan backends (0.4.0)**: a separate 2-slot backend registry
  (`imgui_backend_*`) keeps the engine-owned handles. SDL3 attaches to the
  engine window; Vulkan attaches to the engine instance/physical
  device/device/queue/descriptor pool/render pass. All handles are 64-bit
  and engine-owned; missing handles fail typed without touching the
  backend. The selftest pairs the real SDL3 platform backend with the
  vendored null renderer (a renderer backend is required for the dynamic
  texture atlas; the engine uses Vulkan). The only mechanical vendored-file
  edit is include normalization to quoted same-directory paths, because the
  XIOM link line has no `-I` passthrough.
- Compiles with `--cxx-standard 17` (the Vulkan backend needs it); the
  core itself is C++11-compatible.

## Known limitations

- Scope at 0.4.0: version + frame lifecycle + tessellation stats +
  long-lived context handles + SDL3 platform and Vulkan renderer backends;
  widget wrappers, tables, draw-list APIs, and the GLFW backend remain
  Phase 3 (`ROADMAP.md`).
- The Vulkan tier targets an engine-owned render pass; the dynamic-rendering
  path is the follow-up. The descriptor pool must meet imgui's minimum
  sampled-image + sampler descriptor counts.
- The context API is still a probe-shaped handle registry; the backend
  registry adds real platform/renderer attach points, but engine UI calls
  (widgets) are Phase 3.
- Windows x64 primary; the vendored path is portable, no other platform has
  been run yet.
