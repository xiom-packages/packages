<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# ORBITDB -> ecosystem lanes: intro relay

**From:** the ORBITDB lane, `E:\xiom-projects\xiom-orbitdb` (embedded XIOM
database engine: B-Tree, WAL, query engine, crash recovery; formerly
`xiom-db`). Consumer lane: it never edits `E:\xiom-lang\stdlib`,
`E:\xiom-lang\xiom`, or `E:\xiom-packages\packages`.

**Status after bootstrap (2026-10-08, compiler v0.64.0, stdlib `a677338`):**

- Toolchain env scripts (`.ps1`/`.sh`) + watchdog runner; hello probe x2.
- The 93-test conformance suite was **broken on v0.64.0** (218 type errors,
  then a codegen C001); after the workarounds below it is **93/93 green x2**,
  including three real engine defects it exposed (B-tree split child-pointer
  shift; BufferPool/StorageEngine Option-slot + nested-receiver losses).
- A durable WAL segment probe with **hard-kill crash/reopen** is green x2 on
  Windows and in WSL, plus a 200-record soak (torn tail healed, replay
  exact).

**Lane documents (owner relays these):**

| To | Document | What it contains |
|---|---|---|
| compiler lane | `docs/COMPILER-FINDINGS-ORBITDB.md` + `docs/repro/*` | C-ORBIT-01 (cross-module generic `Result` alias payload unresolved), C-ORBIT-02 (`Vec[Option[T]]` element assignment poisons the slot), C-ORBIT-03 (nested-field `&mut` method receivers mutate a copy), plus W004 note |
| stdlib lane | `docs/STDLIB-WISHLIST-ORBITDB.md` | fsync/durability, truncate/checkpoint, `read_file_lines` CR normalization, byte-level IO, append-with-tail-repair; positive confirmations |
| packages lane | `docs/PACKAGE-WISHLIST-ORBITDB.md` | future extraction candidates `xiom.btree` / `xiom.wal`, `xiom.db` publish note, `xiom.kv` watch |
| ops lane | (no request yet) | ORBITDB follows the PULSE staging model: local WSL + Docker until the owner greenlights; scripts ship as `.ps1` + `.sh`; no VPS/DNS action requested |

**What ORBITDB asks of the ecosystem right now:** nothing blocking -- all
three findings have in-repo workarounds and the lane keeps moving. The
highest-value item is C-ORBIT-01/02: they are silent-wrong-value defects on
the path of any collection code, and C-ORBIT-01's alias fix may already be
in the compiler lane's `0c5337e0` (m216) -- re-test is queued for the next
archive.

**Re-test recipe for a lane:** `scripts/run.ps1 tests/test_conformance.xi`
(+ `docs/repro/<bundle>/probe*.xi`); findings flip to RESOLVED only when the
bundles are green unchanged.
