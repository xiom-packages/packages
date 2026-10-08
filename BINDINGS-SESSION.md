# BINDINGS-SESSION -- xiom-packages bindings lane

Handoff file for the native session. Read the relay block first; the ledger
below records evidence and open asks.

**STATUS: BATCH 1 MERGED + WRAPPED** -- merged on main @ `05a19deb`, wrapped at
`5ea29bb5`/`2cb3f03a` (xiom.sqlite 0.2.0 on the allowlist, 505 names).
Waiting for the **eco-v0.1.89 publish confirmation** before starting xiom-sdl3.
Lane findings: `docs/BINDINGS-COMPILER-FINDINGS.md`; asks:
`docs/BINDINGS-STDLIB-WISHLIST.md`; repros: `docs/repro/bindings-pilot/`.

## Relay (bindings -> native, per BINDINGS-LANE.md §6)

```
BINDINGS BATCH 1: head=dfaa17b2 (+ this handoff commit); packages=xiom.sqlite 0.2.0;
tests=xiom.sqlite 16/16 PASS x6 consecutive build+run cycles (default compiler flags,
2026-10-08, v0.64.0); licenses=package MIT OR Apache-2.0, vendored SQLite 3.53.4
Public Domain (vendor/LICENSE); pins=sqlite3.c sha256
B1DD5D74EC7F29055A6684FA06FB3C2F6821C87DD38F9A458DFD2E8A1DB28189, sqlite3.h sha256
919E7F2E8ED1D8F56AC17B412B8971C76AA5D1A879752CC6058F75E7D5910E1D, sqlite3ext.h sha256
AC9645E5C9FF0CF176EFDD6E75CB5E98F46295D38E02DB5C4D208826A39AB4BE, upstream
sqlite-amalgamation-3530400.zip sha3-256 628a44cf...27934e verified with certutil and
sha256 1E71DDF9...E87D; gate=G0 OK (keywords:["binding"], license), G1 OK (compiles on
the pin), G2 OK (SHA256 over vendored header set + version 3.53.4/libversion_number
3053004 pinned in SPEC.md), G3 n/a vendored path (no SKIP case: the amalgamation is
compiled in), G4 OK (16 functional checks incl. open/exec/prepared/bind/error codes),
G5 OK (all unsafe+extern confined to src/ffi.xi; facade+satellites pure); namespace-check
xiom.sqlite OK (0 conflicts vs 1724 namespaces);
needs=1) allowlist append + ops scope enumeration for xiom.sqlite (native lane);
2) port.ps1 runner hook for per-package extra compiler args, resolved package-relative:
   xiom --run tests/test_conformance.xi --c-source <abs>/vendor/sqlite3.c --opt-level
   default; --c-source needs an ABSOLUTE path (clang cwd is a scratch dir) and the
   suite needs >=180s watchdog (amalgamation compiles at link time, ~25-50s observed);
   same hook will serve the sdl3/opengl SKIP suites.
```

Suggested owner one-liner to forward to the native session:

> Bindings batch 1 (xiom.sqlite) is green on branch `bindings` at dfaa17b2:
> relay in E:\xiom-packages\bindings\BINDINGS-SESSION.md; merge + allowlist
> append for xiom.sqlite + port.ps1 per-package compiler-args hook requested.

## Session ledger

- Worktree: `E:\xiom-packages\bindings`, branch `bindings`, kept fresh
  (merged origin/main at 6fa4f9a6 before starting; relay transport commit
  ceeea349 noted).
- Pilot package 1 of 3: **xiom.sqlite** -- done, pending native merge/publish.
  Per the plan, work on xiom-sdl3 starts after the native session merges and
  publishes this batch.
- Suite command (from `packages/xiom-sqlite`):
  `xiom --run tests/test_conformance.xi --c-source <abs>\vendor\sqlite3.c`
  Evidence: 6 consecutive build+run cycles 16/16 PASS (22-31s each; first cold
  run ~50s). The compile+run is deterministic now -- see enum finding below.
- G2 pin verified from git blobs, not just the worktree:
  `git cat-file -p HEAD:packages/xiom-sqlite/vendor/sqlite3.c` SHA256 ==
  B1DD5D74... and byte length 9,515,341. `vendor/** -text` (package-local
  .gitattributes) prevents core.autocrlf from breaking the pins on fresh
  checkouts.

### Compiler findings (v0.64.0) -- details for docs/COMPILER-FINDINGS.md

1. **Enum payload reads miscompile nondeterministically across BUILDS.**
   `SqliteValue` as a user enum with payloads (`Integer(Int)`, `Text(Str)`,
   ...) made accessors fail in ~50% of rebuilds of the SAME source
   (11/16 vs 16/16 passes; a 4-check micro probe flipped to all-false in 1 of
   6 builds, i.e. the whole enum layout was wrong in that build). Same class
   as the existing `xiom.graphql` enum-payload finding. Fixed by a tagged
   struct (`kind` + plain fields); 8/8 micro builds and 6/6 suite builds
   green after the change. Re-test the enum model at the next pin.
2. **`pub const` references inside confined (`unsafe`) blocks and long
   const-if chains recurse the resolver** -> compiler stack overflow
   (exit 0xC00000FD) in full-catalog builds. Workaround: literals inside
   `src/ffi.xi` bodies and in `error_name`; public consts unchanged.
3. **Cross-module const aliases** (`pub const A: Int = other.B`) recurse the
   resolver when referenced. Facade consts use literal values.
4. **Child modules cannot import their parent** (known: documented in
   `xiom-vault`). FFI core is a sibling (`xiom.sqlite.ffi`); only the parent
   facade imports children.
5. **`xiom.ffi.alloc` inside a confined block + `xiom.ffi.free` spins.**
   The guard pass rewrites `alloc` to `xiom_guard_alloc` inside the block
   while `free` stays libc; the guard heap then loops (flat memory, 100% CPU
   -- watchdog it). Workaround: no malloc/free in confined blocks; C
   out-params write into an XIOM-owned `Vec[UInt8]` slot.
6. **A module exporting an associated fn whose last segment is `up` (or
   `down`) crashes the compiler with `xiom.test` in the catalog.**
   Migration methods renamed `migrate_up`/`migrate_down`.
7. **Unqualified imports from library modules do not resolve** (`use
   xiom.sqlite;` then bare `prepare(...)` -> undefined variable); sibling
   module qualification (`ffi.prepare(...)`) works. Also `use xiom.ffi;` in
   a module named `...ffi` shadows the alias -> avoid the stdlib import there.
8. Note: `xiom --run` returned exit 0 for a suite whose `main` returned 5;
   port.ps1's [PASS]/[FAIL] marker counting is the reliable signal.

### Safety note (owner-facing)

A hung test binary from this lane (the alloc/free guard-heap spin, finding 5,
before it was diagnosed) ran ~21 minutes burning CPU and is the most likely
contributor to the 98 GB memory event / restart at 11:54 on 2026-10-08.
After diagnosis all runs used a memory/time-capped watchdog; the final suite
runs peaked at ~7 MB RSS. No other lane process was touched.

## Inbound context (2026-10-08, after batch 1 merged @ 05a19deb, wrapped 5ea29bb5/2cb3f03a)

- Batch 1 merged and wrapped: `xiom.sqlite` 0.2.0 is on the allowlist (505 names);
  `port.args.json` hook live (`docs/BINDINGS-LANE.md` §10); findings recorded in
  `docs/COMPILER-FINDINGS.md`. **sdl3 starts only after the eco-v0.1.89 publish
  confirmation** (owner/native relay); keep-fresh before starting.
- New project lanes joined the ecosystem (Projects -> packages -> stdlib ->
  compiler): PULSE (web), ORBITDB (embedded DB), XVECTOR (vector DB). Relays were
  addressed to the packages lane; binding-relevant reads:
  - ORBITDB (`docs/RELAY-PACKAGES-ORBITDB.md`): **"No C-FFI/bindings need from
    ORBITDB (pure XIOM target)"** -- acknowledged, nothing for this lane.
  - XVECTOR (`docs/PACKAGE-WISHLIST-XVECTOR.md`): proposes `xiom.vectors`,
    `xiom.wal`, `xiom.ann` (pure-XIOM domain layers, native-lane coordination);
    the accelerator row asks the bindings lane to `Watch` for the Phase 10
    SIMD/kernel path and to say whether a pure-XIOM SIMD kernel package is
    planned before they propose a second kernel package.
- Bindings-lane position (for relay to XVECTOR/native):
  1. `xiom-blas` / `xiom-eigen` / `xiom-openblas` exist in THIS worktree as
     pre-rostered `incubating` placeholders (tests `unknown`; specs describe
     CBLAS/OpenBLAS FFI, current code is stubs -- same pre-pilot state
     `xiom.sqlite` was in). Nothing published; no timeline is promised. When the
     bindings Phase 2 reaches them they will be opt-in accelerators behind the
     portable `xiom.vectors` contract -- the binding API surface should mirror
     the pure-XIOM functions, never define them.
  2. The bindings lane plans **no pure-XIOM SIMD kernel package**; that is
     native/stdlib territory. If `xiom.simd`-class work appears there, bindings
     adopt it as the portable path and keep FFI libs as drop-in accelerators.
  3. Name/scope coordination for `xiom.wal` (ORBITDB vs XVECTOR duplication) is
     a native-lane call; this lane has no storage-format stake.

## Next (after native merge + publish confirmation)

Phase 1 pilot continues with **xiom-sdl3** (system-library path, SKIP when
absent) and then **xiom-opengl** (GPU-lite loader probe). A Phase-2 sector
order proposal follows the pilot.
