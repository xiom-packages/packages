# xiom.control

> **Status:** `ported` -- conformance-tested on compiler v0.61.3 (27/27); NOT published yet.
> **Scope:** Pure-XIOM control primitives: signal filters, PID control, trajectory interpolation, and state machines.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Modules

| Module | Description |
|--------|-------------|
| `xiom.control.filter` | Low-pass, moving-average, and Kalman filters |
| `xiom.control.pid` | PID controller with output and integral limits |
| `xiom.control.trajectory` | Waypoint trajectories with clamped interpolation |
| `xiom.control.state_machine` | Transition-guarded finite state machines |

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.control
```

The 27 conformance tests cover filter behavior, PID math and clamping, trajectory interpolation, and state-machine transitions.

## Not yet implemented

- LQR and the other placeholder inventory items are not part of v0.1; the implemented surface is the four modules above.

## Known limitations

- The conformance suite dispatches tests through `run_test_at(index)` instead of a `Vec[fn() -> TestResult]` table with `tests[i]()`: compiler v0.61.3 miscompiles indexed calls through `Vec[fn]` elements (access violation before any test output). The same defect currently makes `xiom.test.run_all` unusable on this toolchain. See SPEC.md for the minimal repro.
