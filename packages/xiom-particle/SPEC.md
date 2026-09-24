# xiom.particle -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.particle` (`src/particle.xi`). Manifest: `package.xi` (name
`xiom.particle`, version `0.1.0`). Depends on `xiom.std` for the manifest
only; the library module imports nothing.

## Scope

A fixed-capacity particle pool with integer kinematics:

- `ParticlePool`: six parallel `Vec[Int]` arenas (`xs`, `ys`, `vx`, `vy`,
  `life_ms`, `alive`) that always share one length;
- spawning into the first dead slot, updating every live slot by a
  millisecond timestep, expiry at zero life, explicit kill, and whole-pool
  clear;
- read-only accessors for capacity, live count, liveness, position, and
  remaining life.

Pure and deterministic: no clock access, no I/O, no FFI, no allocation
after construction, no global state, no locking.

## Non-goals

- Rendering, GPU buffers, sprites, or batching.
- Collisions, broadphase/spatial indexing, or response.
- Forces: gravity, drag, wind, attractors, springs.
- Random emission, emitters, spawn rates, distributions.
- Per-particle payloads (mass, colour, size, id), sorting, or removal that
  shifts indices.
- Floating-point positions, sub-micro-unit precision, or variable
  timesteps with fraction carry.
- Thread safety or atomics.

## Units and representation

- Position `x`, `y`: integer micro-units.
- Velocity `vx`, `vy`: integer micro-units per second.
- Lifetime `life_ms`: integer milliseconds.
- Timestep `dt_ms`: integer milliseconds.

`alive[i] != 0` means slot `i` is live; the canonical live value written by
`particle_spawn` is `1`, and `particle_kill`/expiry write `0`. Slots are
never inserted or removed: capacity is fixed at construction and every
arena has exactly `capacity` entries.

## API signatures

All functions are free functions in module `xiom.particle`:

```xi
pub type ParticlePool = {
  xs: Vec[Int];
  ys: Vec[Int];
  vx: Vec[Int];
  vy: Vec[Int];
  life_ms: Vec[Int];
  alive: Vec[Int];
}
pub fn particle_pool_new(capacity: Int) -> ParticlePool
pub fn particle_capacity(p: &ParticlePool) -> Int
pub fn particle_alive_count(p: &ParticlePool) -> Int
pub fn particle_is_alive(p: &ParticlePool, i: Int) -> Bool
pub fn particle_spawn(p: &mut ParticlePool, x: Int, y: Int, vx: Int, vy: Int, life_ms: Int) -> Int
pub fn particle_update(p: &mut ParticlePool, dt_ms: Int)
pub fn particle_kill(p: &mut ParticlePool, i: Int) -> Bool
pub fn particle_clear(p: &mut ParticlePool)
pub fn particle_x(p: &ParticlePool, i: Int) -> Int
pub fn particle_y(p: &ParticlePool, i: Int) -> Int
pub fn particle_life_ms(p: &ParticlePool, i: Int) -> Int
```

Every struct field is an internal implementation detail; callers must go
through the free functions.

## Slot model

- `particle_pool_new(capacity)` clamps `capacity` to at least 1, allocates
  six zeroed `Vec[Int]` of that length, and returns the struct. All slots
  are dead (`alive[i] == 0`, `life_ms[i] == 0`).
- `particle_is_alive` is false for `i < 0`, `i >= capacity`, and dead
  slots.
- `particle_alive_count` scans `alive` and counts non-zero entries.
- `particle_spawn` scans from slot 0 for the first `alive[i] == 0`,
  overwrites all six fields of that slot (`alive[i] = 1`, `life_ms` clamped
  to at least 1), and returns `i`. When no dead slot exists it returns `-1`
  and changes nothing.
- `particle_kill(i)` returns false for out-of-range or already-dead slots;
  otherwise it sets `alive[i] = 0` and `life_ms[i] = 0` and returns true.
- Expiry inside `particle_update` sets `alive[i] = 0` and leaves the
  (non-positive) remaining life stored, so an overshot slot can report a
  negative `particle_life_ms`.
- `particle_clear` zeroes all six fields of every slot, so the pool is
  immediately reusable from slot 0.

## Update rules and truncation

For `dt_ms > 0`, every live slot is processed in slot order:

1. `x += vx * dt_ms / 1000`
2. `y += vy * dt_ms / 1000`
3. `life_ms -= dt_ms`
4. if `life_ms <= 0`, set `alive = 0`

Division truncates toward zero (XIOM integer division), so
`2999 / 1000 == 2`, `-2999 / 1000 == -2`, and `999 / 1000 == 0`. Each
position is computed as `old + trunc(v * dt / 1000)`; fractions never carry
between updates, so `dt_ms < 1000` steps a sub-1000 micro-unit/s velocity
by zero every time. Motion precedes expiry: a particle whose life reaches 0
on an update still moved on that update; dead slots are skipped by all
later updates.

`dt_ms <= 0` is a no-op (documented extension of the "dt 0 no-op" rule):
negative `dt` would otherwise move particles backwards and add life back.

Overflow is not checked: with 64-bit `Int` the products `vx * dt_ms` and
`life_ms - dt_ms` saturate/wrap only for inputs near the integer limits,
which the module treats as caller responsibility.

## Accessors

`particle_x`, `particle_y`, and `particle_life_ms` return the stored slot
value, or 0 when `i` is out of range. A dead slot reports its leftover
storage: 0 after kill or exact expiry, possibly negative after a large
`dt_ms` overshoot.

## Complexity

| Operation | Complexity |
|---|---|
| `particle_pool_new` | O(capacity) |
| `particle_capacity` | O(1) |
| `particle_alive_count` | O(capacity) |
| `particle_is_alive` / `particle_x` / `particle_y` / `particle_life_ms` | O(1) |
| `particle_spawn` | O(capacity) first-fit scan |
| `particle_update` | O(capacity) |
| `particle_kill` | O(1) |
| `particle_clear` | O(capacity) |

## Error paths

None. There is no panicking input: out-of-range reads return 0,
out-of-range kills return false, a full pool returns -1, and `capacity` is
clamped so a pool always has at least one slot.

## Test plan

`tests/test_conformance.xi` (`module particle_tests`, 21 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count):

1. capacity clamps to at least 1 (0 and -7 become 1, 5 stays 5);
2. fresh pool has no live particles, all accessors read 0, liveness is
   false in and out of range;
3. spawn fills the first free slot and stores position/life per slot;
4. spawn clamps `life_ms` to at least 1 (for 0 and -9);
5. a full pool returns -1 and stores nothing;
6. kill clears a live slot (`alive` 0, `life_ms` 0) and is false on a dead
   one;
7. kill out of range (-1, capacity, far beyond) returns false;
8. spawn reuses the first killed slot, then reports full again;
9. an expired slot is reused by the next spawn;
10. update adds `v*dt/1000` for `dt == 1000` and `dt == 500`;
11. `v*dt/1000` truncates toward zero for positive and negative velocities
    (999, 1500, -1500, 2500, -2500 over `dt == 1`);
12. each step truncates independently (2599 and -999 over 3 ms, then 1 ms);
13. `life_ms` drops by `dt` on each update (100 -> 70 -> 30 -> 1);
14. life reaches 0 and expires exactly on that update;
15. a dead slot is not advanced by later updates;
16. `dt == 0` and negative `dt` are no-ops;
17. a huge `dt` moves then kills every live slot (position and leftover
    life pinned);
18. clear zeroes every slot and frees the whole pool;
19. accessors pin stored values and read 0 out of range;
20. a 100-particle pool keeps `particle_alive_count` equal to an
    independent per-slot scan over 60 updates, never increases, ends at 0,
    and the first slot is reusable afterwards;
21. dead slots are refilled left to right after a mix of expiry and kill.

All checks pin exact integer values; none are weakened to ranges.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.particle
```

Last verified: compiler 0.61.3, `port: PASS (passed=21 failed=0
program_exit=0 exit=0)`.

## Known limitations

- Fixed capacity: no growth, no dynamic allocation, `-1` when full.
- Integer micro-units only: truncated `v*dt/1000` per update, no fraction
  carry, timestep-dependent motion.
- No forces, collisions, rendering, emission, payloads, or ordering.
- Not thread-safe.
- Out-of-range accessors return 0 rather than an error type.

## Compiler / stdlib notes for v0.61.3

- Free functions only (no methods) and explicit `&`/`&mut` parameters;
  every struct field is public but documented as internal.
- The tests route read-only calls through tiny helpers taking `&mut` so a
  `&local` call is never followed by a `&mut local` call in the same
  function body (advisory E001), matching the sibling packages.
- No `Vec[StructType]`: the pool keeps parallel `Vec[Int]` arenas, which
  the language supports.
- Vec element reads go through typed `let` (`let a: Int = p.alive[i];`) to
  keep inference unambiguous, and `use` statements end with `;` while
  `module` does not.
- `use xiom.particle;` plus `xiom.test.assert` / `xiom.io.println` in the
  suite, matching the sibling packages' test style.
