# xiom.sensor

> **Status:** `ported` -- conformance-tested on compiler v0.61.3 (38/38); NOT published yet.
> **Scope:** Pure-XIOM sensor math: GPS geodesy, quaternion/attitude helpers, IMU orientation, multi-sensor fusion, and calibration.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Modules

| Module | Description |
|--------|-------------|
| `xiom.sensor.imu` | IMU readings, quaternion/Euler algebra, tilt-compensated orientation |
| `xiom.sensor.gps` | GPS validity, distance, bearing, destination, UTM conversion |
| `xiom.sensor.fusion` | Complementary and weighted fusion, confidence from HDOP |
| `xiom.sensor.calibration` | Per-axis offset/scale calibration, calibration from samples |

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.sensor
```

The 38 conformance tests cover geodesy, quaternion algebra, fusion, and calibration boundaries.

## Not yet implemented

- Hardware acquisition (LiDAR, camera capture) and any FFI binding; the v0.1 surface is pure computation only.

## Known limitations

- `calibration_apply` enforces `axis` in `[0, 2]` via a `requires` contract; out-of-range axes are a contract violation that aborts the run rather than silently returning the uncorrected value. The conformance suite covers the valid boundaries (axes 0, 1, 2); see SPEC.md for details.
