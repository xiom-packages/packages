<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# Query Pipeline

The query subsystem turns a declarative `Query` into a set of matching values. In Phase 0 it always runs a full in-order scan; the `planner` scaffold marks where index-aware execution lands in Phase 3.

> **Semantics decision (Phase 0):** `QueryCondition` filters **values**, not keys.
> `query_where(q, Gt, 150)` over values `[100,200,300]` returns `[200,300]`.
> Key-range access is `db_range(low, high)` / `btree_range_query`.
> The Phase 3 plan below says "conditions on the key column" -- that requires a
> deliberate semantics extension (per-condition key/value selector) before the
> planner can push predicates into the index. Do not silently flip this.

> **Semantics extension decision (M4.1, 2026-10-09 -- resolved additively):**
> key-range access became a first-class, **additive** query API:
> `query_key_range(q, low, high)` restricts the scanned key range to
> `[low, high]` inclusive *before* anything else runs; `QueryCondition` still
> filters **values**. Both axes compose in a fixed order:
> **key range -> value conditions -> offset -> limit**. The planner pushes the
> bounds into the index (`PointLookup` when `low == high`, `IndexRange`
> otherwise, `FullScan` without bounds) and `estimated_rows` is the clamped
> range width for bounds plans, the tree size for a full scan. A seeded
> property test (200 cases) pins plan results equal to a brute-force model.
> No per-condition key/value selector was added -- conditions stay value-only.

## Building a query -- `xiom.db.engine.core` (`src/engine/core.xi`)

```
QueryOp       = Eq | Neq | Lt | Lte | Gt | Gte
QueryCondition= { op: QueryOp, value: Int }
Query         = { conditions: Vec[QueryCondition], limit: Int, offset: Int,
                  has_bounds: Bool, low: Int, high: Int }
query_key_range(q, low, high)   // additive key bounds (requires low <= high)
```

| Builder | Contract | Effect |
|---------|----------|--------|
| `query_new()` | -- | Empty query, no limit/offset. |
| `query_where(q, op, value)` | -- | Append a condition (AND semantics). |
| `query_limit(q, limit)` | `requires: limit > 0` | Cap result count. |
| `query_offset(q, offset)` | `requires: offset >= 0` | Skip a prefix. |
| `query_reset(q)` | -- | Clear conditions, limit, offset. |

## Execution model -- `query_execute(q, tree)`

```
                 +---------------------------+
   tree -------> | btree_to_vec (in-order)   |  values ascending by key
                 `------------+--------------+
                              v
                 +---------------------------+
                 | filter: matches_all(AND)  |  every condition must hold
                 `------------+--------------+
                              v
                 +---------------------------+
                 | skip `offset` matches     |
                 `------------+--------------+
                              v
                 +---------------------------+
                 | take first `limit` (if >0)|
                 `------------+--------------+
                              v
                          Vec[Int] result
```

1. **Scan** -- `btree_to_vec(tree)` yields all values in key order.
2. **Filter** -- `matches_all_conditions` requires every `QueryCondition` to pass (`test_condition` implements the six operators).
3. **Offset** -- the first `offset` *matching* values are skipped.
4. **Limit** -- if `limit > 0` and more than `limit` remain, the tail is truncated.

**Determinism:** because the scan order is the tree's in-order sequence, the same `(tree, query)` always yields the same vector. See [contracts-and-invariants.md](contracts-and-invariants.md) S6.

**Complexity:** O(n) scan + O(n-c) filtering for `c` conditions. Fine for small/medium data; the planner removes the full scan when a condition constrains the key.

## Durable handle -- `DBFile`

`DBFile` (`src/engine.xi`) exposes the same read paths over its recovered tree:

| Call | Semantics |
|------|-----------|
| `db_file_get(key)` | point lookup (`btree_search`) |
| `db_file_range(low, high)` | keys in `[low, high]` inclusive, values in key order (`btree_range_query`) |
| `db_file_query(query)` | planned value-filter query: key bounds (when set) push into the index, then value conditions / offset / limit |

The same value-vs-key split applies: `QueryCondition` filters **values**;
`db_file_range` is the key-range access. Queries run against the state
reconstructed from the checkpoint snapshot + WAL tail replay, so they are
valid immediately after `db_file_open`.

## The planner -- `query/planner.xi` *(scaffold, Phase 3)*

```
PlanKind  = FullScan | IndexRange | PointLookup
QueryPlan = { kind, low, high, has_bounds, estimated_rows }
```

- `plan_query(q, tree)` -- currently returns a `FullScan` plan with `estimated_rows = btree_size(tree)`.
- `execute_plan(plan, q, tree)` -- dispatches on `kind`; every branch presently delegates to `query_execute`.

**Phase 3 plan:**
1. Inspect conditions on the key column; derive a tight `[low, high]`.
2. For an equality, emit `PointLookup` -> `btree_search`.
3. For a bounded range, emit `IndexRange` -> `btree_range_query(tree, low, high)` (O(log n + k)), then apply residual predicates.
4. Cost `FullScan` vs. `IndexRange` using `estimated_rows` and pick the cheaper.

Because execution already flows through `plan_query` -> `execute_plan` conceptually, wiring the planner in does not change the query builder or the engine's `engine_query` call site.
