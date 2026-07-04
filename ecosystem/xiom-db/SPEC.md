# XiomDB Specification

## Architecture Overview

XiomDB is a production-grade embedded database type system written in pure XIOM. It provides in-memory data structures for storage, indexing, crash recovery, and query execution — designed to be embedded directly into XIOM applications without external dependencies.

### Architecture Diagram

```
┌─────────────────────────────────────────────┐
│                  Engine                      │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
│  │  Query   │  │   BTree   │  │    WAL    │  │
│  │  Engine  │──│   Index   │──│  Recovery │  │
│  └─────────┘  └──────────┘  └───────────┘  │
│        │            │              │         │
│  ┌─────┴────────────┴──────────────┴──────┐ │
│  │            Core Types                   │ │
│  │  Page·Schema·Row·ResultSet·Transaction  │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Module Dependency Graph

```
engine.xi ──→ btree.xi, wal.xi, query.xi
wal.xi    ──→ btree.xi
query.xi  ──→ btree.xi
btree.xi  ──→ (self-contained)
types.xi  ──→ (self-contained)
```

---

## Module Documentation

### 1. `xiom.db.types` — Core Types (`src/types.xi`)

Low-level storage primitives and schema definitions.

**Storage Layer**
- `Page`: 4KB data page with `id` (UInt64), `data` (Vec[UInt8]), and `checksum` (UInt32). Used by the buffer pool for caching.
- `BufferPool`: LRU-style page cache with hit/miss tracking and capacity-limited storage.

**Schema Layer**
- `ColumnType` enum: `IntType | FloatType | BoolType | StringType | BytesType`
- `ColumnDef`: Column metadata — name, type, nullability, default value.
- `Schema`: Table definition with named columns and a primary key index.
- `IndexDef`: Index specification with name, table reference, column index, type (BTree/Hash), and uniqueness flag.
- `IndexType` enum: `BTreeIndex | HashIndex`

**Data Layer**
- `Row`: Record with `id` (UInt64) and `data` (Vec[Int]). Supports column access by index.
- `ResultSet`: Columnar result container with named columns and row iteration.

**Transaction Layer**
- `Transaction`: ACID transaction with WAL operation tracking and Active/Committed/Aborted lifecycle.
- `TxState` enum: `Active | Committed | Aborted`
- `WALOp` enum: `Insert | Update | Delete`

**Error Handling**
- `DbError` enum: `NotFound | DuplicateKey | ConstraintViolation | SchemaMismatch | StorageError | Corruption`
- `DbResult[T]`: Typed result alias `Result[T, DbError]`

**Configuration**
- `DatabaseConfig`: Tuning parameters — page size, buffer pool capacity, WAL toggle, B-tree order.
- `StorageEngine`: Configuration + BufferPool composite.

---

### 2. `xiom.db.btree` — B-Tree Index (`src/btree.xi`)

In-memory B-Tree implementation using a flat array representation.

**Design Rationale**
B-tree nodes cannot reference each other directly in XIOM structs (no recursive borrows). The solution stores all nodes in a flat `Vec[BTreeNode]` and uses integer indices for parent-child references.

**Types**
- `BTree`: Contains `root` (Int index into nodes), `order` (max children per node), and `nodes` (Vec[BTreeNode]).
- `BTreeNode`: Contains `keys` (Vec[Int]), `values` (Vec[Int]), `children` (Vec[Int] of node indices), and `is_leaf` (Bool).

**API Reference**

| Function | Signature | Description |
|---|---|---|
| `btree_new` | `(order: Int) -> BTree` | Creates empty B-tree of given order |
| `btree_insert` | `(tree: &mut BTree, key: Int, value: Int) -> Bool` | Inserts key-value; returns false on duplicate |
| `btree_search` | `(tree: &BTree, key: Int) -> Option[Int]` | Returns value for key or None |
| `btree_delete` | `(tree: &mut BTree, key: Int) -> Bool` | Deletes key; returns false if not found |
| `btree_range_query` | `(tree: &BTree, low: Int, high: Int) -> Vec[Int]` | Returns values with keys in [low, high] |
| `btree_size` | `(tree: &BTree) -> Int` | Total key count |
| `btree_min` | `(tree: &BTree) -> Option[Int]` | Smallest key's value |
| `btree_max` | `(tree: &BTree) -> Option[Int]` | Largest key's value |
| `btree_to_vec` | `(tree: &BTree) -> Vec[Int]` | In-order traversal of all values |

**Internal Operations**
- `split_root`: Splits root when full, creating new root level.
- `split_child`: Splits a full child node, promoting median to parent.
- `insert_nonfull`: Recursive insertion into non-full subtree.
- `delete_from_node`: Recursive deletion handling underflow via borrow/merge.
- `fill_child`: Ensures child has enough keys before descent (borrow from sibling or merge).

**Complexity**
- Search: O(log n)
- Insert: O(log n) with at most O(log n) splits
- Delete: O(log n) with at most O(log n) merges
- Range query: O(log n + k) where k is result size

---

### 3. `xiom.db.wal` — Write-Ahead Log (`src/wal.xi`)

Durability and crash recovery through sequential logging.

**Types**
- `WALOpType` enum: `InsertOp | UpdateOp | DeleteOp`
- `WALEntry`: Operation record with `op`, `key`, `value`, and `timestamp`.
- `WAL`: Ordered sequence of `WALEntry` records.

**API Reference**

| Function | Signature | Description |
|---|---|---|
| `wal_new` | `() -> WAL` | Creates empty log |
| `wal_append` | `(wal: &mut WAL, entry: WALEntry)` | Appends entry to log |
| `wal_replay` | `(wal: &WAL, target: &mut BTree) -> Bool` | Replays all entries onto target B-tree; returns false if any entry failed |
| `wal_clear` | `(wal: &mut WAL)` | Empties the log |
| `wal_truncate` | `(wal: &mut WAL, before_timestamp: Int)` | Removes entries with timestamp < threshold |
| `wal_len` | `(wal: &WAL) -> Int` | Entry count |
| `wal_is_empty` | `(wal: &WAL) -> Bool` | True if log is empty |
| `wal_entry_count` | `(wal: &WAL, op_filter: WALOpType) -> Int` | Count of entries matching operation type |

**Replay Semantics**
- `InsertOp`: Calls `btree_insert`; skips duplicates (idempotent).
- `UpdateOp`: Deletes old key then inserts new value; logs failure if key not found.
- `DeleteOp`: Calls `btree_delete`; logs failure if key not found.
- Returns `false` if any operation failed, but continues replay for remaining entries.

---

### 4. `xiom.db.query` — Query Engine (`src/query.xi`)

Declarative query construction and execution against B-tree indexes.

**Types**
- `QueryOp` enum: `Eq | Neq | Lt | Lte | Gt | Gte` — comparison operators.
- `QueryCondition`: Single predicate with an operator and a target value.
- `Query`: Collection of conditions with optional `limit` and `offset`.

**API Reference**

| Function | Signature | Description |
|---|---|---|
| `query_new` | `() -> Query` | Creates query with no conditions, no limit/offset |
| `query_where` | `(q: &mut Query, op: QueryOp, value: Int)` | Adds a condition (AND semantics) |
| `query_limit` | `(q: &mut Query, limit: Int)` | Sets result count cap (0 = unlimited) |
| `query_offset` | `(q: &mut Query, offset: Int)` | Sets skip count before first result |
| `query_execute` | `(q: &Query, tree: &BTree) -> Vec[Int]` | Runs query against tree, returns matching values |
| `query_condition_count` | `(q: &Query) -> Int` | Number of active conditions |
| `query_has_limit` | `(q: &Query) -> Bool` | Whether a limit is set |
| `query_has_offset` | `(q: &Query) -> Bool` | Whether an offset is set |
| `query_reset` | `(q: &mut Query)` | Clears all conditions, limit, and offset |

**Execution Model**
1. All values are extracted from the B-tree via in-order traversal (`btree_to_vec`).
2. Each value is tested against all conditions (AND conjunction).
3. Matching values are collected, offset is applied, then limit truncation.
4. If limit = 0, all matching results are returned.

**Example**
```
var q = query_new();
query_where(&mut q, QueryOp.Gt, 10);
query_where(&mut q, QueryOp.Lt, 50);
query_limit(&mut q, 20);
var results = query_execute(&q, &tree);
// Returns at most 20 values where 10 < value < 50
```

---

### 5. `xiom.db.engine` — Database Engine (`src/engine.xi`)

Unified database facade combining B-tree storage, WAL durability, and query execution.

**Types**
- `Engine`: Holds a `BTree`, a `WAL`, and an internal `timestamp_counter` (monotonic).

**API Reference**

| Function | Signature | Description |
|---|---|---|
| `engine_new` | `(order: Int) -> Engine` | Creates engine with fresh tree and empty WAL |
| `engine_insert` | `(eng: &mut Engine, key: Int, value: Int) -> Bool` | Logs to WAL then inserts into B-tree |
| `engine_get` | `(eng: &Engine, key: Int) -> Option[Int]` | Reads value by key |
| `engine_delete` | `(eng: &mut Engine, key: Int) -> Bool` | Logs delete to WAL then removes from tree |
| `engine_update` | `(eng: &mut Engine, key: Int, value: Int) -> Bool` | Logs update to WAL, deletes old, inserts new |
| `engine_query` | `(eng: &Engine, query: &Query) -> Vec[Int]` | Executes query against engine's tree |
| `engine_recover` | `(eng: &mut Engine) -> Bool` | Recreates tree from WAL replay |
| `engine_range_query` | `(eng: &Engine, low: Int, high: Int) -> Vec[Int]` | Range scan on keys |
| `engine_size` | `(eng: &Engine) -> Int` | Total records in tree |
| `engine_wal_size` | `(eng: &Engine) -> Int` | WAL entry count |
| `engine_flush_wal` | `(eng: &mut Engine)` | Clears WAL (checkpoint) |
| `engine_truncate_wal` | `(eng: &mut Engine, before_timestamp: Int)` | Removes old WAL entries |

**Write Path**
```
engine_insert(key, value)
  → next_timestamp()           // get monotonic TS
  → wal_append(InsertOp entry) // durability first
  → btree_insert()             // then index
```

**Recovery Path**
```
engine_recover()
  → btree_new()          // fresh empty tree
  → wal_replay()         // rebuild from log
  → timestamp_counter = 0
```

---

## Design Notes

### Flat Array B-Tree
Traditional B-tree implementations use recursive pointers between nodes. XIOM's borrow checker prohibits storing references inside structs (no `&BTreeNode` fields). The flat array approach — storing all nodes in a `Vec` and using integer indices — avoids this limitation while maintaining O(log n) access. Node splitting/merging creates new nodes by appending to the vec and updating parent indices.

### WAL Before Data
All mutating operations (`engine_insert`, `engine_delete`, `engine_update`) follow the WAL-before-data principle: the operation is logged to the WAL first, and only then applied to the B-tree. This ensures that after a crash, `engine_recover()` can reconstruct the tree state from the log.

### Monotonic Timestamps
The engine uses an internal integer counter rather than wall-clock time for WAL timestamps. This guarantees strict ordering and avoids clock skew issues in embedded contexts.

### Query Execution Strategy
The query engine performs a full table scan (`btree_to_vec` → filter → offset → limit). This is suitable for small to medium datasets. Future optimizations could leverage B-tree range queries for conditions on the key column, or add secondary indexes.

### Error Strategy
Operations return `Bool` (success/failure) or `Option[T]` (presence/absence) rather than panicking. The `DbError` enum in `types.xi` provides typed error codes for the `DbResult[T]` type alias, enabling caller-side error discrimination without exception mechanisms.

### Buffer Pool
The `BufferPool` in `types.xi` provides a simple direct-mapped page cache. Pages are indexed by `id % capacity`. While less sophisticated than LRU, it has O(1) lookup and constant memory overhead — suitable for embedded use cases where predictable performance matters more than optimal hit rates.

---

## File Layout

```
ecosystem/xiom-db/
├── package.xi          # Package manifest
├── SPEC.md             # This specification
└── src/
    ├── types.xi        # Core types: Page, Schema, Row, Transaction, DbError
    ├── btree.xi        # B-Tree index: insert, search, delete, range query
    ├── wal.xi          # Write-Ahead Log: append, replay, truncate
    ├── query.xi        # Query engine: conditions, limit/offset, execution
    └── engine.xi       # Database engine: unified insert/get/delete/query/recover
```
