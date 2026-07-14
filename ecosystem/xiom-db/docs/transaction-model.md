# Transaction Model

> **Status:** Phase 0 — `xiom.db.txn.transaction` implements the transaction **state machine** and operation accumulation only. There is no isolation, locking, or MVCC yet; those arrive in Phase 3.

## Types — `txn/transaction.xi`

```
WALOp   = Insert | Update | Delete            // coarse operation tag
TxState = Active | Committed | Aborted
Transaction = { id: UInt64, state: TxState, operations: Vec[WALOp] }
```

## State machine

```
        Transaction.new(id)
              │
              ▼
        ┌──────────┐   commit()   ┌────────────┐
        │  Active  │─────────────►│ Committed  │  (terminal)
        └──────────┘              └────────────┘
              │ abort()
              ▼
        ┌──────────┐
        │ Aborted  │  (terminal)
        └──────────┘
```

- `Transaction.new(id)` — starts in `Active` with no operations.
- `Transaction.add_op(op)` — records intent; returns a new `Transaction` with the op appended (values are immutable, so mutators return a fresh value).
- `Transaction.commit()` — transitions to `Committed`, preserving the operation list.
- `Transaction.abort()` — transitions to `Aborted`, preserving the operation list.
- `Transaction.is_active()` — `state == Active`.

**Invariant:** `Committed` and `Aborted` are terminal. Once a transaction leaves `Active` it must not transition again. In this phase the type does not enforce that at compile time; call sites must treat the terminal states as final. Enforcement (and rejection of `add_op` after commit) is a Phase 3 hardening item.

## Relationship to the WAL

Today the engine logs each mutation directly to the WAL with a monotonic timestamp; it does not group them under a transaction id. `Transaction` is the scaffolding that Phase 3 uses to:

1. Tag WAL records with a `TxnId` (from `xiom.core.ids`).
2. Only make a transaction's effects visible after `commit`.
3. Roll back an `Aborted` transaction's operations.

## Phase 3 direction

| Capability | Plan |
|------------|------|
| Atomic commit/rollback | Buffer a transaction's ops; apply on commit, discard on abort |
| Isolation (MVCC) | Version-stamped rows; snapshot reads keyed by start-LSN |
| Conflict detection | Write-write conflict checks via `xiom.core.txn.txn_manager` |
| Durable transaction boundaries | Begin/commit markers in the WAL segment |

The `txn/transaction.xi` boundary is where `xiom.core.txn` (Txn, TxnManager, snapshots) is integrated without disturbing the index or query layers.
