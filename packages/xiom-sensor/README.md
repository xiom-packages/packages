# xiom-sensor

> Pure XIOM sensor fusion library — IMU, GPS, pose estimation, and calibration.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/XIOM-lang/XIOM.git )
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-sensor provides algorithms for robotic sensor processing:
- **IMU Processing** — 9-DOF orientation estimation, quaternion math
- **GPS Navigation** — Haversine, bearing, destination, UTM conversion
- **Sensor Fusion** — complementary filter, dead reckoning, weighted averaging
- **Calibration** — auto-calibration from sample data

## Installation

```bash
xiom install xiom-sensor
```

## Quick Start

```xiom
use xiom.sensor.imu;
use xiom.sensor.gps;
use xiom.sensor.fusion;

fn main() -> Int {
  var reading = imu_reading_new();
  var q = imu_compute_orientation(&reading);
  var euler = quat_to_euler(&q);

  var p1 = GeoPoint{ lat: 48.8566, lon: 2.3522, alt: 0.0 };
  var p2 = GeoPoint{ lat: 51.5074, lon: -0.1278, alt: 0.0 };
  var dist = gps_distance_m(&p1, &p2);

  return 0;
}
```

## API Reference

### IMU (`xiom.sensor.imu`)

| Function | Description |
|----------|-------------|
| `imu_reading_new()` | Zero-initialized IMU reading |
| `quat_identity()` | Identity quaternion |
| `quat_from_euler(roll, pitch, yaw)` | Euler to quaternion |
| `quat_to_euler(q)` | Quaternion to Euler |
| `quat_multiply(a, b)` | Hamilton product |
| `quat_conjugate(q)` | Conjugate |
| `quat_normalize(q)` | Unit normalization |
| `quat_rotate_vector(q, vx, vy, vz)` | Rotate 3D vector |
| `imu_compute_orientation(reading)` | Accel+mag orientation |

### GPS (`xiom.sensor.gps`)

| Function | Description |
|----------|-------------|
| `gps_distance_m(a, b)` | Haversine distance (meters) |
| `gps_bearing_deg(a, b)` | Initial bearing (degrees) |
| `gps_destination(point, bearing, dist)` | Project destination |
| `gps_is_valid(fix)` | Check GPS fix validity |
| `gps_to_utm(lat, lon)` | WGS84 to UTM |
| `utm_to_gps(easting, northing, zone, southern)` | UTM to WGS84 |

### Fusion (`xiom.sensor.fusion`)

| Function | Description |
|----------|-------------|
| `fusion_complementary(imu, gps, alpha)` | IMU/GPS complementary filter |
| `fusion_weighted(poses)` | Confidence-weighted average |
| `fusion_predict(pose, velocity, heading, dt)` | Dead reckoning |
| `confidence_from_hdop(hdop)` | HDOP to confidence |

### Calibration (`xiom.sensor.calibration`)

| Function | Description |
|----------|-------------|
| `calibration_identity()` | No-op calibration |
| `calibration_compute_offset(readings)` | Mean offset |
| `calibration_apply(value, cal, axis)` | Apply correction |
| `calibration_from_samples(samples)` | Auto-calibrate |

## Safety Contracts

- All quaternion operations handle zero vectors (returns identity)
- GPS distance handles identical points (returns 0)
- UTM conversion includes Norway/Svalbard zone exceptions
- Calibration handles empty sample sets (returns identity)
- Fusion handles invalid GPS fixes (downgrades confidence)

## Dependencies

- `xiom-std` (standard library)
- `xiom.math` (trigonometry: sin, cos, atan2, asin, sqrt, pow, tan)

## Build & Run

```bash
xiom --run myprogram.xi
```

## License

MIT OR Apache-2.0
