# PROVENANCE -- xiom.box2d

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream project:** Box2D -- https://github.com/erincatto/box2d
  (MIT; the license text is vendored unmodified at `vendor/LICENSE`).
- **Declared pin (G2):** tag **v3.1.1**; tarball
  https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz
  (780,115 bytes; SHA256
  `FB6EF914B50F4312D7D921A600EABC12318BB3C55A0B8C0B90608FA4488EF2E4`).
- **Vendored artifact:** the upstream v3.1.1 `src/*.c|h` sources are copied
  byte-for-byte into `vendor/` (flat layout) and the public headers into
  `vendor/box2d/`, so the quoted includes (`"box2d/types.h"`, `"body.h"`)
  resolve against each file's own directory -- the xiom link line has no
  `-I` passthrough and the vendored bytes stay unmodified.  `vendor/LICENSE`
  is copied from upstream.  35 C sources + 6 public headers; per-file SHA256
  table in `SPEC.md` sec. 2 (`vendor/LICENSE` included).
- **Source study clone:** `E:\repos\box2d` (github.com/erincatto/box2d, MIT;
  registered in `E:\repos\CLEANUP.md`, review-after 2026-11-15, "keep for
  re-carve").  Study only -- the vendored tree comes from the pinned tag
  archive above, never from a dirty working checkout.
- **Declared surface (54 bridge entry points, 0 skips):** every `b2probe_*`
  / `b2b_*` symbol in `box2d.xi` has a public safe wrapper or an internal
  caller:

  | Bridge symbol | XIOM wrapper |
  |---|---|
  | `b2probe_version` | `b2_version` |
  | `b2probe_gravity` | `b2_gravity` |
  | `b2probe_drop` | `b2_drop` |
  | `b2probe_impulse` | `b2_impulse` |
  | `b2probe_revolute_motor` | `b2_revolute_motor` |
  | `b2probe_prismatic_motor` | `b2_prismatic_motor` |
  | `b2b_world_create` | `b2_world_create` |
  | `b2b_world_destroy` | `b2_world_destroy` |
  | `b2b_world_dt` | `b2_world_dt_micros` |
  | `b2b_body_add` | `b2_body_add` |
  | `b2b_body_remove` | `b2_body_remove` |
  | `b2b_body_count` | `b2_body_count` |
  | `b2b_body_mass` | `b2_body_mass_milli` |
  | `b2b_step` | `b2_step` |
  | `b2b_step_n` | `b2_step_n` |
  | `b2b_body_state` | `b2_body_state` |
  | `b2b_state_pos_x` | (internal: read inside `b2_body_state`) |
  | `b2b_state_pos_y` | (internal: read inside `b2_body_state`) |
  | `b2b_state_vel_x` | (internal: read inside `b2_body_state`) |
  | `b2b_state_vel_y` | (internal: read inside `b2_body_state`) |
  | `b2b_state_angle` | (internal: read inside `b2_body_state`) |
  | `b2b_state_w` | (internal: read inside `b2_body_state`) |
  | `b2b_state_awake` | (internal: read inside `b2_body_state`) |
  | `b2b_raycast` | `b2_raycast` |
  | `b2b_ray_hit` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_body` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_point_x` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_point_y` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_normal_x` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_normal_y` | (internal: read inside `b2_raycast`) |
  | `b2b_ray_fraction` | (internal: read inside `b2_raycast`) |
  | `b2b_overlap_circle` | `b2_overlap_circle` |
  | `b2b_overlap_box` | `b2_overlap_box` |
  | `b2b_overlap_fetch` | `b2_overlap` |
  | `b2b_overlap_body` | (internal: read inside `b2_overlap`) |
  | `b2b_overlap_x` | (internal: read inside `b2_overlap`) |
  | `b2b_overlap_y` | (internal: read inside `b2_overlap`) |
  | `b2b_contact_count` | `b2_contact_event_count` |
  | `b2b_contact_fetch` | `b2_contact_event` |
  | `b2b_contact_body_a` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_body_b` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_x` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_y` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_nx` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_ny` | (internal: read inside `b2_contact_event`) |
  | `b2b_contact_speed` | (internal: read inside `b2_contact_event`) |
  | `b2b_joint_add` | `b2_joint_add` |
  | `b2b_joint_remove` | `b2_joint_remove` |
  | `b2b_joint_count` | `b2_joint_count` |
  | `b2b_joint_state` | `b2_joint_state` |
  | `b2b_joint_state_kind` | (internal: read inside `b2_joint_state`) |
  | `b2b_joint_state_primary` | (internal: read inside `b2_joint_state`) |
  | `b2b_joint_state_body_a` | (internal: read inside `b2_joint_state`) |
  | `b2b_joint_state_body_b` | (internal: read inside `b2_joint_state`) |

  In addition the full vendored library compiles into the test binary (all 35
  C sources via `port.args.json`).  The bound API is a declared subset of the
  Box2D v3.1.1 C API (fixed-scenario probes + the caller 2D-solver surface),
  extended at each wave; edge/chain shapes and mouse/filter joints are
  staged (`ROADMAP.md` Phase 5).
- **Derived vs independent:** `vendor/**` is upstream code, vendored
  byte-for-byte (no edits).  `src/box2d_bridge.c`, `box2d.xi`, and `tests/`
  are original to this package; the bridge is written against the vendored
  public headers (`box2d/box2d.h`) and keeps every float/struct-by-value
  interaction inside C.  No upstream code was copied into the XIOM module.
- **Boundary discipline:** integer-only ABI (values cross as thousandths);
  no malloc/free (B-05); the 0.3.0 probes use XIOM-owned out-param slots, the
  0.4.0 caller surface is pointer-free -- state is cached bridge-side and
  fetched with dedicated scalar accessors (B-20/B-24/B-25 discipline: no
  foreign-pointer reads, no pointer casts, no bare null); handles are
  registry slots, never raw pointers; body and joint ids are per-world
  monotonic and stale ids are rejected.  Each world owns a hidden static
  anchor body as the `B2_WORLD` joint side.  Overlap lists and contact-event
  snapshots are canonicalized to ascending ids so repeated runs are
  bit-identical.  Every bridge shape enables Box2D contact + hit events
  (upstream defaults them off).
- **Link model:** static -- the vendored C sources are compiled at port time
  via `--c-source`; no DLL, no dl-load, no runtime probe.
- **License:** `vendor/` is MIT (notice retained); everything outside
  `vendor/` is MIT OR Apache-2.0.
- **Platform:** `windows-x64` declared in `STATUS.json` (compile-class,
  `runtime_deps: []`).
- **Evidence:** `tests/test_conformance.xi` (26 checks) x2 green on the
  pinned v0.64.5 toolchain; the run record (run_by/commit/checked) lives in
  `STATUS.json`.
