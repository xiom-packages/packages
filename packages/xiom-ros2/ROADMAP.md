# xiom.ros2 Roadmap

## Current State -- v0.2.0 (delivered 2026-10-16)

| Component | Status | Notes |
|-----------|--------|-------|
| Loader | Done | Multi-soname (`librcl.so` / `rcl.dll` / `librcl.dylib`), 39 required + 1 optional entry points + C-runtime companion; typed ABSENT/ABI/HOST classification |
| Init / Shutdown | Done | `rcl_init_options_init`/`set_domain_id`/`fini` + `rcl_init` + `rcl_shutdown` + `rcl_context_fini`; default or explicit domain id |
| Context | Done | validity, instance id, domain id queries |
| Node | Done | init/fini + name/namespace read-back; options fabricated (no global args, no rosout -- documented) |
| Publisher | Done | preset + custom QoS; publish with caller-owned message buffers |
| Subscription | Done | preset + custom QoS; take with caller-owned buffers (typed no-message state) |
| Clock | Done | steady/system/ros clock init/fini + now |
| Timers | Done | private or shared clock; NULL-callback design (rcl-documented); call/is_ready/period/time-until/cancel/reset |
| Wait sets | Done | init/fini/clear/resize/add subscription+timer/wait/fired reads/is_valid |
| Spin | Done | callback-free `ros2_spin_once` (wait + fired report + timer call accounting) |
| Type support | Done | generic resolve (soname+getter symbol) + std_msgs/String convenience |
| QoS | Done (core) | presets + custom history/depth/reliability/durability/liveliness; deadline/lifespan/lease pinned to RMW_DURATION_UNSPECIFIED |
| C bridge | Not needed | superseded by the dynamic-loader discipline (zero vendored C) |

### Contracts Coverage

- 63 public functions, 175 `requires:` clauses; validation on all handle and
  buffer parameters; QoS cross-field rules enforced.
- Z3-provable: none claimed (verifier emitter limitation on this pin;
  runtime-checked by the suite) -- lane standard.

### Test Coverage

- 82 checks in `tests/test_conformance.xi`, x2 green on v0.64.5 (SKIP arm on
  hosts without librcl; the live arm is written and runs when available --
  Pi leg).
- Coverage evidence table: AUDIT.md section "Coverage evidence".

---

## v0.3.0 -- Callback bridging (compiler-gated)

- [ ] C function-pointer bridging in the FFI (lane survey: no shipped
      package passes an XIOM fn pointer to C yet) -- then subscription
      callbacks (`rcl_subscription_init` callback slot) and timer callbacks
      (`rcl_timer_init2`), plus `rclc`-style executor spin.
- [ ] Guard conditions (`rcl_guard_condition_init/trigger/fini`; options
      by value -> pointer-pretend, already proven) + wait-set
      add_guard_condition.

## v0.4.0 -- Services / clients

- [ ] `rcl_service_init/fini`, `rcl_take_request`, `rcl_send_response`;
  `rcl_client_init/fini`, `rcl_send_request`, `rcl_take_response`
  (same loader discipline; request/response buffers are caller-owned).

## v0.5.0 -- QoS remainder + parameters

- [ ] Deadline / lifespan / liveliness-lease writes (offsets already
      pinned in SPEC section 3; needs only value plumbing + tests).
- [ ] Parameter server wrappers (needs the typesupport/rcl_interfaces
      layer; design pass first).

## v0.6.0 -- Actions / lifecycle / TF

- [ ] Actions (`rcl_action_*` graph + goal handles; needs callback
      decisions), lifecycle nodes, TF2 buffer/listener.

## v0.7.0 -- Serialisation & message types

- [ ] std_msgs helpers for the common primitives using caller-owned
      buffers (String lands in the live suite already); custom `.msg`/`.idl`
      codegen pass.

## v1.0.0 -- Stable

- [ ] Full declared surface + distro matrix verified live (Humble/Iron/
      Jazzy; `rcl_timer_init` fallback re-verified on Humble hardware).
- [ ] 90%+ coverage on all modules; formal contract verification once the
      Z3 emitter handles Str-touching shapes; cross-platform CI.

---

## Backlog / Future

| Feature | Priority | Notes |
|---------|----------|-------|
| Actions (goal-oriented) | Medium | after callbacks land |
| Lifecycle nodes | Medium | managed node states |
| TF2 transforms | High | separate `xiom.tf2` package candidate |
| Composition | Medium | `rclcpp_components` is out of the C surface |
| Intra-process comms | Low | rmw-level, not rcl |
| Launch system | Low | `.launch.py` generation |
| RViz / rosbag2 | Low | ecosystem tools, not core bindings |

---

## Dependency Graph

```
xiom.ros2 (this package)
  |-- xiom-std (string, collections, ptr)
  |-- xiom.ffi.dl (runtime symbol resolution; no build-time link)
  |-- librcl + rmw + DDS (system-installed at run time)
  `-- typesupport libs resolved per message package (e.g. std_msgs)
```

## Version matrix / ABI pin

ABI layouts pinned to rcl rolling `e5754f0d` + rmw `4158e1ed` + rcutils
`0f55f24e` (SPEC section 3; humble/iron/jazzy header diffs checked -- qos
order + wait-set layout stable; Humble timer fallback in the loader).
Re-carve: re-verify the offsets + entry-point set against the target
distro's headers and update SPEC/PROVENANCE in one commit.
