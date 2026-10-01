# xiom.mechanics

> **Status:** `incubating` -- conformance-tested (24/24); not yet published on the XIOM registry.
> **Scope:** deterministic classical mechanics on fixed-point integers: linear
> state, constant-acceleration ticks (semi-implicit Euler), projectile
> range/apex, 1D collisions with restitution in basis points, spring-damper
> ticks with a symplectic stability guard, and work/energy/momentum
> accounting with conservation checks.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports nothing and uses no FFI). Tests additionally use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.mechanics` is a small, pure-XIOM module for deterministic mechanics
simulation on a single 64-bit signed integer type. Every quantity is a
**fixed-point raw integer at scale 1e-4** (`MECH_SCALE = 10000`): a raw value
`r` denotes `r / 10000` in SI units (m, s, kg, N, J, kg*m/s). There are no
floating-point values anywhere, so results are bit-for-bit reproducible across
platforms and toolchains.

The module provides:

- **linear state** (`Particle`) and constant-acceleration integration,
- **semi-implicit (symplectic) Euler ticks** with the velocity updated before
  the position (documented discrete drift),
- **projectile apex and range** for equal launch/landing heights,
- **1D two-body collisions** with restitution in basis points (0..10000),
  including the elastic and perfectly inelastic limits,
- **spring-damper ticks** with a stability guard (`dt^2 * k/m <= 4`),
- **work, kinetic, potential and spring energy accounting**, plus total
  momentum and a momentum-conservation check,
- **physical invariants** of a collision (momentum, non-increasing energy,
  non-increasing relative speed) with documented tolerances.

## Model and rounding

- Scale: `MECH_SCALE = 10000` (4 fraction digits). Raw = value * 10000.
- Products use `_mech_mul(a, b) = (a * b) / 10000`, truncated toward zero.
- Quotients use `_mech_div(a, b) = (a * 10000) / b`, truncated toward zero.
- XIOM `Int` `/` truncates toward zero, so negative magnitudes round up
  (toward zero). Every function documents its truncation points; there is no
  hidden rounding.
- Both helpers saturate at the Int64 ends instead of wrapping when an
  intermediate product would overflow.
- Semi-implicit Euler tick: `v1 = v + a*dt; x1 = x + v1*dt`. From rest after
  `n` constant-acceleration ticks, `x = a*dt^2*n*(n+1)/2`; this is the
  documented discrete result, not the analytic `a*t^2/2`.
- Restitution (bps): `u1 = ((m1 - e*m2)*v1 + (1 + e)*m2*v2) / (m1 + m2)` and
  `u2 = ((m2 - e*m1)*v2 + (1 + e)*m1*v1) / (m1 + m2)`, with
  `e = restitution_bps / 10000`.
- Spring stability: a tick is accepted only when
  `dt^2 * (k/m) <= 4` in fixed-point evaluation (damping only stabilizes and
  is not part of the guard).

See `SPEC.md` for the exact recurrences, guard rules, error catalog and test
plan.

## API

| Function | Returns | Description |
|---|---|---|
| `mech_particle_new(x, v)` | `Particle` | Raw state constructor. |
| `mech_particle_step(p, a, dt)` | `Result[Particle, Str]` | One semi-implicit tick; `dt <= 0` rejected. |
| `mech_particle_step_n(p, a, dt, ticks)` | `Result[Particle, Str]` | `ticks` ticks, `0..MECH_MAX_TICKS`; 0 is identity. |
| `mech_projectile_apex(y0, v0y, g)` | `Result[Int, Str]` | `y0 + v0y^2/(2g)`; `g <= 0` rejected. |
| `mech_projectile_range(x0, v0x, v0y, g)` | `Result[Int, Str]` | `x0 + v0x * (2*v0y/g)`; `g <= 0` rejected. |
| `mech_collide_1d(m1, v1, m2, v2, bps)` | `Result[CollisionPair, Str]` | Restitution collision; `bps` in 0..10000, masses positive. |
| `mech_collide_elastic_1d(m1, v1, m2, v2)` | `Result[CollisionPair, Str]` | `mech_collide_1d` at 10000 bps. |
| `mech_collide_inelastic_1d(m1, v1, m2, v2)` | `Result[CollisionPair, Str]` | `mech_collide_1d` at 0 bps (common velocity). |
| `mech_spring_stable(k, m, dt)` | `Bool` | `dt^2*k/m <= 4`; false for `m <= 0`, `k < 0`, `dt <= 0`. |
| `mech_spring_step(x, v, k, c, m, dt)` | `Result[Particle, Str]` | One damped-spring tick; five guards. |
| `mech_spring_energy(x, v, k, m)` | `Result[Int, Str]` | `k*x^2/2 + m*v^2/2`. |
| `mech_kinetic_energy(m, v)` | `Result[Int, Str]` | `m*v^2/2`; `m < 0` rejected. |
| `mech_potential_energy(m, g, h)` | `Int` | `m*g*h`, signed, total. |
| `mech_work(force, distance)` | `Int` | `F*d`, signed, total. |
| `mech_momentum(m, v)` | `Int` | `m*v`, signed, total. |
| `mech_momentum_total2(m1, v1, m2, v2)` | `Int` | `m1*v1 + m2*v2`, signed. |
| `mech_momentum_conserved(m1, v1, m2, v2, bps)` | `Result[Bool, Str]` | `true` when the collision momentum drift is within tolerance. |
| `mech_energy_total(ke, pe)` | `Int` | `ke + pe` accounting helper. |
| `mech_invariants_hold(m1, v1, m2, v2, bps)` | `Result[Bool, Str]` | Momentum, energy and relative-speed invariants. |

Constants: `MECH_SCALE` (10000), `MECH_BPS_ONE` (10000), `MECH_MAX_TICKS`
(1000000), `MECH_MOMENTUM_TOL` (4), `MECH_ENERGY_TOL` (4).

## Usage

```xi
use xiom.mechanics;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // 2 kg at 3 m/s meets 1 kg at rest elastically.
  match mech_collide_elastic_1d(20000, 30000, 10000, 0) {
    Ok(pair) => {
      io.println("u1 = " + convert.int_to_string(pair.u1) +
                 ", u2 = " + convert.int_to_string(pair.u2));
    },
    Err(msg) => { io.println(msg); },
  }
  return 0;
}
```

(Raw encodings are shown inline: `20000` is 2.0 kg, `30000` is 3.0 m/s.)

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.mechanics
```

Expected tail: 24 `[PASS]` lines, `xiom.mechanics: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Fixed-point 1e-4 only.** Every value is a raw Int; there are no floats,
  no `Vec[Float64]`, no unit parsing or formatting, and no dimensional
  analysis. Precision is 0.0001 units; compounding truncation is documented
  per function.
- **Discrete integration.** Ticks are explicit; the semi-implicit Euler
  position carries the documented `a*dt^2` per-tick term. Springs are
  single-degree-of-freedom only, with the symplectic stability guard.
- **1D collisions only.** Two bodies, restitution in bps, no rotation, no
  friction, no contact geometry, no multi-body chains, no continuous
  collision detection.
- **Total but guarded API.** Invalid inputs are `Err(...)` with the exact
  messages in `SPEC.md`; the `Int`-returning energy/momentum helpers are
  signed and total. Saturating arithmetic replaces wraparound in the
  fixed-point helpers.
- **No overflow contract for extreme inputs.** The helpers saturate and the
  documented envelope keeps real products far from the Int64 ends; inputs are
  expected to be finite physical values.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
