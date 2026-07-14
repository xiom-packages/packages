# Contracts & Invariants

Every correctness rule in xiom-db is expressed either as a `requires:` / `ensures:` clause on a function or as an invariant maintained by a module. This document is the exhaustive catalog. Shared predicates live in `xiom.db.contracts` and `xiom.core.contracts` so the same rule is used at both the contract site and any runtime check.

## 1. B-tree key ordering (index/btree.xi)

**Invariant:** within any node, `keys` are **strictly ascending** and contain **no duplicates**; for an internal node, all keys in `children[i]` are less than `keys[i]`, and all keys in `children[i+1]` are greater.

- Enforced on write: `btree_insert` first calls `btree_search` and returns `false` if the key already exists, so duplicates never enter the tree.
- Enforced on split/merge: `split_root`, `split_child`, `merge_children`, `borrow_from_left/right` preserve ordering by construction.
- Predicate: `contracts.sorted_keys(keys)` returns true only for a strictly ascending run (stronger than the non-decreasing `xiom.core.contracts.is_sorted_ints`).
- `btree_new(order)` — **`requires: order >= 3`**. Below 3, a node cannot split into two non-empty children separated by a median key, so balancing is impossible. Mirrored by `contracts.valid_btree_order`.
- `btree_range_query(low, high)` — **`requires: low <= high`**. Mirrored by `contracts.valid_range`.

**Balance invariant:** every leaf is at the same depth; non-root nodes hold between `ceil(order/2)-1` and `order-1` keys. Deletion restores this via `fill_child` (borrow from a sibling with spare keys, else merge).

## 2. WAL-before-data (engine.xi)

**Invariant:** for every mutation, the WAL record is appended **before** the index is modified.

- `engine_insert` / `engine_delete` / `engine_update` all execute `next_timestamp()` → `wal_append(...)` → `btree_*` in that fixed order.
- **Consequence (recovery contract):** the index is always reconstructible from the log via `wal_replay`. `engine_recover` guarantees that after it returns, the tree equals the replay of the full log onto an empty tree.

## 3. Monotonic WAL ordering (engine.xi)

**Invariant:** WAL timestamps are strictly increasing.

- Guaranteed because `next_timestamp` is the single source (`timestamp_counter = timestamp_counter + 1`), and no other module writes it.
- `wal_truncate(before_ts)` — **`requires: before_timestamp >= 0`**. Related core predicate: `xiom.core.contracts.is_valid_lsn_ordering` for the Phase 2 LSN form.

## 4. Page integrity (storage/page.xi)

**Invariant:** a page's stored `checksum` equals the checksum of its `data`.

- `Page.new(id, data, checksum)` — **`requires: data.len() <= 4096`** (a page fits its block).
- `Page.is_valid()` recomputes and compares; a mismatch signals `Corruption`.
- `BufferPool.new(capacity)` — **`requires: capacity >= 1`** (the direct-mapped index `id % capacity` needs a non-zero modulus).
- Related core predicate: `xiom.core.contracts.is_valid_page_size` (power-of-two, 512..65536), used by `config.database_config_validate`.

## 5. Configuration validity (config.xi)

**Contract:** `database_config_validate(cfg)` is true iff:
- `is_valid_page_size(page_size)` (power of two in [512, 65536]),
- `buffer_pool_capacity >= 1`,
- `btree_order >= 3`.

`db_open` / `engine_new` carry `requires: order >= 3` so an invalid order cannot reach the index.

## 6. Query determinism (query/query.xi)

**Invariant:** `query_execute` is deterministic and order-stable.

- Values are visited in the B-tree's **in-order** sequence (`btree_to_vec`), which is ascending by key.
- Filtering applies all conditions with **AND** semantics; offset skips a prefix; limit truncates the tail.
- `query_limit(limit)` — **`requires: limit > 0`** (absence of a limit is expressed by not setting one).
- `query_offset(offset)` — **`requires: offset >= 0`**.
- Given the same tree and query, the result vector is identical every run.

## 7. Schema validity (catalog/schema_validator.xi)

**Contract:** `validate_schema(schema)` returns `Ok(true)` iff:
- at least one column,
- `0 <= primary_key < column_count`,
- all column names unique (else `ConstraintViolation`).

`validate_index(idx, schema)` requires the index's table to match and its column to be in range. `validate_column` requires a non-empty name (type/default compatibility is `TODO(Phase 4)`).

## 8. Tuple framing (storage/tuple.xi)

**Contract:** `tuple_decode(buf)` returns `Err(Corruption)` unless `buf` is well-framed: at least `[id, len]`, `len >= 0`, and `buf.len() >= 2 + len`. `tuple_encode`/`tuple_decode` are inverse for valid rows.

## 9. Facade lifecycle (api/database.xi)

**Invariant:** a closed `Database` performs no work.

- After `db_close`, `open == false`; every subsequent `db_*` call returns a safe default (`false`, `None`, or an empty vector) instead of touching the engine.
- `db_open(order)` / `db_open_with(config)` — **`requires: order >= 3`** / `config.btree_order >= 3`.

---

## Predicate reference

| Predicate | Module | Meaning |
|-----------|--------|---------|
| `valid_btree_order(order)` | db.contracts | `order >= 3` |
| `valid_key(key)` | db.contracts | admissible index key (currently always true for Int) |
| `sorted_keys(keys)` | db.contracts | strictly ascending, no duplicates |
| `valid_range(low, high)` | db.contracts | `low <= high` |
| `non_decreasing(v)` | db.contracts → core | delegates to `is_sorted_ints` |
| `is_valid_page_size(size)` | core.contracts | power of two in [512, 65536] |
| `is_valid_lsn_ordering(prev, next)` | core.contracts | `next > prev` (Phase 2) |
| `database_config_validate(cfg)` | db.config | full config validity |
