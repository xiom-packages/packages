# xiom.box2d

Box2D v3.1.1 physics bindings for XIOM. The upstream C sources are vendored
into `vendor/` (MIT) and compiled into the test binary with `--c-source` --
no system library, no DLL, no SDK.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.5; native 26/26 x2; 0.4.0 adds the caller 2D-solver surface: world/
> bodies/step/state, broadphase queries, contact events and the remaining
> tractable joint types; 0.3.0 added revolute + prismatic joint motors with
> wrapped-angle semantics). 0.2.0 shipped in `eco-v0.1.123` (sha256
> `314568d7...`); 0.3.0 published in `eco-v0.1.157` (sha256 `3c2ebda1...`).
> **Lane:** bindings (`keywords: ["binding"]`).

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
| Fixed scenarios | `b2_drop(start_y_milli, steps)` -> `B2DropResult`, `b2_impulse(impulse_milli)` -> vx milli, `b2_revolute_motor(...)`, `b2_prismatic_motor(...)` |
| Caller surface (0.4.0) | `b2_world_create(gx, gy, dt_micros, capacity)` / `b2_world_destroy` / `b2_world_dt_micros`; `b2_body_add(B2BodyDesc)` / `b2_body_remove` / `b2_body_count` / `b2_body_mass_milli`; `b2_step` / `b2_step_n`; `b2_body_state` -> `B2State` |
| Queries (0.4.0) | `b2_raycast` -> `B2RayHit`; `b2_overlap_circle` / `b2_overlap_box` / `b2_overlap` -> `B2Overlap` |
| Contacts (0.4.0) | `b2_contact_event_count` / `b2_contact_event` -> `B2ContactEvent` (begin/end/hit) |
| Joints (0.4.0) | `b2_joint_add(B2JointDesc)` / `b2_joint_remove` / `b2_joint_count` / `b2_joint_state`; kinds revolute/prismatic/weld/distance/wheel/motor; `B2_WORLD` = the static world side |
| Constant | `B2_DEFAULT_STEPS` (300 = 5 s at 60 Hz) |

The 0.4.0 surface is pointer-free: state is cached bridge-side and read back
as fresh milli values (no out-param slots). Full details: `SPEC.md`; vendored
provenance + per-file pin: `SPEC.md` §2, `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.box2d
```

Expected: 26 `[PASS]`, exit 0. The suite runs real simulation steps (resting
drop + impulse + motor-driven revolute/prismatic joints + world/body/step/
state flows, raycast/overlap queries, contact begin/hit/end events and
weld/distance/wheel/motor joints), not only symbol resolution.
