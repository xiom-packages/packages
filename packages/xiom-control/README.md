# xiom-control

> Pure XIOM control systems library — PID, state machines, filters, and trajectory planning.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-control provides production-grade control algorithms for robotics and automation:
- **PID Controllers** with anti-windup and output clamping
- **State Machines** with condition-based transitions
- **Signal Filters** — low-pass, moving average, Kalman
- **Trajectory Planning** with waypoint interpolation

## Installation

```bash
xiom install xiom-control
```

## Quick Start

```xiom
use xiom.control.pid;
use xiom.control.filter;

fn main() -> Int {
  var pid = pid_new(1.0, 0.1, 0.05);
  pid_set_setpoint(&mut pid, 100.0);
  var output = pid_compute(&mut pid, 95.0, 0.01);

  var lpf = lpf_new(10.0, 100.0);
  var filtered = lpf_compute(&mut lpf, output);

  return 0;
}
```

## API Reference

### PID (`xiom.control.pid`)
| Function | Description |
|----------|-------------|
| `pid_new(kp, ki, kd)` | Create PID controller |
| `pid_set_setpoint(ctrl, sp)` | Set target value |
| `pid_set_limits(ctrl, min, max)` | Clamp output range |
| `pid_set_integral_limit(ctrl, limit)` | Anti-windup clamp |
| `pid_compute(ctrl, measurement, dt)` | Compute control signal |
| `pid_reset(ctrl)` | Reset integral/error |
| `pid_get_error(ctrl)` | Get current error |

### State Machine (`xiom.control.state_machine`)
| Function | Description |
|----------|-------------|
| `sm_new()` | Create empty FSM |
| `sm_add_state(sm, name)` | Add state, returns ID |
| `sm_add_transition(sm, from, to, condition)` | Add transition |
| `sm_transition(sm, condition)` | Execute transition |
| `sm_current(sm)` | Current state ID |
| `sm_can_transition(sm, condition)` | Check transition validity |

### Filters (`xiom.control.filter`)
| Function | Description |
|----------|-------------|
| `lpf_new(cutoff, sample_rate)` | Low-pass filter |
| `lpf_compute(filt, input)` | Apply filter |
| `lpf_reset(filt)` | Reset filter state |
| `ma_new(window_size)` | Moving average filter |
| `ma_compute(ma, input)` | Add sample, get average |
| `kalman_new(q, r)` | Kalman filter |
| `kalman_compute(kf, measurement)` | Update filter |

### Trajectory (`xiom.control.trajectory`)
| Function | Description |
|----------|-------------|
| `trajectory_new()` | Create empty trajectory |
| `trajectory_add_waypoint(traj, wp)` | Add waypoint |
| `trajectory_interpolate(traj, t)` | Linear interpolation at time t |
| `trajectory_duration(traj)` | Total duration |

## Safety Contracts

All functions with preconditions are compile-time guarded:
- `pid_set_limits`: requires min < max
- `pid_compute`: requires dt > 0.0
- `lpf_new`: requires cutoff_freq > 0.0, sample_rate > 0.0
- `ma_new`: requires window_size > 0

## Dependencies

- `xiom-std` (standard library)
- `xiom.math` (trigonometry, square root)

## Build & Run

```bash
xiom --run myprogram.xi
```

## License

MIT OR Apache-2.0
