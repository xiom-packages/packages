# xiom.serverless -- Specification

Status: `incubating` (implemented, harness-green, not published).
Modules: `xiom.serverless` (`src/serverless.xi`), `xiom.serverless.deploy`
(`src/deploy.xi`), `xiom.serverless.invoke` (`src/invoke.xi`),
`xiom.serverless.check` (`src/check.xi`). Manifest: `package.xi` (name
`xiom.serverless`, version `0.1.0`). `xiom.std` is a manifest dependency; the
library modules import `xiom.convert` only.

## 1. Scope

Serverless compute abstractions as a pure, deterministic state machine -- the
semantic core a FaaS control plane and runtime would drive:

- function definition: lifecycle, monotonic versions, handler code, memory and
  timeout metadata;
- trigger/event-source wiring: timer/HTTP/queue sources bound to a function;
- deploy package/rollout state machine with failure and rollback;
- runtime/handler lifecycle: COLD/WARM/BUSY instances with cold-start
  accounting (`cold_starts`, `cold_start_ms`, `cold_invocations`,
  `warm_invocations`);
- synchronous and asynchronous invocation with a deterministic FIFO
  queue/dispatch/finish executor, a concurrency cap, timeouts, failure codes
  and a completion trace.

No networking, no threads, no atomics, no locks, no clock, no I/O, no FFI, no
global state. Time is an explicit `elapsed_ms` argument; a backend owns real
execution.

## 2. Non-goals

- Real sockets, HTTP, timers, containers or sandboxes.
- Actual parallelism or preemption; `max_concurrency` is a deterministic
  dispatch bound, not a scheduler.
- Payload serialization: payloads, outputs and codes are `Int` slots (the
  caller can map them to bytes); timeout/cold-start time is integer ms.
- Retries, DLQs, idempotency, per-tenant isolation, quotas or billing.
- Provider-specific manifest formats (AWS Lambda, Azure Functions, ...); the
  model is provider-neutral.
- Removal of entities: tables only grow; ids are never reused.

## 3. State

The whole system is one value; callers only go through the free functions.
Parallel `Vec[Int]` tables are pushed/rebuilt together and can never skew.

```xi
pub type ServerlessSystem = {
  // functions
  function_ids: Vec[Int];        // unique, >= 0
  function_states: Vec[Int];     // SV_FN_*
  function_versions: Vec[Int];   // 0 while DRAFT, >= 1 once deployed
  function_handlers: Vec[Int];   // SV_HANDLER_*
  function_memory_mb: Vec[Int];  // >= 1
  function_timeout_ms: Vec[Int]; // >= 1
  // triggers
  trigger_ids: Vec[Int];         // unique, >= 0
  trigger_functions: Vec[Int];   // existing function id
  trigger_kinds: Vec[Int];       // SV_TRIGGER_*
  trigger_enabled: Vec[Int];     // 0 / 1
  trigger_fires: Vec[Int];       // >= 0
  // deploys
  deploy_ids: Vec[Int];          // unique, >= 0
  deploy_functions: Vec[Int];    // existing function id
  deploy_states: Vec[Int];       // SV_DEPLOY_*
  deploy_versions: Vec[Int];     // >= 1 (target version)
  deploy_steps_total: Vec[Int];  // >= 1
  deploy_steps_done: Vec[Int];   // 0 .. steps_total
  deploy_codes: Vec[Int];        // failure code (>= 1 while FAILED)
  deploy_prev_versions: Vec[Int]; // function version before READY
  // invocations
  invocation_ids: Vec[Int];        // unique, >= 0
  invocation_functions: Vec[Int];  // existing function id
  invocation_states: Vec[Int];     // SV_INV_*
  invocation_payloads: Vec[Int];
  invocation_outputs: Vec[Int];    // 0 until DONE
  invocation_codes: Vec[Int];      // SV_CODE_*
  invocation_instances: Vec[Int];  // instance slot or SV_NO_INSTANCE
  invocation_colds: Vec[Int];      // 1 = the run paid a cold start
  queue: Vec[Int];                 // FIFO of QUEUED invocation ids
  // runtime instances
  instance_ids: Vec[Int];          // unique, >= 0
  instance_functions: Vec[Int];    // existing function id
  instance_states: Vec[Int];       // SV_RT_*
  instance_served: Vec[Int];       // invocations served, >= 0
  // configuration and counters
  boot_ms: Int;              // cold-start cost per COLD -> WARM, >= 0
  max_concurrency: Int;      // async dispatch cap, >= 1
  next_instance_id: Int;     // auto-allocation cursor, >= 0
  running: Int;              // async invocations currently RUNNING
  completed: Int;            // DONE invocations
  failed: Int;               // FAILED invocations (handler/timeout/aborted)
  timed_out: Int;            // failures with SV_CODE_TIMEOUT
  aborted: Int;              // failures with SV_CODE_ABORTED
  cold_starts: Int;          // COLD -> WARM transitions
  cold_start_ms: Int;        // == cold_starts * boot_ms
  cold_invocations: Int;     // finished invocations that paid a cold start
  warm_invocations: Int;     // finished invocations served warm
  completion_order: Vec[Int]; // terminal invocation ids, in order
}
```

Codes: functions `SV_FN_DRAFT` 0 / `SV_FN_ACTIVE` 1 / `SV_FN_DISABLED` 2;
handlers `SV_HANDLER_ECHO` 0 / `SV_HANDLER_DOUBLE` 1 / `SV_HANDLER_FAIL` 2;
triggers `SV_TRIGGER_TIMER` 0 / `SV_TRIGGER_HTTP` 1 / `SV_TRIGGER_QUEUE` 2;
deploys `SV_DEPLOY_PENDING` 0 / `SV_DEPLOY_IN_PROGRESS` 1 / `SV_DEPLOY_READY` 2
/ `SV_DEPLOY_FAILED` 3 / `SV_DEPLOY_ROLLED_BACK` 4; invocations
`SV_INV_QUEUED` 0 / `SV_INV_RUNNING` 1 / `SV_INV_DONE` 2 / `SV_INV_FAILED` 3;
codes `SV_CODE_OK` 0 / `SV_CODE_HANDLER` 1 / `SV_CODE_TIMEOUT` 2 /
`SV_CODE_ABORTED` 3; runtimes `SV_RT_COLD` 0 / `SV_RT_WARM` 1 / `SV_RT_BUSY` 2.
Sentinels: `SV_NOT_FOUND` -1, `SV_NO_INSTANCE` -1.

### 3.1 Invariant

`serverless_check_invariant(s)` (module `xiom.serverless.check`) is true
exactly when:

1. every entity table has equal-length parallel vectors and unique ids
   (functions, triggers, deploys, invocations, instances);
2. function states/handlers are valid, versions `>= 0`, memory/timeouts
   `>= 1`; version 0 implies DRAFT and every non-DRAFT state has version
   `>= 1`;
3. trigger functions exist, kinds are valid, enable flags are 0/1, fire
   counters are `>= 0`;
4. deploy functions exist, states are valid, `1 <= steps_total`,
   `0 <= steps_done <= steps_total`, versions `>= 1`, READY implies
   `steps_done == steps_total`; FAILED carries `code >= 1`, every other state
   carries 0 except ROLLED_BACK, which keeps the failure code when it sealed a
   FAILED rollout;
5. invocation functions exist, states are valid, `DONE` implies code 0 and
   `FAILED` implies a non-zero code;
6. the queue holds exactly the QUEUED invocations, each exactly once;
7. instance functions exist, states are valid, `instance_served >= 0`;
8. `running` equals the RUNNING count and is `<= max_concurrency`;
   `completed + failed` equals the terminal count; the trace lists each
   terminal invocation exactly once; `cold_invocations + warm_invocations +
   aborted == completed + failed`; `cold_start_ms == cold_starts * boot_ms`.

## 4. Function lifecycle

```
function_new(id, handler, memory_mb, timeout_ms)
    id < 0            -> Err("serverless: function id must be >= 0")
    duplicate id      -> Err("serverless: duplicate function id")
    unknown handler   -> Err("serverless: unknown handler")
    memory_mb < 1     -> Err("serverless: memory must be >= 1")
    timeout_ms < 1    -> Err("serverless: timeout must be >= 1")
    otherwise          -> DRAFT, version 0, Ok(id)
function_disable(id) : ACTIVE -> DISABLED; DRAFT -> "function is not active";
                       DISABLED -> "already disabled"
function_enable(id)  : DISABLED -> ACTIVE; ACTIVE -> "already active";
                       DRAFT -> "function has no deployment"
```

Every error leaves the state unchanged. Versions only advance through deploy
activation; disabling preserves the version.

## 5. Trigger wiring

```
trigger_new(tid, fid, kind, enabled)
    tid < 0 / duplicate / unknown function / unknown kind / enabled not 0|1
    -> the exact error, state unchanged
    otherwise -> Ok(tid), fires 0
trigger_enable / trigger_disable : toggle; wrong state -> "already ..."
trigger_fire(tid, invocation_id, payload)
    1. unknown trigger        -> Err("serverless: unknown trigger id")
    2. disabled trigger       -> Err("serverless: trigger is disabled")
    3. bound function not ACTIVE -> Err("serverless: function is not active")
    4. invocation_id < 0      -> Err("serverless: invocation id must be >= 0")
    5. duplicate invocation   -> Err("serverless: duplicate invocation id")
    6. otherwise: append a QUEUED invocation (payload), push it on the FIFO,
       fires += 1, Ok(invocation_id)
```

Validation order is part of the contract (checked by the suite); every error
leaves the state unchanged.

## 6. Deploy machine

```
deploy_begin(did, fid, version, steps_total)
    did < 0 / duplicate / unknown function / disabled function
    -> the exact error
    steps_total < 1        -> Err("serverless: steps must be >= 1")
    version != current + 1 -> Err("serverless: version must be current + 1")
    otherwise -> PENDING, steps_done 0, code 0, prev = current version,
                 Ok(did)
deploy_step(did) : PENDING/IN_PROGRESS only; steps_done += 1, state becomes
    IN_PROGRESS; when steps_done == steps_total -> READY and the function
    takes the deploy version and becomes ACTIVE. Terminal states are refused
    ("deploy already ready/failed/rolled back") and are unchanged.
deploy_fail(did, code) : PENDING/IN_PROGRESS -> FAILED with code (>= 1),
    Ok(code); terminal states refused.
deploy_rollback(did) : READY -> ROLLED_BACK, restoring prev version and
    ACTIVE when prev >= 1 else DRAFT; FAILED -> ROLLED_BACK (code kept);
    ROLLED_BACK -> "already rolled back"; PENDING/IN_PROGRESS ->
    "deploy is not rollbackable".
```

Deploys are immutable history; a rolled-back version can be redeployed because
versions are monotonic (`current + 1`).

## 7. Invocation machine

Sync path (`invoke_sync`):

```
1. invocation_id < 0        -> "invocation id must be >= 0"
2. duplicate invocation     -> "duplicate invocation id"
3. elapsed_ms < 0           -> "elapsed_ms must be >= 0"
4. unknown function         -> "unknown function id"
5. function not ACTIVE      -> "function is not active"
6. record RUNNING; attach runtime; settle (below)
```

Async path:

```
invoke_async(iid, fid, payload)   : validations 1,2,4,5; append QUEUED, push.
invoke_dispatch()                  : empty queue -> "no queued invocations";
    running >= max_concurrency -> "concurrency limit reached"; pops the FIFO
    front; if the bound function is no longer ACTIVE the invocation is settled
    FAILED/SV_CODE_ABORTED (failed += 1, aborted += 1, traced) and the call
    fails with "function is not active"; otherwise attach a runtime, state
    RUNNING, running += 1, Ok(id).
invoke_finish(iid, elapsed_ms)     : elapsed < 0 -> "elapsed_ms must be >= 0";
    unknown / DONE / FAILED / not RUNNING -> exact lifecycle error; otherwise
    settle (below) with the async flag.
invoke_run_all(max_steps, elapsed) : max_steps < 0 or elapsed < 0 -> the exact
    error; loop: empty queue -> Ok(trace); dispatched >= max_steps ->
    Err("step limit exceeded"); dispatch + finish; a failed invocation aborts
    the run and surfaces its error. The loop terminates: every iteration
    removes one queue entry and max_steps caps the dispatches.
```

Settle (shared, `elapsed_ms` caller-supplied):

```
instance BUSY -> WARM (released); async running -= 1
cold/warm counter += 1 (based on the recorded cold flag)
elapsed_ms >  timeout_ms -> FAILED, SV_CODE_TIMEOUT, failed/timed_out += 1,
                            traced, Err("invocation timed out")
handler == SV_HANDLER_FAIL -> FAILED, SV_CODE_HANDLER, failed += 1, traced,
                              Err("handler failed")
otherwise -> DONE, output = handler(payload) (ECHO: payload, DOUBLE: 2x),
             completed += 1, traced, Ok(output)
```

Timeout wins over a failing handler; `elapsed_ms == timeout_ms` succeeds.
Common sense: sync invocations do not count against `running`; async ones do.

## 8. Runtime instances and cold starts

```
runtime_alloc(iid, fid) : iid < 0 / duplicate / unknown function -> exact
    error; otherwise COLD instance, Ok(iid); does NOT charge a cold start.
runtime_init(iid)       : COLD -> WARM, cold_starts += 1,
    cold_start_ms += boot_ms, Ok(cold_starts); WARM -> "already warm";
    BUSY -> "instance is busy".
```

Dispatch/first use acquisition (`_attach_runtime`):

1. first WARM instance of the function (slots ascend -> deterministic);
2. else first COLD instance, initialized (cold start charged);
3. else a fresh instance auto-allocated at the smallest free id from
   `next_instance_id` and initialized.

The chosen instance is recorded on the invocation together with the cold flag;
`instance_served += 1`, state BUSY. A finished invocation increments exactly
one of `cold_invocations`/`warm_invocations`, which is why
`cold_invocations + warm_invocations + aborted == completed + failed` holds
for every reachable state. `cold_start_ms == cold_starts * boot_ms` because
every cold start charges the same system `boot_ms`.

## 9. Error catalog

All messages are stable and prefixed `serverless: `; the suite pins every
message. No panicking input exists: every function is total, and read
accessors return `-1`/`false`/`""` sentinels.

| Area | Errors |
|---|---|
| construction | `max_concurrency must be >= 1`, `boot_ms must be >= 0` |
| functions | `function id must be >= 0`, `duplicate function id`, `unknown handler`, `memory must be >= 1`, `timeout must be >= 1`, `unknown function id`, `function is not active`, `function is already active`, `function is already disabled`, `function has no deployment`, `function is disabled` |
| deploys | `deploy id must be >= 0`, `duplicate deploy id`, `steps must be >= 1`, `version must be current + 1`, `unknown deploy id`, `deploy already ready`, `deploy already failed`, `deploy already rolled back`, `deploy is not rollbackable`, `failure code must be >= 1` |
| triggers | `trigger id must be >= 0`, `duplicate trigger id`, `unknown trigger kind`, `enabled must be 0 or 1`, `unknown trigger id`, `trigger is disabled`, `trigger is already enabled`, `trigger is already disabled` |
| invocations | `invocation id must be >= 0`, `duplicate invocation id`, `unknown invocation id`, `invocation already complete`, `invocation already failed`, `invocation is not running`, `invocation timed out`, `handler failed`, `elapsed_ms must be >= 0`, `no queued invocations`, `concurrency limit reached`, `max_steps must be >= 0`, `step limit exceeded` |
| runtimes | `instance id must be >= 0`, `duplicate instance id`, `unknown instance id`, `instance already warm`, `instance is busy` |

## 10. Complexity

| Operation | Complexity |
|---|---|
| `serverless_new`, counters, `*_count`, `serverless_queued` | O(1) |
| id lookups (`*_state`, `*_version`, ...) | O(table length) |
| `function_*`, `trigger_*`, `deploy_*`, `runtime_*` transitions | O(table lengths) |
| `invoke_sync` / `invoke_finish` | O(function count + invocation count + instance count) |
| `invoke_dispatch` | O(queue length + invocation count + instance count) |
| `invoke_run_all` | O(max_steps x dispatch cost) |
| `invocation_trace_text` | O(trace length) |
| `serverless_check_invariant` | O(n^2) over each entity table |

## 11. Test plan

`tests/test_conformance.xi` (`module serverless_tests`, 23 checks, hello-style
`main` printing `[PASS]`/`[FAIL]` and returning the failure count). Every
fixture is built through `serverless_new`; all Str equality routes through
`compare.str_compare`; read accessors are wrapped in `&mut` helpers so no
`&local` read precedes a `&mut local` call in the same body (advisory E001).

1. `serverless_new` validates config and initializes empty state;
2. `function_new` validates metadata and starts DRAFT v0;
3. `function_disable/enable` drive the ACTIVE <-> DISABLED lifecycle;
4. `deploy_begin` validates ids, function, steps and version;
5. `deploy_step` progresses to READY and activates the version;
6. `deploy_fail` and rollback seal a failed rollout;
7. rollback of READY restores the previous version and keeps vN+1 deployable;
8. `trigger_new` validates wiring and stores kind/enabled/fires;
9. trigger enable/disable validate the flag lifecycle;
10. `trigger_fire` enqueues invocations and counts fires;
11. `trigger_fire` refuses disabled triggers and inactive functions;
12. `invoke_sync` evaluates handlers, validates and reuses warm instances;
13. `invoke_sync` succeeds at the timeout boundary and fails past it;
14. handler failure is reported with its code and timeout wins over it;
15. async dispatch enforces `max_concurrency` and the FIFO order;
16. dispatch/finish reject an invalid invocation lifecycle;
17. `runtime_alloc`/`runtime_init` drive COLD -> WARM and reject busy re-init;
18. cold/warm accounting follows instance reuse and fresh allocation;
19. `run_all` drains FIFO with a trace and enforces `max_steps`;
20. dispatch after disable aborts the invocation with `SV_CODE_ABORTED`;
21. trigger -> queue -> `run_all` integrates the full pipeline;
22. the invariant holds across 20 dispatch/finish cycles on one warm instance;
23. state and kind name helpers are stable.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom-serverless -TimeoutSec 60
```

Last verified: compiler v0.62.2,
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## 12. Compiler / stdlib notes for v0.62.2

- The package is split into four modules; `xiom.serverless.invoke`,
  `xiom.serverless.deploy` and `xiom.serverless.check` import
  `xiom.serverless` and share the public `ServerlessSystem` type by direct
  field access (verified working). Private helpers cannot cross modules, so
  each module keeps a small module-local copy of `_slot_in` and its validity
  predicates -- intentional and documented.
- Free functions only; `Ok`/`Err` are constructed only inside `_ok_*`/
  `_err_*` leaf helpers.
- `Vec[Int]` element reads are bound with a typed `let` (BUG-17 family); Str
  equality in tests goes through `str_compare`.
- No `Vec[StructType]`, no `Vec[Str]`, no indexed `Vec[fn]` dispatch (handler
  codes use explicit case dispatch), no generic callbacks, no `Vec[Float64]`,
  no `mut` patterns, no `log`-named function, no FFI, no threads.
- Every loop is bounded: queue/vector scans shrink or advance monotonically
  and `invoke_run_all`/`deploy_step` enforce explicit caps; the instance
  auto-allocation skip loop strictly increases its candidate.

## 13. Known limitations

- The model is single-threaded; a concurrent backend must provide the critical
  section around every transition.
- No preemption: `max_concurrency` bounds dispatches, it does not run or
  suspend anything.
- `invoke_run_all` finishes each invocation immediately with one shared
  `elapsed_ms`; interleaved concurrency needs `invoke_dispatch` +
  `invoke_finish` driven by the caller.
- The queue is a flat FIFO; there is no priority, batching or placement policy.
- An invocation queued for a function that is later disabled is failed with
  `SV_CODE_ABORTED` at dispatch (no re-queueing, no dead letter).
- No retries, DLQ, idempotency or exactly-once semantics; a failed invocation
  is observed, not retried.
- Tables only grow and ids are never reused; this is deliberate for
  reproducibility.
