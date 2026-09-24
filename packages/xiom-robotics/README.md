# xiom.robotics

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** planar robot helpers with scalar `Float64` and `Int` values:
> 2-link forward kinematics, end-effector distance and reach checks, angle
> normalization, and a differential-drive model.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports `xiom.math` for `pi`, `sin`, `cos`, `sqrt` and `abs_float`
> and uses no FFI of its own). Tests additionally use `xiom.test`, `xiom.io`
> and `xiom.math`.

## What it is

`xiom.robotics` is a small, dependency-light planar robotics module built
from scalar arithmetic. It covers the textbook closed forms for:

- **forward kinematics** of a 2-link arm (`robot_fk2`, `robot_fk2_at`),
  returning a `RoboPose2 { x; y }` in metres with the base on the ground
  frame or at a caller-supplied offset;
- **reach geometry**: the end-effector distance for a given elbow angle
  (`robot_end_distance`) and the annular reachability test
  (`robot_reach_ok`);
- **angle hygiene**: normalization into `[-pi, pi]`
  (`robot_clamp_angle_rad`);
- **differential drive**: forward body speed, yaw rate and the inverse
  wheel-speed split (`robot_diff_drive_v_mm_s`,
  `robot_diff_drive_omega_mrad_s`, `robot_wheel_speeds_mm_s`) in integer
  millimetres and milliradians per second.

No inverse kinematics, no dynamics, no trajectory generation, no sensors,
no unit parsing. See `SPEC.md` for the exact formulas, guard rules and test
plan.

## Guard rules

Invalid inputs are total, not errors: they map to `false` or `0` and never
panic.

- **G1 end_distance magnitudes:** `robot_end_distance` folds negative link
  lengths with `abs_float`, so `|l1|` and `|l2|` are used.
- **G2 reach_ok negatives:** `robot_reach_ok` returns `false` when any of
  `l1_m`, `l2_m`, `r_m` is negative; there is no magnitude folding there.
- **G3 clamp loop:** `robot_clamp_angle_rad` folds a finite angle by adding
  or subtracting `2*pi` in a while loop until it lies in `[-pi, pi]`;
  `+pi` and `-pi` are kept as-is and non-finite inputs are not supported
  (the loop would not terminate).
- **G4 drive base:** `robot_diff_drive_omega_mrad_s` returns `0` when
  `wheel_base_mm <= 0`.

Integer helpers truncate toward zero rather than rounding: `(-3) / 2 == -1`
and `100000 / 3000 == 33`.

## API

| Function | Returns | Units | Description |
|---|---|---|---|
| `robot_fk2(l1_m, l2_m, theta1_rad, theta2_rad)` | `RoboPose2` | m | `x = l1*cos(t1) + l2*cos(t1+t2)`, `y = l1*sin(t1) + l2*sin(t1+t2)`; base at the origin. |
| `robot_fk2_at(base_x, base_y, l1_m, l2_m, theta1_rad, theta2_rad)` | `RoboPose2` | m | `robot_fk2(...)` translated by `(base_x, base_y)`. |
| `robot_end_distance(l1_m, l2_m, theta2_rad)` | `Float64` | m | `sqrt(l1^2 + l2^2 + 2*l1*l2*cos(theta2))` using `|l1|`, `|l2|` (G1). |
| `robot_reach_ok(l1_m, l2_m, r_m)` | `Bool` | m | `|l1 - l2| <= r <= l1 + l2`, boundaries included; any negative argument is `false` (G2). |
| `robot_clamp_angle_rad(a)` | `Float64` | rad | Folds a finite angle into `[-pi, pi]` with a while loop (G3). |
| `robot_diff_drive_v_mm_s(v_left_mm_s, v_right_mm_s)` | `Int` | mm/s | `(vl + vr) / 2`, truncated toward zero. |
| `robot_diff_drive_omega_mrad_s(v_left_mm_s, v_right_mm_s, wheel_base_mm)` | `Int` | mrad/s | `(vr - vl) * 1000 / wheel_base_mm`, truncated toward zero; `wheel_base_mm <= 0 -> 0` (G4). |
| `robot_wheel_speeds_mm_s(v_mm_s, omega_mrad_s, wheel_base_mm)` | `(Int, Int)` | mm/s | `delta = omega*base/2000` (truncated toward zero); returns `(v - delta, v + delta)`. |

The `RoboPose2` struct is declared as
`pub type RoboPose2 = { x: Float64; y: Float64; }`; read the fields with
`.` (`let p = robot_fk2(...); p.x`).

## Usage

```xi
use xiom.robotics;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let p = robot_fk2(0.5, 0.5, 0.0, 1.5707963267948966);
  io.println("elbow 90 deg: (" +
    convert.float_to_string(p.x) + ", " +
    convert.float_to_string(p.y) + ") m");
  io.println("reachable 0.7 m by (0.8, 0.4)? " +
    convert.bool_to_string(robot_reach_ok(0.8, 0.4, 0.7)));
  let w = robot_wheel_speeds_mm_s(500, 1000, 500);
  io.println("wheels: " + convert.int_to_string(w.0) + ", " +
    convert.int_to_string(w.1) + " mm/s");
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.robotics
```

Expected tail: 19 `[PASS]` lines, `xiom.robotics: all tests passed`, then
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Planar 2-link only.** Two revolute joints in a plane, one rigid link
  each, base pose fixed: no 3D, no prismatic joints, no mobile base with
  orientation, no joint limits, and no link offsets in y.
- **No inverse kinematics and no dynamics.** No IK solver, Jacobians,
  singularities, torque, mass, inertia, friction, gravity or motor models;
  no trajectory planning or control loops.
- **No frame arithmetic.** `robot_fk2_at` translates the base only; there is
  no rotation of the base frame, no homogeneous transforms, no quaternions.
- **Integer model resolution.** The differential-drive helpers work in
  integer mm/s and mrad/s and truncate toward zero, so inverse-then-forward
  round trips lose less than one integer step; they are not a floating-point
  odometry integrator.
- **Guard-based edge handling.** Rejected inputs return `false`/`0` and are
  indistinguishable from genuine zero values; validate first when the
  distinction matters (see `SPEC.md` section 3).
- **No overflow/NaN contract.** IEEE-754 double semantics apply for
  `Float64`; `Int` arithmetic is expected to stay in range. Inputs are
  expected to be finite, and `robot_clamp_angle_rad` requires it (G3).

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
