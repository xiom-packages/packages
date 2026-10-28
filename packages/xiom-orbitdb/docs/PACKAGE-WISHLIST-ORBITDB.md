<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> packages lane: wishlist

> **Bus (2026-10-10):** open asks migrated to `xiom-relays`: xiom.btree
> re-extract with the order-3 fix `REL-20261010-1550-orbitdb-9`, variant
> qualification `REL-20261010-1550-orbitdb-10`. Track them there (pull +
> `relay.py view --lane packages`); this file keeps the closed history and
> the deltas below. + consumer notes

**Relay:** hand this file to the packages-lane session. ORBITDB consumes
packages from the registry only (never vendored, never edited). Evidence
paths are from `E:\xiom-projects\xiom-orbitdb`.

**Pin (2026-10-09):** compiler **v0.64.2**, stdlib `e7896ff`, registry
`https://registry.xiom-lang.org` (packages lane @ `6bb40bb0`; its wishlist
ledger notes all three consumer lanes green on v0.64.2, no new asks).

**Context:** ORBITDB (formerly xiom-db) is the embedded database engine --
B-Tree, WAL, query engine, crash recovery. It is zero-dependency and, as of
2026-10-09, runs its full lane on v0.64.2 with every compiler workaround
dropped (suite 120/120 x2 Windows + WSL, WAL/page/DB crash harnesses x2,
fuzz + 2000-key policy soak, incremental checkpoints and durable
transactions). The wishlist below is about extracting the durable primitives
into reusable packages as they harden.

## Proposed packages (ORBITDB needs / will grow)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence from ORBITDB |
|---|---|---|---|---|
| `xiom.btree` | Ordered in-memory index: flat-array B-tree with `insert/search/delete/range_query/min/max/size/to_vec` (the borrow-checker-safe representation used by ORBITDB). | data-structure package domain; the API will grow (cursors, bulk load, secondary-index helpers) and ORBITDB will iterate on delete invariants | xiom.std | `src/index/btree.xi` (then the B-tree section of `src/engine.xi`); this session fixed a real split bug (child-pointer shift) found by `tests/probes/probe_core_diag.xi` (100 inserts, order 5). Extraction is honest only after delete/underflow invariants for odd orders are fixed (see ROADMAP Phase 1). |
| `xiom.wal` | Append-only durable log: text record codec, replay into an index, torn-tail healing, segment truncate/checkpoint seam. | storage policy + file format; stdlib should stay zero-dep core. PULSE asked for an embedded store (`xiom.kv`); a shared WAL is its crash-safety engine. | xiom.std (fsync pending stdlib row) | `tests/probes/probe_wal_file.xi` + `scripts/crash_test.{ps1,sh}`: write N -> hard kill -> torn tail -> replay N -> heal N+1, GREEN x2 Windows + WSL; 200-record soak (2,881 B segment). |
| `xiom.db` (this engine; eventual publish) | Embedded database: the layered engine (B-Tree + WAL + query + recovery) behind the `xiom.db.*` module surface. | n/a -- this is the product, not a utility | xiom.std, later `xiom.btree`/`xiom.wal` if extracted | ORBITDB repo; renamed from xiom-db (2026-10). Final package name + publish timing are the owner's call; no rush -- and per owner direction the VPS/CI/public-release stays parked until greenlit. |

## Consumer notes / registry watch

- **`xiom.kv` 0.1.0** is published and available. ORBITDB is not consuming
  it in Phase 0 (the engine is the product), but the WAL/compaction design
  work will compare against it. The known-red gate from the PULSE lane
  (`kv_get` corruption, C-PULSE-10 in PULSE's compiler findings) is tracked
  there; ORBITDB will record a consumer probe if/when it adopts.
- **No consumer pass on registry packages yet** from ORBITDB: no
  consumer-visible package defects to report this session. The first
  consumer probe will follow the PULSE pattern
  (`tests/probes/probe_pkg_*.xi`) and this doc will carry its own rows.
- **C FFI/bindings worktree:** ORBITDB targets pure XIOM (no FFI) through
  Phase 2; no bindings request -- **confirmed in the 2026-10-09 handshake:
  no FFI asks from this lane; `xiom.wal`/`xiom.btree` stay native-lane
  extractions.** If that changes (e.g. mmap), it will be filed here first.
- **Toolchain note for consumers:** on v0.64.0, registry package adoption
  still needs `xiom.toml` `source-roots` (C-PULSE-02, PULSE's compiler
  findings) -- ORBITDB has no `xiom.toml` yet and no registry deps, so it
  is unaffected so far.

## Suggested order

1. `xiom.btree` extraction after the delete/underflow invariant work
   (ORBITDB Phase 1) -- the flat-array representation is proven against
   the borrow checker and now against a real split bug.
2. `xiom.wal` extraction when stdlib lands fsync + append-tail-repair
   (ORBITDB Phase 2) -- the crash harness is the acceptance test.
3. `xiom.db` publish when Phase 1-2 make durability honest (owner gate).

## Delta 2026-10-08 (packages-lane answers + ORBITDB response)

- **`xiom.btree`: name held; extraction gate = ORBITDB churn soak -- MET.**
  Evidence: `tests/probes/probe_btree_churn.xi` randomized
  insert/delete/search vs a reference model + structural validator, green at
  orders 4/5/6 x 20,000 ops (keyspace 4096) plus a seed matrix, and two
  in-suite churn regressions (**95/95 x2**). One contract to carry:
  `min_keys = (order-2)/2` for this split scheme. Churn probe = acceptance
  test.
- **`xiom.wal`: ships standalone (3 users, one format), API shaped from
  ORBITDB crash-probe evidence.** ORBITDB's response
  (`docs/relay-archive/RELAY-PACKAGES-RESPONSE-ORBITDB.md`) proposes: keep
  `xiom.durable`'s `WalOpKind` / `WalRecord { lsn, op, key, value,
  payload, timestamp }` vocabulary, add the disk segment layer
  (`wal_open/append/flush/replay/truncate/close`), torn-tail heal + the
  crash harness as the acceptance test; `payload[0]` = subtype tag for
  xvector/xiom.db extension.
- **`xiom.durable` reconciliation:** `xiom.wal` becomes the single WAL home;
  durable keeps `src/txn/*` and consumes it. ORBITDB will land the disk layer
  against durable's record shape (reference implementation in
  `src/wal_file.xi` + `probe_wal_file` acceptance).
- **`xiom.kv` watch unchanged:** C-PULSE-10 is Linux-only; the fsync row is
  filed in the stdlib wishlist.

## Delta 2026-10-09 (v0.64.2 re-test + package status)

- **v0.64.2 re-test complete**: all compiler workarounds dropped
  (`6f6c3ba`); suite 120/120 x2 Win + WSL; crash/fuzz/soak green; deep
  container equality (m239) live. None of this changes the registry surface.
- **`xiom.btree`**: extraction gate (churn soak) MET and now additionally
  covered by the deterministic fuzz harness (B-tree vs model, orders 4/5,
  x2 both platforms). Still awaiting the extraction decision; ORBITDB keeps
  the reference implementation in `src/index/btree.xi`.
- **`xiom.wal`**: gate NOT met yet -- the stdlib fsync row is still a stub
  (`os/fs_ffi.fsync` and `os/sync_io.sync_fd` return Err) and
  append-tail-repair is still hand-rolled. ORBITDB's `src/wal_file.xi` has
  grown the proposed shape: record `{lsn, op, key, value, payload,
  timestamp}`, op codes 1..10 incl. `BeginTxn/CommitTxn/AbortTxn`,
  torn-tail heal, truncate keeping `lsn >= from`, and a `Checkpoint` anchor
  payload -- carry these into the `xiom.wal`/`xiom.durable` reconciliation.
- **`xiom.kv`**: still not consumed; no ORBITDB consumer pass yet (registry
  publish activity on the packages side noted; nothing required from
  ORBITDB).
- **No new package defects from ORBITDB**; the registry gate from the PULSE
  lane remains the only tracked consumer-blocking item we know of.
- **Consumer demand raised (2026-10-09):** PULSE wants `xiom.db` as its
  embedded/relational driver (framework 0.3, `open/exec/query/tx`) and
  XVECTOR is the hybrid-join counterpart. `xiom.db` publish priority
  follows the production plan's M6; the API promise is exactly
  `docs/PULSE-INTEGRATION.md` (no more).

## Delta 2026-10-10 (xiom.wal 0.1.0 -- first registry consumer pass)

- **`xiom.wal` 0.1.0 is published (eco-v0.1.121) and installed; ORBITDB ran
  the promised first consumer pass** (PULSE pattern): project
  `tests/pkg/xiom.toml` (registry dep `xiom-wal = "0.1.0"`, mapped to the
  installed package by the v0.64.2 resolver) + `tests/pkg/probe_pkg_wal.xi`.
  **18 checks GREEN x2 Windows + WSL:**
  - API: LSN assignment/resume, `wal_len`/`wal_last_lsn`, tagged payload
    round-trip (`payload[0]` subtype), op codes 1..10 + write-kind,
    truncate keeping `lsn >= from` with payload/timestamp preserved,
    torn-tail skipped on replay + heal-before-append, `wal_flush` documented
    no-op.
  - **Two-way format interop** (the "one format" claim): a package-written
    segment reads bit-equal through `src/wal_file.xi` (records + LSN
    resume), an ORBITDB-written segment replays through the package with
    identical fields, and the codec v1 byte literals are identical.
- **Composite finding (v0.64.2):** importing the package next to our
  reference module re-exposed the m225 twin-enum caveat ACROSS packages --
  `src/wal_file.xi`'s bare `WALOpKind` variants resolved to the package's
  same-variant-name `WalOpKind` and failed T001 (`expected WALOpKind,
  found Checkpoint`) until the three functions were re-qualified. The
  package's own bare variants happened to pass in this composition, but the
  resolution looks order-sensitive: we recommend the package qualify its
  internal variants too (cheap, removes the fragility); compiler-lane
  follow-up: declaring-module preference does not hold cross-package.
- **Adoption decision:** ORBITDB keeps its in-repo reference module through
  Phase 2 (zero-dep engine); the probe now guards the format, so adopting
  the registry package later is a one-step change. `xiom.btree` remains
  unpublished; the churn gate stays MET.
- Pins: compiler v0.64.2, stdlib lane checkout, packages lane @ `47202b72`;
  registry live (`xiom.wal` 0.1.0; `xiom.http` 0.1.4 current).

## Delta 2026-10-10 (relay: order-3 upstream fix + xiom.btree registry-live)

- **Relay received (package lane):** no FFI asks; `xiom.wal` 0.1.0 **and
  `xiom.btree` 0.1.0 are registry-live**; `xiom.db` is ORBITDB's product
  (owner-parked). Their two open items: the order-3 btree defect (ours to
  fix upstream) and C-ORBIT-06 (compiler, filed).
- **Order-3 B-tree defect FIXED upstream** (`fix(btree)` commit, this repo):
  with `min_keys = (order-2)/2 = 0`, merges can leave keyless pass-through
  nodes; three algorithms assumed non-empty nodes:
  1. `get_predecessor` / `get_successor` descended the rightmost/leftmost
     path into a keyless leaf and read `keys[-1]` / `keys[0]` out of bounds
     (the reported corruption: the garbage key materialized into the node;
     diagnosed via a temporary full-model trace: divergence after the
     delete of key 8, op 67);
  2. `fill_child` merged on a keyless single-child parent, reading
     `children[pos + 1]` past the end (their SPEC 2.3 path) -- now descends
     straight through;
  3. `btree_min` / `btree_max` returned None when the terminal leaf of the
     extreme path was empty -- now reuse the empty-chain-aware
     predecessor/successor.
  Tests: new suite regression `btree: churn order 3 vs model (min_keys 0 /
  empty chains)` (their reproducer: order 3, keyspace 16, seed 777, ops
  2000; first divergence pre-fix op 67) and the fuzz rotation now spans
  orders 3/4/5.
- **Evidence:** suite **128/128 x2** Windows + WSL; fuzz x2 both; churn
  order 3 @ 20k/4096 seeds 777+2026 GREEN (remaining 1353 / 1022), orders
  4/5 @ 20k/4096 regression GREEN; WSL churn order-3 20k + reproducer GREEN.
- **For the next `xiom.btree` release:** re-extract the fixed module and
  re-run the acceptance matrix with `-Order 3` included (their churn runner
  already supports it). Once the updated package is installed, ORBITDB runs
  the two-way consumer probe (the `xiom.wal` pattern) -- the extraction now
  needs no "order >= 4" carve-out.
- **Minor compiler-lane note (owner relay, no number yet):** standalone
  `xiom --check src/engine.xi` reports `T001: argument 1 type mismatch:
  expected Engine, found module` (lines ~1207) while the same file compiles
  clean as an imported module (suite/probes). Pre-existing on HEAD;
  minimal repro not yet found (a crafted module/field-name collision did NOT
  reproduce). Not a gate for this lane (we check through programs).
