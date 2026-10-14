# AUDIT: xiom.xess

## Status (2026-10-14, v0.64.4)

Dynamic-loader binding for the Intel XeSS Super Resolution runtime at 0.1.0.
41/41 declared public entries bound (37 `libxess.dll` + 4 `libxess_dx11.dll`);
nothing vendored (closed-SDK doctrine; `PROVENANCE.md`).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Decision | system-library SKIP path only (no SDK binaries/headers committed) |
| Pin | XeSS v3.0.2 `8fe81bdb`; 7 public headers hashed in `PROVENANCE.md` |
| Link model | none at build time; runtime `xiom.ffi.dl` (core + optional companion) |
| FFI confinement | all `unsafe` in the root module `xess.xi` (G5); no C bridge needed |
| Suite | `tests/test_conformance.xi` |
| Runs | default PATH: typed SKIP **24/24 x2**; pin `bin` on PATH: present path **29/29 x2** (SPEC sec. 6) |

## Design notes

- **Native `FfDecoder`-style ownership is caller-side**: contexts are opaque
  `Int` handles returned by the backend create calls; the caller owns the
  device/command objects.  No XIOM-side lifetime wrapper is fabricated.
- **f32 discipline**: cast-call *returns* must not be floating point on this
  pin (B-12); the module therefore reads f32 out-params from owned slots with
  a pure-arithmetic decoder and encodes f32 in-params with an exact
  round-to-nearest-even integer encoder built on `float.float_bits`
  (`xess_f32_bits_from_f64`).  Both directions are unit-tested with
  independently computed bit patterns (incl. subnormal RNE ties, overflow to
  infinity, NaN canonicalization).
- **Slots**: every out-param is one owned `Vec[UInt8]` push-loop buffer, read
  byte-indexed (B-17/B-24); `Vec.with_len` is never used (shaderc audit:
  heap-buffer-overflow on this pin).
- **Handles**: all handles/foreign pointers cross as `Int` parameters in the
  fn-pointer casts (B-25: `Int as *UInt8` is not value-preserving); the one
  pointer *out* into a slot (`xess_dump_parameters_t::path`) relies on
  `Str.c_str() as Int`, which is the value-preserving direction.
- **Callback setter** takes a C-ABI `Int` address (0 = none): fn values do
  not cross to C on this pin (B-13/B-18/B-22; sdl3 dispatcher precedent).
- **Typed error paths**: absent core -> `XESS_LOAD_ABSENT` (SKIP); a loaded
  DLL missing declared entries -> `XESS_LOAD_ABI` (FAIL); missing D3D11
  companion -> flat `CANT_LOAD_LIBRARY` outcome without any null call-through.
  The suite exercises ABSENT (bogus sonames) and ABI (kernel32.dll) on every
  host, plus the companion-absent path on the present path.

## Compliance

- No secrets; no environment reads; no files written by the suite.
- Suite cleanup: both handles closed on every load path (loader failure paths
  close partially-opened handles; present path closes core+companion).
- G2/G6/G7 records: `SPEC.md` (pin, export matrix, layouts) and
  `PROVENANCE.md` (upstream, oracle hashes, derived vs independent, re-carve).
