# xiom.btree

In-memory B-tree index for XIOM: ordered key/value storage with
insert/search/delete, predecessor/successor replacement on internal deletes,
underflow borrow/merge, inclusive range scans and in-order traversal over a
flat append-only node array. Pure XIOM, standard library only (`xiom.std`).

Extracted verbatim from ORBITDB's engine B-tree (commit `10109e1`), validated
by the ORBITDB churn soak (orders 4/5/6, 20k ops at keyspace 4096, plus the
quick default and seed matrices) -- see `SPEC.md` for pins and evidence.

> **Status:** `incubating` -- conformance suite green on the pin (v0.64.2):
> **22/22 x2** plus the churn matrix (orders 4/5/6 x 20k ops @ keyspace
> 4096). Order-3 delete is a documented upstream limitation (SPEC section
> 2.3). Published in `eco-v0.1.121` (sha256 `1ce8446e...`).

## Consumer snippet

```xiom
var t = btree_new(4);
let _ = btree_insert(&mut t, 42, 100);
let v = btree_search(&t, 42); // Some(100)
```

Keys and values are `Int`. Duplicate inserts are rejected (`btree_insert`
returns false) and keep the first value. Read APIs return values, ordered by
ascending key; `btree_range_query` bounds are inclusive.

## API

| Function | Result |
| --- | --- |
| `btree_new(order)` | `BTree` (empty; `order >= 3`) |
| `btree_insert(&mut, key, value)` | `Bool` (false when the key already exists) |
| `btree_search(&tree, key)` | `Option[Int]` (stored value) |
| `btree_delete(&mut, key)` | `Bool` (false when the key is absent) |
| `btree_range_query(&tree, low, high)` | `Vec[Int]` (values; inclusive bounds) |
| `btree_min(&tree)` / `btree_max(&tree)` | `Option[Int]` (value at the extreme key) |
| `btree_size(&tree)` | `Int` (key count) |
| `btree_to_vec(&tree)` | `Vec[Int]` (values in key-ascending order) |

Types `BTree` and `BTreeNode` are public with public fields (the flat `nodes`
array and integer child indices exist for the borrow checker; node indices are
append-only today -- free-list reuse is future work).

## Accepted scope and known limitation

- Acceptance matrix: orders 4/5/6 (the ORBITDB relay gate), keyspace 4096,
  20k ops per order, plus quick default x2 and the seed matrix. All green on
  v0.64.1; see `SPEC.md` section 2.2.
- KNOWN LIMITATION: order 3 delete (min_keys = 0) can corrupt the tree via an
  out-of-bounds read in the underflow merge path; reproduced with the
  acceptance probe (order 3, keyspace 16, seed 777, first divergence op 67).
  Order 3 is therefore validated for insert/search/range/structure only.
  The extraction is verbatim; the fix belongs to the upstream ORBITDB tree and
  is tracked in `ROADMAP.md`.

## Tests

```
scripts/port.ps1 -Package xiom-btree -TimeoutSec 90     # 22 conformance checks
tests/churn.ps1 -Order 4 -Ops 20000 -N 4096             # acceptance probe
```

The churn runner dot-sources `scripts/xiom.ps1` read-only, keeps the ORBITDB
`ORBITDB_CHURN_*` env names, and exits with the probe's exit code (0 = green).
