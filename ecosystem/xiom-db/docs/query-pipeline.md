# Query Pipeline

The query subsystem turns a declarative `Query` into a set of matching values. In Phase 0 it always runs a full in-order scan; the `planner` scaffold marks where index-aware execution lands in Phase 3.

## Building a query — `query/query.xi`

```
QueryOp       = Eq | Neq | Lt | Lte | Gt | Gte
QueryCondition= { op: QueryOp, value: Int }
Query         = { conditions: Vec[QueryCondition], limit: Int, offset: Int }
```

| Builder | Contract | Effect |
|---------|----------|--------|
| `query_new()` | — | Empty query, no limit/offset. |
| `query_where(q, op, value)` | — | Append a condition (AND semantics). |
| `query_limit(q, limit)` | `requires: limit > 0` | Cap result count. |
| `query_offset(q, offset)` | `requires: offset >= 0` | Skip a prefix. |
| `query_reset(q)` | — | Clear conditions, limit, offset. |

## Execution model — `query_execute(q, tree)`

```
                 ┌───────────────────────────┐
   tree ───────► │ btree_to_vec (in-order)   │  values ascending by key
                 └────────────┬──────────────┘
                              ▼
                 ┌───────────────────────────┐
                 │ filter: matches_all(AND)  │  every condition must hold
                 └────────────┬──────────────┘
                              ▼
                 ┌───────────────────────────┐
                 │ skip `offset` matches     │
                 └────────────┬──────────────┘
                              ▼
                 ┌───────────────────────────┐
                 │ take first `limit` (if >0)│
                 └────────────┬──────────────┘
                              ▼
                          Vec[Int] result
```

1. **Scan** — `btree_to_vec(tree)` yields all values in key order.
2. **Filter** — `matches_all_conditions` requires every `QueryCondition` to pass (`test_condition` implements the six operators).
3. **Offset** — the first `offset` *matching* values are skipped.
4. **Limit** — if `limit > 0` and more than `limit` remain, the tail is truncated.

**Determinism:** because the scan order is the tree's in-order sequence, the same `(tree, query)` always yields the same vector. See [contracts-and-invariants.md](contracts-and-invariants.md) §6.

**Complexity:** O(n) scan + O(n·c) filtering for `c` conditions. Fine for small/medium data; the planner removes the full scan when a condition constrains the key.

## The planner — `query/planner.xi` *(scaffold, Phase 3)*

```
PlanKind  = FullScan | IndexRange | PointLookup
QueryPlan = { kind, low, high, has_bounds, estimated_rows }
```

- `plan_query(q, tree)` — currently returns a `FullScan` plan with `estimated_rows = btree_size(tree)`.
- `execute_plan(plan, q, tree)` — dispatches on `kind`; every branch presently delegates to `query_execute`.

**Phase 3 plan:**
1. Inspect conditions on the key column; derive a tight `[low, high]`.
2. For an equality, emit `PointLookup` → `btree_search`.
3. For a bounded range, emit `IndexRange` → `btree_range_query(tree, low, high)` (O(log n + k)), then apply residual predicates.
4. Cost `FullScan` vs. `IndexRange` using `estimated_rows` and pick the cheaper.

Because execution already flows through `plan_query` → `execute_plan` conceptually, wiring the planner in does not change the query builder or the engine's `engine_query` call site.
