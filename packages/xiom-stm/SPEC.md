# xiom.stm -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.stm` (`src/stm.xi`). Pure XIOM, no FFI.

## 1. Scope

Deterministic single-threaded software-transactional-memory primitives,
expressed as explicit model steps:

- **versioned cells** (TVar-like) holding a committed `Int` value and the
  version of the commit that last wrote them;
- **transactions** with an explicit state machine and a flattened read set
  and write set;
- **optimistic commit** that validates recorded versions, applies buffered
  writes under one shared commit version, or aborts with a reason code;
- **deterministic retry bookkeeping** with a per-transaction retry budget;

plus state-dump helpers for tests and pinned error/reason catalogs. Every
fallible operation returns `Result[Int, StmError]`.

The module never spawns a thread, never executes an atomic instruction, never
reads a clock and never calls FFI. Interleavings are modeled, not executed:
the caller drives them explicitly (begin A, read A, begin B, commit B,
commit A, ...), so every conflict and retry outcome is reproducible.

## 2. Non-goals

- Real threads, atomics, fences/memory ordering, blocking or spinning.
- Snapshot isolation of reads: reads observe the latest committed value;
  conflicts are detected at commit time (optimistic validation), not at read
  time.
- Generic payloads: cells hold `Int` only.
- Multiple cell spaces or transaction registries: state is module-level and
  `stm_reset()` is a full reset.
- Automatic retry loops: `stm_retry` is an explicit call; there is no
  `retry`-on-variable construct and no scheduler.
- Garbage collection of set entries: retried attempts are isolated by an
  epoch counter; stale entries are inert and retained until `stm_reset()`.
- Any FFI.

## 3. Cells and versioning

Each cell has:

- `value`: the committed `Int` payload (initial value at creation);
- `version`: the version of the commit that last wrote it (0 until the first
  such commit);
- `commits`: number of commits that wrote it.

A single **version clock** starts at 0. Every successful commit advances the
clock by exactly one, and that new version is assigned to every cell written
by the commit. A read-only commit (empty write set) still advances the clock.
A conflict abort or a user abort never changes the clock and never changes
any cell.

Cell ids are dense from 0 in creation order and stable until `stm_reset()`.

## 4. Transaction state machine

```
                stm_txn_begin()
                       |
                       v
                  +---------+  stm_commit() ok        +-----------+
                  | Active  | ----------------------> | Committed |
                  | state 1 |                         |  state 2  |
                  +---------+                         +-----------+
                    |   ^
     stm_abort()    |   |  stm_retry()  (retries < max)
     commit conflict|   |
                    v   |
                  +-----------+
                  | Aborted   |   state 3
                  +-----------+
```

- `stm_txn_begin()` creates a transaction in `Active` with attempt 1, retry
  count 0, abort reason 0, `start_version = stm_clock()` and empty logical
  read/write sets.
- `stm_read`, `stm_write`, `stm_commit` and `stm_abort` require `Active`;
  otherwise `Err` code 4 with `extra = current state`.
- A successful commit moves `Active -> Committed`; a conflict abort and
  `stm_abort` move `Active -> Aborted`. Both are terminal for the current
  attempt.
- `stm_retry` is the only transition out of `Aborted` (to `Active`); it is
  rejected with `Err` code 4 when the transaction is not `Aborted`, and with
  `Err` code 8 when the retry budget is exhausted (state stays `Aborted`).
- `Committed` and `Aborted` are terminal: `stm_commit`, `stm_abort` and the
  transactional operations reject them with `Err` code 4.

## 5. Read set and write set

Entries are stored in flattened module tables with `(txn, epoch)` identity;
an `stm_retry` increments the transaction's epoch, which makes every entry
of the previous attempt inert (sizes and lookups count only the current
epoch).

**Read** (`stm_read(txn, cell)`):

1. If the cell is in the write set, return the buffered value
   (read-your-writes) and do not add a read-set entry.
2. Otherwise, record the cell's current version in the read set if this is
   the first read of that cell in the current attempt, then return the
   cell's committed value.
3. Later reads of the same cell return the latest committed value but do not
   add entries.

Because every read returns the latest committed value, a transaction that
re-reads a cell after a competing commit observes the new value, yet its
recorded first-read version is stale, so its commit aborts. This "reads are
current, validation is at commit" rule is pinned by test 19.

**Write** (`stm_write(txn, cell, value)`):

1. If the cell already has a write-set entry in the current attempt, replace
   the buffered value (the recorded version is kept).
2. Otherwise, append an entry recording the cell's current version at
   first-write time, then buffer the value.
3. Writes are invisible outside the transaction (and to
   `stm_cell_value`) until commit. `Ok` carries the write-set size.

## 6. Commit validation algorithm

`stm_commit(txn)` runs, in this exact order:

1. If `txn` is invalid: `Err` code 3. If not `Active`: `Err` code 4.
2. **Read-set validation**: scan the current-epoch read-set entries in
   insertion order; the first entry whose recorded version differs from the
   cell's current version is a read conflict (abort reason 1).
3. If no read conflict, **write-set validation**: scan the current-epoch
   write-set entries in insertion order; the first entry whose recorded
   version differs from the cell's current version is a write-write
   conflict (abort reason 2).
4. On a conflict: set the state to `Aborted`, record the conflicting cell and
   the reason, count one abort and one conflict, apply nothing, change no
   version, and return `Err` code 7 with `cell = first conflicting cell` and
   `extra = abort reason`.
5. Otherwise: `new_version = clock + 1`; for every current-epoch write-set
   entry in insertion order set `cell.value = buffered value`,
   `cell.version = new_version`, increment `cell.commits`; then set
   `clock = new_version`, set the state to `Committed`, count one commit and
   return `Ok(new_version)`.

Blind writes (a write to a cell never read) are validated by step 3; that is
the classic write-write conflict. A transaction's own writes never conflict
with themselves.

## 7. Abort reasons and error catalog

Abort reasons (`stm_abort_reason_message`), stored per transaction since the
last begin or retry:

| Reason | Message | Set by |
|---|---|---|
| 0 | `stm: no abort` | begin / retry |
| 1 | `stm: read conflict` | commit step 2 |
| 2 | `stm: write conflict` | commit step 3 |
| 3 | `stm: user abort` | `stm_abort` |
| other | `stm: unknown abort reason` | -- |

`StmError` codes (`stm_error_message`), fields `(code, txn, cell, extra)`:

| Code | Message | txn | cell | extra |
|---|---|---|---|---|
| 1 | `stm: cell capacity exceeded` | -1 | -1 | `stm_max_cells()` |
| 2 | `stm: invalid cell id` | txn | cell | -1 |
| 3 | `stm: invalid transaction id` | txn | cell | -1 |
| 4 | `stm: transaction is not active` | txn | cell (ops) / -1 | current state |
| 5 | `stm: read set is full` | txn | cell | `stm_max_read_set_entries()` |
| 6 | `stm: write set is full` | txn | cell | `stm_max_write_set_entries()` |
| 7 | `stm: transaction conflict` | txn | conflicting cell | abort reason |
| 8 | `stm: retry limit reached` | txn | -1 | `stm_max_retries()` |
| 9 | `stm: transaction capacity exceeded` | -1 | -1 | `stm_max_txns()` |
| other | `stm: unknown error` | -- | -- | -- |

`stm_abort` returns `Ok(3)` (the user abort reason). Every failed operation
leaves committed state untouched; a failed first read/write (codes 5/6) does
not add an entry.

## 8. Retry bookkeeping

Each transaction tracks `attempt` (1-based), `retries` (granted so far) and
`start_version`. `stm_retry(txn)`:

1. requires an `Aborted` transaction (`Err` code 4 otherwise);
2. requires `retries < stm_max_retries()` (`Err` code 8 otherwise, state
   unchanged);
3. increments `epoch`, `attempt` and `retries`, sets
   `start_version = stm_clock()`, clears the abort reason and conflict cell,
   sets the state to `Active`, counts one retry, and returns
   `Ok(new attempt)`.

The retry budget is deterministic: with the default limit 4, attempts 1..5
can run (begin plus four retries); the fifth `stm_retry` after the fifth
abort fails with code 8. `stm_txn_read_set_size` / `stm_txn_write_set_size`
report only the current attempt's entries (0 immediately after a retry).

## 9. Limits

| Limit | Value | Accessor | Enforced at |
|---|---|---|---|
| Cells per reset | 1024 | `stm_max_cells()` | `stm_cell_new` (code 1) |
| Transactions per reset | 1024 | `stm_max_txns()` | `stm_txn_begin` (code 9) |
| Read-set entries per transaction | 64 | `stm_max_read_set_entries()` | `stm_read` (code 5) |
| Write-set entries per transaction | 64 | `stm_max_write_set_entries()` | `stm_write` (code 6) |
| Retries per transaction | 4 | `stm_max_retries()` | `stm_retry` (code 8) |

Global flattened tables are additionally capped at 8192 entries each; hitting
a global cap reports the same code (5/6) with the same per-transaction
`extra`. Transaction handles are dense from 0 and never reused until
`stm_reset()`.

## 10. Test plan

`tests/test_conformance.xi` runs 20 checks, each starting from
`stm_reset()`:

| # | Check | Pins |
|---|---|---|
| 1 | cells are created with committed values at version 0 | ids, values, version 0, clock 0 |
| 2 | state machine: begin, empty commit, terminal states reject ops | Ok values, state 2, codes 4 |
| 3 | first read records the version; re-reads dedupe | read set, reads stat |
| 4 | write buffering with read-your-writes | buffered value, ws size, commit |
| 5 | one commit version applies to every buffered write | shared version, clock +1 |
| 6 | read conflict aborts commit and applies nothing | code 7 reason 1, no partial apply |
| 7 | blind-write conflicts are detected at commit (write-write) | code 7 reason 2 |
| 8 | read-only commits advance the clock but write no cell | clock vs cell version |
| 9 | explicit abort and the deterministic retry budget | reason 3, attempts 2..5, code 8 |
| 10 | retry after a conflict re-reads fresh state and commits | epoch isolation |
| 11 | invalid cell and transaction handles are rejected | codes 2/3 quads |
| 12 | read set capacity is enforced per transaction | code 5, extra 64 |
| 13 | write set capacity is enforced and applied in order | code 6, commit contents |
| 14 | cell and transaction capacity limits | codes 1/9, max accessors |
| 15 | aborted transactions reject reads, writes and commits | code 4, preserved metadata |
| 16 | state dumps pin structure and counters | dump fragments, invalid txn dump |
| 17 | error and abort reason catalogs are pinned | all 9 codes + reasons 0..3 |
| 18 | statistics accumulate deterministically | all 7 counters |
| 19 | interleaved transactions observe latest committed values | current reads, stale validation |
| 20 | stress: 40 conflict/retry/commit cycles stay consistent | clock 80, 40 commits/aborts/retries |

## 11. Dump formats

Test-facing one-line formats (fragments, not whole lines, are pinned where
noted):

```
cells[n=<count> clock=<clock>] c<id>[v=<value> ver=<version> commits=<count>] ...
txn[<id> state=<state> attempt=<n> retries=<n> start=<v> rs=<n> ws=<n> abort=<reason> conflict=<cell>]
stats[commits=<n> aborts=<n> conflicts=<n> retries=<n> reads=<n> writes=<n> user_aborts=<n>]
```

`stm_txn_dump` on an invalid handle returns exactly `txn[invalid]`.
`stm_dump()` is `stm_cell_dump()` + newline + `stm_stats_dump()`.
