# xiom.btree 0.1.0 -- specification

In-memory B-tree index over a flat append-only node array. Pure XIOM,
`xiom.std` only. Single root module `xiom.btree` extracted VERBATIM from the
B-TREE INDEX region of ORBITDB `src/engine.xi` (lines 21-631; extraction
policy below). No contracts are added: the only two `requires:` clauses in the
package are the two that exist in the source (`btree_new`: `order >= 3`;
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

**Public types** (fields public, consumed by the churn probe and available to
consumers):

```
pub type BTree     = { root: Int; order: Int; nodes: Vec[BTreeNode]; }
pub type BTreeNode = { keys: Vec[Int]; values: Vec[Int]; children: Vec[Int]; is_leaf: Bool; }
```

`nodes` is a flat array; `children` holds integer indices into it; `is_leaf`
distinguishes node kinds. Node indices are append-only today: splits and
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

### 2.1 Extraction pins (2026-10-09)

SHA256 of the extracted/adapted source files at extraction time:

| File | SHA256 |
| --- | --- |
| `src/btree.xi` (verbatim carve) | `d30f5f5977a96c746bd8a9b472af91393ed8d74cf43f04182e6afa89bfd493e2` |
| `tests/probes/probe_btree_churn.xi` (adapted probe) | `e4b6af1ad28d76cbe731c66fa97e2970cca15a77bf1d17b5a77361039a9da34c` |
| `tests/test_conformance.xi` (authored suite) | `642b8372f2360b5503818f9b7ba2bc530332783605ef80e46fa7c16cbd61543f` |
| `tests/churn.ps1` (authored runner) | `d56af6433f78ff34f0a3bbf30126ff5b57ebc468245a0b489125051ee4612f39` |

Carve provenance: ORBITDB commit `10109e1` /
`10109e15a7f70b83a91b587a7e51598119205c25` (2026-10-09 16:58:02 +0300),
re-checked read-only with
`git -C E:\xiom-projects\xiom-orbitdb log -1 --format="%h %H %ci" -- src/engine.xi`.
Churn probe provenance: ORBITDB commit `c7d4901` (per the packages/ORBITDB
relay response).

### 2.2 Acceptance evidence (v0.64.1, this extraction run)

Acceptance test = the adapted churn probe (`tests/probes/probe_btree_churn.xi`,
`ORBITDB_CHURN_*` env kept from the relay). Recorded:

| Check | Command | Result |
| --- | --- | --- |
| conformance x2 | `scripts/port.ps1 -Package xiom-btree -TimeoutSec 90` | PASS passed=22 failed=0 (4.3s), PASS passed=22 failed=0 (4.3s) |
| churn 20k @ 4096, orders 4/5/6 | `tests/churn.ps1 -Order N -Ops 20000 -N 4096` | GREEN x3: order 4 remaining=1355 (2.6s), order 5 remaining=1355 (2.9s), order 6 remaining=1355 (2.5s) |
| quick default x2 | `tests/churn.ps1 -Order 4 -Ops 2000 -N 256` | GREEN x2 (remaining=90, 2.8s each) |
| seed matrix (quick) | orders 4/5/6 x seeds 2026/777, `-Ops 2000 -N 256` | GREEN x6 (remaining: 65 for 2026, 88 for 777) |
| byte-level bracket scan | five legacy angle-bracket shapes in `packages/xiom-btree` | 0 hits |

### 2.3 Known order-3 delete defect (finding; upstream-frozen code)

`min_keys = (order - 2) / 2` is 0 for order 3. With min_keys 0, merges can
produce non-root internal nodes with 0 keys and 1 child. A later delete that
descends into such a node calls `fill_child`, which (having no second child to
merge with) invokes `merge_children` on the single-child parent; that reads
`parent.children[pos + 1]` and `parent.keys[pos]` past the end. On v0.64.1 the
observed effect is structural corruption (an out-of-bounds garbage key,
`-8070446941336389272`, was materialized into a node), not a clean panic.

Reproduction (verbatim probe, no modifications):

```
tests/churn.ps1 -Order 3 -Ops 100 -N 16 -Seed 777
-> MISMATCH search-missing op=69 key=4 (exit 3)
```

The ORBITDB gate matrix was orders 4/5/6 only (their relay: "try 4 and 5",
soak green at 4/5/6); order 3 was never in the acceptance set. The extraction
policy is verbatim, so this package does not fix it. Consequences in this
package:

- order 3 is covered for insert/search/range/structure only;
- delete-path coverage and the acceptance matrix use orders 4/5/6;
- resolution is tracked in `ROADMAP.md` (upstream fix or an explicit
  `order >= 4` restatement, then the matrix can be re-expanded to order 3).

## 3. Layout

```
packages/xiom-btree/
  package.xi                    manifest (xiom.btree 0.1.0, xiom.std dep)
  src/btree.xi                  single root module `xiom.btree`
                                (carve of engine.xi lines 21-631; 616 lines)
  tests/test_conformance.xi     22 checks, one [PASS]/[FAIL] line each
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

`tests/test_conformance.xi` (22 checks): empty-tree behavior; insert/search
round-trip; duplicate insert (first value wins); leaf delete and missing-key
delete; full drain and borrow/merge sequences on orders 4/5; internal root-key
replacement; descending even deletes on order 5; deterministic LCG model
churn (orders 4/5, seeds 2026/777); inclusive range bounds, `low == high`,
empty ranges; min/max tracking; to_vec ascending order; structural validation
from the node array on orders 3/4/5; negative keys. All deterministic, no
fixtures on disk, exit 0 only when green.
