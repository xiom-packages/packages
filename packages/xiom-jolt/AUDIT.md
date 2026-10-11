# AUDIT: xiom.jolt

## Status (2026-10-11)

Vendored C++ implementation at 0.2.0, **verified on the m258 compiler build**
(`--cxx-standard`, commit `54a9a619`, unpushed at verification time -- ships
in the next archive).  Jolt requires real C++17; the flag is threaded into
`port.args.json` (`--cxx-standard 17`), so the suite only runs on a compiler
carrying m258 or later (older compilers reject the flag and Jolt cannot
build there anyway).

| Item | State |
|------|-------|
| Compiler | v0.64.3 + m258 (local main build; verify on the next archive) |
| Upstream | JoltPhysics tag **v5.6.0** (tarball sha256 `6E069EE0...`, 19.4 MB) |
| Generator | `tools/combine.py` -- mirrors `Jolt/**` (`<Jolt/...>` -> `"Jolt/..."`), 25 per-directory TUs + a bridge shim at the vendor root; tree sha256 `ea20c2d1...` |
| Bridge | `src/jolt_bridge.cpp` via the generated `vendor/jolt_bridge.cpp` shim: drop + velocity probes, single-threaded job system, scalar returns (B-11 avoidance) |
| Suite | `tests/test_conformance.xi`, 4 checks |
| Runs | **4/4 x2** on the m258 build (~34 s/run): drop settles at 479 milli, body asleep; impulse vx=4995 milli; determinism |
| History | The v0.64.3 release-check "if constexpr probe green -> unblocked" verdict was a false positive (clang accepts constexpr if as a C++14 extension); corrected via bus items `REL-20261010-1815-bindings` / `-7` |

## Design notes

- One generated shim TU at the vendor root compiles the reviewable bridge
  from `src/`; the quoted `"Jolt/..."` includes resolve through the
  compiler's include stack (the xiom link line has no `-I` passthrough).
- The bridge uses `JobSystemSingleThreaded` -- deterministic, no worker
  threads; suitable for probes, not throughput work.
- Scalar returns only (packed/negative codes), no out-param slots.

## Re-verification procedure

1. Regenerate: `python tools/combine.py <upstream-root> vendor` (the sparse
   clone/tarball recipe is in `SPEC.md`).
2. `scripts/port.ps1 -Package xiom.jolt` (watchdog >=600 s; 26 TUs) x2 --
   requires the compiler archive with m258.
3. Record `STATUS.json`; re-verdict bus item `REL-20261010-1815-bindings`
   on the archive and close it.
