# xiom.robotics -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.robotics` (`src/robotics.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only; the module imports `xiom.math` for the
constant `PI` and the scalar helpers `sin`, `cos`, `sqrt`, `abs_float`; the
tests use `xiom.test`, `xiom.io` and `xiom.math`.

## 1. Scope

Planar robotics closed forms for a 2-link revolute arm and a
differential-drive base, all scalar:

- forward kinematics with the base at the origin or translated
  (`robot_fk2`, `robot_fk2_at`), returning a `RoboPose2`;
- end-effector distance from the base for a given elbow angle
  (`robot_end_distance`);
- annular reachability of a target radius (`robot_reach_ok`);
- angle normalization into `[-pi, pi]` (`robot_clamp_angle_rad`);
- differential-drive forward and inverse maps in integer mm/s and mrad/s
  (`robot_diff_drive_v_mm_s`, `robot_diff_drive_omega_mrad_s`,
  `robot_wheel_speeds_mm_s`).

Every function is a free function (no methods), deterministic, allocation-
free and total: invalid inputs map to `false` or `0`, never to an error or a
panic.

## 2. Non-goals

- Inverse kinematics, Jacobians, singularities, workspace optimization.
- Dynamics: no mass, inertia, torque, friction, gravity, actuators or
  integration.
- Trajectory generation or control: no planning, interpolation, PID.
- Sensing: no encoders, IMU, odometry integration or state estimation.
- 3D geometry, quaternions, homogeneous transforms, base-frame rotation.
- Joint limits, link offsets in y, prismatic joints, gear ratios.
- Units machinery, parsing, formatting, randomness, file I/O, FFI.

## 3. Guard rules

Invalid inputs are total: they return `false` or `0` and are never errors
or panics. The rules are module-wide for the corresponding arguments and
are pinned by the conformance suite.

| Rule | Argument | Condition | Effect | Applies to |
|---|---|---|---|---|
| G1 | link lengths | negative | use `\|l1\|`, `\|l2\|` | `robot_end_distance` |
| G2 | links, radius | negative | `false` | `robot_reach_ok` |
| G3 | angle | outside `[-pi, pi]` | fold by `+/- 2*pi` loop | `robot_clamp_angle_rad` |
| G4 | wheel base | `<= 0` | `0` | `robot_diff_drive_omega_mrad_s` |

Consequences worth stating explicitly:

- **G1 vs G2 disagree by design.** `robot_end_distance` treats a negative
  length as a magnitude (distance is unsigned geometry), while
  `robot_reach_ok` rejects negative lengths and radii outright so a sign
  error is not silently hidden. Both behaviours are pinned by tests t8 and
  t11.
- **G3 folds, it does not wrap with modulo.** `+pi` and `-pi` are kept
  as-is; `3*pi/2 -> -pi/2`; `-2*pi -> 0`; `5*pi -> pi`; `10.0 -> 10 - 4*pi`.
  The loop runs `ceil(|a| / (2*pi))` times, so cost grows with `|a|` and a
  non-finite input would not terminate (inputs are expected finite).
- **Truncation, not rounding, in the integer helpers.** Integer division
  truncates toward zero: `(1 + 2) / 2 == 1`, `(-3 + 0) / 2 == -1`,
  `100 * 1000 / 3000 == 33`, `-100 * 1000 / 3000 == -33`.
- **A real zero is not distinguishable from a guarded input** in the
  return value; callers who need the distinction must validate first.
- **`robot_reach_ok(0, 0, 0)` is `true`**: the degenerate zero-link arm
  reaches exactly the origin, which satisfies `|l1-l2| <= r <= l1+l2`.

## 4. Units and conventions

| Quantity | Symbol | Unit | Used by |
|---|---|---|---|
| link length, position, radius, distance | `_m` | metre (m) | `robot_fk2*`, `robot_end_distance`, `robot_reach_ok` |
| joint angle | `_rad` | radian (rad) | `robot_fk2*`, `robot_end_distance`, `robot_reach_ok` |
| body/wheel speed | `_mm_s` | millimetre per second (mm/s) | differential drive |
| yaw rate | `_mrad_s` | milliradian per second (mrad/s) | differential drive |
| wheel base | `_mm` | millimetre (mm) | differential drive |

Angles are counter-clockwise from the `+x` axis. Link 1's angle `theta1_rad`
is absolute; link 2's angle `theta2_rad` is relative to link 1. The base is
at `(0, 0)` in `robot_fk2` and at `(base_x, base_y)` in `robot_fk2_at`.

## 5. Formulas

All `Float64` arithmetic is IEEE-754; the listed example values are decimal
pins used by the tests with an absolute tolerance of 1e-9. Integer values
are exact.

### 5.1 Forward kinematics

| Function | Formula | Pinned examples |
|---|---|---|
| `robot_fk2(l1, l2, t1, t2)` | `x = l1*cos(t1) + l2*cos(t1+t2)`, `y = l1*sin(t1) + l2*sin(t1+t2)` | `(1.5, 2.5, 0, 0) -> (4, 0)`; `(1, 1, 0, pi/2) -> (1, 1)`; `(1.5, 1.5, pi/2, pi/2) -> (-1.5, 1.5)` |
| `robot_fk2_at(bx, by, l1, l2, t1, t2)` | `robot_fk2(...)` translated by `(bx, by)` | `(10, -5, 1, 1, 0, 0) -> (12, -5)`; `(1, 1, 2, 3, 0, pi) -> (0, 1)` |

### 5.2 Reach geometry

| Function | Formula | Pinned examples |
|---|---|---|
| `robot_end_distance(l1, l2, t2)` | `sqrt(\|l1\|^2 + \|l2\|^2 + 2*\|l1\|*\|l2\|*cos(t2))` (law of cosines) | `(3, 4, 0) -> 7`; `(5, 2, pi) -> 3`; `(3, 4, pi/2) -> 5`; `(-3, 4, pi) -> 1` |
| `robot_reach_ok(l1, l2, r)` | `\|l1-l2\| <= r <= l1+l2` (annulus, boundaries closed) | `(1, 1, 2) -> true`; `(1, 2, 1) -> true`; `(1, 1, 2.0001) -> false`; `(-1, 1, 1) -> false` |

### 5.3 Angle normalization

| Function | Formula | Pinned examples |
|---|---|---|
| `robot_clamp_angle_rad(a)` | while `a > pi`: `a -= 2*pi`; while `a < -pi`: `a += 2*pi` | `0 -> 0`; `3*pi/2 -> -pi/2`; `-2*pi -> 0`; `5*pi -> pi`; `10 -> 10 - 4*pi` |

### 5.4 Differential drive

The robot is a two-wheel differential base: `v` is the forward speed of the
wheel contact mid-point in mm/s and `omega` is the yaw rate in mrad/s,
positive counter-clockwise. Integer division truncates toward zero.

| Function | Formula | Pinned examples |
|---|---|---|
| `robot_diff_drive_v_mm_s(vl, vr)` | `(vl + vr) / 2` | `(300, 300) -> 300`; `(100, 300) -> 200`; `(-3, 0) -> -1` |
| `robot_diff_drive_omega_mrad_s(vl, vr, base)` | `(vr - vl) * 1000 / base`; `base <= 0 -> 0` | `(100, 300, 400) -> 500`; `(-200, 200, 400) -> 1000`; `(0, 100, 3000) -> 33`; `(100, 300, 0) -> 0` |
| `robot_wheel_speeds_mm_s(v, omega, base)` | `delta = omega * base / 2000`; returns `(v - delta, v + delta)` | `(500, 1000, 500) -> (250, 750)`; `(10, 333, 1000) -> (-156, 176)` |

`robot_wheel_speeds_mm_s` is the inverse of the forward pair up to the
truncation of `delta`: for moderate magnitudes,
`robot_diff_drive_v_mm_s(l, r) == v` and
`robot_diff_drive_omega_mrad_s(l, r, base) == omega` when
`(l, r) = robot_wheel_speeds_mm_s(v, omega, base)`.

## 6. Constants and types

| Name | Definition | Notes |
|---|---|---|
| `RoboPose2` | `{ x: Float64; y: Float64; }` | Exported struct; a planar point/pose in metres with the base frame at the origin, `+x` right and `+y` up. |
| `pi` | `xiom.math.PI` = `3.141592653589793` | Imported from the stdlib; no local pi literal. |

No other constants are baked into the module: link lengths, wheel bases and
angles are caller inputs.

## 7. API signatures

```xi
pub type RoboPose2 = { x: Float64; y: Float64; }
pub fn robot_fk2(l1_m: Float64, l2_m: Float64, theta1_rad: Float64, theta2_rad: Float64) -> RoboPose2
pub fn robot_fk2_at(base_x: Float64, base_y: Float64, l1_m: Float64, l2_m: Float64, theta1_rad: Float64, theta2_rad: Float64) -> RoboPose2
pub fn robot_end_distance(l1_m: Float64, l2_m: Float64, theta2_rad: Float64) -> Float64
pub fn robot_reach_ok(l1_m: Float64, l2_m: Float64, r_m: Float64) -> Bool
pub fn robot_clamp_angle_rad(a: Float64) -> Float64
pub fn robot_diff_drive_v_mm_s(v_left_mm_s: Int, v_right_mm_s: Int) -> Int
pub fn robot_diff_drive_omega_mrad_s(v_left_mm_s: Int, v_right_mm_s: Int, wheel_base_mm: Int) -> Int
pub fn robot_wheel_speeds_mm_s(v_mm_s: Int, omega_mrad_s: Int, wheel_base_mm: Int) -> (Int, Int)
```

All functions are O(1) (except `robot_clamp_angle_rad`, which is
O(`|a|/(2*pi)`)), total for finite inputs, and free functions: no methods,
no FFI, no lambdas, no generics, no `Result`/`Option`, no `Vec` and no
`match`.

## 8. Test plan

`tests/test_conformance.xi` (module `robotics_tests`) runs 19 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Float comparisons use
`robo_close(a, b) = abs_float(a - b) < 1e-9` (`xiom.math.abs_float`; the
raw libm `fabs` is module-private in the stdlib). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | fk2 straight extended | `t1 = t2 = 0 -> x = l1 + l2`, `y = 0` (two link pairs) |
| t2 | fk2 90-degree elbow | `(1, 1, 0, pi/2) -> (1, 1)`; zero second link keeps x |
| t3 | fk2 general angles | `(2, 1, pi/2, -pi/2) -> (1, 2)`; `(1.5, 1.5, pi/2, pi/2) -> (-1.5, 1.5)` |
| t4 | fk2_at offsets | translation by `(10, -5)`, `(1, 1)` with folded elbow, `(0.5, -0.5)` with 90-degree elbow |
| t5 | end_distance `t2 = 0` | fully extended: `l1 + l2` (7, 7, 4 cases) |
| t6 | end_distance `t2 = pi` | folded back: `\|l1 - l2\|` (3, 0, 0.25) |
| t7 | end_distance `t2 = pi/2` | Pythagorean `sqrt(l1^2 + l2^2)` (5, 13, 0) |
| t8 | end_distance guard G1 | negative lengths folded to magnitudes |
| t9 | reach_ok boundaries true | annulus boundaries included (six cases) |
| t10 | reach_ok boundaries false | just outside inner/outer boundary; negative radius |
| t11 | reach_ok guard G2 | any negative argument is false; `(0, 0, 0)` is true |
| t12 | clamp identity | `0`, `+/-0.5`, `+pi`, `-pi` unchanged |
| t13 | clamp folds | `3pi/2 -> -pi/2`, `-3pi/2 -> pi/2`, `5pi -> pi`, `-2pi -> 0` |
| t14 | clamp multi-turn | `-5pi -> -pi`, `7pi/2 -> -pi/2`, `2pi -> 0`, `10 -> 10 - 4pi`, `1e-12` unchanged |
| t15 | diff drive v | straight, turn, truncation `3/2 -> 1`, `-3/2 -> -1` |
| t16 | diff drive omega | `500`, spin-in-place `1000`, `-200`, truncation `+/-33` |
| t17 | diff drive omega guard G4 | `wheel_base <= 0 -> 0` (0, -400, -1) |
| t18 | wheel_speeds round-trip | `(250, 750)` and `(-50, -150)` reconstruct `v` and `omega` |
| t19 | large and small magnitudes | `3e6` fk pins, `1.003e9` translated base, `5e6`/`5e-6` distances, `1e6` Int omega, `(10, 333, 1000) -> (-156, 176)` |

Every expected value in the table is a decimal pin of section 5; no
assertion is computed with the same expression it checks. The test file
reads no `Vec`, builds no `Str` from elements, dispatches no `Vec[fn]`,
uses no `match`, and calls each test explicitly from `main`.

## 9. Known limitations

- Planar 2-link arm only: no 3D, no prismatic joints, no link offsets in
  `y`, no joint limits, no base rotation.
- No inverse kinematics, Jacobians or workspace analysis.
- No dynamics, trajectory generation or control.
- Differential drive is a kinematic model in integer mm/s and mrad/s;
  truncation toward zero is intentional and not compensated.
- Guard results are indistinguishable from real zeros/false in the return
  value.
- `Float64` rounding applies; the module does not round or quantise
  `Float64` outputs.
- No overflow, NaN or infinity contract beyond IEEE-754 double semantics;
  `robot_clamp_angle_rad` requires finite input.

## 10. Compiler / stdlib notes

Built against XIOM v0.61.3. Standard repo discipline: free functions only
(no methods), no lambdas, no `Vec` of any element type in this module, no
`Result`/`Option`, no `match`, no inline `mut` patterns, `module` without a
trailing semicolon, `use` lines with one, and the copyright + SPDX header on
every `.xi` file. `RoboPose2` is returned by value and its fields are read
with `.x`/`.y`; no `Ok`/`Err` wrapper is used in the struct-returning
functions. The tests use local `let` bindings for both the struct and the
`(Int, Int)` tuple, and route all `Str` usage through `xiom.test`/`xiom.io`
values built locally, so no `str_compare` workaround is needed.
