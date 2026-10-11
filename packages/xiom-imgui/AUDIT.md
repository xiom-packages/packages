# AUDIT: xiom.imgui

## Status (2026-10-11)

Vendored-C++ implementation at 0.3.0. The pre-pilot tree (a 90-extern
surface with precompiled bridge objects, GLFW + Vulkan backends, and a
demo) is preserved in git history only; it required the Vulkan SDK and
prebuilt `.obj` files at build time, which breaks the binding gate. The
headless probe since 0.2.0 is SDK-free.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | Dear ImGui v1.92.9b (tag), vendored unmodified (MIT) |
| Link model | `--c-source` (4 core sources + null backend + bridge via `port.args.json`) |
| FFI confinement | all `unsafe`/`extern` in the root module `imgui.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 7 checks (real headless frames + context handles) |
| Runs | **7/7 x2** on the pin (`scripts/port.ps1`) |

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
- Compiles under the link line's default C++ standard (C++14): the vendored
  core is C++11-compatible. (Larger C++17 libraries need the standard-flag
  passthrough request recorded in the session ledger -- see `xiom.jolt`.)

## Known limitations

- Scope at 0.3.0: version + frame lifecycle + tessellation stats +
  long-lived context handles; widget wrappers and backends are Phase 3
  (`ROADMAP.md`).
- The context API is a probe-shaped handle registry, not a full UI loop
  (no input, no rendering): Phase 3 adds widget wrappers and the
  GLFW/Vulkan backends over the same handles.
- Windows x64 primary; the vendored path is portable, no other platform has
  been run yet.
