# xiom.physics -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.physics` (`src/physics.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only; the module imports `xiom.math` for the
constant `PI`; the tests use `xiom.test`, `xiom.io` and `xiom.math`.

## 1. Scope

Introductory Newtonian mechanics for a single scalar quantity at a time, all
in SI units and all in `Float64`:

- kinematics: average velocity, average acceleration, SUVAT position and
  velocity at a time,
- energy and momentum: kinetic energy, gravitational potential energy,
  linear momentum,
- work and power,
- gravitation: the Newtonian two-mass force with G = 6.674e-11,
- geometry: circle area and sphere volume.

Every function is a free function taking and returning `Float64`; the module
is deterministic, allocation-free and total (invalid inputs are mapped to
0.0, never to an error or a panic).

## 2. Non-goals

- Vectors, tuples or matrices: no vector algebra, no coordinate frames, no
  body orientation. `xiom.physics` deals in scalars only.
- Relativity: no Lorentz factor, relativistic energy/momentum, time
  dilation, length contraction or curved spacetime.
- Dynamics: no numerical integration, springs, drag, friction, collisions,
  rigid bodies, orbits or N-body simulation. Only the closed forms in
  section 5 are provided.
- Units machinery: no dimensional analysis, no unit parsing or formatting,
  no conversion between related units (km/h, feet, grams, ...).
- Any FFI, file I/O, randomness or registry integration.

## 3. Guard rules

Invalid inputs are total: they return 0.0 and are never errors or panics.
The rules are module-wide (they apply uniformly to all functions that take
the corresponding argument) and are pinned by the conformance suite.

| Rule | Argument | Condition | Effect | Applies to |
|---|---|---|---|---|
| G1 | time | `<= 0` | `0.0` | `phys_velocity`, `phys_acceleration`, `phys_position`, `phys_velocity_at`, `phys_power` |
| G2 | radius | `< 0` | `0.0` | `phys_circle_area`, `phys_sphere_volume` |
| G3 | separation | `<= 0` | `0.0` | `phys_gravitational_force` |
| G4 | kinetic mass | `< 0` | `0.0` | `phys_kinetic_energy` |

Consequences worth stating explicitly:

- **G1 is uniform.** A non-positive elapsed time is rejected by every
  function that takes one, including the two polynomial helpers:
  `phys_position(s0, v0, a, 0.0)` returns `0.0` rather than `s0`, and
  `phys_velocity_at(v0, a, 0.0)` returns `0.0` rather than `v0`. The
  polynomial pairs remain exact for all `t > 0`.
- **G4 is specific to kinetic energy.** `phys_potential_energy` and
  `phys_momentum` are signed quantities and compute the formula for any
  mass; `phys_gravitational_force` keeps the sign of its masses.
- **A real zero is not distinguishable from a rejected input** in the
  return value; callers who need the distinction must validate first.

Signed results are preserved everywhere else: displacement, velocity,
momentum, work and potential energy may be negative.

## 4. Units and conventions

| Quantity | Symbol | SI unit | Function |
|---|---|---|---|
| distance, position, radius, height | `_m` | metre (m) | `phys_*` | 
| time | `_s` | second (s) | `phys_*` |
| mass | `_kg` | kilogram (kg) | `phys_*` |
| velocity, speed | -- | metre per second (m/s) | `phys_velocity`, `phys_velocity_at` |
| acceleration, field strength | -- | metre per second squared (m/s^2) | `phys_acceleration`, SUVAT |
| force | `_n` | newton (N = kg*m/s^2) | `phys_work`, `phys_gravitational_force` |
| energy, work | `_j` | joule (J = N*m) | kinetic, potential, `phys_work` |
| power | -- | watt (W = J/s) | `phys_power` |
| momentum | -- | kg*m/s | `phys_momentum` |

The unit of every input is encoded in the parameter name and the unit of
every result is stated in the function documentation. Angles, degrees and
non-SI units are not accepted anywhere.

## 5. Formulas

All arithmetic is IEEE-754 `Float64`; the listed example values are decimal
pins used by the tests with an absolute tolerance of 1e-9.

### 5.1 Kinematics

| Function | Formula | Pinned examples |
|---|---|---|
| `phys_velocity(d, t)` | `d / t` | `(100, 10) -> 10`; `(50, 4) -> 12.5`; `(-20, 4) -> -5` |
| `phys_acceleration(dv, dt)` | `dv / dt` | `(20, 4) -> 5`; `(-9.8, 2) -> -4.9` |
| `phys_position(s0, v0, a, t)` | `s0 + v0*t + a*t*t/2` | `(1, 2, 3, 4) -> 33`; `(0, 0, 9.80665, 2) -> 19.6133` |
| `phys_velocity_at(v0, a, t)` | `v0 + a*t` | `(2, 3, 4) -> 14`; `(0, 9.80665, 3) -> 29.41995` |

Free fall from rest with `g = 9.80665 m/s^2`:
`phys_position(0, 0, g, 3) = 44.129925 m` (= g*t^2/2) and
`phys_velocity_at(0, g, 3) = 29.41995 m/s` (= g*t).

### 5.2 Energy, momentum, work, power

| Function | Formula | Pinned examples |
|---|---|---|
| `phys_kinetic_energy(m, v)` | `0.5*m*v^2` | `(2, 3) -> 9`; `(4, 2.5) -> 12.5`; `(1, -2) -> 2` |
| `phys_potential_energy(m, h, g)` | `m*g*h` | `(2, 1.5, 9.80665) -> 29.41995`; `(1, -2, 9.8) -> -19.6` |
| `phys_momentum(m, v)` | `m*v` | `(2, 3) -> 6`; `(1, -4) -> -4` |
| `phys_work(f, d)` | `f*d` | `(10, 4) -> 40`; `(2, -3) -> -6` |
| `phys_power(w, t)` | `w / t` | `(100, 4) -> 25`; `(-50, 2) -> -25` |

### 5.3 Gravitation and geometry

| Function | Formula | Pinned examples |
|---|---|---|
| `phys_gravitational_force(m1, m2, r)` | `G*m1*m2/r^2` | `(5.972e24, 1, 6.371e6) -> 9.819532032816 N`; `(1, 1, 1) -> 6.674e-11 N`; `(1e11, 1e11, 1e6) -> 0.6674 N` |
| `phys_circle_area(r)` | `pi*r^2` | `(2) -> 12.566370614 m^2`; `(1) -> 3.1415926535898 m^2` |
| `phys_sphere_volume(r)` | `4*pi*r^3/3` | `(1) -> 4.188790205 m^3`; `(2) -> 33.51032163829 m^3` |

## 6. Constants

| Name | Value | Unit | Notes |
|---|---|---|---|
| `PHYS_G` | `6.674e-11` | m^3 kg^-1 s^-2 | Newtonian constant of gravitation, exported and used by `phys_gravitational_force`. |
| `pi` | `xiom.math.PI` = `3.141592653589793` | dimensionless | Imported from the stdlib; no local pi literal. |

No other physical constants (g, Earth mass, vacuum permittivity, ...) are
baked into the module: `g` is a caller-supplied argument, and the Earth-like
test values are inputs, not constants.

## 7. API signatures

```xi
pub const PHYS_G: Float64
pub fn phys_velocity(distance_m: Float64, time_s: Float64) -> Float64
pub fn phys_acceleration(delta_v: Float64, delta_t: Float64) -> Float64
pub fn phys_position(s0: Float64, v0: Float64, a: Float64, t: Float64) -> Float64
pub fn phys_velocity_at(v0: Float64, a: Float64, t: Float64) -> Float64
pub fn phys_kinetic_energy(mass_kg: Float64, velocity: Float64) -> Float64
pub fn phys_potential_energy(mass_kg: Float64, height_m: Float64, g: Float64) -> Float64
pub fn phys_momentum(mass_kg: Float64, velocity: Float64) -> Float64
pub fn phys_work(force_n: Float64, distance_m: Float64) -> Float64
pub fn phys_power(work_j: Float64, time_s: Float64) -> Float64
pub fn phys_gravitational_force(m1_kg: Float64, m2_kg: Float64, r_m: Float64) -> Float64
pub fn phys_circle_area(r_m: Float64) -> Float64
pub fn phys_sphere_volume(r_m: Float64) -> Float64
```

All functions are O(1), total, and free functions (no methods, no FFI, no
lambdas, no generics).

## 8. Test plan

`tests/test_conformance.xi` (module `physics_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Float comparisons use
`phys_close(a, b) = abs_float(a - b) < 1e-9` (`xiom.math.abs_float`; the
raw libm `fabs` is module-private in the stdlib). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | velocity known | 100 m / 10 s = 10 m/s; 12.5; zero; signed displacement |
| t2 | velocity guard G1 | `time_s <= 0 -> 0.0` |
| t3 | acceleration known | 5 m/s^2; deceleration -4.9; zero numerator |
| t4 | acceleration guard G1 | `delta_t <= 0 -> 0.0` |
| t5 | SUVAT position | `s0 + v0*t + a*t*t/2` at four inputs (33, 14, 19.6133, 5) |
| t6 | position guard G1 | `t <= 0 -> 0.0` even though the polynomial gives `s0` |
| t7 | SUVAT velocity | `v0 + a*t` including deceleration (14, 5, 29.41995, 4) |
| t8 | velocity_at guard G1 | `t <= 0 -> 0.0` even though the polynomial gives `v0` |
| t9 | free fall from rest | `s = g*t^2/2 = 44.129925 m`, `v = g*t = 29.41995 m/s`, g = 9.80665 |
| t10 | kinetic energy known | 2 kg at 3 m/s = 9 J; 12.5; zero; v squared loses the sign |
| t11 | kinetic energy guard G4 | negative mass -> 0.0 (three cases) |
| t12 | potential energy | `m*g*h` pinned; zero mass/height; signed negative height |
| t13 | momentum | 6 kg*m/s; -4; zero; 5 |
| t14 | work | 40 J; zero displacement; negative work (opposing force) |
| t15 | power | 100 J / 4 s = 25 W; zero work; -25 |
| t16 | power guard G1 | `time_s <= 0 -> 0.0` |
| t17 | gravity Earth-like | 9.819532032816 N for 1 kg at 6.371e6 m; G pinned via (1, 1, 1); 0.6674 |
| t18 | gravity guard G3 | `r <= 0 -> 0.0`; zero mass gives zero force |
| t19 | circle area | r = 2 -> 12.566370614; 3.1415926535898; 0.7853981633974; 0 |
| t20 | sphere volume | r = 1 -> 4.188790205; 33.51032163829; 0.5235987756; 0 |
| t21 | geometry guard G2 | negative radius -> 0.0 (circle and sphere) |
| t22 | zero inputs | every function maps all-zero inputs to 0.0 |

Every expected value in the table above is a decimal pin of section 5; no
assertion is computed with the same expression it checks. The test file
reads no `Vec`, builds no `Str` from elements, dispatches no `Vec[fn]`, and
calls each test explicitly from `main`.

## 9. Known limitations

- Scalar-only API: no vectors, tensors or coordinate frames (`xiom.geom` and
  `xiom.linear` cover those separately).
- Newtonian only: no relativity, no quantum or statistical mechanics.
- Guard results are indistinguishable from real zeros in the return value.
- `Float64` rounding applies; the module does not round or quantise outputs.
- No overflow, NaN or infinity contract beyond IEEE-754 double semantics.
- Gravity is a single instantaneous two-mass force: no fields, no N-body,
  no orbital integration and no softening parameter.

## 10. Compiler / stdlib notes

Built against XIOM v0.61.3. Standard repo discipline: free functions only
(no methods), no lambdas, no `Vec[Struct]`, no `Vec[Float64]`, no
`Result`/`Option` (every function is total), no `match` in the module, no
inline `mut` patterns, `module` without a trailing semicolon, `use` lines
with one, and the copyright + SPDX header on every `.xi` file. The tests
route all `Str` usage through `xiom.test`/`xiom.io` values built locally, so
no `str_compare` workaround is needed.
