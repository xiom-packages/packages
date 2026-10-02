# xiom.serverless

> **Status:** `incubating` -- implemented and harness-green, not yet published.
> **Scope:** serverless compute abstractions as a pure, deterministic model:
> function definition and invocation, trigger/event-source wiring, the deploy
> package/rollout state machine, runtime/handler lifecycle with cold-start
> accounting, and synchronous + async invoke over a deterministic FIFO
> queue/executor.
> **Deps:** `xiom.std` (stdlib modules `xiom.convert` and `xiom.test`/
> `xiom.io`/`xiom.string.compare` in tests). Pure XIOM -- no networking, no
> threads, no clock, no FFI, no I/O in the library.

## What it is

`xiom.serverless` models the semantic core of a FaaS platform as a value:
every function is a total transition over a `ServerlessSystem` and the caller
(or a future backend) owns time, concurrency and I/O. Execution time is an
`elapsed_ms` argument, so timeouts, cold starts and warm reuse are fully
deterministic and testable without a clock.

The state machine:

- **functions**: `DRAFT -> ACTIVE <-> DISABLED`; monotonic versions (a rollout
  targets `current + 1`), handler code (echo/double/fail), memory and timeout
  metadata;
- **triggers**: timer / HTTP / queue event sources bound to a function, with an
  enable flag and a fire counter; firing enqueues an invocation;
- **deploys**: `PENDING -> IN_PROGRESS -> READY`, plus `FAILED` and
  `ROLLED_BACK`; `READY` activates the target version; rolling back a `READY`
  deploy restores the previous version and lifecycle;
- **invocations**: `QUEUED -> RUNNING -> DONE | FAILED` with exact failure
  codes for handler failure, timeout and dispatch abort; a FIFO queue bounded
  by `max_concurrency`;
- **runtime instances**: `COLD -> WARM -> BUSY -> WARM`; dispatch prefers a
  warm instance, otherwise initializes a cold one (charging the cold start) or
  allocates a fresh one, and every finished invocation is counted as cold or
  warm.

## Modules

The package is split by plane (each file under 600 lines):

| Module | File | Contents |
|---|---|---|
| `xiom.serverless` | `src/serverless.xi` | Type, constants, construction, functions, triggers, accessors, names |
| `xiom.serverless.deploy` | `src/deploy.xi` | Rollout state machine + deploy accessors |
| `xiom.serverless.invoke` | `src/invoke.xi` | Sync/async invoke, queue, runtimes, cold-start accounting |
| `xiom.serverless.check` | `src/check.xi` | `serverless_check_invariant` |

## API

`xiom.serverless`:

| Function | Returns | Description |
|---|---|---|
| `serverless_new(max_concurrency, boot_ms)` | `Result[ServerlessSystem, Str]` | Empty system; cap `>= 1`, boot cost `>= 0`. |
| `function_new(s, id, handler, memory_mb, timeout_ms)` | `Result[Int, Str]` | Register a function in `DRAFT` v0. |
| `function_disable(s, id)` / `function_enable(s, id)` | `Result[Int, Str]` | `ACTIVE <-> DISABLED`; enable needs a deployment. |
| `trigger_new(s, tid, fid, kind, enabled)` | `Result[Int, Str]` | Wire an event source (kind `SV_TRIGGER_*`, enabled 0/1). |
| `trigger_enable(s, tid)` / `trigger_disable(s, tid)` | `Result[Int, Str]` | Toggle a trigger. |
| `trigger_fire(s, tid, invocation_id, payload)` | `Result[Int, Str]` | Enqueue an async invocation, bump the fire count. |
| `function_count/state/version/handler/memory_mb/timeout_ms` | `Int` | Function accessors (`SV_NOT_FOUND` = -1). |
| `trigger_count/kind/is_enabled/fires` | `Int`/`Bool` | Trigger accessors. |
| `serverless_handler_name`, `*_state_name`, `trigger_kind_name` | `Str` | Stable names, `"unknown"` fallback. |

`xiom.serverless.deploy`:

| Function | Returns | Description |
|---|---|---|
| `deploy_begin(s, did, fid, version, steps_total)` | `Result[Int, Str]` | Start a rollout (`version == current + 1`). |
| `deploy_step(s, did)` | `Result[Int, Str]` | One rollout step; reaching `steps_total` -> `READY` + activation. |
| `deploy_fail(s, did, code)` | `Result[Int, Str]` | Abort a pending/in-progress rollout (`code >= 1`). |
| `deploy_rollback(s, did)` | `Result[Int, Str]` | Roll back a `FAILED` or `READY` deploy. |
| `deploy_count/state/steps_done/steps_total/code` | `Int` | Deploy accessors. |

`xiom.serverless.invoke`:

| Function | Returns | Description |
|---|---|---|
| `invoke_sync(s, iid, fid, payload, elapsed_ms)` | `Result[Int, Str]` | Direct invocation; returns the handler output. |
| `invoke_async(s, iid, fid, payload)` | `Result[Int, Str]` | Accept into the FIFO queue. |
| `invoke_dispatch(s)` | `Result[Int, Str]` | `QUEUED -> RUNNING` under `max_concurrency`; aborts on inactive functions. |
| `invoke_finish(s, iid, elapsed_ms)` | `Result[Int, Str]` | `RUNNING -> DONE | FAILED`; releases the runtime. |
| `invoke_run_all(s, max_steps, elapsed_ms)` | `Result[Vec[Int], Str]` | Bounded driver; returns the run trace. |
| `runtime_alloc(s, iid, fid)` / `runtime_init(s, iid)` | `Result[Int, Str]` | Instance lifecycle; init charges a cold start. |
| `invocation_*` accessors, `runtime_*` accessors, counters | `Int`/`Str` | State, output, code, instance, trace text, cold/warm accounting. |

`xiom.serverless.check`:

| Function | Returns | Description |
|---|---|---|
| `serverless_check_invariant(s)` | `Bool` | Structural invariant over all tables (see SPEC.md). |

## Example

```xi
use xiom.serverless; use xiom.serverless.deploy; use xiom.serverless.invoke;

fn example() {
  match serverless_new(2, 25) {
    Ok(s) => {
      function_new(&mut s, 1, SV_HANDLER_DOUBLE, 128, 1000);
      deploy_begin(&mut s, 1, 1, 1, 1);
      deploy_step(&mut s, 1);                 // function 1 is now ACTIVE v1
      trigger_new(&mut s, 1, 1, SV_TRIGGER_HTTP, 1);
      trigger_fire(&mut s, 1, 10, 21);        // queued
      invoke_run_all(&mut s, 4, 5);           // run trace [10]; output 42
    },
    Err(_) => {},
  }
}
```

## Tests

```
.\scripts\port.ps1 -Package xiom-serverless -TimeoutSec 60
```

23 deterministic conformance checks, no external files, no clock, no
network. Expected: `port: PASS (passed=23 failed=0 program_exit=0)`.

## Install / publish

```
xiom pkg install xiom.serverless@0.1.0     # consumer
xiom pkg publish                           # maintainer
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
