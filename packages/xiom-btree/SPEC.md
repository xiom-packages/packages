# xiom.btree 0.1.1 -- specification

In-memory B-tree index over a flat append-only node array. Pure XIOM,
`xiom.std` only. Single root module `xiom.btree` extracted VERBATIM from the
B-TREE INDEX region of ORBITDB `src/engine.xi` (lines 21-735 at the
2026-10-11 re-carve; originally 21-631 at 0.1.0; extraction policy below).
No contracts are added: the only two `requires:` clauses in the package are
the two that exist in the source (`btree_new`: `order >= 3`;
`btree_range_query`: `low <= high`). No externs; no `unsafe`. The module
imports nothing (core types only; verified by compiling with an empty import
list).

## 1. Scope, surface and guarantees

**Public API:**

| Function | Result |
| --- | --- |
| `btree_new(order)` | `BTree` (empty tree; `order >= 3`) |
| `btree_insert(&mut, key, value)` | `Bool` (false when the key already exists) |
| `btree_search(&tree, key)` | `Option[Int]` (stored value) |
| `btree_delete(&mut, key)` | `Bool` (false when the key is absent) |
| `btree_range_query(&tree, low, high)` | `Vec[Int]` (values, inclusive bounds; `low <= high`) |
| `btree_min(&tree)` / `btree_max(&tree)` | `Option[Int]` (value at the extreme key) |
| `btree_size(&tree)` | `Int` (key count) |
| `btree_to_vec(&tree)` | `Vec[Int]` (values in key-ascending order) |
| `ns_len` / `ns_get` / `ns_set` / `ns_push` / `ns_mark_clean` | `NodeStore` accessors (length / read; write + mark dirty; append; mark-all-clean) |

**Public types** (fields public, consumed by the churn probe and available to
consumers):

```
pub type BTree     = { root: Int; order: Int; store: NodeStore; }
pub type NodeStore = { nodes: Vec[BTreeNode]; dirty: Vec[Bool]; }
pub type BTreeNode = { keys: Vec[Int]; values: Vec[Int]; children: Vec[Int]; is_leaf: Bool; }
```

`store.nodes` is a flat array (the parallel `dirty` vector marks nodes changed
since the last snapshot flush); `children` holds integer indices into it;
`is_leaf` distinguishes node kinds. Node indices are append-only today: splits and
merges append new nodes, and a node emptied by a merge is abandoned in place
(never reused, never removed). Free-list reuse is future work (ROADMAP).

**Semantics (as extracted, not reinterpreted):**

- Duplicate insert: `btree_insert` returns `false` and does NOT update the
  value; the first written value wins. (Documented behavior of the source;
  changed only if ORBITDB changes it.)
- All read APIs return stored VALUES, not keys. `btree_to_vec` and
  `btree_range_query` return values ordered by ascending key.
- `btree_range_query` bounds are inclusive on both ends; a range with no keys
  returns an empty vector.
- Deleting an absent key is a no-op returning `false`.

**Structural invariants** (verified by the probe and the suite validator):

- keys strictly ascending within a node;
- leaf => no children; internal => `children.len() == keys.len() + 1`;
- non-root key count in `[min_keys, order - 1]`; root up to `order - 1`;
- all leaves at the same depth.

`min_keys = (order - 2) / 2` for this split scheme (odd orders included;
documented invariant from the ORBITDB relay). Degrees are not enforced in
types; churn beyond the frozen matrix is consumer responsibility.

## 2. Pins

### 2.1 Re-extraction pins (2026-10-11)

SHA256 of the extracted/adapted source files at re-extraction time:

| File | SHA256 |
| --- | --- |
| `src/btree.xi` (verbatim carve) | `0a82f20126f4552abfae044a6955ff981ceb544ff173f741cbe8d944ad3f47bd` |
| `tests/probes/probe_btree_churn.xi` (adapted probe) | `e017d0d1bd054e2b43c8e1010de2fe5dac720c3532ce5f4761aae95fad91008a` |
| `tests/test_conformance.xi` (authored suite) | `42667c837c0ca11f24aa3939ebcccf6949169b5f13892f71f19346edbafb0db5` |
| `tests/churn.ps1` (authored runner) | `d56af6433f78ff34f0a3bbf30126ff5b57ebc468245a0b489125051ee4612f39` |

Carve provenance: ORBITDB commit `c017165` /
`c01716504873f3f1a4d61cb28bd87bba6c3c0d1c` (2026-10-10 18:40:09 +0300) --
the order-3 fix re-carve (0.1.1; region 611 -> 715 lines, carrying the M1.1
`NodeStore` and the keyless-chain delete fixes). The original 0.1.0 carve was
ORBITDB `10109e1` / `10109e15a7f70b83a91b587a7e51598119205c25` (2026-10-09
16:58:02 +0300). Both re-checked read-only with
`git -C E:\xiom-projects\xiom-orbitdb log -1 --format="%h %H %ci" -- src/engine.xi`.
Churn probe provenance: ORBITDB commit `c7d4901` (per the packages/ORBITDB
relay response).

### 2.2 Acceptance evidence (v0.64.3, the 0.1.1 re-extraction run)

Acceptance test = the adapted churn probe (`tests/probes/probe_btree_churn.xi`,
`ORBITDB_CHURN_*` env kept from the relay). Recorded:

| Check | Command | Result |
| --- | --- | --- |
| conformance x2 | `scripts/port.ps1 -Package xiom-btree -TimeoutSec 240` | PASS passed=23 failed=0 x2 (includes the order-3 regression churn) |
| churn 20k @ 4096, order 3 | `tests/churn.ps1 -Order 3 -Ops 20000 -N 4096` | GREEN x2: seed 777 remaining=1353, seed 2026 remaining=1022 |
| churn 20k @ 4096, orders 4/5/6 | `tests/churn.ps1 -Order N -Ops 20000 -N 4096` | GREEN x3: remaining=1355 each |
| order-3 regression | `tests/churn.ps1 -Order 3 -Ops 2000 -N 16 -Seed 777` | GREEN (pre-fix: MISMATCH op=67, exit 3) |
| quick default x2 | `tests/churn.ps1 -Order 4 -Ops 2000 -N 256` | GREEN x2 (remaining=90) |
| seed matrix (quick) | orders 3/4/5/6 x seeds 2026/777, `-Ops 2000 -N 256` | GREEN x8 (remaining: 65 for 2026, 88 for 777) |
| byte-level bracket scan | five legacy angle-bracket shapes in `packages/xiom-btree` | 0 hits |

### 2.3 Order-3 delete defect -- FIXED upstream (`c017165`)

`min_keys = (order - 2) / 2` is 0 for order 3: merges could produce non-root
internal 0-key/1-child pass-through nodes, and a delete descending into one
read past the children array (`merge_children` on a single-child parent), the
observed effect being structural corruption (garbage key materialized), not a
clean panic. The 0.1.0 package documented this and excluded order-3 deletes;
its reproducer was `tests/churn.ps1 -Order 3 -Ops 100 -N 16 -Seed 777` ->
`MISMATCH search-missing op=69 key=4` (exit 3; keyspace-16 probe first
divergence at op 67).

Fixed upstream in ORBITDB `c017165` (keyless pass-through chains):
predecessor/successor lookups return `Option` and walk keyless chains
(`subtree_has_key`), `fill_child` passes straight through a keyless parent,
and `btree_min`/`btree_max` route through them. This package re-carved the
region verbatim at that commit (0.1.1) and re-expanded the acceptance matrix
to order 3 -- including the former reproducer, now GREEN.

## 3. Layout

```
packages/xiom-btree/
  package.xi                    manifest (xiom.btree 0.1.1, xiom.std dep)
  src/btree.xi                  single root module `xiom.btree`
                                (carve of engine.xi lines 21-735; 720 lines)
  tests/test_conformance.xi     23 checks, one [PASS]/[FAIL] line each
  tests/probes/probe_btree_churn.xi  adapted acceptance probe
  tests/churn.ps1               env-driven probe runner (exit code = probe's)
  SPEC.md README.md ROADMAP.md STATUS.json .gitignore
```

## 4. Provenance and ORBITDB reconciliation

Extraction rules applied:

- module declaration changed to `module xiom.btree`; the source import list
  was dropped entirely (the BTree region uses core types only -- checked by
  compiling with zero imports);
- every function and type is byte-identical to the source region; formatting
  and comments untouched; the two existing `requires:` clauses kept verbatim;
  no new contracts, no externs.

The rest of `engine.xi` (WAL legacy, query, query planner, Engine, database
API) is NOT extracted and this package never modifies the ORBITDB repo.
Reconciliation (separate, sequenced step; same pattern as
`xiom.durable -> xiom.wal`): ORBITDB deletes its local B-TREE INDEX region and
consumes `xiom.btree`; until then the two copies are pinned to the same
commit and must not drift.

## 5. Tests

`tests/test_conformance.xi` (23 checks): empty-tree behavior; insert/search
round-trip; duplicate insert (first value wins); leaf delete and missing-key
delete; full drain and borrow/merge sequences on orders 4/5; internal root-key
replacement; descending even deletes on order 5; deterministic LCG model
churn (orders 4/5, seeds 2026/777; **order 3, 2000 ops, keyspace 16, seed 777
-- the former defect reproducer**); inclusive range bounds, `low == high`,
empty ranges; min/max tracking; to_vec ascending order; structural validation
from the node array on orders 3/4/5; negative keys. All deterministic, no
fixtures on disk, exit 0 only when green.
