# xiom.jolt

Jolt Physics (v5.6.0, MIT) bindings for XIOM. The upstream `Jolt/**` tree is
mirrored into `vendor/` by `tools/combine.py` (25 per-directory TUs + a
bridge shim) and compiled into the test binary with `--c-source`; Jolt
requires C++17, carried by the pinned v0.64.4 toolchain (thread via
`port.args.json`).

> **Status:** `incubating` -- suite **18/18 x2** on the v0.64.4 pin: the
> 0.2.0 probes (drop settles at 479 milli asleep; impulse vx=4995) plus the
> 0.3.0 caller-usable world/body surface (engine contract v0 flow: world +
> ground + box/sphere + N fixed steps + read-back; run record in
> `STATUS.json`). 0.2.0 published in `eco-v0.1.161` (sha256 `f08d65ca...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.jolt;

fn main() {
  // Probes (0.2.0)
  let d = jolt_drop();
  if d.is_ok {
    io.println("settled (see JoltDropResult)");
  }

  // World/body surface (0.3.0): world + ground + falling box + N steps + read-back
  let wr = jolt_world_create(0, -9810, 0, 16666, 64);
  if wr.is_ok {
    let w = wr.value;
    let ground = jolt_body_add(w, JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 20000;
      ey_milli: 500;
      ez_milli: 20000;
      mass_milli: 0;
      px_milli: 0;
      py_milli: -500;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: true;
    });
    let box = jolt_body_add(w, JoltBodyDesc{
      shape: JOLT_SHAPE_BOX;
      ex_milli: 500;
      ey_milli: 500;
      ez_milli: 500;
      mass_milli: 0;
      px_milli: 0;
      py_milli: 5000;
      pz_milli: 0;
      rx_milli: 0;
      ry_milli: 0;
      rz_milli: 0;
      rw_milli: 0;
      is_static: false;
    });
    let stepped = jolt_step_n(w, 16666, 300);
    if stepped.is_ok && box.is_ok {
      let st = jolt_body_state(w, box.value);
      if st.is_ok {
        io.println("box y (milli)");
      }
    }
    let gone = jolt_world_destroy(w);
  }
}
```

All lengths are thousandths (milli) and all times microseconds; rotation is
a quaternion in milli (all-zero = identity). Fixed `dt` only -- no wall
clock.

## API

| Area | Functions |
|------|-----------|
| Probes | `jolt_drop` -> `JoltDropResult` (final_y_milli/awake); `jolt_impulse_vx` -> vx in milli |
| World | `jolt_world_create` -> `JoltWorld` (handle/capacity/dt_micros); `jolt_world_dt_micros`; `jolt_world_destroy` -> bodies destroyed |
| Bodies | `jolt_body_add(w, JoltBodyDesc)` -> id (`JOLT_SHAPE_BOX` / `JOLT_SHAPE_SPHERE`); `jolt_body_remove` -> count left; `jolt_body_count` |
| Stepping | `jolt_step(w, dt_micros)`; `jolt_step_n(w, dt_micros, n)` |
| Read-back | `jolt_body_state(w, id)` -> `JoltBodyState` (position 3, rotation 4, velocity 3, awake) |

Worlds are bridge-owned: handles are registry slots, valid until
`jolt_world_destroy`; body ids are stale after `jolt_body_remove` and are
rejected. Generator + pins: `SPEC.md`; upstream/license ledger:
`PROVENANCE.md`; toolchain requirement and verification record: `AUDIT.md`.

## Tests

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

18 `[PASS]` expected, x2 recorded in `STATUS.json`.
