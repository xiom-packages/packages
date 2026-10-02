# xiom.pool

> **Status:** `stable` -- conformance-tested (22/22); published at `v0.1.1` on the XIOM registry.
> **Scope:** a deterministic fixed-capacity slot pool with generation-checked
> lease tokens; single-threaded by construction.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_string`;
> tests additionally use `xiom.string.compare`, `xiom.test` and `xiom.io`).

## What it is

`xiom.pool` manages a fixed number of integer slots: callers keep their own
resources in a container indexed by slot id, borrow a free slot, and release
it when done. It is a pure state machine -- no allocation, no blocking, no
destructors, no threads -- with deterministic, documented ordering:

- a fresh pool hands out slots in ascending order (`0, 1, 2, ...`);
- a released slot is reused by the next borrow (LIFO free stack);
- `pool_release` is the raw path for callers that track ids themselves;
- `pool_borrow_lease` / `pool_release_lease` issue and check an opaque lease
  token that encodes the slot id and a per-slot generation, so a duplicate or
  stale release is rejected instead of silently corrupting the free stack.

Counters (`in_use`, `available`, `high_water`, lifetime borrows and releases)
make the pool observable for tests and diagnostics.

## API

| Function | Returns | Description |
|---|---|---|
| `pool_new(capacity)` | `Pool` | Fresh pool; a negative capacity is clamped to 0. |
| `pool_capacity(p)` | `Int` | Number of slots. |
| `pool_in_use(p)` | `Int` | Currently borrowed slots. |
| `pool_available(p)` | `Int` | Free slots (`capacity - in_use`). |
| `pool_high_water(p)` | `Int` | Peak simultaneous borrows. |
| `pool_total_borrows(p)` | `Int` | Lifetime successful borrows. |
| `pool_total_releases(p)` | `Int` | Lifetime successful releases, drains included. |
| `pool_is_borrowed(p, id)` | `Bool` | Slot state; `false` out of range. |
| `pool_generation(p, id)` | `Int` | Borrow generation of a slot; `-1` out of range. |
| `pool_borrow(p)` | `Result[Int, Str]` | `Ok(id)`; `Err("pool: exhausted")` when full. |
| `pool_borrow_lease(p)` | `Result[Int, Str]` | `Ok(lease)`; lease `>= 1`. |
| `pool_release(p, id)` | `Result[Int, Str]` | `Ok(id)`; rejects bad ids and repeated releases. |
| `pool_release_lease(p, lease)` | `Result[Int, Str]` | `Ok(id)`; rejects bad and stale tokens. |
| `pool_drain(p)` | `Int` | Releases every borrowed slot; returns the count. |

## Usage

```xi
use xiom.pool;
use xiom.io;

fn main() -> Int {
  var p = pool_new(2);
  let a = pool_borrow(&mut p);          // Ok(0)
  match a {
    Ok(slot) => {
      io.println(pool_in_use(&p));      // 1
      let r = pool_release(&mut p, slot);
      match r {
        Ok(_) => {},
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  io.println(pool_high_water(&p));      // 1
  return 0;
}
```

Lease path:

```xi
var p = pool_new(1);
let l = pool_borrow_lease(&mut p);      // Ok(2): generation 1, slot 0
match l {
  Ok(lease) => {
    io.println(pool_release_lease(&mut p, lease));  // Ok(0)
    io.println(pool_release_lease(&mut p, lease));  // Err("pool: stale lease 2")
  },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.pool
```

Expected tail: 22 `[PASS]` lines, `xiom.pool: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. The test module
emits benign E001 borrow warnings (the same advisory class as `xiom.tls`'s
suite); they do not affect the exit code.

## Limitations

- Slot ids only: the pool does not store resources (no generic containers in
  XIOM v0.61.3), so callers index their own storage by slot id.
- Single-threaded by construction: no locks, no atomics, no blocking waits
  and no cross-thread publication.
- No automatic release: XIOM has no destructors, so every lease must be
  released explicitly; `pool_drain` is the bulk escape hatch.
- Lease tokens are opaque `Int`s valid only for the pool instance that
  issued them; they are not cryptographic and not transferable across pools.
- Generations grow without bound (an `Int` wrap would eventually alias); no
  pool can issue enough borrows for that to occur in practice.
- In-memory only: no FFI, no file I/O.

See `SPEC.md` for the exact semantics, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
