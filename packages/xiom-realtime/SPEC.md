# xiom-realtime -- Specification

> **Status: v0.1.0 implemented.** Priority type system, task state machine, priority-based scheduler with deadline enforcement, retry logic, and scheduler statistics are implemented in `realtime.xi` (pure XIOM, no extern dependencies). Room/channel/presence/event layers are planned for future versions.

## Overview

`xiom-realtime` is the application-level realtime package for the XIOM ecosystem. It layers reusable realtime semantics -- scheduling, channels, rooms, presence, broadcast, ordering, and ephemeral/durable events -- on top of `xiom-websocket` (transport) and `xiom-micro` (distributed fan-out).

The scheduling core is organized around a priority-based task queue with:
- Five priority levels (Critical through Background)
- State machine (Pending -> Running -> Completed/Failed/Skipped)
- Deadline enforcement with task expiry
- Automatic retry with configurable max retries
- Concurrent execution slots with max_concurrent limit

## Module

- **Module:** `xiom.realtime`
- **Version:** 0.1.0
- **Dependencies:** `xiom.string`, `xiom.convert` (pure XIOM)

---

## Implemented Types (v0.1.0)

### `RtPriority` (enum)

```xiom
pub enum RtPriority {
  Critical,
  High,
  Normal,
  Low,
  Background,
} derive[Clone]
```

### `RtTaskState` (enum)

```xiom
pub enum RtTaskState {
  Pending,
  Running,
  Completed,
  Failed,
  Skipped,
} derive[Clone]
```

State machine transitions:
- `Pending` -> `Running` (scheduler picks task)
- `Running` -> `Completed` (task finishes)
- `Running` -> `Failed` (retries exhausted)
- `Running` -> `Pending` (retry on failure, within max_retries)
- `Pending` -> `Skipped` (deadline expired)

### `RtTask`

```xiom
pub type RtTask = {
  id: Str;
  name: Str;
  priority: RtPriority;
  deadline_ms: Int;
  created_at_ms: Int;
  state: RtTaskState;
  retry_count: Int;
  max_retries: Int;
} derive[Clone]
```

### `RtScheduler`

```xiom
pub type RtScheduler = {
  tasks: Vec[RtTask];
  now_ms: Int;
  max_concurrent: Int;
  running_count: Int;
  stats: RtSchedulerStats;
} derive[Clone]
```

### `RtSchedulerStats`

```xiom
pub type RtSchedulerStats = {
  total_scheduled: Int;
  total_completed: Int;
  total_failed: Int;
  total_skipped: Int;
} derive[Clone]
```

### `RtScheduleResult`

```xiom
pub type RtScheduleResult = {
  executed: Vec[Str];
  deferred: Vec[Str];
  failed: Vec[Str];
} derive[Clone]
```

---

## Implemented API (v0.1.0)

### Priority Helpers

| Function | Signature |
|----------|-----------|
| `priority_to_int` | `(p: RtPriority) -> Int` |
| `priority_from_int` | `(n: Int) -> RtPriority` |
| `priority_to_str` | `(p: RtPriority) -> Str` |

### Task Builder & Query

| Function | Signature |
|----------|-----------|
| `task_new` | `(id: Str, name: Str, priority: RtPriority, deadline_ms: Int, now_ms: Int) -> RtTask` |
| `task_is_pending` | `(task: &RtTask) -> Bool` |
| `task_is_expired` | `(task: &RtTask, now_ms: Int) -> Bool` |
| `task_can_retry` | `(task: &RtTask) -> Bool` |
| `task_cmp_priority` | `(a: &RtTask, b: &RtTask) -> Int` |

### Scheduler Builder & Task Management

| Function | Signature |
|----------|-----------|
| `scheduler_new` | `(max_concurrent: Int) -> RtScheduler` |
| `scheduler_add_task` | `(sched: &mut RtScheduler, task: RtTask)` |
| `scheduler_task_count` | `(sched: &RtScheduler) -> Int` |
| `scheduler_pending_count` | `(sched: &RtScheduler) -> Int` |
| `scheduler_set_now` | `(sched: &mut RtScheduler, ms: Int)` |

### Tick Execution

| Function | Signature |
|----------|-----------|
| `scheduler_tick` | `(sched: &mut RtScheduler) -> RtScheduleResult` |

Work flow per tick:
1. Sort pending tasks by priority (bubble sort, O(n2), Critical first)
2. Calculate available slots (`max_concurrent - running_count`)
3. For each pending task (in priority order, up to available slots):
   - If expired (deadline passed) -> mark Skipped, increment stats
   - Otherwise -> mark Running, add to `executed`, increment `running_count`
4. Remaining pending tasks -> added to `deferred`

### Task Lifecycle

| Function | Signature | Transition |
|----------|-----------|------------|
| `scheduler_complete_task` | `(sched: &mut RtScheduler, task_id: Str) -> Bool` | Running -> Completed |
| `scheduler_fail_task` | `(sched: &mut RtScheduler, task_id: Str) -> Bool` | Running -> Pending (retry) or Failed (exhausted) |

### Scheduler Query

| Function | Signature |
|----------|-----------|
| `scheduler_find_task` | `(sched: &RtScheduler, task_id: Str) -> Option[RtTask]` |
| `scheduler_state_counts` | `(sched: &RtScheduler) -> (Int, Int, Int, Int, Int)` |
| `scheduler_is_idle` | `(sched: &RtScheduler) -> Bool` |

`scheduler_state_counts` returns a 5-tuple of `(pending, running, completed, failed, skipped)`.

---

## Scheduling Algorithm

### Priority Ordering

Tasks are ordered by `RtPriority` numeric value (Critical=0, High=1, Normal=2, Low=3, Background=4). The scheduler uses a stable bubble sort to arrange pending tasks before each tick.

### Concurrency Model

`max_concurrent` limits how many tasks can be in `Running` state simultaneously. Additional pending tasks are deferred until `scheduler_complete_task` or `scheduler_fail_task` frees a slot. When all slots are full (`running_count >= max_concurrent`), `scheduler_tick` defers all pending tasks without executing any.

### Deadline Enforcement

Each task has an optional `deadline_ms`. A task with `deadline_ms > 0` is expired when `now_ms > created_at_ms + deadline_ms`. Expired tasks are skipped (not executed) and counted in `stats.total_skipped`. Tasks with `deadline_ms == 0` never expire.

### Retry Logic

On failure (`scheduler_fail_task`):
- If `retry_count < max_retries` (default: 3) -> task returns to Pending, `retry_count` incremented
- If `retry_count >= max_retries` -> task transitions to Failed

---

## Contract Hotspots (Future Versions)

- Membership legality.
- Subscription state transitions.
- Presence TTL refresh.
- Event expiry rules.
- Sequence monotonicity.
- Deduplication windows.
- Authorization on send/join.
- Offline replay bounds.

## Planned Modules (Future Versions)

The design is organized around three layers (Subscription, Presence, Event) with cross-cutting concerns.

| Layer | Module | File | Status |
|-------|--------|------|--------|
| Scheduling | Priority Scheduler | `realtime.xi` | **Implemented** |
| Subscription | Channel | `src/channel.xi` | Planned |
| Subscription | Room | `src/room.xi` | Planned |
| Subscription | Membership | `src/membership.xi` | Planned |
| Subscription | Subscription | `src/subscription.xi` | Planned |
| Presence | Presence | `src/presence.xi` | Planned |
| Event | Event | `src/event.xi` | Planned |
| Event | Broadcast | `src/broadcast.xi` | Planned |
| Event | Fan-out | `src/fanout.xi` | Planned |
| Event | Ordering | `src/ordering.xi` | Planned |
| Cross-cutting | Auth | `src/auth.xi` | Planned |
| Event | Typing | `src/typing.xi` | Planned |
| Event | Activity | `src/activity.xi` | Planned |
| Event | Offline | `src/offline.xi` | Planned |
| Cross-cutting | Policy | `src/policy.xi` | Planned |
| Adapters | Integration bridges | `src/integration/` | Planned |
| Composition | Workflows | `src/workflows/` | Planned |

## Design Decisions

### Pure XIOM

The v0.1.0 scheduler uses no `extern "C"` declarations. All sorting, comparison, and state transitions are implemented in pure XIOM. This ensures the scheduler compiles and runs on any platform where the XIOM compiler works.

### Bubble Sort

The priority sort uses bubble sort (O(n2)) which is adequate for small task queues. Future versions will use a heap-based priority queue (`xiom.collections.BinaryHeap`) for O(log n) insert and O(1) extract-min.

### No Preemption

v0.1.0 uses cooperative scheduling: tasks must explicitly complete or fail. Preemptive scheduling with real-time guarantees is planned for v0.2.0.

### Monotonic Clock

The scheduler uses an explicit `now_ms` field rather than a system call. This makes the scheduler deterministic and testable -- callers set `now_ms` before each tick.
