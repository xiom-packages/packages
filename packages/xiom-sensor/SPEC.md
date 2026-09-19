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
