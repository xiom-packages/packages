# xiom.executor

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** a task execution engine as a pure, deterministic state machine:
> task metadata (ids, priorities, submission order, states), a ready queue
> with FIFO and priority selection policies, futures, continuations, a bounded
> driver loop and stats counters. The model is the semantic core a scheduler
> or thread pool would drive -- it contains no threads, no atomics, no locks,
> no clock and no I/O.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string`
> and `xiom.convert` from it, the tests additionally use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.executor` models a task execution engine as a plain value type and a set
of free functions. An `Executor` holds:

- four parallel task vectors -- ids, priorities, submission sequence numbers
  and state codes (`NEW`, `READY`, `RUNNING`, `DONE`, `FAILED`);
- the ready queue (`ready_ids`), written by submission and by continuations;
- five parallel future vectors -- ids, states (`PENDING`, `READY`, `FAILED`),
  value slots, failure-code slots and attached continuation task ids;
- counters (`submitted`, `completed`, `failed`, `steps`) and the completion
  order trace.

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state and
outcome follow. A real backend (a thread pool, an event loop, `xiom.sync`
primitives) owns atomicity and blocking; this module owns the *semantics* --
what a correct executor must do -- in a form that can be tested exactly,
without sleeps or races.

Tasks move `NEW -> READY -> RUNNING -> DONE | FAILED`; every edge is one-way.
Dispatch (`executor_next`) selects one ready task by policy, marks it
`RUNNING` and removes it from the queue. Completion (`executor_complete` /
`executor_fail`) is explicit, so a driver can model arbitrary work outcomes.
When a task completes and a future with the same id is still `PENDING`, that
future is published with the task's value or failure code; a future's attached
continuation task is then enqueued exactly once.

Two ready-queue policies are supported:

- `EXEC_POLICY_FIFO` -- the queue front (arrival order);
- `EXEC_POLICY_PRIORITY` -- the largest task priority, with ties broken by the
  smallest submission sequence (stable by submission id).

## API

| Function | Returns | Description |
|---|---|---|
| `executor_new(policy)` | `Result[Executor, Str]` | Empty executor with a FIFO or PRIORITY policy. |
| `executor_set_policy(&mut e, policy)` | `Result[Int, Str]` | Change the active policy; unknown codes refused. |
| `executor_policy(e)` | `Int` | Active policy code. |
| `executor_submit(&mut e, id, priority)` | `Result[Int, Str]` | Submit a task (starts `NEW`); `Ok(submission order)`. |
| `executor_enqueue(&mut e, id)` | `Result[Int, Str]` | Move `NEW -> READY`; `Ok(queue position)`. |
| `executor_submit_ready(&mut e, id, priority)` | `Result[Int, Str]` | Submit and enqueue in one call. |
| `executor_ready_len(e)` | `Int` | Ready-queue length. |
| `executor_ready_ids(e)` | `Vec[Int]` | Copy of the ready queue, front first. |
| `executor_next(&mut e)` | `Result[Int, Str]` | Dispatch the next ready task under the active policy. |
| `executor_next_policy(&mut e, policy)` | `Result[Int, Str]` | Dispatch under an explicit policy. |
| `executor_complete(&mut e, id, value)` | `Result[Int, Str]` | `RUNNING -> DONE`; publishes to the same-id future. |
| `executor_fail(&mut e, id, code)` | `Result[Int, Str]` | `RUNNING -> FAILED` with a failure code. |
| `executor_run_all(&mut e, max_steps)` | `Result[Vec[Int], Str]` | Driver loop; `Ok(completion trace)` or step-limit error. |
| `future_new(&mut e, id)` | `Result[Int, Str]` | Create a `PENDING` future. |
| `future_attach_continuation(&mut e, fid, tid)` | `Result[Int, Str]` | Attach a continuation task to a pending future. |
| `future_set_ready(&mut e, id, value)` | `Result[Int, Str]` | `PENDING -> READY` with a value slot. |
| `future_set_failed(&mut e, id, code)` | `Result[Int, Str]` | `PENDING -> FAILED` with a failure code. |
| `executor_task_count(e)` | `Int` | Number of submitted tasks. |
| `executor_has_task(e, id)` | `Bool` | Task existence. |
| `executor_task_state(e, id)` | `Int` | `EXEC_TASK_*` code, `-1` when unknown. |
| `executor_task_priority(e, id)` | `Int` | Task priority, `-1` when unknown. |
| `executor_task_order(e, id)` | `Int` | Submission sequence, `-1` when unknown. |
| `executor_future_count(e)` | `Int` | Number of futures. |
| `executor_has_future(e, id)` | `Bool` | Future existence. |
| `executor_future_state(e, id)` | `Int` | `EXEC_FUTURE_*` code, `-1` when unknown. |
| `executor_future_value(e, id)` | `Int` | Value slot (0 while unset), `-1` when unknown. |
| `executor_future_code(e, id)` | `Int` | Failure-code slot (0 while unset), `-1` when unknown. |
| `executor_future_continuation(e, id)` | `Int` | Attached continuation id, `-1` when none/unknown. |
| `executor_future_has_continuation(e, id)` | `Bool` | True when a continuation is attached. |
| `executor_submitted(e)` | `Int` | Successful submissions. |
| `executor_completed(e)` | `Int` | Successful completions. |
| `executor_failed(e)` | `Int` | Successful failures. |
| `executor_steps(e)` | `Int` | Successful dispatches. |
| `executor_trace_len(e)` | `Int` | Completion trace length. |
| `executor_trace(e)` | `Vec[Int]` | Copy of terminal task ids in order. |
| `executor_trace_text(e)` | `Str` | Trace as comma-separated ids (`""` when empty). |
| `executor_policy_name(policy)` | `Str` | `"fifo"`, `"priority"` or `"unknown"`. |
| `executor_task_state_name(state)` | `Str` | `"new"`, `"ready"`, `"running"`, `"done"`, `"failed"`. |
| `executor_future_state_name(state)` | `Str` | `"pending"`, `"ready"`, `"failed"`. |
| `executor_check_invariant(e)` | `Bool` | Structural invariant check (see SPEC.md). |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.executor;

match executor_new(EXEC_POLICY_PRIORITY) {
  Ok(e) => {
    var ex = e;

    // Two independent tasks: id 1 at priority 1, id 2 at priority 5.
    executor_submit_ready(&mut ex, 1, 1);
    executor_submit_ready(&mut ex, 2, 5);

    // PRIORITY dispatches 2 first, then 1.
    match executor_next(&mut ex) {
      Ok(id) => { executor_complete(&mut ex, id, id * 10); },
      Err(_) => { /* "executor: no ready tasks" */ },
    }

    match executor_run_all(&mut ex, 16) {
      Ok(trace) => { /* trace == [1] here; "2,1" in executor_trace_text */ },
      Err(_) => { /* "executor: step limit exceeded" */ },
    }
  },
  Err(_) => { /* "executor: unknown policy" */ },
}
```

Continuation pattern: a task produces a result, a follow-up task runs after
the future completes.

```xi
var ex = ...;
executor_submit(&mut ex, 7, 0);                  // producer, starts NEW
executor_submit(&mut ex, 8, 0);                  // continuation, starts NEW
future_new(&mut ex, 7);
future_attach_continuation(&mut ex, 7, 8);       // wake 8 when future 7 settles
executor_enqueue(&mut ex, 7);
executor_run_all(&mut ex, 16);                   // completion trace: "7,8"
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.executor
```

Expected: the namespaced module passes the section-4 namespace rule, 27
`[PASS]` lines, and a final `port: PASS (passed=27 failed=0 program_exit=0
exit=0)`.

## Limitations

- **Deterministic model, no real threads.** There is no concurrency,
  atomicity or memory ordering here; a backend that runs tasks on real threads
  must serialise access to the executor value itself.
- **No preemption or time slicing.** A dispatched task stays `RUNNING` until
  the driver calls `executor_complete` or `executor_fail`; the library never
  advances a task on its own.
- **`executor_run_all` always succeeds dispatched tasks.** It completes each
  task with the task id as the published value. To model failures, drive the
  loop yourself with `executor_next` + `executor_fail`.
- **Task and future id spaces are caller-managed.** Publishing on task
  completion targets the future with the same id, and only while that future
  is `PENDING` (a manually settled future is left unchanged). Task ids are
  never reused; there is no removal or resubmission.
- **One continuation per future.** A second attach is refused; the
  continuation task must be submitted before the attach, and is enqueued only
  while still `NEW` (so a task already queued is not duplicated).
- **A failed future also notifies its continuation.** The continuation can
  read `executor_future_state` / `executor_future_code` to distinguish.
- **No waiting, timeouts, cancellation or joins.** Futures are observation
  slots, not blocking handles; the library has no clock.
- **`PRIORITY` is not preemptive.** Priority only orders the ready queue at
  dispatch time; already-running tasks are unaffected.
- **Complexity.** Id lookups are linear scans and queue removal rebuilds the
  vector, so selection/removal are O(queue x tasks); fine for the model, not
  tuned for very long queues.
- Not thread-safe: values follow ordinary XIOM move/borrow rules.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
