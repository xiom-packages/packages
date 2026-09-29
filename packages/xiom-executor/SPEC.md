# xiom.executor -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.executor` (`src/executor.xi`). Manifest: `package.xi` (name
`xiom.executor`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.string` and `xiom.convert` only.

## 1. Scope

A task execution engine as a pure, deterministic state machine -- the semantic
core that a scheduler, thread pool or async runtime would drive:

- task metadata (ids, priorities, submission order, states) as parallel
  `Vec[Int]` fields, with validation helpers and a structural invariant;
- submission (`executor_submit`) and ready-queue insertion
  (`executor_enqueue`, `executor_submit_ready`);
- two ready-queue selection policies, FIFO and PRIORITY, with a documented,
  deterministic selection rule (`executor_next`, `executor_next_policy`);
- futures (`future_new`, `future_set_ready`, `future_set_failed`) as parallel
  `Vec[Int]` fields with exact lifecycle errors;
- continuations: one continuation task per future, enqueued exactly once when
  the future reaches a terminal state (`future_attach_continuation`);
- a bounded driver loop (`executor_run_all`) returning the completion order
  trace;
- stats accessors (`submitted`, `completed`, `failed`, `steps`) and the
  completion trace (`executor_trace`, `executor_trace_text`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a backend owns concurrency and blocking.

## 2. Non-goals

- Actual scheduling, threads, work stealing, or parallel execution. The
  executor is a value; a backend drives it and performs the work.
- Preemption or time slicing: a `RUNNING` task changes state only through an
  explicit `executor_complete` / `executor_fail` call.
- Waiting, blocking, joins, timeouts or cancellation on futures. A future is
  an observation slot, not a blocking handle.
- Dynamic reprioritisation, aging or fairness guarantees beyond the documented
  selection rule.
- Task removal, id reuse or resubmission; the task table only grows.
- Interop with the stdlib `xiom.async.executor` (a different, runtime-level
  module); this package is the deterministic semantic model.

## 3. State

```xi
pub type Executor = {
  policy: Int;             // EXEC_POLICY_* selection policy
  task_ids: Vec[Int];      // task ids, unique, >= 0
  task_priorities: Vec[Int]; // priorities, >= 0 (larger = more urgent)
  task_orders: Vec[Int];   // submission sequences (dense: task_orders[i] == i)
  task_states: Vec[Int];   // EXEC_TASK_* codes, parallel to task_ids
  ready_ids: Vec[Int];     // ready queue, index 0 = front
  next_order: Int;         // next submission sequence == task count
  future_ids: Vec[Int];    // future ids, unique, >= 0
  future_states: Vec[Int]; // EXEC_FUTURE_* codes
  future_values: Vec[Int]; // published value slot
  future_codes: Vec[Int];  // published failure-code slot
  future_cont: Vec[Int];   // attached continuation task id or -1
  submitted: Int;          // successful executor_submit calls
  completed: Int;          // successful executor_complete calls
  failed: Int;             // successful executor_fail calls
  steps: Int;              // successful executor_next dispatches
  completion_order: Vec[Int]; // terminal task ids, in completion order
}
```

Every field is an internal implementation detail; callers go through the free
functions. The parallel vectors are pushed and rebuilt together by every
mutation, so they can never skew.

Task state codes: `EXEC_TASK_NEW` (0), `EXEC_TASK_READY` (1),
`EXEC_TASK_RUNNING` (2), `EXEC_TASK_DONE` (3), `EXEC_TASK_FAILED` (4).
Future state codes: `EXEC_FUTURE_PENDING` (0), `EXEC_FUTURE_READY` (1),
`EXEC_FUTURE_FAILED` (2). Sentinels: `EXEC_NO_CONTINUATION` (-1),
`EXEC_NOT_FOUND` (-1).

### 3.1 Invariant

`executor_check_invariant(e)` is true exactly when:

1. the four task vectors have equal length `n`, `submitted == n` and
   `next_order == n`;
2. every task id is `>= 0` and unique; every priority is `>= 0`;
   `task_orders[i] == i`; every state is an `EXEC_TASK_*` code;
3. every ready-queue id names a task in state `READY`, with no duplicates,
   and every `READY` task is queued exactly once;
4. `completed` equals the number of `DONE` tasks, `failed` equals the number
   of `FAILED` tasks, and `steps == DONE + FAILED + RUNNING`;
5. `completion_order` lists each terminal task exactly once and its length is
   `completed + failed`;
6. the five future vectors have equal length; every future id is `>= 0` and
   unique; every future state is an `EXEC_FUTURE_*` code; every attached
   continuation names an existing task.

## 4. State machine rules

Notation: `e` is an `Executor`; `p` is a task id; `v` is a value; `c` is a
failure code.

### 4.1 S1 -- construction (`executor_new(policy)`)

- precondition: `policy` is `EXEC_POLICY_FIFO` or `EXEC_POLICY_PRIORITY`;
- effect: empty task and future tables, empty ready queue, all counters zero,
  active policy `policy`;
- error: `Err("executor: unknown policy")` otherwise (no value produced).

### 4.2 S2 -- policy change (`executor_set_policy(policy)`)

- valid policy: `policy` becomes active, `Ok(policy)`;
- otherwise `Err("executor: unknown policy")`; state unchanged.

### 4.3 S3 -- submission (`executor_submit(p, priority)`)

Validation order:

1. `p < 0` -> `Err("executor: task id must be >= 0")`;
2. `priority < 0` -> `Err("executor: priority must be >= 0")`;
3. `p` already known -> `Err("executor: duplicate task id")`;
4. otherwise the task is appended in state `NEW` with submission sequence
   `next_order` (assigned in order 0, 1, 2, ...), `next_order += 1`,
   `submitted += 1`, `Ok(submission sequence)`.

Every error leaves the state unchanged. A submitted task is **not** runnable
until `executor_enqueue`.

### 4.4 S4 -- enqueue (`executor_enqueue(p)`)

1. unknown `p` -> `Err("executor: unknown task id")`;
2. state already `READY` -> `Err("executor: task already queued")`;
3. state `RUNNING` -> `Err("executor: task already running")`;
4. state `DONE` -> `Err("executor: task already complete")`;
5. state `FAILED` -> `Err("executor: task already failed")`;
6. otherwise state `NEW -> READY`, append `p` to the back of `ready_ids`,
   `Ok(append position)`.

The append position is a queue coordinate, not a dispatch guarantee: under
the PRIORITY policy the dispatch order may differ.

`executor_submit_ready(p, priority)` composes S3 then S4 and returns the S4
result; when S3 fails nothing is submitted.

### 4.5 S5 -- dispatch (`executor_next` / `executor_next_policy(policy)`)

1. invalid `policy` -> `Err("executor: unknown policy")`;
2. empty queue -> `Err("executor: no ready tasks")`;
3. otherwise the selected id is removed from the queue, its state becomes
   `RUNNING`, `steps += 1`, and `Ok(task id)` is returned.

`executor_next(e)` uses the active policy `e.policy`. Every error leaves the
state unchanged.

### 4.6 S6 -- successful completion (`executor_complete(p, v)`)

1. unknown `p` -> `Err("executor: unknown task id")`;
2. state `DONE` -> `Err("executor: task already complete")`;
3. state `FAILED` -> `Err("executor: task already failed")`;
4. state `NEW` or `READY` -> `Err("executor: task is not running")`;
5. otherwise `RUNNING -> DONE`, `completed += 1`, `p` is appended to
   `completion_order`, and the **publish step** runs for the future whose id
   is `p` (section 6); `Ok(completed count)`.

### 4.7 S7 -- failure (`executor_fail(p, c)`)

Same validation order as S6; on success `RUNNING -> FAILED`, `failed += 1`,
`p` is appended to `completion_order`, the publish step runs with state
`FAILED` and code `c`, and `Ok(failed count)` is returned.

### 4.8 S8 -- driver loop (`executor_run_all(max_steps)`)

1. `max_steps < 0` -> `Err("executor: max_steps must be >= 0")`;
2. loop: while the ready queue is non-empty, if the number of dispatches
   already made by this call has reached `max_steps`, return
   `Err("executor: step limit exceeded")` (states reached so far are
   retained); otherwise dispatch the next task under the active policy and
   complete it successfully with the task id as its value, appending it to the
   run trace;
3. when the queue drains, return `Ok(trace)` -- the ids completed by this run,
   in completion order (empty when nothing was ready).

The loop is bounded by construction: every dispatch is `READY -> RUNNING` and
every task is dispatched at most once, so at most `n` dispatches can occur;
`max_steps` is a caller-chosen safety bound. Transition errors are surfaced
unchanged. Continuations enqueued by completed futures are picked up by later
iterations.

### 4.9 Derived state

`completion_order` is the terminal-transition witness: task ids in the order
they reached `DONE` or `FAILED`, each at most once. `executor_trace_text`
renders it as comma-separated ids.

## 5. Ready-queue selection policies

`_pick_index(e, policy)` returns the ready-queue index to dispatch:

```
FIFO (EXEC_POLICY_FIFO = 0):
    return 0                          # queue front = earliest arrival

PRIORITY (EXEC_POLICY_PRIORITY = 1):
    best = 0
    for i in 1 .. len(ready_ids) - 1:
        cand = ready_ids[i]; cur = ready_ids[best]
        if priority[cand] > priority[cur]:            best = i
        elif priority[cand] == priority[cur]:
            if order[cand] < order[cur]:              best = i   # stable
    return best
```

Properties:

- **Total and deterministic**: priorities are integers and submission
  sequences are unique (dense, 0-based), so the comparison never ties at the
  end; a residual tie (impossible in a valid state) falls to the earliest
  queue position because the scan is left-to-right on a strict improvement.
- **Stable by submission id**: on equal priority the earlier-submitted task
  wins, regardless of its id or queue position.
- **Not preemptive**: only ready tasks are ranked; a running task is never
  displaced.
- FIFO ignores priorities entirely.

## 6. Futures and continuations

### 6.1 Future lifecycle

- `future_new(id)`: `id < 0` -> `Err("executor: future id must be >= 0")`;
  duplicate -> `Err("executor: duplicate future id")`; otherwise a `PENDING`
  future with value slot 0, code slot 0 and no continuation.
- `future_set_ready(id, v)`: `PENDING -> READY` (value `v`), `Ok(v)`;
  `READY` -> `Err("executor: future already complete")` (double complete);
  `FAILED` -> `Err("executor: future already failed")`
  (complete-after-failure); unknown -> `Err("executor: unknown future id")`.
- `future_set_failed(id, c)`: `PENDING -> FAILED` (code `c`), `Ok(c)`;
  `READY` -> `Err("executor: future already complete")`; `FAILED` ->
  `Err("executor: future already complete")` (double complete); unknown ->
  `Err("executor: unknown future id")`.

Terminal future states are final: at most one publish transition can succeed
per future.

### 6.2 Continuation attachment

`future_attach_continuation(future_id, task_id)` validation order:

1. unknown future -> `Err("executor: unknown future id")`;
2. future `READY` -> `Err("executor: future already ready")`;
3. future `FAILED` -> `Err("executor: future already failed")`;
4. unknown task -> `Err("executor: unknown task id")`;
5. continuation task `DONE` -> `Err("executor: continuation task already
   complete")`;
6. continuation task `FAILED` -> `Err("executor: continuation task already
   failed")`;
7. future already carries a continuation -> `Err("executor: future already
   has a continuation")`;
8. otherwise `future_cont[fi] = task_id`, `Ok(task_id)`.

At most one continuation per future. The continuation task may be `NEW`,
`READY` or `RUNNING` when attached; it must simply not be terminal. Attaching
to a terminal future is refused, so a continuation cannot be installed after
the completion it was meant to observe.

### 6.3 Publish step (exactly-once enqueue)

When a future moves to a terminal state (by `future_set_ready`,
`future_set_failed`, or a task completion publishing to its same-id future),
the publish step runs:

```
if future state was PENDING:
    state' = READY | FAILED; value/code' = published
    cont = future_cont[future]
    if cont >= 0 and task[cont].state == NEW:
        task[cont].state = READY
        ready_ids.push(cont)          # the one and only enqueue point
```

Exactly-once argument:

1. a future publishes at most once because terminal states are final and
   every publish path requires `PENDING`;
2. the continuation enqueue happens only inside that single transition;
3. enqueueing requires the continuation task to still be `NEW`, which the
   transition makes `READY`; a repeat is impossible, and a task already
   `READY` / `RUNNING` / terminal is left untouched (no duplicate queue
   entry);
4. therefore the ready queue gains a continuation task at most once, for both
   success (`READY`) and failure (`FAILED`) terminal states.

A failed future notifies its continuation just like a ready one; the
continuation distinguishes the outcome with `executor_future_state` and
`executor_future_code`.

### 6.4 Task completion publishing

`executor_complete(p, v)` / `executor_fail(p, c)` publish to the future whose
id equals the task id, but only while that future exists and is `PENDING`.
The publish result is best-effort: a missing future, or one already
manually settled, does not fail the task transition. `executor_run_all`
therefore chains continuations through same-id futures automatically.

## 7. Error catalog

All error strings are stable and prefixed `executor: `.

| Function | Condition | Err message | State on error |
|---|---|---|---|
| `executor_new` / `executor_set_policy` | policy not 0/1 | `executor: unknown policy` | no value produced / unchanged |
| `executor_submit` | `id < 0` | `executor: task id must be >= 0` | unchanged |
| `executor_submit` | `priority < 0` | `executor: priority must be >= 0` | unchanged |
| `executor_submit` | id already known | `executor: duplicate task id` | unchanged |
| `executor_enqueue` | unknown id | `executor: unknown task id` | unchanged |
| `executor_enqueue` | state `READY` | `executor: task already queued` | unchanged |
| `executor_enqueue` | state `RUNNING` | `executor: task already running` | unchanged |
| `executor_enqueue` | state `DONE` | `executor: task already complete` | unchanged |
| `executor_enqueue` | state `FAILED` | `executor: task already failed` | unchanged |
| `executor_next` / `executor_next_policy` | policy not 0/1 | `executor: unknown policy` | unchanged |
| `executor_next` / `executor_next_policy` | empty queue | `executor: no ready tasks` | unchanged |
| `executor_complete` / `executor_fail` | unknown id | `executor: unknown task id` | unchanged |
| `executor_complete` / `executor_fail` | state `DONE` | `executor: task already complete` | unchanged |
| `executor_complete` / `executor_fail` | state `FAILED` | `executor: task already failed` | unchanged |
| `executor_complete` / `executor_fail` | state `NEW`/`READY` | `executor: task is not running` | unchanged |
| `executor_run_all` | `max_steps < 0` | `executor: max_steps must be >= 0` | unchanged |
| `executor_run_all` | bound reached with work left | `executor: step limit exceeded` | dispatches so far retained |
| `future_new` | `id < 0` | `executor: future id must be >= 0` | unchanged |
| `future_new` | id already known | `executor: duplicate future id` | unchanged |
| `future_set_ready` | unknown id | `executor: unknown future id` | unchanged |
| `future_set_ready` | future `READY` | `executor: future already complete` | unchanged |
| `future_set_ready` | future `FAILED` | `executor: future already failed` | unchanged |
| `future_set_failed` | unknown id | `executor: unknown future id` | unchanged |
| `future_set_failed` | future `READY` or `FAILED` | `executor: future already complete` | unchanged |
| `future_attach_continuation` | unknown future | `executor: unknown future id` | unchanged |
| `future_attach_continuation` | future `READY` | `executor: future already ready` | unchanged |
| `future_attach_continuation` | future `FAILED` | `executor: future already failed` | unchanged |
| `future_attach_continuation` | unknown task | `executor: unknown task id` | unchanged |
| `future_attach_continuation` | continuation task `DONE` | `executor: continuation task already complete` | unchanged |
| `future_attach_continuation` | continuation task `FAILED` | `executor: continuation task already failed` | unchanged |
| `future_attach_continuation` | already attached | `executor: future already has a continuation` | unchanged |

No panicking input exists: every function is total, and read accessors return
`-1`/`false`/`""` sentinels instead of erroring.

## 8. Complexity

| Operation | Complexity |
|---|---|
| `executor_new` / `executor_set_policy` / `executor_policy` | O(1) |
| `executor_submit` | O(task count) -- duplicate scan |
| `executor_enqueue` / `executor_submit_ready` | O(task count) -- id lookup |
| `executor_next` / `executor_next_policy` | O(queue length x task count) -- selection scan with id lookups; queue removal rebuilds the vector |
| `executor_complete` / `executor_fail` | O(task count + future count) |
| `executor_run_all` | O(max_steps x (task count + queue length x task count)) |
| `executor_task_state` / `executor_task_priority` / `executor_task_order` / `executor_has_task` | O(task count) |
| `executor_future_state` / value / code / continuation / `executor_has_future` | O(future count) |
| counters, `executor_ready_len` / `executor_task_count` / `executor_future_count` / `executor_trace_len` | O(1) |
| `executor_ready_ids` / `executor_trace` / `executor_trace_text` | O(n) copy |
| `executor_check_invariant` | O(task count^2 + future count^2) |

## 9. Test plan

`tests/test_conformance.xi` (`module executor_tests`, 27 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test through
`executor_new`; every string comparison routes through `compare.str_compare`.

1. `executor_new` initializes policy, empty metadata and zero stats;
2. unknown policies are rejected by `new` and `set_policy`;
3. `submit` validates `id >= 0`, `priority >= 0` and uniqueness;
4. FIFO dispatches ready tasks in queue arrival order;
5. priority policy picks the largest priority first;
6. priority ties are stable by submission sequence, a later high priority
   jumps ahead;
7. policy can be switched and overridden per dispatch;
8. dispatch pops the queue entry and marks the task `RUNNING`;
9. `enqueue` validates the task lifecycle and refuses re-entry;
10. dispatch on an empty queue errors without changing state;
11. `complete` moves `RUNNING -> DONE`, traces it and validates;
12. `fail` moves `RUNNING -> FAILED`, traces it and validates;
13. task accessors expose state, priority and submission order;
14. `future_new` validates ids and starts `PENDING` with empty slots;
15. `future_set_ready` publishes once and refuses double-complete;
16. `future_set_failed` publishes once and refuses complete-after-failure;
17. `attach_continuation` validates future and task lifecycles;
18. a ready future enqueues its continuation exactly once;
19. a failed future also notifies its continuation once;
20. task completion publishes to the same-id future (value or code);
21. `run_all` completes FIFO tasks and returns the completion trace;
22. `run_all` follows the continuation chain enqueued by a future;
23. `run_all` enforces `max_steps` and validates the bound;
24. stats accumulate submitted, steps, completed and failed;
25. trace text renders comma-separated ids and copies are independent;
26. the invariant holds across 30 mixed dispatch cycles;
27. policy and state name helpers are stable.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.executor
```

Last verified: compiler v0.62.1, `port: PASS (passed=27 failed=0
program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes for v0.62.1

- Free functions only (no methods), with explicit `&`/`&mut` parameters and
  `&mut` at every call site.
- `Ok`/`Err` are constructed only inside the `_ok_*` / `_err_*` leaf helper
  functions.
- `Vec[Int]` element reads are bound with a typed `let` before use.
- Parallel `Vec[Int]` fields (`task_*`, `future_*`) are pushed and rebuilt in
  the same function, so they can never skew.
- Str equality (tests and the run_all no-ready probe) goes through
  `str_compare`; `==` on `Str` values read from Vec elements lowers to a
  pointer comparison.
- No `Vec[StructType]`, no indexed `Vec[fn]` dispatch, no generic callbacks,
  no `Vec[Float64]`, no `mut` in match patterns, no FFI, no threads.
- No `log`-named function; the trace accessor is `executor_trace` /
  `executor_trace_text`.
- Wrapper functions in the test suite take `&mut` for read-only access, so a
  `&local` read call is never followed by a `&mut local` call in the same
  function body (advisory E001).

## 11. Known limitations

- The model is single-threaded and non-atomic; a concurrent backend must
  provide the critical section around every transition.
- No preemption, no time slicing, no waiting/joining, no timeouts and no
  cancellation.
- `executor_run_all` cannot express failures: it completes every dispatched
  task with the task id as its value. Use `executor_next` +
  `executor_fail` for failure scenarios.
- Task and future tables only grow; there is no removal, and ids cannot be
  reused.
- Publishing on task completion is same-id and best-effort: a missing future
  or a manually settled future is simply not republished.
- One continuation per future; a continuation attached while already
  `READY`/`RUNNING` is not re-enqueued on completion (there is nothing to
  re-enqueue), and a terminal task cannot be a continuation target.
- `PRIORITY` affects dispatch order only; running tasks are never displaced.
- Selection and queue removal use linear scans and vector rebuilds; a backend
  with very long queues would use an indexed ring instead.
