# AUDIT: xiom.jolt (STAGED -- blocked on the compiler C++ standard)

## Status (2026-10-10)

Jolt Physics requires **real C++17** (`std::string_view`,
`std::align_val_t`, structured bindings).  Compiler v0.64.3 still defaults
to C++14 and exposes no `--cxx-standard` passthrough, so the generated
vendored tree cannot build through `--c-source` yet.  The release-check
verdict that marked the blocker fixed was a **false positive**: clang
accepts `if constexpr` as a C++14 extension (warning
`-Wc++17-extensions`, `__cplusplus 201402L`), which the probe used.
Correction filed as bus item `REL-20261010-1815-bindings`; the original
item is `REL-20261010-1548-bindings-7` (row corrected in the v0.64.3
release check).

What is already built and validated under `-std=c++17` (system clang, and
the artifact *generation* is reproducible at any time):

| Item | State |
|------|-------|
| Upstream pin | JoltPhysics tag **v5.6.0** (tarball sha256 `6E069EE0...`, 19.4 MB) |
| Generator | `tools/combine.py` -- mirrors `Jolt/**` (`<Jolt/...>` -> `"Jolt/..."`), emits 25 per-directory TUs + a bridge shim at the vendor root; tree sha256 printed per run (e.g. `11611994...`) |
| Bridge | `src/jolt_bridge.cpp` (compiled via the generated `vendor/jolt_bridge.cpp` shim): drop + velocity probes, single-threaded job system, scalar returns (B-11 avoidance) |
| Module + suite | `jolt.xi` + `tests/test_conformance.xi` (4 checks: drop settle, sleep, velocity hand-off, determinism) |
| port.args.json | 25 TU entries + the bridge shim |
| Local validation | all 25 TUs + the bridge compile with `-std=c++17` (~30 s); on v0.64.3 they abort with `no member named string_view` (Core.h:537) and `no type named align_val_t` (Float4.h) |

## Unblock procedure

1. When the compiler ships a `--cxx-standard c++17` flag (or a gnu++17
   default): regenerate with
   `python tools/combine.py <upstream-root> vendor` (the sparse clone /
   tarball recipe is in `SPEC.md`), then
2. run `scripts/port.ps1 -Package xiom.jolt` (watchdog >=600 s; 26 TUs) x2
   and record `STATUS.json`;
3. re-verify bus items `-7` / `-1815` and close them with the run evidence.

## Known limitations

- Pilot scope: two physics probes; broad-phase queries, joints, character
  controllers, soft bodies are Phase 2 (`ROADMAP.md`).
- The bridge uses `JobSystemSingleThreaded` (deterministic, no worker
  threads) -- suitable for probes, not for throughput work.
