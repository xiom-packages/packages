# AUDIT: xiom.portaudio

## Status (2026-10-09)

Dynamic-loader implementation at 0.2.0. The pre-pilot module declared static
`extern "C"` PortAudio functions (link-time dependency) and is preserved in
git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname + 8-entry-point set + struct prefix + samples (`SPEC.md` §2) |
| Link model | none at build time; runtime `xiom.ffi.dl`; no headers, nothing vendored |
| FFI confinement | all `unsafe` in the root module `portaudio.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | absent: **PASS 2/2 x2** (SKIP path); present (Audacity V19.7.0): **PASS 5/5 x2** (version, 52 devices, default output/input names) |

## Design notes

- `PaDeviceInfo` name extraction: `structVersion` int at offset 0 (with
  4 bytes padding), `char* name` at offset 8 -- read via
  `xiom.ffi.ptr_read_u64_le` and copied with `Str::from_c_str`.
- `Pa_GetVersion` reports 1246976 (0x130700 = 19.7.0); the suite asserts a
  non-empty version text rather than pinning the exact build string.
- Bridge locals use the `f_` prefix (compiler finding B-10); `int_to_str` is
  local to the module.
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- Pilot scope: version/devices/defaults only; streams, callbacks and
  host-API info are Phase 2.
- Windows soname `portaudio_x64.dll` only; MSYS2's `libportaudio-2.dll` and
  POSIX variants are Phase 2.
- `PaDeviceInfo` field offsets are asserted for the pinned builds; a
  different ABI would need the re-pin procedure (SPEC §2).
