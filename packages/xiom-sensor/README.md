# xiom.sensor

> **Status:** `ported` -- conformance-tested (38/38); not yet published.
> **Scope:** Pure-XIOM sensor math: GPS geodesy, quaternion/attitude helpers, IMU orientation, multi-sensor fusion, and calibration.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Modules

| Module | Description |
|--------|-------------|
| `xiom.sensor.imu` | IMU readings, quaternion/Euler algebra, tilt-compensated orientation |
| `xiom.sensor.gps` | GPS validity, distance, bearing, destination, UTM conversion |
| `xiom.sensor.fusion` | Complementary and weighted fusion, confidence from HDOP |
| `xiom.sensor.calibration` | Per-axis offset/scale calibration, calibration from samples |

## Contracts

Public entry points carry `requires:`/`ensures:` contracts where expressible:
28 clauses (7 requires, 21 ensures) across 20 of the 24 public functions, plus
documented "unasserted" properties for the rest. Clauses are runtime-checked
on every conformance run. Solver (xiom-verify/Z3 on compiler v0.62.2) status
is recorded per file in SPEC.md: all clauses remain solver-unproven, and the
two `fusion.xi` "violated" reports are documented false positives from
verifier encoding gaps (references, struct selectors, path-sensitivity).

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.sensor
```

The 38 conformance tests cover geodesy, quaternion algebra, fusion, and calibration boundaries. All clauses hold at runtime for the tested inputs (38/38 green).

## Not yet implemented

- Hardware acquisition (LiDAR, camera capture) and any FFI binding; the v0.1 surface is pure computation only.

## Known limitations

- `calibration_apply` enforces `axis` in `[0, 2]` via a `requires` contract; out-of-range axes are a contract violation that aborts the run rather than silently returning the uncorrected value. The conformance suite covers the valid boundaries (axes 0, 1, 2); see SPEC.md for details.
- Contract solver coverage is limited on compiler v0.62.2 (references, struct-field results, and guarded divisions are not encoded correctly); every clause is runtime-checked and solver-unproven clauses are listed in SPEC.md.
