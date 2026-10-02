# xiom.control Specification

Control systems library for XIOM -- PID controllers, state machines, signal processing filters, and trajectory interpolation.

---

## Module: `xiom.control.pid`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `PIDController` | `kp`, `ki`, `kd`, `setpoint`, `integral`, `prev_error`, `integral_limit`, `output_min`, `output_max` | PID controller state |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `pid_new` | `(kp: Float64, ki: Float64, kd: Float64) -> PIDController` | Create PID controller with given gains |
| `pid_set_limits` | `(ctrl: &mut PIDController, min: Float64, max: Float64)` | Set output clamping limits |
| `pid_set_integral_limit` | `(ctrl: &mut PIDController, limit: Float64)` | Set anti-windup integral limit |
| `pid_set_setpoint` | `(ctrl: &mut PIDController, sp: Float64)` | Set target setpoint |
| `pid_compute` | `(ctrl: &mut PIDController, measurement: Float64, dt: Float64) -> Float64` | Compute control output |
| `pid_reset` | `(ctrl: &mut PIDController)` | Reset integral and previous error |
| `pid_get_error` | `(ctrl: &PIDController) -> Float64` | Get last error value |

### Contract Guarantees

All seven entry points carry checked contracts (full inventory below):

- `pid_new`: **requires** `kp > 0.0`, `ki >= 0.0`, `kd >= 0.0`; **ensures** gains stored, integral/prev_error zeroed, `integral_limit > 0.0`, `output_min < output_max`
- `pid_set_limits`: **requires** `min < max`; **ensures** both limits stored
- `pid_set_integral_limit`: **requires** `limit > 0.0`; **ensures** limit stored
- `pid_set_setpoint`: **ensures** setpoint stored
- `pid_compute`: **requires** `dt > 0.0`; **ensures** integral within `+/-integral_limit` and result within `[output_min, output_max]`
- `pid_reset`: **ensures** integral and prev_error are `0.0`
- `pid_get_error`: **ensures** `result == setpoint - prev_error`

### Algorithm

Standard PID with integral anti-windup (clamping) and output limiting:

```
error = setpoint - measurement
integral += error * dt  (clamped to +/-integral_limit)
derivative = (error - prev_error) / dt
output = kp*error + ki*integral + kd*derivative  (clamped to [output_min, output_max])
```

---

## Module: `xiom.control.state_machine`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `StateMachineState` | `Idle`, `Running`, `Paused`, `Error(code: Int)`, `Complete` | State enum |
| `Transition` | `from: Int`, `to: Int`, `condition: Int` | Transition between state IDs |
| `StateMachine` | `current: Int`, `states: Vec[Str]`, `transitions: Vec[Transition]`, `state_data: Vec[Int]` | FSM runtime |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `sm_new` | `() -> StateMachine` | Create empty state machine |
| `sm_add_state` | `(sm: &mut StateMachine, name: Str) -> Int` | Add state, returns ID |
| `sm_add_transition` | `(sm: &mut StateMachine, from: Int, to: Int, condition: Int)` | Add transition rule |
| `sm_transition` | `(sm: &mut StateMachine, condition: Int) -> Bool` | Attempt transition by condition |
| `sm_current` | `(sm: &StateMachine) -> Int` | Get current state ID |
| `sm_can_transition` | `(sm: &StateMachine, condition: Int) -> Bool` | Check if transition is valid |

### Usage Pattern

States are integer IDs. Conditions are integer codes. Transitions match `(current_state, condition)` pairs to determine the next state.

---

## Module: `xiom.control.filter`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `LowPassFilter` | `alpha: Float64`, `prev_output: Float64`, `initialized: Bool` | First-order IIR low-pass |
| `MovingAverage` | `window: Vec[Float64]`, `window_size: Int`, `index: Int`, `sum: Float64`, `count: Int` | Simple moving average |
| `KalmanFilter1D` | `q: Float64`, `r: Float64`, `x: Float64`, `p: Float64`, `k: Float64`, `initialized: Bool` | 1D Kalman filter |

### Functions

#### LowPassFilter

| Function | Signature | Description |
|----------|-----------|-------------|
| `lpf_new` | `(cutoff_freq: Float64, sample_rate: Float64) -> LowPassFilter` | Create filter with alpha = dt/(RC + dt) |
| `lpf_compute` | `(filt: &mut LowPassFilter, input: Float64) -> Float64` | Apply filter to input sample |
| `lpf_reset` | `(filt: &mut LowPassFilter)` | Reset filter state |

#### MovingAverage

| Function | Signature | Description |
|----------|-----------|-------------|
| `ma_new` | `(window_size: Int) -> MovingAverage` | Create moving average with window |
| `ma_compute` | `(ma: &mut MovingAverage, input: Float64) -> Float64` | Add sample, return average |

#### KalmanFilter1D

| Function | Signature | Description |
|----------|-----------|-------------|
| `kalman_new` | `(process_noise: Float64, measurement_noise: Float64) -> KalmanFilter1D` | Create Kalman filter |
| `kalman_compute` | `(kf: &mut KalmanFilter1D, measurement: Float64) -> Float64` | Update with measurement, return estimate |

### Contract Guarantees

All seven entry points carry checked contracts (full inventory below):

- `lpf_new`: **requires** `cutoff_freq > 0.0`, `sample_rate > 0.0`; **ensures** `alpha` in `[0.0, 1.0]`, `prev_output == 0.0`, `!initialized`
- `lpf_compute`: **ensures** `initialized == true` and `prev_output == result`
- `lpf_reset`: **ensures** `prev_output == 0.0`, `!initialized`
- `ma_new`: **requires** `window_size > 0`; **ensures** fields stored/zeroed and `window.len() == window_size`
- `ma_compute`: **requires** `window_size > 0`; **ensures** `count <= window_size` and `index` in `[0, window_size)`
- `kalman_new`: **requires** `process_noise > 0.0`, `measurement_noise > 0.0`; **ensures** noises stored, `p == 1.0`, `k == 0.0`, `!initialized`
- `kalman_compute`: **ensures** `initialized == true` and `k` in `[0.0, 1.0]`

### Algorithms

- **Low-pass filter**: `y[n] = alpha * x[n] + (1 - alpha) * y[n-1]` where `alpha = dt / (RC + dt)` and `RC = 1 / (2*pi*fc)`
- **Moving average**: Cumulative average for first N samples (warm-up), then sliding window
- **Kalman filter**: Predict (`p += q`) then update (`k = p/(p+r)`, `x += k*(z-x)`, `p = (1-k)*p`)

---

## Module: `xiom.control.trajectory`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `Waypoint` | `x: Float64`, `y: Float64`, `z: Float64`, `time: Float64` | 4D waypoint |
| `Trajectory` | `waypoints: Vec[Waypoint]`, `duration: Float64` | Ordered waypoint sequence |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `trajectory_new` | `() -> Trajectory` | Create empty trajectory |
| `trajectory_add_waypoint` | `(traj: &mut Trajectory, wp: Waypoint)` | Append waypoint, update duration |
| `trajectory_interpolate` | `(traj: &Trajectory, t: Float64) -> (Float64, Float64, Float64)` | Linear interpolation at time t |
| `trajectory_duration` | `(traj: &Trajectory) -> Float64` | Total trajectory duration |

### Interpolation

Piecewise linear between consecutive waypoints. Clamps to first/last waypoint for t outside range.

---

## Usage Examples

```xiom
use xiom.control.pid;
use xiom.control.filter;
use xiom.control.trajectory;

fn main() {
  var pid = pid_new(1.0, 0.1, 0.05);
  pid_set_setpoint(&mut pid, 100.0);
  pid_set_limits(&mut pid, -50.0, 50.0);

  var filt = lpf_new(10.0, 100.0);
  var output = lpf_compute(&mut filt, pid_compute(&mut pid, 95.0, 0.01));

  var traj = trajectory_new();
  trajectory_add_waypoint(&mut traj, Waypoint{ x: 0.0, y: 0.0, z: 0.0, time: 0.0 });
  trajectory_add_waypoint(&mut traj, Waypoint{ x: 1.0, y: 2.0, z: 0.0, time: 5.0 });
  var pos = trajectory_interpolate(&traj, 2.5);
}
```

---

## Design Notes

- **No generics**: All functions use concrete `Float64` and `Int` types
- **No FFI**: All algorithms are pure XIOM implementations
- **While loops only**: No `for` loops per XIOM language constraints
- **Contracts**: `requires` guards protect against invalid inputs at compile time
- **Anti-windup**: PID integral is clamped to prevent integrator windup

---

## Contract inventory (stable gate G4)

Added 2026-10-02 with compiler v0.62.2. All 24 public entry points carry
contracts; 6 record types carry invariants. Totals: **15 `requires`, 36
`ensures`, 7 type invariants** (58 checked clauses). Contracts are
runtime-checked by the compiler; a violation traps with the clause location.

| Entry point | `requires` | `ensures` |
|---|---|---|
| `pid_new` | `kp > 0.0`, `ki >= 0.0`, `kd >= 0.0` | gains stored; integral/prev_error `0.0`; `integral_limit > 0.0`; `output_min < output_max` |
| `pid_set_limits` | `min < max` | limits stored |
| `pid_set_integral_limit` | `limit > 0.0` | limit stored |
| `pid_set_setpoint` | -- | setpoint stored |
| `pid_compute` | `dt > 0.0` | integral within `+/-integral_limit`; result within `[output_min, output_max]` |
| `pid_reset` | -- | integral and prev_error `0.0` |
| `pid_get_error` | -- | `result == setpoint - prev_error` |
| `lpf_new` | `cutoff_freq > 0.0`, `sample_rate > 0.0` | `alpha` in `[0.0, 1.0]`; output zeroed; not initialized |
| `lpf_compute` | -- | initialized; `prev_output == result` |
| `lpf_reset` | -- | output zeroed; not initialized |
| `ma_new` | `window_size > 0` | size/index/count stored; `window.len() == window_size` |
| `ma_compute` | `window_size > 0` | `count <= window_size`; `index` in `[0, window_size)` |
| `kalman_new` | `process_noise > 0.0`, `measurement_noise > 0.0` | noises stored; `p == 1.0`; `k == 0.0`; not initialized |
| `kalman_compute` | -- | initialized; `k` in `[0.0, 1.0]` |
| `sm_new` | -- | `current == 0`; all vectors empty |
| `sm_add_state` | -- | `result == states.len() - 1`; `states.len() == state_data.len()` |
| `sm_add_transition` | `from`/`to` in `[0, states.len())` | `transitions.len() >= 1` |
| `sm_current` | -- | `result == current` |
| `sm_can_transition` | -- | `result => current` is a valid state index |
| `sm_transition` | -- | `result => current` is a valid state index |
| `trajectory_new` | -- | `duration == 0.0`; no waypoints |
| `trajectory_add_waypoint` | `wp.time >= duration` (non-decreasing times) | `duration >= wp.time` |
| `trajectory_duration` | -- | `result == duration` |
| `trajectory_interpolate` | -- | empty trajectory => `(0.0, 0.0, 0.0)` |

Type invariants (record member `invariant:`, compiler-checked):

| Type | Invariants |
|---|---|
| `PIDController` | `output_min < output_max`; `integral_limit > 0.0` |
| `LowPassFilter` | `alpha >= 0.0 && alpha <= 1.0` |
| `MovingAverage` | `window_size > 0` |
| `KalmanFilter1D` | `q > 0.0 && r > 0.0` |
| `StateMachine` | `current >= 0` |
| `Trajectory` | `duration >= 0.0` |

---

## Verification status (Z3, stable gate G4)

Run 2026-10-02 with `xiom-verify.exe` (v0.62.2, Phase 5f) and the bundled
`z3.exe` (`$env:Z3_PATH = $env:LOCALAPPDATA\xiom.new\bin\z3.exe`), one run per
file from the package directory:

| File | Result | Disposition |
|---|---|---|
| `src/pid.xi` | 0 proven, 2 violated, 13 unknown, 19 SMT errors | solver-unproven |
| `src/filter.xi` | 0 proven, 3 violated, 13 unknown, 32 SMT errors | solver-unproven |
| `src/state_machine.xi` | 0 proven, 1 violated, 14 unknown, 10 SMT errors | solver-unproven |
| `src/trajectory.xi` | 0 proven, 1 violated, 9 unknown, 3 SMT errors | solver-unproven |
| `tests/test_conformance.xi` | aborted (no `Results:` line) | not verifiable: no contracts; verifier does not resolve package `use` imports |

**All 58 clauses are solver-unproven** and stay annotated for review/tests per
`docs/PROMOTION.md`. The `violated` counts are **not counterexamples**: every
`[FAIL] VIOLATED` line is accompanied by a Z3 `[RED] ERROR` (e.g. `unknown
constant PIDController-kp`, `Sort mismatch ... supplied sort is (Array
PIDController Real)`); the tool then reports `z3 invocation failed` and writes
`xiom_verify_output.smt2`. The verifier cannot encode record receivers in
contract expressions: warnings `X7007 ... field access '.x' on non-datatype
receiver` precede the errors, and clauses touching `result.<field>`,
`&mut` fields, or `Vec.len()` are skipped as unsupported (`X7007`).

Isolation control (same machine, same command): a scalar-only probe
(`divide`, `clamp01`, `abs_int`, no record fields) reported
`Results: 4 proven, 0 violated, 0 unknown, 0 errors`, exit 0. The limitation is
therefore the verifier's record-field support, not the clause shape used here.
`lpf_new`'s division-based `alpha` bound was additionally exercised by the
conformance tests for representative inputs.

### Unasserted properties (documented, not contract-expressible today)

- **Non-empty interpolation geometry** -- piecewise-linear positions and
  first/last-waypoint clamping for non-empty trajectories are unasserted
  (requires quantified reasoning over waypoint sequences; only the empty case
  is a clause). Covered by 4 conformance checks.
- **Multi-call sequence behavior** -- Kalman convergence, moving-average
  window semantics, and PID tracking over successive `*_compute` calls are
  unasserted (single-call postconditions cannot reference call history).
  Covered by 4 conformance checks.
- **PID output closed form** -- `kp*error + ki*integral + kd*derivative` is
  unasserted (intermediate error/derivative are not visible in the
  post-state); the clamp range is asserted instead.
- **`pid_get_error` semantics** -- returns `setpoint - prev_error` (last
  measurement-derived value), not the current error; asserted only as the
  implemented arithmetic. The AUDIT.md semantic-bug note stays open; behavior
  is frozen for this promotion.
- **`current < states.len()`** -- unasserted as a `StateMachine` invariant:
  `sm_new()` legitimately starts `current == 0` with zero states, so only
  `current >= 0` holds for all constructed values.
- **Strict `alpha` openness** -- contracts assert the closed `[0, 1]` bound;
  the strict `(0, 1)` property for finite positive inputs is left to tests and
  can round to an endpoint for extreme inputs.
- **Non-finite floats** -- NaN/Inf inputs are outside the asserted domain
  (no finiteness predicate in contract expressions); violating clauses trap at
  runtime rather than producing silent garbage.

## Known limitations

- **Test dispatch is direct, not table-driven**: `tests/test_conformance.xi` dispatches
  its 32 cases through `run_test_at(index)` instead of a `Vec[fn() -> TestResult]`
  table with `tests[i]()`. Compiler 0.61.3 miscompiles indexed calls through
  `Vec[fn]` elements (the emitted IR dereferences the function address itself and
  calls the value loaded from the code bytes), crashing with an access violation
  (`0xC0000005`, exit `-1073741819`) before any test output. The same defect makes
  `xiom.test.run_all` unusable on this toolchain. The direct dispatch preserves the
  exact same 32 tests and report output.
