# xiom.stm

> **Status:** `incubating` -- conformance-tested (20/20); not yet published on the XIOM registry.
> **Scope:** deterministic single-threaded software-transactional-memory
> primitives: versioned cells (TVar-like), optimistic transactions with
> read/write sets, commit validation, conflict aborts with reason codes and
> retry bookkeeping. A semantic model, not a concurrent runtime: threads,
> atomics and schedulers are out of scope.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_base`).
> Tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

## What it is

`xiom.stm` is a pure XIOM model of optimistic software transactional memory.
It never spawns a thread, never executes an atomic instruction, never reads a
clock and never calls FFI. Interleavings are driven explicitly by the caller
(begin A, read A, begin B, commit B, commit A, ...), so every conflict and
retry outcome is reproducible.

- **Cells (TVar-like)** hold a committed value plus the version of the commit
  that last wrote them. A shared version clock starts at 0 and advances by
  exactly one per successful commit.
- **Transactions** are an explicit state machine: `Active -> Committed` or
  `Active -> Aborted`. Reads record the cell version at first read (read
  set); writes are buffered (write set) and are visible to the writing
  transaction immediately (read-your-writes).
- **Commit** validates the read set and then the write set against current
  cell versions. The first stale entry aborts the transaction with a reason
  code (read conflict / write conflict) and applies nothing. On success every
  buffered write becomes visible with one shared commit version.
- **Retry** is explicit and bounded: `stm_retry` restarts an aborted
  transaction as a fresh attempt with an empty logical read/write set; the
  transaction becomes `Aborted` again only when the abort/retry policy says
  so. There is no spinning.

See `SPEC.md` for the full semantics, the error catalog and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `stm_reset()` | `Unit` | Full reset: cells, transactions, sets, clock and statistics. |
| `stm_clock()` | `Int` | Version of the most recent successful commit (0 initially). |
| `stm_cell_new(initial_value)` | `Result[Int, StmError]` | Create a cell at version 0; `Ok(id)`. `Err` code 1 when at capacity. |
| `stm_cell_value(cell)` / `stm_cell_version(cell)` / `stm_cell_commit_count(cell)` | `Result[Int, StmError]` | Committed value, last-writing version, commit count. `Err` code 2 for an invalid id. |
| `stm_cell_count()` / `stm_cell_dump()` | `Int` / `Str` | Cell count and one-line test dump. |
| `stm_txn_begin()` | `Result[Int, StmError]` | Start an Active transaction; `Ok(txn)`. `Err` code 9 when at capacity. |
| `stm_read(txn, cell)` | `Result[Int, StmError]` | Read with read-your-writes; records the first-read version. `Err` 2/3/4/5. |
| `stm_write(txn, cell, value)` | `Result[Int, StmError]` | Buffer a write; `Ok(write-set size)`. `Err` 2/3/4/6. |
| `stm_commit(txn)` | `Result[Int, StmError]` | Validate and apply; `Ok(new version)`. `Err` 3/4/7 (conflict: reason in `extra`). |
| `stm_abort(txn)` | `Result[Int, StmError]` | Explicit user abort; `Ok(3)`. `Err` 3/4. |
| `stm_retry(txn)` | `Result[Int, StmError]` | New attempt for an Aborted txn; `Ok(attempt)`. `Err` 3/4/8. |
| `stm_txn_state(txn)` | `Result[Int, StmError]` | 1 = Active, 2 = Committed, 3 = Aborted. `Err` code 3. |
| `stm_txn_start_version(txn)` / `stm_txn_attempt(txn)` / `stm_txn_retry_count(txn)` | `Result[Int, StmError]` | Start version, 1-based attempt, retries so far. `Err` code 3. |
| `stm_txn_abort_reason(txn)` / `stm_txn_conflict_cell(txn)` | `Result[Int, StmError]` | Abort reason (0..3) and conflicting cell (-1 none). `Err` code 3. |
| `stm_txn_read_set_size(txn)` / `stm_txn_write_set_size(txn)` | `Result[Int, StmError]` | Live (current-attempt) set sizes. `Err` code 3. |
| `stm_txn_dump(txn)` | `Str` | One-line txn dump; `"txn[invalid]"` for a bad handle. |
| `stm_commits()` / `stm_aborts()` / `stm_conflicts()` / `stm_retries()` / `stm_reads()` / `stm_writes()` / `stm_user_aborts()` | `Int` | Statistics since `stm_reset()`. |
| `stm_stats_dump()` / `stm_dump()` | `Str` | One-line stats dump; `stm_dump()` adds the cell dump line. |
| `stm_max_cells()` / `stm_max_txns()` / `stm_max_retries()` / `stm_max_read_set_entries()` / `stm_max_write_set_entries()` | `Int` | Pinned limits: 1024 / 1024 / 4 / 64 / 64. |
| `stm_error_message(code)` | `Str` | Pinned error text; `"stm: unknown error"` outside the catalog. |
| `stm_abort_reason_message(reason)` | `Str` | Pinned reason text; `"stm: unknown abort reason"` outside the catalog. |

Every `StmError` carries `(code, txn, cell, extra)`: `txn`/`cell` are the
offending handles (-1 when none), `extra` is the bound, state or abort reason
context (-1 when none). Failed calls leave all committed state untouched.

## Install

The package is not on the XIOM registry yet. Once published:

```
xiom pkg install xiom.stm@0.1.0
```

Until then, add this repository as a path dependency (`deps: { "xiom.stm":
"path:../xiom-stm" }`) or copy `src/stm.xi` into your tree.

## Usage

```xi
use xiom.stm;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  stm_reset();
  var cell_a = -1;                       // account A
  var cell_b = -1;                       // account B
  let ca = stm_cell_new(100);
  let cb = stm_cell_new(50);
  if ca.is_ok { cell_a = ca.value; }
  if cb.is_ok { cell_b = cb.value; }

  let ta_r = stm_txn_begin();
  let tb_r = stm_txn_begin();
  var ta = -1;
  var tb = -1;
  if ta_r.is_ok { ta = ta_r.value; }
  if tb_r.is_ok { tb = tb_r.value; }

  // ta reads A; tb transfers 10 from A to B and commits first.
  match stm_read(ta, cell_a) {
    Ok(v) => { io.println("A before: " + convert.int_to_string(v)); },
    Err(e) => { io.println(stm_error_message(e.code)); },
  }
  let w1 = stm_write(tb, cell_a, 90);
  let w2 = stm_write(tb, cell_b, 60);
  let committed = stm_commit(tb);        // Ok(1): A=90, B=60
  io.println("transferred: " + convert.bool_to_string(committed.is_ok));

  // ta's snapshot is stale: commit aborts with a read conflict (code 7,
  // reason 1) and applies nothing.
  let conflicted = stm_commit(ta);
  if !conflicted.is_ok {
    let e: StmError = conflicted.error;
    io.println(stm_error_message(e.code));          // stm: transaction conflict
    io.println(stm_abort_reason_message(e.extra));  // stm: read conflict
  }
  let retry_result = stm_retry(ta);      // Ok(2): fresh attempt
  io.println("retried: " + convert.bool_to_string(retry_result.is_ok));
  let after = stm_cell_value(cell_a);
  if after.is_ok {
    let v: Int = after.value;
    io.println("A after retry: " + convert.int_to_string(v)); // 90
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.stm
```

Expected tail: 20 `[PASS]` lines, `xiom.stm: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`. Every test builds
its fixture in-test (`stm_reset()` is a full reset), so tests are
order-independent. See `SPEC.md` section 10 for the coverage map.

## Limitations

- **Deterministic model only.** No threads, no atomics, no clock, no FFI.
  Every interleaving is a sequence of explicit API calls; real contention and
  liveness are out of scope.
- **Reads observe the latest committed value**, not a frozen snapshot; a
  transaction that re-reads after a competing commit sees the new value but
  still aborts at commit because the version recorded at the first read is
  stale (documented, tested).
- **Module-level state.** There is exactly one global cell space and one
  transaction registry per process; `stm_reset()` is a full reset, not a
  resize.
- **No garbage collection of set entries.** Retried attempts are isolated by
  an epoch counter; stale entries are inert but retained until `stm_reset()`.
- **Bounded.** 1024 cells, 1024 transactions, 64 read-set and 64 write-set
  entries per transaction, 4 retries per transaction; all caps are pinned by
  tests and reported through the `stm_max_*` accessors.
- **Integer payloads only.** Cells hold `Int`; no generic cell payloads, no
  `Float64` (per the porting rules).
- **No blocking or waiting.** `stm_retry` is an explicit call; there is no
  `retry`-on-variable construct and no scheduler.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
