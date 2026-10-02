# xiom.actor

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.
> **Scope:** actor-model scheduling as a pure, deterministic state machine:
> actor records with behavior state, bounded mailboxes with overflow policies,
> message records (sender, tag, int payloads), a ready queue with priority +
> FIFO selection, behavior switch (`become`) with versioned state, supervision
> links (restart/stop/escalate), dead-letter routing, and step-driven
> execution with traces and stats. No threads, no atomics, no locks, no
> clock, no I/O.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.convert`
> from it, the tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.actor` models an actor runtime as a plain value type and a set of free
functions. An `ActorSystem` holds:

- actor records as fourteen parallel `Vec[Int]` fields: ids, scheduling
  priorities, creation order, lifecycle states (`IDLE`, `SCHEDULED`,
  `RUNNING`, `STOPPED`, `FAILED`), behavior codes and versions, spawn
  behaviors, mailbox capacities and overflow policies, supervision links and
  directives, restart/processed/accumulator counters;
- messages as one global FIFO (parallel id/target/sender/tag/payload
  vectors); a mailbox is the sub-FIFO of messages targeting one actor, so
  per-actor order is exactly arrival order;
- the ready queue (`ready_ids`); selection is deterministic: largest
  priority first, ties broken by queue arrival (FIFO within a level);
- dead letters (six parallel vectors) with an exact reason per lost message:
  unknown target, stopped target, failed target, overflow (DROP_NEW),
  evicted (DROP_OLDEST);
- a dispatch trace, a consumed-message log, a human-readable event log and
  stats counters (`messages_sent`, `messages_processed`, `mail_drained`,
  `steps`, `total_restarts`, `total_stops`, `total_escalations`,
  `total_crashes`).

Because there is no concurrency in the library, every operation is a total,
deterministic transition: given the same state and inputs, the same state
and outcome follow. A real runtime owns threads, timers and I/O; this module
owns the *semantics* -- what a correct actor scheduler must do -- in a form
that can be tested exactly, without sleeps or races.

Three built-in behaviors are provided, and `become` switches between them at
runtime while bumping a version counter:

- `ACTOR_BEHAVIOR_ECHO` -- logs each message; a tag `>= ACTOR_TAG_BECOME`
  (100) switches the actor to `COUNT`;
- `ACTOR_BEHAVIOR_COUNT` -- adds each payload to the actor accumulator; tag
  `ACTOR_TAG_REVERT` (200) switches back to `ECHO`, tag
  `ACTOR_TAG_SELF_STOP` (201) stops the actor;
- `ACTOR_BEHAVIOR_SINK` -- counts the message and does nothing else.

Independently of the behavior, a message with tag `ACTOR_TAG_CRASH` (999)
crashes the receiver with the payload as the crash code. The crash is then
resolved by the receiver's supervisor:

- `ACTOR_RESTART` (default) -- reset behavior state (spawn behavior, version
  0, accumulator 0), keep the mailbox, reschedule if it is not empty;
- `ACTOR_STOP` -- stop the actor and dead-letter its mailbox;
- `ACTOR_ESCALATE` -- fail the actor permanently, dead-letter its mailbox,
  then crash the supervisor with the same code (recursively).

An actor without a supervisor fails permanently and dead-letters its
mailbox. Supervision links form a forest: one supervisor per child, and a
link that would create a cycle is refused.

## API

| Function | Returns | Description |
|---|---|---|
| `actor_system_new()` | `ActorSystem` | Empty system: no actors, empty queues, zero counters. |
| `actor_spawn(&mut s, id, priority, capacity, overflow, behavior)` | `Result[Int, Str]` | Spawn an actor; `Ok(creation order)`. `capacity = 0` means unbounded. |
| `actor_send(&mut s, target, sender, tag, payload)` | `Result[Int, Str]` | Send a message; `Ok(sequence id)`. Dead-lettered sends still return their id. |
| `actor_become(&mut s, id, behavior)` | `Result[Int, Str]` | Switch behavior and bump its version; `Ok(new version)`. |
| `actor_supervise(&mut s, child, supervisor)` | `Result[Int, Str]` | Link a child to a supervisor; refuses cycles and duplicate links. |
| `actor_set_supervise_policy(&mut s, id, directive)` | `Result[Int, Str]` | Set `RESTART`/`STOP`/`ESCALATE` for `id` as a supervisor. |
| `actor_crash(&mut s, id, code)` | `Result[Int, Str]` | Crash an actor and apply its supervisor's directive. |
| `actor_step(&mut s)` | `Result[Int, Str]` | Dispatch one ready actor and consume its oldest message. |
| `actor_peek_next(&mut s)` | `Result[Int, Str]` | The actor `actor_step` would dispatch, without any change. |
| `actor_run_all(&mut s, max_steps)` | `Result[Vec[Int], Str]` | Drive to quiescence; `Ok(dispatch trace of this run)`. |
| `actor_count(s)` | `Int` | Number of actors. |
| `actor_has_actor(s, id)` | `Bool` | Actor existence. |
| `actor_state(s, id)` | `Int` | `ACTOR_*` state code, `-1` when unknown. |
| `actor_behavior(s, id)` | `Int` | `ACTOR_BEHAVIOR_*` code, `-1` when unknown. |
| `actor_behavior_version(s, id)` | `Int` | Behavior version (0 at spawn/restart, +1 per become). |
| `actor_spawn_behavior(s, id)` | `Int` | Behavior a restart resets to. |
| `actor_priority(s, id)` | `Int` | Scheduling priority. |
| `actor_capacity(s, id)` | `Int` | Mailbox capacity (0 = unbounded). |
| `actor_overflow(s, id)` | `Int` | `ACTOR_OVERFLOW_*` code. |
| `actor_supervisor(s, id)` | `Int` | Supervisor id, or `ACTOR_NO_SUPERVISOR` (-1). |
| `actor_directive(s, id)` | `Int` | Directive `id` applies as a supervisor. |
| `actor_restart_count(s, id)` | `Int` | Supervised restarts of one actor. |
| `actor_processed_count(s, id)` | `Int` | Messages consumed by one actor. |
| `actor_accumulator(s, id)` | `Int` | `COUNT` accumulator. |
| `actor_mailbox_len(s, id)` | `Int` | Queued messages for one actor. |
| `actor_mailbox_tags(s, id)` | `Vec[Int]` | Copy of queued tags, oldest first. |
| `actor_ready_len(s)` | `Int` | Ready-queue length. |
| `actor_ready_ids(s)` | `Vec[Int]` | Copy of the ready queue, front first. |
| `actor_messages_sent(s)` | `Int` | Successful enqueues. |
| `actor_messages_processed(s)` | `Int` | Messages consumed by steps (crash messages included). |
| `actor_steps(s)` | `Int` | Successful dispatches. |
| `actor_restarts(s)` | `Int` | Total supervised restarts. |
| `actor_stops(s)` | `Int` | Total stops (self and supervised). |
| `actor_escalations(s)` | `Int` | Total escalations. |
| `actor_crashes(s)` | `Int` | Total crash transitions (including escalated and unhandled). |
| `actor_trace_len(s)` | `Int` | Dispatch-trace length. |
| `actor_trace(s)` | `Vec[Int]` | Copy of the global dispatch trace. |
| `actor_trace_text(s)` | `Str` | Trace as comma-separated ids (`""` when empty). |
| `actor_processed_total(s)` | `Int` | Consumed-message log length. |
| `actor_processed_actor(s, i)` | `Int` | Actor of log entry `i`, `-1` when out of range. |
| `actor_processed_tag(s, i)` | `Int` | Tag of log entry `i`, `-1` when out of range. |
| `actor_processed_payload(s, i)` | `Int` | Payload of log entry `i`, `-1` when out of range. |
| `actor_processed_text(s)` | `Str` | Log as `actor:tag` pairs, comma-separated. |
| `actor_event_count(s)` | `Int` | Event-log length. |
| `actor_event_at(s, i)` | `Str` | Event-log entry `i`, `""` when out of range. |
| `actor_dead_letter_count(s)` | `Int` | Dead-lettered messages. |
| `actor_dead_letter_id(s, i)` | `Int` | Sequence id of dead letter `i`, `-1` when out of range. |
| `actor_dead_letter_target(s, i)` | `Int` | Intended target of dead letter `i`. |
| `actor_dead_letter_sender(s, i)` | `Int` | Sender of dead letter `i`. |
| `actor_dead_letter_tag(s, i)` | `Int` | Tag of dead letter `i`. |
| `actor_dead_letter_payload(s, i)` | `Int` | Payload of dead letter `i`. |
| `actor_dead_letter_reason(s, i)` | `Int` | `ACTOR_DEAD_*` reason of dead letter `i`. |
| `actor_state_name(state)` | `Str` | `"idle"`, `"scheduled"`, `"running"`, `"stopped"`, `"failed"`. |
| `actor_behavior_name(behavior)` | `Str` | `"echo"`, `"count"`, `"sink"`. |
| `actor_directive_name(directive)` | `Str` | `"restart"`, `"stop"`, `"escalate"`. |
| `actor_overflow_name(overflow)` | `Str` | `"drop-new"`, `"drop-oldest"`. |
| `actor_dead_reason_name(reason)` | `Str` | `"unknown-target"`, `"stopped"`, `"overflow"`, `"evicted"`, `"failed"`. |
| `actor_check_invariant(s)` | `Bool` | Structural invariant check (see SPEC.md). |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Usage

```xi
use xiom.actor;

var s = actor_system_new();

// A worker (priority 5, capacity 3, evict-oldest) supervised by a sink.
actor_spawn(&mut s, 1, 0, 0, ACTOR_OVERFLOW_DROP_NEW, ACTOR_BEHAVIOR_SINK);   // supervisor
actor_spawn(&mut s, 2, 5, 3, ACTOR_OVERFLOW_DROP_OLDEST, ACTOR_BEHAVIOR_ECHO);
actor_supervise(&mut s, 2, 1);   // 1 supervises 2; directive defaults to RESTART

actor_send(&mut s, 2, -1, 11, 1);              // tag 11, payload 1 (external sender)
actor_send(&mut s, 2, -1, 12, 2);
actor_send(&mut s, 2, -1, ACTOR_TAG_CRASH, 3); // crash: RESTART keeps the mailbox

match actor_run_all(&mut s, 16) {
  Ok(trace) => { /* trace == [2, 2]; actor 2 is restarted and idle again */ },
  Err(_) => { /* "actor: step limit exceeded" */ },
}

// actor_check_invariant(&s) == true
```

## Tests

```
.\scripts\port.ps1 -Package xiom.actor -TimeoutSec 60
```

Expected: 28 `[PASS]` lines, then `xiom.actor: all tests passed`, exit 0
(program), `port: PASS (passed=28 failed=0 ...)`.

The suite is fixture-driven and deterministic: mailbox overflow (both
policies), FIFO ordering, become/versioning, the three built-in behaviors,
supervision `RESTART`/`STOP`/`ESCALATE` (including an escalation chain),
dead-letter reasons, priority scheduling, the bounded `run_all` driver,
accessor bounds, and the structural invariant across mixed 30-cycle
send/step workloads.

## Install / publish

```
xiom pkg install xiom.actor@0.1.0     # consumer (once published)
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
