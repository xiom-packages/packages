# AUDIT: xiom.ffmpeg

## Status (2026-10-09)

System-library dynamic-loader implementation at 0.2.0. The pre-pilot module
(27 static `extern "C"` declarations, compile-time linked) required FFmpeg
import libraries at build time and is preserved in git history only.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Decision | **system-library SKIP path only** (native lane 2026-10-09; `SPEC.md` §2, `BINDINGS-LANE.md` §11) |
| Pin | generation table + entry points + local samples (`SPEC.md` §3) |
| Link model | none at build time; runtime `xiom.ffi.dl` (generation scan) |
| FFI confinement | all `unsafe` in the root module `ffmpeg.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | default PATH: SKIP 2/2 x2; Cascadeur 6.0 LGPL: 4/4 x2; Blender 7.1.1 GPL: 4/4; OneDrive/DaVinci partial generations: SKIP 2/2 |

## Design notes

- A **generation** = the four shared libraries of one FFmpeg release; all
  four must resolve, so a partial set (e.g., DaVinci Resolve's 6.x without
  `swresample-4.dll`) is skipped instead of mixing ABI generations.
- The probe calls only version/configuration/license entry points -- the
  LGPL-safe surface approved by the native lane. A GPL-configured host build
  is reported as data (`license`, `gpl_enabled`) and is not an error: the
  package never depends on a GPL-only feature.
- License strings verified by byte scan of the DLLs' `avcodec_license()`
  constants: `LGPL version 2.1 or later` in Cascadeur/DaVinci/OneDrive
  builds, `GPL version 2 or later` in Blender's.
- Bridge locals use the `f_` prefix (finding B-10); no allocation in
  confined blocks (finding B-05).
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- Pilot scope: identification/license evidence only; demux/decode/encode are
  Phase 2.
- Only the five built-in generations are scanned; an unusual soname needs
  `ffmpeg_probe_named`.
- Windows x64 only: FFmpeg shared builds on other platforms use different
  sonames (the generation table is platform-specific).
