# xiom.sensor Specification

Sensor fusion library for XIOM -- IMU orientation computation, GPS navigation, pose fusion, and sensor calibration.

---

## Module: `xiom.sensor.imu`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `IMUReading` | `accel_x`, `accel_y`, `accel_z`, `gyro_x`, `gyro_y`, `gyro_z`, `mag_x`, `mag_y`, `mag_z`, `timestamp` | Raw 9-DOF IMU data |
| `Quaternion` | `w: Float64`, `x: Float64`, `y: Float64`, `z: Float64` | Unit quaternion orientation |
| `EulerAngles` | `roll: Float64`, `pitch: Float64`, `yaw: Float64` | Tait-Bryan angles (radians) |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `imu_reading_new` | `() -> IMUReading` | Zero-initialized reading |
| `quat_identity` | `() -> Quaternion` | Identity quaternion (1, 0, 0, 0) |
| `quat_from_euler` | `(roll, pitch, yaw: Float64) -> Quaternion` | Euler-to-quaternion conversion |
| `euler_to_quat` | `(roll, pitch, yaw: Float64) -> Quaternion` | Alias for quat_from_euler |
| `quat_to_euler` | `(q: &Quaternion) -> EulerAngles` | Quaternion to Euler angles |
| `quat_multiply` | `(a: &Quaternion, b: &Quaternion) -> Quaternion` | Hamilton product |
| `quat_conjugate` | `(q: &Quaternion) -> Quaternion` | Conjugate quaternion |
| `quat_normalize` | `(q: &Quaternion) -> Quaternion` | Normalize to unit length |
| `quat_rotate_vector` | `(q: &Quaternion, vx, vy, vz: Float64) -> (Float64, Float64, Float64)` | Rotate 3D vector by quaternion |
| `imu_compute_orientation` | `(reading: &IMUReading) -> Quaternion` | Tilt-compensated orientation from accel + mag |

### Algorithm: `imu_compute_orientation`

1. Normalize accelerometer vector
2. Compute roll = `atan2(ay, az)`, pitch = `atan2(-ax, sqrt(ay2 + az2))`
3. Normalize magnetometer vector
4. Tilt-compensate magnetometer using roll and pitch
5. Compute yaw = `atan2(-mag_y_tilt, mag_x_tilt)`
6. Convert roll/pitch/yaw to quaternion

---

## Module: `xiom.sensor.gps`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `GPSFix` | `lat`, `lon`, `alt`, `hdop`, `satellites`, `fix_quality`, `timestamp` | GPS position fix |
| `GeoPoint` | `lat: Float64`, `lon: Float64`, `alt: Float64` | Geographic coordinate |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `gps_distance_m` | `(a: &GeoPoint, b: &GeoPoint) -> Float64` | Haversine distance in meters |
| `gps_bearing_deg` | `(a: &GeoPoint, b: &GeoPoint) -> Float64` | Initial bearing in degrees |
| `gps_destination` | `(point: &GeoPoint, bearing_deg: Float64, distance_m: Float64) -> GeoPoint` | Destination from bearing/distance |
| `gps_is_valid` | `(fix: &GPSFix) -> Bool` | True if fix_quality > 0 |
| `gps_to_utm` | `(lat: Float64, lon: Float64) -> (Float64, Float64, Int)` | WGS84 to UTM (easting, northing, zone) |
| `utm_to_gps` | `(easting: Float64, northing: Float64, zone: Int, southern: Bool) -> (Float64, Float64)` | UTM to WGS84 |

### Algorithms

- **Haversine distance**: Great-circle distance with 6,371 km Earth radius
- **Bearing**: Forward azimuth between two points
- **Destination**: Direct geodesic problem (spherical Earth)
- **UTM**: Full WGS84 <-> UTM conversion with zone detection, false easting/northing

---

## Module: `xiom.sensor.fusion`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `FusedPose` | `x`, `y`, `z`, `roll`, `pitch`, `yaw`, `confidence`, `timestamp` | Fused position + orientation |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `fusion_complementary` | `(imu: &IMUReading, gps: &GPSFix, alpha: Float64) -> FusedPose` | IMU/GPS complementary filter |
| `fusion_weighted` | `(poses: &Vec[FusedPose]) -> FusedPose` | Confidence-weighted pose average |
| `fusion_predict` | `(pose: &FusedPose, velocity: Float64, heading: Float64, dt: Float64) -> FusedPose` | Dead-reckoning prediction |
| `confidence_from_hdop` | `(hdop: Float64) -> Float64` | HDOP to confidence mapping (1/HDOP) |

### Algorithm: Complementary Filter

```
conf_imu = 0.7
conf_gps = max(0, 1 - HDOP/100)
confidence = alpha * conf_imu + (1-alpha) * conf_gps
```

Combines IMU orientation with GPS position using a weighted blend controlled by `alpha`.

### Algorithm: Dead Reckoning

```
heading_rad = heading * pi/180
new_lat = lat + (v * cos(heading) * dt) / R_earth
new_lon = lon + (v * sin(heading) * dt) / (R_earth * cos(lat))
confidence *= 0.95
```

---

## Module: `xiom.sensor.calibration`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `CalibrationData` | `offset_x`, `offset_y`, `offset_z`, `scale_x`, `scale_y`, `scale_z` | 3-axis calibration |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `calibration_identity` | `() -> CalibrationData` | Identity calibration (no correction) |
| `calibration_compute_offset` | `(readings: &Vec[Float64]) -> Float64` | Mean of samples |
| `calibration_apply` | `(value: Float64, cal: &CalibrationData, axis: Int) -> Float64` | Apply `value = (raw - offset) * scale` |
| `calibration_from_samples` | `(samples: &Vec[(Float64, Float64, Float64)]) -> CalibrationData` | Auto-calibrate from samples |

### Algorithm: `calibration_from_samples`

1. Compute per-axis mean (offset)
2. Compute per-axis RMS deviation from mean
3. Set scale to normalize magnitude to 1.0
4. Returns combined offset + scale calibration

---

## Contracts and verification

### Contract inventory (compiler v0.62.2)

28 clauses total: 7 `requires:` and 21 `ensures:` across 20 of the 24 public
entry points. Clauses are runtime-checked on every conformance run.

| Module | Entry point | Requires | Ensures |
|--------|-------------|----------|---------|
| gps | `gps_is_valid` | -- | `result == (fix.fix_quality > 0)` |
| gps | `gps_distance_m` | -- | `result >= 0.0` |
| gps | `gps_bearing_deg` | -- | `result >= 0.0 && result < 360.0` |
| gps | `gps_destination` | `distance_m >= 0.0` | `result.alt == point.alt` |
| gps | `gps_to_utm` | `lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0` | -- |
| gps | `utm_to_gps` | `zone >= 1 && zone <= 60` | -- |
| imu | `imu_reading_new` | -- | all 10 fields zero (`accel_*`, `gyro_*`, `mag_*`, `timestamp`) |
| imu | `quat_identity` | -- | `w == 1.0 && x == 0.0 && y == 0.0 && z == 0.0` |
| imu | `quat_normalize` | -- | zero input `=>` identity quaternion |
| imu | `quat_conjugate` | -- | `w == q.w, x == -q.x, y == -q.y, z == -q.z` |
| imu | `quat_to_euler` | -- | `-pi/2 <= result.pitch <= pi/2` |
| imu | `imu_compute_orientation` | -- | zero accel `=>` identity quaternion |
| fusion | `fusion_complementary` | `0.0 <= alpha <= 1.0` | `0.0 <= result.confidence <= 1.0` |
| fusion | `fusion_weighted` | -- | `poses.len() == 0 => result.confidence == 0.0` |
| fusion | `fusion_predict` | `dt >= 0.0` | `result.z/roll/pitch` preserved, `result.yaw == heading`; `result.confidence == pose.confidence * 0.95` |
| fusion | `confidence_from_hdop` | `hdop >= 0.0` | `0.0 <= result <= 1.0` |
| calibration | `calibration_identity` | -- | offsets `== 0.0`, scales `== 1.0` |
| calibration | `calibration_compute_offset` | -- | `readings.len() == 0 => result == 0.0` |
| calibration | `calibration_apply` | `0 <= axis <= 2` | axis 0/1/2 `=>` `(value - offset_*) * scale_*` |
| calibration | `calibration_from_samples` | -- | empty `=>` identity; `result.scale_x/y/z > 0.0` |

Multi-predicate `requires:` are a single clause (`&&`); on v0.62.2 the verifier
emits one `:named` assert per clause and duplicate names across clauses on the
same function abort the SMT run, so the predicates are merged.

### Type invariants

No `invariant:` clauses were added. The package types are plain data records:
`Quaternion` legitimately holds non-unit raw values, `GeoPoint`/`GPSFix`
construction accepts raw coordinates (and `gps_destination` may return a
longitude outside `[-180, 180]`, which is documented behavior, not an
invariant violation), and `CalibrationData` is a passive holder whose scales
are only guaranteed positive by `calibration_from_samples` -- a type-level
requirement no constructor enforces. Candidate invariants are therefore
unasserted (no wrapper semantics to enforce).

### Unasserted properties (not expressible as checkable clauses today)

- `quat_multiply`: Hamilton-product definition would restate the body;
  norm preservation needs unit-norm preconditions on both `&Quaternion`
  inputs plus a sqrt-based postcondition.
- `quat_from_euler` / `euler_to_quat`: unit-norm result (trig identity outside
  the solver fragment); alias equivalence unasserted (function calls in
  contract expressions are not supported by the verifier).
- `quat_rotate_vector`: norm preservation / rotation composition (requires a
  unit-quaternion precondition and sqrt).
- `quat_normalize` (non-zero input) and `imu_compute_orientation`: unit-norm
  result unasserted (sqrt/transcendental); the zero-input/zero-accel identity
  cases are asserted.
- `gps_distance_m`: symmetry `d(a,b) == d(b,a)` and triangle inequality
  (transcendental body; two-call equality not supported).
- `gps_bearing_deg`: inverse relation with `gps_destination` unasserted.
- `gps_destination`: lat/lon bounds unasserted -- longitude is deliberately
  not wrapped into `[-180, 180]`; altitude preservation is asserted.
- `gps_to_utm` / `utm_to_gps`: tuple component ranges (`zone` in `[1, 60]`,
  easting/northing bounds) and round-trip tolerance unasserted -- tuple
  components are not addressable in contract expressions; the zone-31
  round trip is covered by tests instead.
- `fusion_complementary`: provenance of `x/y/z/roll/pitch/yaw` depends on the
  IMU/GPS inputs; only the confidence range is asserted.
- `fusion_weighted`: per-element confidence preconditions are not expressible;
  the `sum_weight < 1e-7 => poses[0]` path returns an input unchanged, so a
  universal `result.confidence >= 0.0` clause was deliberately not added.
- `fusion_predict`: timestamp increment `pose.timestamp + (dt as Int)`
  unasserted (float-to-int cast unsupported in contract expressions).
- `calibration_compute_offset`: mean bounds (min/max of samples) unasserted
  (element-wise preconditions not expressible).
- `calibration_from_samples`: exact offset/scale values beyond empty-input
  identity and positive scales are implementation-defined.

### Solver verification status (xiom-verify + Z3, 2026-10-02)

Command (file-first argument order on v0.62.2):

```
$env:Z3_PATH = "$env:LOCALAPPDATA\xiom.new\bin\z3.exe"
& "$env:LOCALAPPDATA\xiom.new\bin\xiom-verify.exe" <file> --check
```

| File | Proven | Violated | Unknown | Errors | Exit |
|------|--------|----------|---------|--------|------|
| `src/calibration.xi` | 0 | 0 | 12 | 15 | 1 |
| `src/gps.xi` | 0 | 0 | 8 | 102 | 1 |
| `src/imu.xi` | 0 | 0 | 9 | 34 | 1 |
| `src/fusion.xi` | 0 | 2 (false positives) | 6 | 19 | 1 |
| `tests/test_conformance.xi` | -- | -- | -- | -- | not analyzable standalone (verifier does not resolve `use xiom.sensor.*` imports) |

All 28 clauses remain **solver-unproven** on v0.62.2; every clause is
runtime-checked and the full suite is green (38/38). The two reported
`fusion.xi` violations are false positives:

- `ens_confidence_from_hdop_151_1` -- the if-merge encoding leaves the
  assignment target unconstrained when the `conf > 1.0` guard is false, so
  `result` is unbounded in the SMT model. Runtime behavior is `[0.0, 1.0]`
  (tests cover HDOP 0.0, 1.0, 10.0).
- `obl_X7004` -- the division-by-zero side condition for `1.0 / hdop` is
  emitted without the `hdop <= 0.0` early-return path context, so it is
  reported violated under `requires: hdop >= 0.0` even though the guard
  makes the division unreachable for `hdop == 0.0`.

### Verifier limitations observed on v0.62.2 (not package defects)

1. **Struct selector naming.** Datatypes are declared with bare selectors
   (`(declare-datatype FusedPose ((mk-FusedPose (x Real) ...)))`) but clauses
   use `<Type>-<field>` (`(FusedPose-x result)`), yielding
   `unknown constant FusedPose-x` and SMT errors for every struct-field
   clause.
2. **Opaque references.** `&T` parameters are modeled as opaque
   `xiom_ptr_<T>` sorts, so field reads on by-reference inputs are
   unsupported (`field access '.x' on non-datatype receiver`).
3. **If-merge encoding.** Conditional assignments do not constrain the merge
   variable on the false branch (see the false-positive violation above).
4. **Path-insensitive side conditions.** X7004 division-by-zero obligations
   ignore enclosing guards (see above).
5. **Cross-module `use`.** Imported types/functions are not loaded; calls to
   `xiom.sensor.imu`/`xiom.sensor.gps` from `fusion.xi` are unmodeled and the
   conformance suite is not analyzable standalone.
6. **Multiple `requires:` clauses.** They emit duplicate `:named` asserts
   (`named expression already defined`), aborting the Z3 invocation; merged
   `&&` clauses avoid this.

A control probe on the same binary (scalar `Int`/`Float64` contracts with
merged requires, multiple implication ensures, straightforward bodies)
returned 4 proven / 0 violated, so the failures above are encoding gaps, not
a missing solver.

## Usage Examples

```xiom
use xiom.sensor.imu;
use xiom.sensor.gps;
use xiom.sensor.fusion;
use xiom.sensor.calibration;

fn main() {
  var imu = imu_reading_new();
  var q = imu_compute_orientation(&imu);
  var euler = quat_to_euler(&q);

  var p1 = GeoPoint{ lat: 48.8566, lon: 2.3522, alt: 0.0 };
  var p2 = GeoPoint{ lat: 51.5074, lon: -0.1278, alt: 0.0 };
  var dist = gps_distance_m(&p1, &p2); // ~343 km

  var cal = calibration_identity();
  var corrected = calibration_apply(0.5, &cal, 0);
}
```

---

## Design Notes

- **No FFI**: All algorithms are pure XIOM -- no hardware/FFI dependencies
- **No generics**: Concrete `Float64` and `Int` types throughout
- **While loops only**: No `for` loops per XIOM language constraints
- **Quaternion math**: Full Hamilton product, conjugation, normalization, and vector rotation
- **UTM**: Complete WGS84 <-> UTM conversion with zone auto-detection including Norway/Svalbard exceptions
- **No silent failures**: All edge cases handled (zero vectors, invalid GPS fixes, empty sample sets)

---

## Known limitations

- `calibration_apply` declares `requires: axis >= 0 && axis <= 2` (single merged clause; see `src/calibration.xi`). Passing an axis outside `[0, 2]` is a contract violation that aborts the process with a non-zero exit code; the defensive fallback `return value;` in the implementation is unreachable for contract-conforming callers. The former conformance test `test_calibration_apply_bad_axis` was removed because it deliberately violated this documented precondition; it is replaced by `test_calibration_apply_axis2`, which asserts the valid upper-bound behavior `(10.0 - 3.0) * 1.0 = 7.0`.
- `test_calibration_apply_identity_axis1` was corrected: with `calibration_identity()` the documented formula `(value - offset) * scale` gives `(5.0 - 0.0) * 1.0 = 5.0`, not the previously asserted `3.0` (which assumed a non-identity `offset_y = 2.0`).
