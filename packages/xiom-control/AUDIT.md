# xiom-control Audit

## Compilation Status
- `src/pid.xi` -- PASSES (standalone)
- `src/filter.xi` -- PASSES (standalone)
- `src/state_machine.xi` -- PASSES (standalone)
- `src/trajectory.xi` -- PASSES (standalone)
- All files compile together: PASS

## Changes Made
- Removed unused `use xiom.math;` from `pid.xi` (no math functions were called).
- Attempted to replace hardcoded PI constant in `filter.xi` with `math.PI`, but the compiler does not resolve module-qualified constants (`math.PI`) in standalone mode. Reverted to the hardcoded constant. The `use xiom.math;` import is retained for potential future stdlib calls.

## Dependencies
- `xiom.math` -- used for trigonometric constants and potential future math operations. Currently only imported in `pid.xi` and `filter.xi`; no math calls are made (all algorithms use basic arithmetic).
- No FFI dependencies. All algorithms are pure XIOM.

## Known Gaps
- `xiom.math` is imported but not used in `pid.xi` or `filter.xi`. The import is harmless but unnecessary.
- `pid_get_error` returns `setpoint - prev_error` which gives the *previous* error, not the current error. This is a semantic bug -- it should return the current error computed in `pid_compute`.
- `filter.xi` hardcodes `3.14159265358979323846` for PI instead of using `xiom.math.PI`.
- No tests exist for any control module. The test directory is empty.
- Kalman filter only supports 1D. No multi-dimensional Kalman filter.
- Trajectory interpolation is linear only. No spline or cubic interpolation.
