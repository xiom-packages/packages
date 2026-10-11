# xiom.jolt

Jolt Physics (v5.6.0, MIT) bindings for XIOM. The upstream `Jolt/**` tree is
mirrored into `vendor/` by `tools/combine.py` (25 per-directory TUs + a
bridge shim) and compiled into the test binary with `--c-source`; Jolt
requires C++17, so the build needs a compiler carrying **m258**
(`--cxx-standard`, thread via `port.args.json`).

> **Status:** `incubating` -- suite **4/4 x2** on the m258 build (drop
> settles at 479 milli asleep; impulse vx=4995). **Lane:** bindings
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.jolt;

fn main() {
  let d = jolt_drop();
  if d.is_ok {
    io.println("settled (see JoltDropResult)");
  }
  let v = jolt_impulse_vx();
  if v.is_ok {
    io.println("velocity hand-off ok");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Drop | `jolt_drop` -> `JoltDropResult` (final_y_milli/awake) |
| Velocity | `jolt_impulse_vx` -> vx in milli |

Generator + pins: `SPEC.md`; toolchain requirement and verification record:
`AUDIT.md`.

## Tests

```
scripts/port.ps1 -Package xiom.jolt
```

Requires the next compiler archive (m258 `--cxx-standard`); 4 `[PASS]`,
~34 s/run (26 TUs).
