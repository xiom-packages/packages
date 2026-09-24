# xiom.physics

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** introductory Newtonian mechanics in SI units with scalar
> `Float64` values: kinematics (SUVAT), energy, momentum, work and power,
> gravitation, and two geometry helpers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports `xiom.math` for the constant `pi` and uses no FFI of its
> own). Tests additionally use `xiom.test`, `xiom.io` and `xiom.math`.

## What it is

`xiom.physics` is a small, dependency-light mechanics module built entirely
from scalar `Float64` arithmetic. Every quantity is a plain double in a unit
spelled out in the function name (`_m`, `_kg`, `_s`, or an SI base
combination for derived quantities: newtons, joules, watts). There are no
vectors, no bodies, no integrators and no unit parsing -- just the textbook
formulas with explicitly documented edge cases.

Twelve free functions cover:

- **kinematics:** `phys_velocity`, `phys_acceleration`, `phys_position`,
  `phys_velocity_at` (the SUVAT pair for constant acceleration),
- **energy, momentum, work, power:** `phys_kinetic_energy`,
  `phys_potential_energy`, `phys_momentum`, `phys_work`, `phys_power`,
- **gravitation:** `phys_gravitational_force` (with the exported
  `PHYS_G = 6.674e-11 m^3 kg^-1 s^-2`),
- **geometry:** `phys_circle_area`, `phys_sphere_volume`.

See `SPEC.md` for the exact formulas, the guard rules and the test plan.

## Guard rules

Invalid inputs are total, not errors: they return `0.0` and never panic.

- **G1 duration:** a time argument `<= 0` returns `0.0` in every function
  that takes one -- `phys_velocity`, `phys_acceleration`, `phys_position`,
  `phys_velocity_at`, `phys_power`. Note this means `phys_position(...)` at
  `t == 0` returns `0.0` rather than `s0`, and `phys_velocity_at(...)` at
  `t == 0` returns `0.0` rather than `v0`.
- **G2 radius:** a radius `< 0` returns `0.0` in `phys_circle_area` and
  `phys_sphere_volume`.
- **G3 separation:** `r_m <= 0` returns `0.0` in
  `phys_gravitational_force`.
- **G4 kinetic mass:** a mass `< 0` returns `0.0` in
  `phys_kinetic_energy` (the energy would otherwise be negative).

Everything else is signed and preserved: displacement, velocity, momentum,
work and potential energy may be negative.

## API

| Function | Returns | Units | Description |
|---|---|---|---|
| `phys_velocity(distance_m, time_s)` | `Float64` | m/s | `distance_m / time_s`; `time_s <= 0 -> 0.0` (G1). |
| `phys_acceleration(delta_v, delta_t)` | `Float64` | m/s^2 | `delta_v / delta_t`; `delta_t <= 0 -> 0.0` (G1). |
| `phys_position(s0, v0, a, t)` | `Float64` | m | `s0 + v0*t + a*t*t/2`; `t <= 0 -> 0.0` (G1). |
| `phys_velocity_at(v0, a, t)` | `Float64` | m/s | `v0 + a*t`; `t <= 0 -> 0.0` (G1). |
| `phys_kinetic_energy(mass_kg, velocity)` | `Float64` | J | `0.5*m*v^2`; `mass_kg < 0 -> 0.0` (G4). |
| `phys_potential_energy(mass_kg, height_m, g)` | `Float64` | J | `m*g*h`, signed. |
| `phys_momentum(mass_kg, velocity)` | `Float64` | kg*m/s | `m*v`, signed by the velocity. |
| `phys_work(force_n, distance_m)` | `Float64` | J | `F*d`, signed. |
| `phys_power(work_j, time_s)` | `Float64` | W | `work_j / time_s`; `time_s <= 0 -> 0.0` (G1). |
| `phys_gravitational_force(m1_kg, m2_kg, r_m)` | `Float64` | N | `G*m1*m2/r^2`, `G = 6.674e-11`; `r_m <= 0 -> 0.0` (G3). |
| `phys_circle_area(r_m)` | `Float64` | m^2 | `pi*r^2`; `r_m < 0 -> 0.0` (G2). |
| `phys_sphere_volume(r_m)` | `Float64` | m^3 | `4*pi*r^3/3`; `r_m < 0 -> 0.0` (G2). |

## Usage

```xi
use xiom.physics;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let g = 9.80665;
  io.println("fall in 3 s: " +
    convert.float_to_string(phys_position(0.0, 0.0, g, 3.0)) + " m");
  io.println("impact speed: " +
    convert.float_to_string(phys_velocity_at(0.0, g, 3.0)) + " m/s");
  io.println("kinetic energy of 2 kg at 3 m/s: " +
    convert.float_to_string(phys_kinetic_energy(2.0, 3.0)) + " J");
  io.println("Earth pull on 1 kg: " +
    convert.float_to_string(phys_gravitational_force(5.972e24, 1.0, 6.371e6)) + " N");
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.physics
```

Expected tail: 22 `[PASS]` lines, `xiom.physics: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Scalar SI only.** Every value is a single `Float64` in an SI unit; there
  are no vectors, tuples, matrices or coordinate frames, and no vector
  kinematics (`(Float64, Float64, Float64)` returned by reference APIs in
  other packages is not used here).
- **No relativity.** Newtonian mechanics only: no Lorentz factors,
  relativistic momentum/energy, mass-energy equivalence, time dilation or
  curved spacetime. For those, see the separate `xiom.relativity` surface.
- **No dynamics beyond the closed forms listed.** Constant acceleration,
  uniform fields and the two-sphere gravity formula only -- no integrators,
  springs, drag, collisions, rigid bodies, orbits or multi-body simulation.
- **No unit system machinery.** Units live in the names; there is no
  dimensional analysis, parsing, formatting, or conversion between units.
- **Guard-based edge handling.** Invalid inputs return `0.0` (no `Result`,
  no panic); a real zero is indistinguishable from a rejected input in the
  output. See `SPEC.md` section 3 for the exact rules.
- **No overflow/NaN contract.** IEEE-754 double behaviour applies for extreme
  magnitudes; inputs are expected to be finite physical values.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
