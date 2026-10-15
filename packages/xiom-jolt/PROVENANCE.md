# PROVENANCE -- xiom.jolt

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage).

- **Upstream project:** Jolt Physics -- https://github.com/jrouwe/JoltPhysics
  (MIT; the license text is vendored unmodified at `vendor/LICENSE`).
- **Declared pin (G2):** tag **v5.6.0**; tarball
  https://github.com/jrouwe/JoltPhysics/archive/refs/tags/v5.6.0.tar.gz
  (19,390,751 bytes; SHA256
  `6E069EE0172478CC78182047AAC87E5310BA14A67A53348AE14CC37801FD3F8E`).
- **Vendored artifact:** `tools/combine.py` mirrors `<upstream>/Jolt/**`
  into `vendor/Jolt/**` with exactly one textual transform --
  `#include <Jolt/...>` becomes `#include "Jolt/..."` so the quoted includes
  resolve through the compiler's include stack (the xiom link line has no
  `-I` passthrough) -- and emits one TU per source directory
  (`vendor/jolt_tu_*.cpp`, 25 of them) plus a shim (`vendor/jolt_bridge.cpp`)
  that compiles the reviewable bridge from `src/`.  `vendor/LICENSE` is
  copied from upstream.  No upstream file is edited beyond the include
  rewrite.
- **Generated tree sha256** (generator `tree_hash`, LICENSE excluded;
  re-verified read-only 2026-10-13 with the generator's own function, matches
  the 0.2.0 vendoring prefix `ea20c2d1...`):
  `ea20c2d1f1f2a16e1fa62efeff5804c9d7b47f51812eefb8ed9ddb4330d6b69b`.
  Re-pin procedure: `SPEC.md` sec. 2.
- **Source study clone:** `E:\repos\JoltPhysics` (MIT; registered in
  `E:\repos\CLEANUP.md`, review-after 2026-12-01).  Study only -- the pinned
  artifact above is the tarball; the vendored tree is never regenerated from
  a dirty working checkout.
- **Declared surface (100% bound):** the package binds **61** bridge entry
  points, every one with a public safe wrapper or an internal caller in
  `jolt.xi` (0 skips):

  | Bridge symbol | XIOM wrapper |
  |---|---|
  | `joltprobe_drop` | `jolt_drop` |
  | `joltprobe_awake` | (internal: read inside `jolt_drop`) |
  | `joltprobe_impulse` | `jolt_impulse_vx` |
  | `joltb_world_create` | `jolt_world_create` |
  | `joltb_world_destroy` | `jolt_world_destroy` |
  | `joltb_world_dt` | `jolt_world_dt_micros` |
  | `joltb_body_add` | `jolt_body_add` |
  | `joltb_body_add_sensor` | `jolt_body_add_sensor` |
  | `joltb_body_remove` | `jolt_body_remove` |
  | `joltb_body_count` | `jolt_body_count` |
  | `joltb_body_apply_force` | `jolt_body_apply_force` |
  | `joltb_body_apply_torque` | `jolt_body_apply_torque` |
  | `joltb_step` | `jolt_step` |
  | `joltb_step_n` | `jolt_step_n` |
  | `joltb_body_state` | `jolt_body_state` |
  | `joltb_state_pos` | (internal: read inside `jolt_body_state`) |
  | `joltb_state_rot` | (internal: read inside `jolt_body_state`) |
  | `joltb_state_vel` | (internal: read inside `jolt_body_state`) |
  | `joltb_state_wvel` | (internal: read inside `jolt_body_state`) |
  | `joltb_state_awake` | (internal: read inside `jolt_body_state`) |
  | `joltb_raycast_closest` | `jolt_raycast` (via internal `jolt_hit_result`) |
  | `joltb_raycast_any` | `jolt_raycast_any` (via internal `jolt_hit_result`) |
  | `joltb_sweep_sphere_closest` | `jolt_sweep_sphere` (via internal `jolt_hit_result`) |
  | `joltb_sweep_capsule_closest` | `jolt_sweep_capsule` (via internal `jolt_hit_result`) |
  | `joltb_overlap_sphere` | `jolt_overlap_sphere` |
  | `joltb_overlap_capsule` | `jolt_overlap_capsule` |
  | `joltb_overlap_fetch` | `jolt_overlap` |
  | `joltb_overlap_body` | (internal: read inside `jolt_overlap`) |
  | `joltb_overlap_pos` | (internal: read inside `jolt_overlap`) |
  | `joltb_query_hit` | (internal: read inside `jolt_hit_result`) |
  | `joltb_query_body` | (internal: read inside `jolt_hit_result`) |
  | `joltb_query_pos` | (internal: read inside `jolt_hit_result`) |
  | `joltb_query_nrm` | (internal: read inside `jolt_hit_result`) |
  | `joltb_query_fraction` | (internal: read inside `jolt_hit_result`) |
  | `joltb_contact_count` | `jolt_contact_count` |
  | `joltb_contact_fetch` | `jolt_contact` |
  | `joltb_contact_point_fetch` | `jolt_contact_point` |
  | `joltb_contact_pair_count` | `jolt_contact_pair_count` |
  | `joltb_contact_body_a` | (internal: read inside `jolt_contact`) |
  | `joltb_contact_body_b` | (internal: read inside `jolt_contact`) |
  | `joltb_contact_point_count` | (internal: read inside `jolt_contact`) |
  | `joltb_contact_normal` | (internal: read inside `jolt_contact`) |
  | `joltb_contact_depth_micros` | (internal: read inside `jolt_contact`) |
  | `joltb_contact_point` | (internal: read inside `jolt_contact`/`jolt_contact_point`) |
  | `joltb_sensor_event_count` | `jolt_sensor_event_count` |
  | `joltb_sensor_event_fetch` | `jolt_sensor_event` |
  | `joltb_sensor_event_sensor` | (internal: read inside `jolt_sensor_event`) |
  | `joltb_sensor_event_other` | (internal: read inside `jolt_sensor_event`) |
  | `joltb_sensor_overlap_count` | `jolt_sensor_overlap_count` |
  | `joltb_body_add_convex` | `jolt_body_add_convex` |
  | `joltb_body_add_compound` | `jolt_body_add_compound` |
  | `joltb_joint_add` | `jolt_joint_add` |
  | `joltb_joint_remove` | `jolt_joint_remove` |
  | `joltb_joint_count` | `jolt_joint_count` |
  | `joltb_joint_set_motor` | `jolt_joint_set_motor` |
  | `joltb_joint_state` | `jolt_joint_state` |
  | `joltb_joint_state_kind` | (internal: read inside `jolt_joint_state`) |
  | `joltb_joint_state_primary` | (internal: read inside `jolt_joint_state`) |
  | `joltb_joint_state_impulse` | (internal: read inside `jolt_joint_state`) |
  | `joltb_joint_state_body_a` | (internal: read inside `jolt_joint_state`) |
  | `joltb_joint_state_body_b` | (internal: read inside `jolt_joint_state`) |

  In addition the full vendored library compiles into the test binary (all
  25 per-directory TUs).  The world/body surface is a declared v0 subset
  (engine contract flow + query/contact/sensor/joint tiers + convex/compound
  shapes), not the full Jolt API -- a binding-subset declaration like
  `xiom.sqlite`, extended at each wave.
- **Derived vs independent:** `vendor/Jolt/**` is upstream code (compiled
  unmodified except the include rewrite).  `src/jolt_bridge.cpp`,
  `tools/combine.py`, `jolt.xi`, and `tests/` are original to this package;
  the bridge is written against the vendored public headers and follows the
  upstream HelloWorld registration pattern (RegisterDefaultAllocator +
  Factory + RegisterTypes).  No upstream code was copied into the XIOM
  module.
- **Boundary discipline:** integer-only ABI (milli/micros; forces milli-N,
  torques milli-N.m); handles are registry indices, never raw pointers
  (B-25); no bare `null` crosses (B-23); XIOM never reads through foreign
  pointers -- state is cached bridge-side and fetched as scalars
  (B-20/B-24); no out-param slots.  Force/torque input uses Jolt's
  `BodyInterface::AddForce`/`AddTorque` (center of mass, `EActivation::
  Activate`); Jolt clears the accumulators after every `Update`, and unknown
  or removed body ids are rejected before the Jolt call.  Query shapes are
  temporary and owned by `RefConst<Shape>` (Jolt shapes start at refcount 0;
  a raw `Release()` would assert), results land in bridge-owned caches
  (POD storage only -- no non-trivial globals), and every list surface is
  canonicalized to ascending packed body id (deterministic broadphase
  order).  Contact/sensor caches are rebuilt per step from a
  `ContactListener` (bounded: 2048 manifolds / 1024 events, <= 8 points per
  manifold).  Joints (0.6.0) are owned by a per-world `Ref<Constraint>`
  registry (one owned slot per joint; ids are bridge-assigned and stale ids
  are rejected); body-world joints use Jolt's `Body::sFixedToWorld`, never a
  caller pointer; the hull/part vertex buffers cross as one `Vec.as_ptr()
  as Int` address per call and are copied into bridge-owned shapes (the
  caller's Vec remains the owner); B-27 keeps the address cast in its own
  confined block, one cast per block.
- **Link model:** static -- the vendored C++ sources are compiled at port
  time via `--c-source` (`--cxx-standard 17`); no DLL, no dl-load, no
  runtime probe.
- **License:** `vendor/` is MIT (notice retained); everything outside
  `vendor/` is MIT OR Apache-2.0.
- **Evidence:** `tests/test_conformance.xi` (109 checks) x2 green on the
  pinned v0.64.4 toolchain; the run record (run_by/commit/checked) lives in
  `STATUS.json`.
