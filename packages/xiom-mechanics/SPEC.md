# xiom.mechanics -- Specification

Status: `incubating`, version `0.1.0`. Conformance suite:
`tests/test_conformance.xi` (24 checks). This document is the normative
description of the implemented behaviour; the tests pin it.

## 1. Representation

Every quantity is a 64-bit signed `Int` at fixed scale

```
MECH_SCALE = 10000        (raw r denotes r / 10000 in SI units)
```

| Quantity | Unit | Raw encoding |
|---|---|---|
| position `x` | m | value * 10000 |
| velocity `v` | m/s | value * 10000 |
| time / tick `dt` | s | value * 10000 |
| acceleration `a`, `g` | m/s^2 | value * 10000 |
| mass `m` | kg | value * 10000 |
| spring constant `k` | N/m | value * 10000 |
| damping `c` | N*s/m | value * 10000 |
| force | N | value * 10000 |
| energy | J | value * 10000 |
| momentum | kg*m/s | value * 10000 |
| restitution | bps | 0..10000 (10000 = 1.0) |

There are no floating-point values, no `Vec[Float64]`, no FFI and no I/O in
the library module.

## 2. Arithmetic and rounding

Two private helpers implement all products and quotients; each performs
exactly one truncating division.

```
_mech_mul(a, b) = (a * b) / 10000          truncated toward zero
_mech_div(a, b) = (a * 10000) / b          truncated toward zero
```

- XIOM `Int` `/` truncates toward zero: positive magnitudes round down,
  negative magnitudes round up (toward zero).
- `_mech_div` with `b == 0` returns 0 defensively; all physical callers guard
  the zero divisor first.
- Saturation: when `|a*b|` (or `|a*10000|`) would exceed the Int64 range, the
  helper returns `Int64_max` or `Int64_min` according to the sign of the
  true result instead of wrapping.
- `_mech_abs(Int64_min) = Int64_max` (total absolute value).
- Every public function documents its truncation points; results are exact
  when all intermediate products and the final quotient divide evenly.

## 3. Particle state and integration

```
Particle = { x: Int; v: Int }        // raw position, raw velocity
```

### 3.1 One tick -- `mech_particle_step(p, a, dt)`

Semi-implicit (symplectic) Euler, constant `a`, explicit tick `dt`:

```
v1 = p.v + _mech_mul(a, dt)
x1 = p.x + _mech_mul(v1, dt)         // NEW velocity
```

Guards: `dt <= 0` -> `Err("mechanics: dt must be positive")`.

From rest after one tick the position advances by `a*dt^2` (not `a*dt^2/2`):
the discrete scheme is the documented contract. Worked fixture (`a` = 2 m/s^2,
`dt` = 0.5 s, start (0, 1 m/s)): one tick -> (1 m, 2 m/s); two ticks ->
(2.5 m, 3 m/s).

### 3.2 N ticks -- `mech_particle_step_n(p, a, dt, ticks)`

Applies the 3.1 recurrence exactly `ticks` times; the loop counter advances by
one per tick, so the function terminates in `O(ticks)`.

- `ticks == 0` returns `p` unchanged.
- `dt <= 0` -> `Err("mechanics: dt must be positive")`.
- `ticks < 0` or `ticks > MECH_MAX_TICKS` (1000000) ->
  `Err("mechanics: tick count out of range")`.

From rest under constant `a` after `n` ticks: `x = a*dt^2*n*(n+1)/2`,
`v = a*dt*n`.

## 4. Projectile range and apex (equal heights)

### 4.1 `mech_projectile_apex(y0, v0y, g)`

```
rise  = _mech_div(_mech_mul(v0y, v0y), _mech_mul(g, 2 * MECH_SCALE))
apex  = y0 + rise                     // one truncation at the division
```

Guard: `g <= 0` -> `Err("mechanics: gravity must be positive")`.

### 4.2 `mech_projectile_range(x0, v0x, v0y, g)`

```
t_flight = _mech_div(_mech_mul(v0y, 2 * MECH_SCALE), g)   // 2*v0y/g, truncated
range    = x0 + _mech_mul(v0x, t_flight)                  // one more truncation
```

Guard: `g <= 0` -> `Err("mechanics: gravity must be positive")`.
The launch height is not a parameter: the range is measured between equal
launch and landing heights, where `y0` cancels.

Worked fixture: `v0x` = 30 m/s, `v0y` = 20 m/s, `g` = 10 m/s^2 ->
`t_flight` = 4 s, range = 120 m; apex rise = 20 m.

## 5. 1D collisions with restitution in basis points

### 5.1 `mech_collide_1d(m1, v1, m2, v2, restitution_bps)`

With `e = restitution_bps / 10000`:

```
u1 = ((m1 - e*m2)*v1 + (1 + e)*m2*v2) / (m1 + m2)
u2 = ((m2 - e*m1)*v2 + (1 + e)*m1*v1) / (m1 + m2)
```

Implementation: each product is one `_mech_mul`, the two numerator terms are
summed, and each velocity takes one `_mech_div` by `(m1 + m2)`.

- `restitution_bps == 10000` (e = 1): perfectly elastic; with equal masses
  the velocities swap exactly, and kinetic energy is conserved in exact
  arithmetic.
- `restitution_bps == 0` (e = 0): perfectly inelastic; both bodies leave with
  the centre-of-mass velocity `(m1*v1 + m2*v2) / (m1 + m2)`.
- `0 < e < 1` is dissipative; `|u2 - u1| = e*|v2 - v1|` in exact arithmetic.

Guards (checked in this order):

| Condition | Err message |
|---|---|
| `m1 <= 0` or `m2 <= 0` | `mechanics: mass must be positive` |
| `m1 > Int64_max - m2` | `mechanics: mass sum overflows` |
| `restitution_bps < 0` or `> 10000` | `mechanics: restitution must be in 0..10000 bps` |

### 5.2 Wrappers

- `mech_collide_elastic_1d(m1, v1, m2, v2)` = `mech_collide_1d(..., 10000)`.
- `mech_collide_inelastic_1d(m1, v1, m2, v2)` = `mech_collide_1d(..., 0)`.

Both use the same guards and messages.

## 6. Spring-damper with stability guard

Equation of motion: `x'' = (-k*x - c*v) / m`.

### 6.1 Guard -- `mech_spring_stable(k, m, dt)`

Returns `true` iff `m > 0`, `k >= 0`, `dt > 0` and the fixed-point value

```
_mech_mul(_mech_mul(dt, dt), _mech_div(k, m)) <= 4 * MECH_SCALE
```

i.e. the symplectic stability window `dt^2 * (k/m) <= 4` (`dt <= 2/omega`,
`omega = sqrt(k/m)`). The boundary is inclusive. Damping is not part of the
guard because positive damping only increases stability. `k == 0` accepts any
positive `dt`.

### 6.2 One tick -- `mech_spring_step(x, v, k, c, m, dt)`

```
force = 0 - _mech_mul(k, x) - _mech_mul(c, v)
a     = _mech_div(force, m)
v1    = v + _mech_mul(a, dt)
x1    = x + _mech_mul(v1, dt)
```

Guards (checked in this order, first failure wins):

| Condition | Err message |
|---|---|
| `m <= 0` | `mechanics: mass must be positive` |
| `k < 0` | `mechanics: stiffness must be non-negative` |
| `c < 0` | `mechanics: damping must be non-negative` |
| `dt <= 0` | `mechanics: dt must be positive` |
| `!mech_spring_stable(k, m, dt)` | `mechanics: unstable step: dt^2*k/m exceeds 4` |

Worked fixtures (`k` = 4 N/m, `m` = 1 kg, `dt` = 0.5 s):

- undamped, start (1 m, 0) -> (0, -2 m/s);
- damped `c` = 1, start (1 m, 2 m/s) -> (0.5 m, -1 m/s).

### 6.3 Energy -- `mech_spring_energy(x, v, k, m)`

```
E = k*x^2/2 + m*v^2/2
```

Two `_mech_mul` chains and one `/2` truncation per half-term, then summed.
Guards: `k < 0` -> `Err("mechanics: stiffness must be non-negative")`;
`m < 0` -> `Err("mechanics: mass must be non-negative")`.
For the undamped fixture above the energy is exactly invariant across the
tick (2 J before, 2 J after); the damped tick leaves 1 J < 2 J.

## 7. Work and energy accounting

| Function | Formula | Guards |
|---|---|---|
| `mech_kinetic_energy(m, v)` | `m*v^2/2` (one `/2` truncation) | `m < 0` -> mass non-negative Err |
| `mech_potential_energy(m, g, h)` | `m*g*h`, signed | none (total) |
| `mech_work(force, distance)` | `F*d`, signed | none (total) |
| `mech_energy_total(ke, pe)` | `ke + pe`, signed | none (total) |

`mech_kinetic_energy` returns `Ok(0)` for `m == 0`; a negative velocity is
squared, so the sign is lost by design.

## 8. Momentum accounting and conservation

| Function | Formula | Guards |
|---|---|---|
| `mech_momentum(m, v)` | `m*v`, signed | none (total) |
| `mech_momentum_total2(m1, v1, m2, v2)` | `m1*v1 + m2*v2`, signed | none (total) |
| `mech_momentum_conserved(m1, v1, m2, v2, bps)` | see below | collision guards |

`mech_momentum_conserved` runs the 5.1 collision and returns
`Ok(abs(p_after - p_before) <= MECH_MOMENTUM_TOL)`, where
`p_before = m1*v1 + m2*v2` and `p_after = m1*u1 + m2*u2`
(`MECH_MOMENTUM_TOL = 4` raw units, one per rounded product).

## 9. Invariants

`mech_invariants_hold(m1, v1, m2, v2, restitution_bps)` evaluates the 5.1
outcome and returns `Ok(true)` iff all three hold
(`MECH_MOMENTUM_TOL = MECH_ENERGY_TOL = 4` raw units):

1. **Momentum:** `|p_after - p_before| <= MECH_MOMENTUM_TOL`.
2. **Energy (dissipative):** `ke_after <= ke_before + MECH_ENERGY_TOL`;
   `ke` is the section 7 kinetic energy of each body summed.
3. **Relative speed:** `|u2 - u1| <= |v2 - v1| + MECH_MOMENTUM_TOL`
   (restitution `<= 1` cannot increase the closing speed).

`Ok(false)` means an invariant was violated; the collision guards produce the
5.1 `Err(...)` messages.

## 10. Constants

| Constant | Value | Meaning |
|---|---|---|
| `MECH_SCALE` | 10000 | raw units per unit (fixed point 1e-4) |
| `MECH_BPS_ONE` | 10000 | restitution 1.0 in basis points |
| `MECH_MAX_TICKS` | 1000000 | `mech_particle_step_n` termination bound |
| `MECH_MOMENTUM_TOL` | 4 | momentum audit tolerance, raw |
| `MECH_ENERGY_TOL` | 4 | energy audit tolerance, raw |

## 11. Types

```
Particle      = { x: Int; v: Int }
CollisionPair = { u1: Int; u2: Int }
```

Fields are raw values at scale 1e-4 (m/s for velocities).

## 12. Conformance test plan

`tests/test_conformance.xi` (24 checks, all fixture-driven, no random input,
every function called directly; no fn tables):

| # | Check |
|---|---|
| 1 | constants; `mech_particle_new` field storage |
| 2 | one semi-implicit tick (position uses the new velocity) |
| 3 | two ticks, hand-computed discrete drift |
| 4 | `mech_particle_step` dt guard |
| 5 | `step_n` equivalence, 0-tick identity, range guards |
| 6 | three-tick free fall at g = 10 |
| 7 | apex values, launch-height offset, gravity guards |
| 8 | range value, x0 offset, gravity guard |
| 9 | elastic equal-mass swap |
| 10 | elastic unequal masses |
| 11 | inelastic common velocity |
| 12 | restitution 5000 / 2500 bps |
| 13 | collision mass/restitution guards |
| 14 | momentum signed values, conservation, guard |
| 15 | kinetic energy, negative mass guard |
| 16 | potential energy, work, `energy_total` |
| 17 | spring stability boundary and degenerate inputs |
| 18 | spring undamped/damped ticks and all five guards |
| 19 | spring energy values and guards |
| 20 | spring energy invariance / dissipation across a tick |
| 21 | invariants true for elastic/inelastic, bad bps Err |
| 22 | full elastic audit: momentum 6, energy 6 J exact |
| 23 | four-tick free fall n(n+1)/2 law |
| 24 | elastic/inelastic wrappers equal generic collision |

## 13. Limitations

- Fixed-point 1e-4 precision; truncation (toward zero) compounds exactly as
  documented per function.
- Semi-implicit Euler only; no higher-order integrators, no adaptive steps,
  no collision-time-of-impact search (collisions are instantaneous events
  given pre/post velocities).
- One-dimensional translational mechanics only: no vectors, rotation,
  friction, restitution outside 0..10000 bps or multi-body contact.
- Springs are single degree of freedom with the symplectic guard; the guard
  is a necessary stability window, not a global error bound.
- The helpers saturate at the Int64 ends; the documented envelope assumes
  finite physical inputs well inside 64-bit range.
