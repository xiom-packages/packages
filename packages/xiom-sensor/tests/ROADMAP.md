# xiom-sensor ROADMAP

## Current State (v0.1.0)

### Source Modules

| File | Module | Public API | Contracts | Status |
|------|--------|------------|-----------|--------|
| `src/gps.xi` | `xiom.sensor.gps` | 6 functions, 2 types | 4 functions covered | Compiles |
| `src/imu.xi` | `xiom.sensor.imu` | 10 functions, 3 types | 0 contracts needed | Compiles |
| `src/fusion.xi` | `xiom.sensor.fusion` | 4 functions, 1 type | 3 functions covered | Compiles |
| `src/calibration.xi` | `xiom.sensor.calibration` | 4 functions, 1 type | 1 function covered | Compiles |

### Public API Summary

**GPS** (`xiom.sensor.gps`)
- `GPSFix`, `GeoPoint` — data types
- `gps_is_valid(fix: &GPSFix) -> Bool`
- `gps_distance_m(a: &GeoPoint, b: &GeoPoint) -> Float64`
- `gps_bearing_deg(a: &GeoPoint, b: &GeoPoint) -> Float64`
- `gps_destination(point: &GeoPoint, bearing_deg: Float64, distance_m: Float64) -> GeoPoint` (requires: distance_m >= 0.0)
- `gps_to_utm(lat: Float64, lon: Float64) -> (Float64, Float64, Int)` (requires: lat in [-90,90], lon in [-180,180])
- `utm_to_gps(easting: Float64, northing: Float64, zone: Int, southern: Bool) -> (Float64, Float64)` (requires: zone in [1,60])

**IMU** (`xiom.sensor.imu`)
- `IMUReading`, `Quaternion`, `EulerAngles` — data types
- `imu_reading_new() -> IMUReading`
- `quat_identity() -> Quaternion`
- `quat_normalize(q: &Quaternion) -> Quaternion`
- `quat_conjugate(q: &Quaternion) -> Quaternion`
- `quat_multiply(a: &Quaternion, b: &Quaternion) -> Quaternion`
- `quat_from_euler(roll, pitch, yaw) -> Quaternion`
- `euler_to_quat(roll, pitch, yaw) -> Quaternion`
- `quat_to_euler(q: &Quaternion) -> EulerAngles`
- `quat_rotate_vector(q: &Quaternion, vx, vy, vz) -> (Float64, Float64, Float64)`
- `imu_compute_orientation(reading: &IMUReading) -> Quaternion`

**Fusion** (`xiom.sensor.fusion`)
- `FusedPose` — data type
- `fusion_complementary(imu, gps, alpha) -> FusedPose` (requires: alpha in [0,1])
- `fusion_weighted(poses: &Vec[FusedPose]) -> FusedPose`
- `fusion_predict(pose, velocity, heading, dt) -> FusedPose` (requires: dt >= 0.0)
- `confidence_from_hdop(hdop: Float64) -> Float64` (requires: hdop >= 0.0)

**Calibration** (`xiom.sensor.calibration`)
- `CalibrationData` — data type
- `calibration_identity() -> CalibrationData`
- `calibration_compute_offset(readings: &Vec[Float64]) -> Float64`
- `calibration_apply(value, cal, axis) -> Float64` (requires: axis in [0,2])
- `calibration_from_samples(samples: &Vec[(Float64,Float64,Float64)]) -> CalibrationData`

### Contracts Added (this session)

| Function | Contract | Rationale |
|----------|----------|-----------|
| `gps_destination` | `distance_m >= 0.0` | Negative distance is nonsensical |
| `gps_to_utm` | `lat >= -90.0 && lat <= 90.0` | Valid latitude range |
| `gps_to_utm` | `lon >= -180.0 && lon <= 180.0` | Valid longitude range |
| `utm_to_gps` | `zone >= 1 && zone <= 60` | Valid UTM zone range |
| `confidence_from_hdop` | `hdop >= 0.0` | HDOP cannot be negative |
| `calibration_apply` | `axis >= 0 && axis <= 2` | Only 3 axes (0,1,2) valid |

### Test Suite

**File:** `tests/test_conformance.xi` — 36 tests

| Module | Tests | Coverage |
|--------|-------|----------|
| GPS | 11 | validity, distance, bearing, destination, UTM conversion, reverse UTM |
| IMU | 10 | quaternion identity, normalize, multiply, conjugate, euler conversion, roundtrip, orientation |
| Fusion | 8 | complementary filter, weighted average, prediction decay, confidence |
| Calibration | 7 | identity, offset computation, apply per-axis, from-samples |

Tests compile to IR. Runtime execution is blocked by Vec<T> generic type lowering (compiler v0.49.7 limitation).

## Near-Term (v0.2.0)

### Priority 1 — AHRS/Madgwick Filter

- [ ] Implement Madgwick AHRS algorithm for 9-DOF IMU fusion
- [ ] Add gyroscope integration (dead reckoning between GPS fixes)
- [ ] Quaternion SLERP for pose interpolation

### Priority 2 — Extended Kalman Filter

- [ ] Add `src/ekf.xi` with EKF state estimation
- [ ] Sensor covariance matrices
- [ ] GPS+IMU tight coupling

### Priority 3 — Calibration Matrix

- [ ] Full 3x3 calibration matrix (cross-axis sensitivity)
- [ ] Temperature compensation curves
- [ ] Magnetometer hard/soft iron calibration

## Medium-Term (v0.3.0)

- [ ] Geoid model for altitude (EGM96/EGM2008)
- [ ] NMEA 0183 sentence parser
- [ ] RTCM differential GPS corrections
- [ ] Barometric altitude fusion
- [ ] Optical flow integration

## Long-Term (v0.4.0+)

- [ ] Visual-inertial odometry (VIO)
- [ ] Loop closure / graph optimization
- [ ] Multi-constellation GNSS (GPS+GLONASS+Galileo+BeiDou)
- [ ] Real-time kinematic (RTK) positioning

## Known Issues

1. **Vec<T> generic type lowering**: The compiler v0.49.7 emits warnings about unknown type 'T' and defaults to i64. This prevents runtime execution of code using `Vec[Float64]`, `Vec[FusedPose]`, etc. IR generation succeeds but linking fails.
2. **Cross-module `use`**: `fusion.xi` imports types from `imu.xi` and `gps.xi` via `use` declarations. These resolve correctly at compile time but generate duplicate LLVM IR symbols. A proper module system with incremental compilation would eliminate this.
3. **Function pointer arrays**: The `xiom.test` TestResult pattern with function arrays (`[t1, t2, ...]`) fails with T001 type errors in v0.49.7. Tests use direct function calls as workaround.

## Build & Test

```powershell
# Compile individual modules to IR
xiom --emit-ir src/gps.xi
xiom --emit-ir src/imu.xi
xiom --emit-ir src/fusion.xi
xiom --emit-ir src/calibration.xi

# Compile tests to IR
xiom --emit-ir tests/test_conformance.xi

# Run tests (requires Vec<T> fix)
xiom --run tests/test_conformance.xi
```
