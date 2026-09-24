# xiom.particle

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** a fixed-capacity particle pool with integer positions,
> velocities, and lifetimes -- pure simulation state, with no rendering,
> collisions, or forces.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.particle` is a small, pure-XIOM particle system core. A
`ParticlePool` is a fixed-capacity struct of six parallel `Vec[Int]` arenas
(positions, velocities, lifetimes, liveness), and every operation is a free
function that the caller invokes with `&` or `&mut`. Spawning reuses the
first dead slot, updating integrates positions and ages particles, and
particles expire deterministically when their remaining life reaches zero.
There is no clock access, no I/O, no FFI, no allocation after construction,
and no global state.

Units are micro-units: positions and velocities are integer **micro-units**
and **micro-units per second**, lifetimes are **milliseconds**. Coordinates
only ever change through explicit `particle_update` calls, so the module is
fully deterministic and testable.

## API

| Function | Returns | Units | Description |
|---|---|---|---|
| `particle_pool_new(capacity)` | `ParticlePool` | slots | Fresh pool with `capacity` slots, clamped to at least 1; every slot dead and zeroed. |
| `particle_capacity(p)` | `Int` | slots | Slot count (clamped capacity). |
| `particle_alive_count(p)` | `Int` | particles | Number of live slots. |
| `particle_is_alive(p, i)` | `Bool` | -- | True when slot `i` is in range and live; false otherwise. |
| `particle_spawn(&mut p, x, y, vx, vy, life_ms)` | `Int` | micro-units, us/s, ms | Writes the first dead slot; returns its index or `-1` when full. `life_ms` is clamped to at least 1. |
| `particle_update(&mut p, dt_ms)` | `Unit` | ms | Advances every live slot: `x += vx*dt/1000`, `y += vy*dt/1000` (truncated toward zero), `life_ms -= dt`; clears slots whose life reaches `<= 0`. `dt <= 0` is a no-op. |
| `particle_kill(&mut p, i)` | `Bool` | -- | True when a live slot was cleared; false for dead or out-of-range slots. |
| `particle_clear(&mut p)` | `Unit` | -- | Zeroes every slot, freeing the whole pool. |
| `particle_x(p, i)` | `Int` | micro-units | Position x of slot `i`; 0 out of range. |
| `particle_y(p, i)` | `Int` | micro-units | Position y of slot `i`; 0 out of range. |
| `particle_life_ms(p, i)` | `Int` | ms | Remaining life of slot `i`; 0 out of range. |

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Update rules

For each live slot, with `dt = dt_ms > 0`:

- `x += vx * dt / 1000` and `y += vy * dt / 1000`, each quotient truncated
  toward zero (`2999/1000 == 2`, `-2997/1000 == -2`);
- `life_ms -= dt`, then the slot is cleared (`alive = 0`) when the remaining
  life is `<= 0`.

Motion is applied before expiry, so a particle that dies on an update still
moved on it; dead slots are never advanced again. Each update truncates
independently, so fractions do not carry between calls (with `dt_ms < 1000`
a velocity below 1000 micro-units/s contributes zero on every step). A
`dt_ms <= 0` call is a documented no-op: a negative `dt` would otherwise
move particles backwards and resurrect them.

## Usage

```xi
use xiom.particle;
use xiom.io;

var pool = particle_pool_new(64);
let i = particle_spawn(&mut pool, 0, 0, 1200, -800, 2000);
particle_update(&mut pool, 500);
io.println(particle_x(&pool, i));       // 600
io.println(particle_y(&pool, i));       // -400
io.println(particle_life_ms(&pool, i)); // 1500
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.particle
```

Expected: the namespaced module passes the section-4 namespace rule, 21
`[PASS]` lines, and a final `port: PASS (passed=21 failed=0 program_exit=0
exit=0)`.

## Limitations

- **Fixed capacity:** the pool never grows. `particle_spawn` returns `-1`
  when every slot is live; a full pool cannot accept another particle until
  one is killed or expires. `capacity` is clamped to `>= 1`, so an empty
  pool does not exist.
- **Integer physics:** positions and velocities are integer micro-units and
  lifetimes are milliseconds. `v*dt/1000` truncates toward zero per update,
  with no fractional carry, so motion is timestep-dependent (sub-1000
  micro-unit/s motion can stall at `dt < 1000` ms).
- **No forces, collisions, or rendering:** there is no gravity, drag, or
  integration beyond the linear step; particles pass through each other and
  nothing is drawn. No random emission, no per-particle payloads (mass,
  colour, size), no spatial index.
- **No reordering or removal:** slots keep their index until killed,
  expired, or overwritten; `particle_kill`/expiry only clear the flag, and
  the next spawn refills the lowest free slot.
- **Not thread-safe:** the pool is a plain value with no internal locking.
- Out-of-range reads return 0 and out-of-range kills return false; there is
  no error channel.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
