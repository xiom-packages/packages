# xiom.lockfree

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic single-threaded atomic-step models of lock-free
> structures: a Treiber stack with ABA tags over a node pool, a bounded MPMC
> ring queue, and atomic counters with CAS-step emulation. This is a semantic
> model, not a concurrent runtime: a real atomics/scheduler backend is out of
> scope.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.convert.int_to_string` and `xiom.convert.int.int_to_base`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Honest scope

`xiom.lockfree` models three classic lock-free algorithms in a single
deterministic thread of control. It never spawns a thread, never executes an
atomic instruction, never reads a clock and never calls FFI. Each concurrent
operation is written as the same sequence of atomic steps a real
implementation uses -- read a shared snapshot, compute a candidate, run a
compare-and-swap (CAS) step, retry on failure -- and the CAS step itself is a
plain function (`stack_cas_step`, `queue_cas_tail_step`, `queue_cas_head_step`,
`counter_cas_step`) whose success/failure outcome tests can pin directly.

Because there is no real contention in this model, an internal CAS always
succeeds on the first attempt; the failure path is exercised through the raw
CAS probes with a stale expected value (exactly what a competing thread would
produce). The model therefore demonstrates ABA tag progression, wrap-around,
full/empty disambiguation and the retry-loop structure, but it does **not**
provide thread safety, memory reclamation (hazard pointers/epochs) or any
wall-clock/liveness behavior. See `SPEC.md` for the full semantics, the error
catalog and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `stack_configure(capacity)` | `Result[Int, LockfreeError]` | Full reset; node capacity 1..4096 (`Err` code 1 otherwise). |
| `stack_push(value)` | `Result[Int, LockfreeError]` | Modeled Treiber push; `Ok(token)` is the new packed head. `Err` code 3 when the pool is exhausted. |
| `stack_pop()` | `Result[Int, LockfreeError]` | Modeled Treiber pop (LIFO); `Err` code 2 when empty. |
| `stack_peek()` | `Result[Int, LockfreeError]` | Top value without popping; `Err` code 2 when empty. |
| `stack_cas_step(expected, desired)` | `Bool` | Raw CAS step on the head word; counts success/failure. |
| `stack_head_token()/` `stack_head_index()/` `stack_head_tag()` | `Int` | Packed head, decoded node index (-1 empty) and ABA tag. |
| `stack_count()/` `stack_free_count()/` `stack_capacity()/` `stack_max_capacity()` | `Int` | Pool counters. |
| `stack_cas_successes()/` `stack_cas_failures()/` `stack_push_count()/` `stack_pop_count()` | `Int` | Operation statistics since the last configure. |
| `stack_dump()` | `Str` | One-line test dump (contents top-to-bottom, counters). |
| `queue_configure(capacity)` | `Result[Int, LockfreeError]` | Full reset; ring capacity 1..65536 (`Err` code 4 otherwise). |
| `queue_enqueue(value)` | `Result[Int, LockfreeError]` | Modeled MPMC enqueue; `Ok(slot)` is the ring slot used. `Err` code 6 when full. |
| `queue_dequeue()` | `Result[Int, LockfreeError]` | Modeled MPMC dequeue (FIFO); `Err` code 5 when empty. |
| `queue_cas_tail_step(expected, desired)/` `queue_cas_head_step(expected, desired)` | `Bool` | Raw CAS steps on the monotonic tail/head counters. |
| `queue_head_counter()/` `queue_tail_counter()/` `queue_count()` | `Int` | Monotonic operation counters and exact element count. |
| `queue_is_empty()/` `queue_is_full()` | `Bool` | `count == 0` / `count == capacity`. |
| `queue_cas_successes()/` `queue_cas_failures()/` `queue_enqueue_count()/` `queue_dequeue_count()` | `Int` | Operation statistics since the last configure. |
| `queue_capacity()/` `queue_max_capacity()` | `Int` | Ring capacity accessors. |
| `queue_dump()` | `Str` | One-line test dump (counters and raw slots). |
| `counter_reset(v)` | `Unit` | Set the counter and clear its statistics. |
| `counter_cas_step(expected, desired)` | `Bool` | Raw CAS step on the counter word; counts success/failure. |
| `counter_add(delta)` | `Result[Int, LockfreeError]` | CAS-loop add; `Err` code 7/8 outside `[0, 2^62-1]`. |
| `counter_add_saturating(delta)` | `Int` | CAS-loop add clamped to `[counter_min(), counter_max()]`. |
| `counter_get()/` `counter_min()/` `counter_max()` | `Int` | Value and range accessors. |
| `counter_cas_successes()/` `counter_cas_failures()/` `counter_add_count()/` `counter_saturating_add_count()` | `Int` | Operation statistics since the last reset. |
| `counter_dump()` | `Str` | One-line test dump. |
| `lockfree_dump()` | `Str` | The three dumps joined by newlines. |
| `lockfree_error_message(code)` | `Str` | Pinned error text; `"lockfree: unknown error"` outside the catalog. |

Every `LockfreeError` carries `(code, value, extra)`: `value` is the offending
input (-1 when none), `extra` is the bound or current context (-1 when none).
All fallible calls leave all state untouched on `Err`.

## Usage

```xi
use xiom.lockfree;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  match stack_configure(4) {
    Ok(cap) => { io.println("stack capacity " + convert.int_to_string(cap)); },
    Err(e) => { io.println(lockfree_error_message(e.code)); },
  }
  match stack_push(11) {
    Ok(token) => {
      // token = tag * (capacity + 1) + (index + 1); tag 1, node 0 -> 6
      io.println("pushed, head token " + convert.int_to_string(token));
    },
    Err(e) => { io.println(lockfree_error_message(e.code)); },
  }
  match stack_pop() {
    Ok(v) => { io.println("popped " + convert.int_to_string(v)); },   // 11
    Err(e) => { io.println(lockfree_error_message(e.code)); },
  }

  match queue_configure(2) {
    Ok(_) => {},
    Err(e) => { io.println(lockfree_error_message(e.code)); },
  }
  let e1 = queue_enqueue(41);
  let e2 = queue_enqueue(42);
  if e1.is_ok && e2.is_ok {
    io.println(queue_dump());
    // queue[cap=2 count=2 head=0 tail=2 full=1 empty=0 slots=41,42 cas_ok=2 cas_fail=0]
  }

  counter_reset(5);
  let cas = counter_cas_step(5, 9);
  io.println(convert.bool_to_string(cas));                           // true
  let add = counter_add_saturating(4);
  io.println(convert.int_to_string(add));                            // 13
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.lockfree
```

Expected tail: 21 `[PASS]` lines, `xiom.lockfree: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`. The suite builds
every fixture in-test (`stack_configure` / `queue_configure` /
`counter_reset` are full resets) and pins the token arithmetic, ABA tag
progression, pool exhaustion, queue wrap-around, full/empty rule, both CAS
outcomes, counter bounds and the dump/error-catalog text. See `SPEC.md`
section 9 for the coverage map.

## Limitations

- **Deterministic model only.** No threads, no atomics, no clock, no FFI;
  internal CAS steps always succeed on the first attempt. `xiom.sync` is
  deliberately not used. Raw CAS probes can force the failure path.
- **No memory reclamation.** The stack models ABA with a tag, but not safe
  reclamation (hazard pointers, epochs, reference counting); nodes are owned
  by the module pool forever.
- **One instance per structure.** State is module-level (parallel `Vec[Int]`
  fields), so there is exactly one stack, one queue and one counter per
  process; `*_configure` / `counter_reset` are full resets, not resizes.
- **Monotonic counters never wrap.** head/tail/counter values grow as Int
  (i64) and are not masked; the model documents wrap-around of the ring slot
  index (`counter % capacity`), not wraparound of the counter itself.
- **Counter range is `[0, 2^62 - 1]`.** `counter_add` returns `Err` outside
  it; `counter_add_saturating` clamps. `counter_reset` and the raw CAS steps
  do not validate (documented setup/probe helpers).
- **Pool/queue caps.** Stack capacity 1..4096, queue capacity 1..65536; the
  defaults (16/16) are built lazily on first use.
- **Full/empty rule relies on an exact count**, not on a phase bit or the
  head/tail values alone; concurrent producers/consumers would have to keep
  that count atomic, which the model documents rather than implements.
- **Dump formats are test-facing** and may gain fields; tests match
  fragments, not whole lines, except where the full format is pinned.

See `SPEC.md` for the full semantics, the error catalog and the test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
