# xiom.actor -- Specification

Status: `incubating` (implemented, conformance-green 28/28, not published).
Module: `xiom.actor` (`src/actor.xi`). Manifest: `package.xi` (name
`xiom.actor`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library module imports `xiom.convert` only.

## 1. Scope

An actor-model scheduler as a pure, deterministic state machine -- the
semantic core an actor runtime would drive:

- actor records (ids, priorities, creation order, states, behaviors and
  versions, spawn behaviors, mailbox capacities and overflow policies,
  supervision links and directives) as parallel `Vec[Int]` fields;
- message records (sequence id, target, sender, tag, int payload) as one
  global FIFO; a mailbox is the per-target sub-FIFO;
- deterministic scheduling over an explicit ready queue: largest priority
  first, ties broken by queue arrival (FIFO within a priority level);
- behavior switch (`become`) with versioned state, and three built-in
  behaviors (`ECHO`, `COUNT`, `SINK`);
- supervision links (one supervisor per child, forest with acyclicity
  enforced at link time) with `RESTART`, `STOP` and `ESCALATE` directives;
- dead-letter routing with an exact reason code per lost message;
- step-driven execution (`actor_step`, `actor_run_all`) with a dispatch
  trace, a consumed-message log, an event log and stats counters;
- a structural invariant (`actor_check_invariant`).

No threads, no atomics, no locks, no clock, no I/O, no FFI, no global state.
The library owns semantics only; a backend owns concurrency and blocking.

## 2. Non-goals

- Actual concurrency, execution of arbitrary user code, or blocking. The
  system is a value; a backend drives it.
- Timers, timeouts, watch/`DOWN` messages, remote actors, clustering,
  persistence, or message serialization.
- Dynamic behaviors beyond the three documented codes. `become` is
  versioned state switching, not a closure or function-pointer table.
- Fairness or aging beyond the documented selection rule.
- Actor removal or id reuse; the actor table only grows.
- Backpressure beyond the two mailbox overflow policies.

## 3. State

```xi
pub type ActorSystem = {
  // actors, parallel by slot (14 vectors, all length n)
  actor_ids: Vec[Int];             // unique actor ids, >= 0
  actor_priorities: Vec[Int];      // >= 0, larger = more urgent
  actor_orders: Vec[Int];          // creation sequence, dense: orders[i] == i
  actor_states: Vec[Int];          // ACTOR_* state codes
  actor_behaviors: Vec[Int];       // ACTOR_BEHAVIOR_* codes
  actor_spawn_behaviors: Vec[Int]; // behavior a restart resets to
  actor_versions: Vec[Int];        // 0 at spawn/restart, +1 per become
  actor_capacities: Vec[Int];      // >= 0; 0 = unbounded
  actor_overflows: Vec[Int];       // ACTOR_OVERFLOW_* codes
  actor_supervisors: Vec[Int];     // supervisor id or ACTOR_NO_SUPERVISOR
  actor_directives: Vec[Int];      // directive this actor applies as a supervisor
  actor_restarts: Vec[Int];        // per-actor supervised restarts
  actor_processed: Vec[Int];       // per-actor consumed messages
  actor_accumulators: Vec[Int];    // COUNT payoff sum
  next_order: Int;                 // next creation sequence == actor count
  // scheduling
  ready_ids: Vec[Int];             // ready queue, index 0 = front
  // messages: one global FIFO, parallel by queue position
  msg_ids: Vec[Int];               // global sequence id (assigned by actor_send)
  msg_targets: Vec[Int];           // recipient actor id
  msg_senders: Vec[Int];           // sender actor id or ACTOR_NO_SENDER
  msg_tags: Vec[Int];              // caller tag, >= 0
  msg_payloads: Vec[Int];          // caller payload, any Int
  next_message_id: Int;            // next sequence id == total validated sends
  mail_drained: Int;               // messages removed from a mailbox unconsumed
  // dead letters, parallel
  dead_ids: Vec[Int];
  dead_targets: Vec[Int];
  dead_senders: Vec[Int];
  dead_tags: Vec[Int];
  dead_payloads: Vec[Int];
  dead_reasons: Vec[Int];          // ACTOR_DEAD_* codes
  // traces and stats
  dispatch_order: Vec[Int];        // global dispatch trace
  events: Vec[Str];                // human-readable audit trail
  proc_actors: Vec[Int];           // consumed-message log (parallel)
  proc_tags: Vec[Int];
  proc_payloads: Vec[Int];
  messages_sent: Int;              // successful enqueues
  messages_processed: Int;         // messages consumed by steps
  steps: Int;                      // successful dispatches
  total_restarts: Int;
  total_stops: Int;
  total_escalations: Int;
  total_crashes: Int;
}
```

Every field is an internal implementation detail; callers go through the
free functions. The parallel vectors are pushed and rebuilt together by
every mutation, so they can never skew. There is no `Vec[StructType]`, no
method syntax and no function-pointer table anywhere in the module.

### 3.1 Constants

| Constant | Value | Meaning |
|---|---|---|
| `ACTOR_OVERFLOW_DROP_NEW` | 0 | Full mailbox: drop the arriving message. |
| `ACTOR_OVERFLOW_DROP_OLDEST` | 1 | Full mailbox: evict the oldest queued message, then append. |
| `ACTOR_IDLE` | 0 | Not queued, empty mailbox. |
| `ACTOR_SCHEDULED` | 1 | In the ready queue. |
| `ACTOR_RUNNING` | 2 | Transient; only observable inside `actor_step`. |
| `ACTOR_STOPPED` | 3 | Terminal (self-stop or supervisor `STOP`). |
| `ACTOR_FAILED` | 4 | Terminal (unhandled or escalated crash). |
| `ACTOR_BEHAVIOR_ECHO` | 0 | Log messages; become `COUNT` at tag >= 100. |
| `ACTOR_BEHAVIOR_COUNT` | 1 | Accumulate payloads; revert at tag 200, self-stop at tag 201. |
| `ACTOR_BEHAVIOR_SINK` | 2 | Count only. |
| `ACTOR_RESTART` | 0 | Supervision directive: reset and reschedule. |
| `ACTOR_STOP` | 1 | Supervision directive: stop and drain. |
| `ACTOR_ESCALATE` | 2 | Supervision directive: fail, drain, crash the supervisor. |
| `ACTOR_DEAD_UNKNOWN` | 0 | Dead letter: target actor does not exist. |
| `ACTOR_DEAD_STOPPED` | 1 | Dead letter: target is stopped (or a `STOP` drained the mailbox). |
| `ACTOR_DEAD_OVERFLOW` | 2 | Dead letter: `DROP_NEW` on a full mailbox. |
| `ACTOR_DEAD_EVICTED` | 3 | Dead letter: `DROP_OLDEST` eviction. |
| `ACTOR_DEAD_FAILED` | 4 | Dead letter: target is failed, or a failure drained the mailbox. |
| `ACTOR_TAG_CRASH` | 999 | Crashes the receiver (payload = crash code), whatever the behavior. |
| `ACTOR_TAG_BECOME` | 100 | ECHO switches to COUNT at `tag >= 100`. |
| `ACTOR_TAG_REVERT` | 200 | COUNT switches back to ECHO. |
| `ACTOR_TAG_SELF_STOP` | 201 | COUNT stops the actor. |
| `ACTOR_NO_SUPERVISOR` | -1 | Sentinel: no supervision link. |
| `ACTOR_NO_SENDER` | -1 | Sentinel: external sender. |
| `ACTOR_NOT_FOUND` | -1 | Sentinel: unknown actor / out-of-range accessor. |

### 3.2 Invariant

`actor_check_invariant(s)` is true exactly when:

1. all fourteen actor vectors have equal length `n`, `next_order == n`, and
   `actor_orders[i] == i`;
2. every actor id is `>= 0` and unique; every priority and capacity is
   `>= 0`; every state, behavior, spawn behavior, overflow and directive
   code is valid; versions, restart counters and processed counters are
   `>= 0`; every supervisor either is `ACTOR_NO_SUPERVISOR` or an existing
   actor id different from the actor itself, and the supervision graph is
   acyclic (no parent chain longer than `n`);
3. every ready-queue entry names a `SCHEDULED` actor with a non-empty
   mailbox, with no duplicates, and every `SCHEDULED` actor is queued
   exactly once; no actor is observed `RUNNING`; every `IDLE` actor has an
   empty mailbox; every `STOPPED`/`FAILED` actor has an empty mailbox;
4. the five message vectors have equal length; every target exists and is
   live (not `STOPPED`, not `FAILED`); sequence ids are strictly increasing
   along the queue and below `next_message_id`; no mailbox exceeds its
   capacity (when > 0);
5. the six dead-letter vectors have equal length, every reason is an
   `ACTOR_DEAD_*` code, and every id is below `next_message_id`;
6. the three processed-log vectors have equal length,
   `messages_processed` equals that length and equals the sum of the
   per-actor processed counters, `steps` equals the dispatch-trace length,
   `messages_sent == queued + processed + drained`, and the sequence ids
   are dense: `messages_sent + (dead letters never enqueued) ==
   next_message_id`.

## 4. Operations

Every operation is a total function of the current state. On any `Err` the
state is unchanged (validation is performed before any mutation). All
`Str` results are compared with `str_compare` by callers; the module itself
never compares strings.

### 4.1 `actor_system_new()`

Returns an empty system: no actors, empty ready queue, empty message and
dead-letter vectors, empty traces, all counters zero. `O(1)`.

### 4.2 `actor_spawn(s, id, priority, capacity, overflow, behavior)`

Validation order:

1. `id < 0` -> `Err("actor: actor id must be >= 0")`;
2. `priority < 0` -> `Err("actor: priority must be >= 0")`;
3. `capacity < 0` -> `Err("actor: capacity must be >= 0")`;
4. unknown `overflow` -> `Err("actor: unknown overflow policy")`;
5. unknown `behavior` -> `Err("actor: unknown behavior")`;
6. `id` already exists -> `Err("actor: duplicate actor id")`;
7. otherwise the actor is appended in state `IDLE`, `orders[i] == next_order`,
   directives default to `ACTOR_RESTART`, supervision to
   `ACTOR_NO_SUPERVISOR`, all per-actor counters 0, `next_order += 1`, an
   event `spawn:<id>:<behavior>` is recorded, `Ok(creation order)`.
   `O(n)`.

### 4.3 `actor_send(s, target, sender, tag, payload)`

Validation order:

1. `target < 0` -> `Err("actor: target id must be >= 0")`;
2. `sender < -1` -> `Err("actor: sender id must be >= -1")`;
3. `tag < 0` -> `Err("actor: tag must be >= 0")`;
4. `sender >= 0` and unknown -> `Err("actor: unknown sender id")`;
5. otherwise a sequence id `seq = next_message_id` is assigned and
   `next_message_id += 1` (ids are dense, unique, monotonically increasing
   across both the queue and the dead letters).

Routing (all accepted cases return `Ok(seq)`):

| Target state | Outcome |
|---|---|
| unknown | dead letter, reason `ACTOR_DEAD_UNKNOWN` |
| `STOPPED` | dead letter, reason `ACTOR_DEAD_STOPPED` |
| `FAILED` | dead letter, reason `ACTOR_DEAD_FAILED` |
| `IDLE`/`SCHEDULED` | overflow policy, then enqueue; an `IDLE` target becomes `SCHEDULED` |

Overflow (only when `capacity > 0` and the mailbox length is `>= capacity`):

- `DROP_NEW`: the arriving message is dead-lettered with
  `ACTOR_DEAD_OVERFLOW`; the mailbox is untouched;
- `DROP_OLDEST`: the oldest queued message for the target is dead-lettered
  with `ACTOR_DEAD_EVICTED` (`mail_drained += 1`) and the arriving message
  is appended.

A successful enqueue increments `messages_sent`. `O(queue length)`.

### 4.4 `actor_become(s, id, behavior)`

1. unknown `behavior` -> `Err("actor: unknown behavior")`;
2. unknown `id` -> `Err("actor: unknown actor id")`;
3. state `STOPPED` -> `Err("actor: actor already stopped")`;
4. state `FAILED` -> `Err("actor: actor already failed")`;
5. otherwise the behavior is set, the version is incremented
   (`version = version + 1`), an event `become:<id>:<behavior>:<version>`
   is recorded, and `Ok(new version)` is returned. `O(n)`.

### 4.5 `actor_supervise(s, child, supervisor)`

1. unknown `child` -> `Err("actor: unknown child id")`;
2. unknown `supervisor` -> `Err("actor: unknown supervisor id")`;
3. `child == supervisor` -> `Err("actor: cannot supervise itself")`;
4. supervisor `STOPPED` -> `Err("actor: supervisor is stopped")`;
5. supervisor `FAILED` -> `Err("actor: supervisor is failed")`;
6. `child` already supervised -> `Err("actor: actor already supervised")`;
7. `child` appears on `supervisor`'s ancestor chain -> `Err("actor:
   supervision cycle")`;
8. otherwise `supervisors[child] = supervisor`, `Ok(supervisor)`. One
   supervisor per child; the graph is a forest. `O(n^2)` worst case.

### 4.6 `actor_set_supervise_policy(s, id, directive)`

1. unknown `directive` -> `Err("actor: unknown directive")`;
2. unknown `id` -> `Err("actor: unknown actor id")`;
3. otherwise `directives[id] = directive`, `Ok(directive)`. The directive
   is accepted for terminal actors too (it only acts while supervising).
   Default is `ACTOR_RESTART`. `O(n)`.

### 4.7 `actor_crash(s, id, code)` and crash resolution

1. unknown `id` -> `Err("actor: unknown actor id")`;
2. state `STOPPED` -> `Err("actor: actor already stopped")`;
3. state `FAILED` -> `Err("actor: actor already failed")`;
4. otherwise the crash transition runs (below), `Ok(code)`.

Crash transition (also triggered by a `ACTOR_TAG_CRASH` message, checked
before the behavior machine; the message itself is logged and counted):

1. the actor becomes `FAILED`, is removed from the ready queue,
   `total_crashes += 1`, event `crash:<id>:<code>`;
2. no supervisor (or a dangling link) -> the mailbox is dead-lettered with
   `ACTOR_DEAD_FAILED`, event `unhandled:<id>`; the actor stays `FAILED`;
3. supervisor directive `RESTART` -> state `IDLE`, behavior reset to the
   spawn behavior, version 0, accumulator 0, per-actor and total restart
   counters incremented, event `restart:<id>:<supervisor>`; when the
   mailbox is non-empty the actor is immediately rescheduled;
4. directive `STOP` -> state `STOPPED`, mailbox dead-lettered with
   `ACTOR_DEAD_STOPPED`, `total_stops += 1`, event
   `stop:<id>:<supervisor>`;
5. directive `ESCALATE` -> mailbox dead-lettered with `ACTOR_DEAD_FAILED`,
   `total_escalations += 1`, event `escalate:<id>:<supervisor>`, then the
   supervisor crashes with the same code (step 1 recursively). Because the
   supervision graph is acyclic and each recursion moves strictly upward,
   escalation terminates in at most `n` crashes.

An already-terminal supervisor is a no-op at the recursion boundary.

### 4.8 `actor_step(s)`

1. empty ready queue -> `Err("actor: no ready actors")`;
2. select the ready-queue index by the scheduling rule (section 5) and
   remove it;
3. state becomes `RUNNING`, `steps += 1`, the id is appended to the
   dispatch trace, event `dispatch:<id>`;
4. the oldest queued message for the actor (lowest queue position with that
   target) is removed and processed (section 7);
5. finalize: if the state is still `RUNNING` it becomes `IDLE`, and the
   actor is rescheduled when its mailbox is non-empty. A state changed by
   the behavior (stop, crash handling) is left untouched;
6. `Ok(actor id)`.

The fallback `Err("actor: mailbox is empty")` exists only to fail closed if
the invariant were ever broken; it restores the actor to `IDLE`.
`O(n + queue length)`.

### 4.9 `actor_peek_next(s)`

Same selection rule as `actor_step` without any state change: `Ok(actor
id)`, or `Err("actor: no ready actors")` for an empty queue. `O(n + queue
length)`.

### 4.10 `actor_run_all(s, max_steps)`

1. `max_steps < 0` -> `Err("actor: max_steps must be >= 0")`;
2. loop: when the ready queue is empty -> `Ok(trace)` with the actor ids
   dispatched by this run; when `dispatched >= max_steps` while the queue
   is non-empty -> `Err("actor: step limit exceeded")` (work done so far
   is retained; no trace is returned); otherwise `actor_step` and append
   its id to the run trace.

Every iteration consumes exactly one message, so the loop is bounded by
`max_steps` and by the queued-message count; it always terminates.
`O(max_steps * (n + queue length))`.

## 5. Scheduling rule

The ready queue is ordered by arrival. Selection scans front to back and
keeps the entry whose actor has the strictly largest priority; only a
strictly larger priority replaces the current best, so among equal
priorities the earliest queue position wins. Consequence: within one
priority level the queue is FIFO, across levels the highest priority
dispatches first. When an actor's mailbox still holds messages at the end
of its step it is re-appended at the back, so it yields to actors that were
already queued (round-robin within the level).

## 6. Mailbox rules

A mailbox is the sub-FIFO of the global message queue with the actor as
target. Order is arrival order, always. A bound of `capacity = 0` disables
overflow handling. `DROP_OLDEST` may reorder nothing: it removes the front
and appends the back, preserving the order of the remaining messages.
Messages are never rewritten or re-sent; a lost message is preserved in the
dead letters with its original id, target, sender, tag and payload plus a
reason. `mail_drained` counts mailbox removals that were not consumption
(evictions and terminal drains).

## 7. Behavior machine

For every consumed message, first the processed log and counters are
updated, then:

- tag `ACTOR_TAG_CRASH` -> crash with `payload` as the crash code;
- behavior `ECHO` -> event `echo:<id>:<tag>:<payload>`; if `tag >=
  ACTOR_TAG_BECOME` become `COUNT` (version +1);
- behavior `COUNT` -> `accumulator += payload`, event
  `count:<id>:<tag>:<payload>`; `tag == ACTOR_TAG_REVERT` becomes `ECHO`;
  `tag == ACTOR_TAG_SELF_STOP` stops the actor (terminal, mailbox drained,
  `total_stops += 1`, event `stop:<id>:self`);
- behavior `SINK` -> event `sink:<id>:<tag>` only.

The crash check wins over the behavior, so a crash message is never an
echo/count/sink. All arithmetic is 64-bit signed `Int`; there are no
floating-point values, so no rounding questions arise.

## 8. Dead letters

| Situation | Reason |
|---|---|
| target actor unknown | `ACTOR_DEAD_UNKNOWN` |
| target `STOPPED` | `ACTOR_DEAD_STOPPED` |
| target `FAILED` | `ACTOR_DEAD_FAILED` |
| `DROP_NEW` on a full mailbox | `ACTOR_DEAD_OVERFLOW` |
| `DROP_OLDEST` eviction | `ACTOR_DEAD_EVICTED` |
| supervisor `STOP` drained the mailbox | `ACTOR_DEAD_STOPPED` |
| terminal failure drained the mailbox (unhandled/escalated crash) | `ACTOR_DEAD_FAILED` |

Dead letters are append-only for the lifetime of the system; the six
parallel vectors only grow.

## 9. Traces and stats

- dispatch trace: every dispatched actor id, in order, globally
  (`actor_trace`, `actor_trace_text`);
- consumed-message log: `(actor, tag, payload)` per consumed message,
  including crash messages (`actor_processed_*`);
- event log: `spawn:`, `dispatch:`, `echo:`, `count:`, `sink:`, `become:`,
  `crash:`, `restart:`, `stop:`, `escalate:`, `unhandled:` entries;
- counters: `messages_sent`, `messages_processed`, `steps`, per-actor
  processed/restart/accumulator, and the totals `total_restarts`,
  `total_stops`, `total_escalations`, `total_crashes`.

## 10. Determinism and termination

The system never reads a clock, a random source, or the environment. Every
operation is a pure transition over plain integer vectors, so a given call
sequence always produces the same state, same traces and same stats. All
loops are bounded: lookups by actor count, queue rebuilds by queue length,
the driver by `max_steps` and the queued-message count, and escalation by
the acyclic supervision chain (`<= n` crashes).

## 11. Test notes

`tests/test_conformance.xi` runs 28 fixture-driven checks (no function
tables; every test calls the API directly). The suite covers: empty-system
behavior; spawn validation and metadata; send/schedule/step; mailbox FIFO
order; become and versioning; COUNT accumulation and revert; self-stop;
priority selection with FIFO ties; snapshot independence; both overflow
policies; send validation and unknown-target dead letters; stopped/failed
targets; supervision link validation and cycle refusal; `RESTART` with
state reset and rescheduling; `STOP` with mailbox drain; `ESCALATE` through
a chain; unhandled crashes; the crash refusal on stopped actors; `run_all`
bounds; stats/trace/log accumulation; accessor bounds; name helpers; the
event log; the invariant across 30 mixed send/step cycles; and an
end-to-end supervised-worker scenario.
