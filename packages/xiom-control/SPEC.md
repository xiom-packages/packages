# xiom-control Specification

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

- `pid_set_limits`: **requires** `min < max`
- `pid_set_integral_limit`: **requires** `limit > 0.0`
- `pid_compute`: **requires** `dt > 0.0`

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

- `lpf_new`: **requires** `cutoff_freq > 0.0`, `sample_rate > 0.0`
- `ma_new`: **requires** `window_size > 0`

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
