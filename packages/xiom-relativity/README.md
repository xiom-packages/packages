# xiom.relativity

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** special-relativity scalar helpers: Lorentz factor, time dilation,
> length contraction, relativistic velocity addition, and energy/momentum
> relations for a single collinear speed.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_float` and
> scalar `xiom.math.sqrt` / `xiom.math.abs_float`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.relativity` is a small, dependency-free module over flat scalars. All
speeds are **permille integers**: `beta_permille = round(beta * 1000)`, so the
representable speed range is `-0.999 c` .. `+0.999 c` and the smallest speed
step is `0.001 c`. The speed of light is the exact SI value
`c = 299792458 m/s`.

Every beta-taking function validates its input: `|beta_permille| >= 1000`
(i.e. `|beta| >= 1`, beta outside the open interval `(-1000, 1000)`) is
invalid and returns `0.0` instead of a NaN or a panic. The one exception is
`rel_velocity_add_permille`, which clamps its inputs into `[-999, 999]`
instead of rejecting them, because a sum of two sub-luminal speeds should
already be sub-luminal.

There is no FFI, no vector math, no struct, and no platform-specific code:
the module is `Float64` scalar arithmetic plus integer permille arithmetic
from `xiom.std`.

## API

| Function | Returns | Units | Description |
|---|---|---|---|
| `rel_lorentz_permille(beta_permille)` | `Float64` | 1 | Lorentz factor `1/sqrt(1 - beta^2)`; `0.0` for invalid beta. |
| `rel_time_dilation_s(proper_s, beta_permille)` | `Float64` | seconds | `proper_s * gamma`; `0.0` for invalid beta. |
| `rel_length_contraction_m(proper_m, beta_permille)` | `Float64` | metres | `proper_m / gamma`; `0.0` for invalid beta. |
| `rel_velocity_add_permille(u_permille, v_permille)` | `Int` | permille | Relativistic sum `(u+v)/(1+u*v/1e6)` on the permille grid; inputs clamped to `[-999, 999]`. |
| `rel_energy_j(mass_kg)` | `Float64` | joules | Rest energy `m * c^2`. |
| `rel_kinetic_energy_j(mass_kg, beta_permille)` | `Float64` | joules | `(gamma - 1) * m * c^2`; `0.0` for invalid beta. |
| `rel_momentum_ns(mass_kg, beta_permille)` | `Float64` | kg*m/s (N*s) | `gamma * m * v`, `v = beta * c`; `0.0` for invalid beta. |
| `rel_beta_from_bits(bits)` | `Int` | permille | Clamp any `Int` into `[-999, 999]` (used by velocity addition). |

`gamma` is always the value returned by `rel_lorentz_permille`.

## Usage

```xi
use xiom.relativity;
use xiom.io;

fn main() -> Int {
  if rel_lorentz_permille(600) > 1.24 {
    io.println("gamma at 0.6c is 1.25");
  }
  if rel_time_dilation_s(1.0, 600) > 1.24 {
    io.println("1 s of proper time is 1.25 s of coordinate time");
  }
  if rel_velocity_add_permille(500, 500) == 800 {
    io.println("0.5c + 0.5c = 0.8c, not c");
  }
  io.println(rel_kinetic_energy_j(1.0, 600));   // 0.25 * c^2 joules
  io.println(rel_momentum_ns(1.0, 600));        // 224844343.5 kg*m/s
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.relativity
```

Expected tail: 20 `[PASS]` lines, `xiom.relativity: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The suite (`tests/test_conformance.xi`) pins the mandated anchors --
`lorentz(0) = 1`, `lorentz(600) = 1.25`, `lorentz(800) = 5/3`,
`lorentz(+-999) = 22.3662720421294`, `lorentz(1000) = 0` invalid, time
dilation and length contraction at `0.6c`, `500 + 500 = 800` permille,
`0 + 0 = 0` and negative speeds, `E(1 kg) = c^2 = 8.987551787368176e16 J`,
kinetic energy at `0.6c`, zero-momentum at `beta = 0`, and the beta clamp.
Float64 checks use the absolute helper `|a - b| < 1e-6`, applied to
`O(1)`-sized quantities or ratios; the `c^2`-scale values are compared
through ratios so the tolerance is not weakened. See `SPEC.md` for the
formulas, rounding rules and the full test-to-semantics map.

## Limitations

- **Scalar 1-D only.** Every speed is collinear and one-dimensional; there
  are no vectors, no 4-vectors, no Lorentz transformations between frames,
  no rotations, and no transverse components.
- **Permille precision.** Speeds are quantized to `0.001 c`; `|beta| = 1`
  is not representable, so `c` itself and beyond are always rejected.
  `rel_velocity_add_permille` uses integer truncation toward zero and its
  documented edge case `999 + 999 -> 1000` permille is the double-truncated
  value, not the exact rational sum (999.9995 permille).
- **No general relativity.** No gravity, no curvature, no geodesics, no
  redshift in a gravitational field, no accelerated-frame treatments; this
  is special relativity kinematics and energy/momentum only.
- **No dynamics.** No forces, no collisions, no decay/annihilation rules,
  no particle physics; the caller supplies the constants.
- **Sentinel errors.** Invalid beta returns `0.0` rather than a `Result`;
  callers must treat `0.0` as "invalid" (it is also the correct value of
  some valid inputs, e.g. zero mass energy), like the other `xiom.*`
  scalar helpers.
- No time-of-flight, no Doppler, no aberration, no light-cone helpers in
  this version.

See `SPEC.md` for the formulas, precision rules and the test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
