# xiom.jolt

Jolt Physics (v5.6.0, MIT) bindings for XIOM. The upstream `Jolt/**` tree is
mirrored into `vendor/` by `tools/combine.py` (25 per-directory TUs + a
bridge shim) and compiled into the test binary with `--c-source`; Jolt
requires C++17, carried by the pinned v0.64.4 toolchain (thread via
`port.args.json`).

> **Status:** `incubating` -- suite **24/24 x2** on the v0.64.4 pin: the
> 0.2.0 probes (drop settles at 479 milli asleep; impulse vx=4995), the
> 0.3.0 caller-usable world/body surface (engine contract v0 flow: world +
> ground + box/sphere + N fixed steps + read-back), and the 0.4.0 per-body
> external force/torque input (one-step-only semantics, angular read-back,
> unknown/removed id rejection; run record in `STATUS.json`). 0.2.0
> published in `eco-v0.1.161` (sha256 `f08d65ca...`); 0.3.0 in
> `eco-v0.1.176` (sha256 `3ac3df4e...`); **0.4.0 unpublished**.
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

External force/torque (0.4.0) targets a live dynamic body for the next step
only -- Jolt clears the accumulated input after every `Update` (repeated
calls before a step accumulate) and each call wakes a sleeping body:

```xiom
// 60 N on 1 kg => dv = 1 m/s after one 1/60 s step; 6 N.m about z spins it
let pushed = jolt_body_apply_force(w, box.value, 60000, 0, 0);
let spun = jolt_body_apply_torque(w, box.value, 0, 0, 6000);
if !pushed.is_ok {
  io.println("stale or unknown body id: " + pushed.error);
}
```

All lengths are thousandths (milli), all times microseconds, forces
milli-Newtons and torques milli Newton-metres; rotation is a quaternion in
milli (all-zero = identity). Fixed `dt` only -- no wall clock.

## API

| Area | Functions |
|------|-----------|
| Probes | `jolt_drop` -> `JoltDropResult` (final_y_milli/awake); `jolt_impulse_vx` -> vx in milli |
| World | `jolt_world_create` -> `JoltWorld` (handle/capacity/dt_micros); `jolt_world_dt_micros`; `jolt_world_destroy` -> bodies destroyed |
| Bodies | `jolt_body_add(w, JoltBodyDesc)` -> id (`JOLT_SHAPE_BOX` / `JOLT_SHAPE_SPHERE`); `jolt_body_remove` -> count left; `jolt_body_count` |
| Force input | `jolt_body_apply_force(w, id, fx_milli, fy_milli, fz_milli)` -> id; `jolt_body_apply_torque(w, id, tx_milli, ty_milli, tz_milli)` -> id (next step only; wakes the body; unknown/removed ids rejected) |
| Stepping | `jolt_step(w, dt_micros)`; `jolt_step_n(w, dt_micros, n)` |
| Read-back | `jolt_body_state(w, id)` -> `JoltBodyState` (position 3, rotation 4, linear velocity 3, angular velocity 3, awake) |

Worlds are bridge-owned: handles are registry slots, valid until
`jolt_world_destroy`; body ids are stale after `jolt_body_remove` and are
rejected. Force/torque input is one-step-only by Jolt design (cleared after
every `Update`), so re-apply per frame; the bridge integer-encodes everything
(milli/micros) and never crosses pointers. Generator + pins: `SPEC.md`;
upstream/license ledger: `PROVENANCE.md`; toolchain requirement and
verification record: `AUDIT.md`.

## Tests

```
scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600
```

24 `[PASS]` expected, x2 recorded in `STATUS.json`.
