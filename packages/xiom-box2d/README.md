# xiom.box2d

Box2D v3.1.1 physics bindings for XIOM. The upstream C sources are vendored
into `vendor/` (MIT) and compiled into the test binary with `--c-source` --
no system library, no DLL, no SDK.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2; 5/5). **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.box2d;

fn main() {
  let v = b2_version();
  io.println("Box2D " + b2_version_str(v));

  let d = b2_drop(10000, B2_DEFAULT_STEPS);   // y in milli (10.0 m)
  if d.is_ok {
    io.println("drop ok (final_y_milli=" + "see value" + ")");
  }

  let g = b2_gravity();
  if g.is_ok {
    io.println("gravity y (milli) = " + "value");
  }
}
```

Values cross the boundary as **thousandths (milli)**: `10000` = 10.0 m,
`-10000` = -10.0 m/s^2, `5000` = 5.0 N*s or m/s.

## API

| Area | Functions |
|------|-----------|
| Version | `b2_version` (packed), `b2_version_str` |
| World | `b2_gravity` -> `B2Gravity` |
| Simulation | `b2_drop(start_y_milli, steps)` -> `B2DropResult`, `b2_impulse(impulse_milli)` -> vx milli |
| Constant | `B2_DEFAULT_STEPS` (300 = 5 s at 60 Hz) |

Full details: `SPEC.md`; vendored provenance + per-file pin: `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.box2d
```

Expected: 5 `[PASS]`, exit 0. The suite runs real simulation steps
(resting drop + impulse), not only symbol resolution.
