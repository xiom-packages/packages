# xiom.ros2 -- SPEC
**Phase**: 3 (Robotics) | **Priority**: Medium (R2 wave, 2026-10-16)
**Status**: v0.2.0 -- **delivered** (rcl loader surface; suite x2 green on the
v0.64.5 pin; live arm = typed SKIP on hosts without librcl)
**Depends on**: `xiom.ffi.dl`, `xiom.ffi`, `xiom.platform` (stdlib); ROS 2
install at run time (`librcl`), nothing at build time.

## 1. Design decision

**System-library path, not vendored** (the `xiom.ssl`/`xiom.openssl`
pattern). A ROS 2 install is a large, distro-versioned runtime (rcl + rmw +
DDS); the module ships **zero C sources**, links nothing at build time, and
resolves `librcl` entry points at run time through `xiom.ffi.dl`. The suite
reports a typed **SKIP** when no candidate soname is present, so CI without
ROS 2 stays green.

Classification (`Ros2Error.kind`):

| Kind | Meaning | Suite verdict |
|---|---|---|
| `ROS2_LOAD_ABSENT` | no candidate librcl soname loaded | SKIP (pass) |
| `ROS2_ABI_HOST` | librcl present, host ABI cannot pass by-value aggregates (x86-64 System V) | SKIP (pass, typed) |
| `ROS2_LOAD_ABI` | a candidate loaded but entry points/companion missing | FAIL |
| `ROS2_RET_FAIL` | an rcl call returned a non-OK `rcl_ret_t` | FAIL (typed, with code) |
| `ROS2_ARG_INVALID` | invalid local argument (e.g. unknown QoS preset) | FAIL (typed) |

## 2. Surface (module `xiom.ros2`, `ros2.xi`, v0.2.0)

| Count | Entity |
|------:|--------|
| 63 | `pub const` (ret-code catalog, QoS enums/presets, clock types, load kinds, layout constants) |
| 11 | `pub type` (Ros2Error, Ros2Library, context/node/pub/sub/clock/timer/wait-set/type-support handles, Ros2SpinResult) |
| 63 | `pub fn` (see groups below) |
| 175 | `requires:` clauses on public functions |
| 82 | suite checks (`tests/test_conformance.xi`), x2 green on v0.64.5 |

Groups:

- **Loader/info**: `ros2_load`, `ros2_load_named`, `ros2_close`,
  `ros2_abi_host_ok`, `ros2_sonames`, `ros2_ret_name`,
  `ros2_error_kind_name`, `ros2_qos_preset_name`.
- **Pure builders** (testable without ROS 2; the fabrication surface):
  `ros2_allocator_build`, `ros2_qos_write`, `ros2_qos_write_custom`,
  `ros2_node_options_build`, `ros2_pubsub_options_build`, `ros2_slot_u64`,
  `ros2_slot_u32`, `ros2_slot_u8`, `ros2_slot_ptr`.
- **Context**: `ros2_context_init` (optional non-default domain id),
  `ros2_context_shutdown`, `ros2_context_fini`, `ros2_context_is_valid`,
  `ros2_context_instance_id`, `ros2_context_domain_id`.
- **Node**: `ros2_node_init`, `ros2_node_fini`, `ros2_node_name`,
  `ros2_node_namespace`.
- **Type support**: `ros2_typesupport_resolve`,
  `ros2_typesupport_std_msgs_string`, `ros2_typesupport_close`.
- **Publisher**: `ros2_publisher_init`, `ros2_publisher_init_qos`,
  `ros2_publisher_fini`, `ros2_publish`.
- **Subscription**: `ros2_subscription_init`,
  `ros2_subscription_init_qos`, `ros2_subscription_fini`, `ros2_take`
  (`Ok(false)` = nothing available).
- **Clock**: `ros2_clock_init`, `ros2_clock_fini`, `ros2_clock_now_ns`.
- **Timers**: `ros2_timer_init` (private steady clock),
  `ros2_timer_init_with_clock`, `ros2_timer_fini`, `ros2_timer_call`,
  `ros2_timer_is_ready`, `ros2_timer_period_ns`,
  `ros2_timer_time_until_next_call_ns`, `ros2_timer_reset`,
  `ros2_timer_cancel`, `ros2_timer_is_canceled`, `ros2_timer_call_ptr`.
- **Wait sets**: `ros2_wait_set_init`, `ros2_wait_set_fini`,
  `ros2_wait_set_clear`, `ros2_wait_set_resize`,
  `ros2_wait_set_add_subscription`, `ros2_wait_set_add_timer`, `ros2_wait`,
  `ros2_wait_set_subscription_fired`, `ros2_wait_set_timer_fired`,
  `ros2_wait_set_is_valid`.
- **Spin** (callback-free): `ros2_spin_once` -- waits on the given
  subscription/timer slot addresses, reports which fired, runs
  `rcl_timer_call` on fired timers; message extraction stays with the caller
  via `ros2_take`.

## 3. ABI channel (pin-bound; see PROVENANCE.md + AUDIT.md)

Two compiler realities on the v0.64.5 pin shape this module:

- **Record-by-value through fn-casts faults silently (B-33).** rcl takes
  `rcl_allocator_t` BY VALUE in `rcl_init_options_init`, `rcl_clock_init`,
  `rcl_timer_init(2)` and `rcl_wait_set_init`. The module therefore uses the
  **pointer-pretend** shape everywhere: the fn-cast declares the parameter
  `*UInt8` and receives the address of an XIOM-owned 40-byte allocator slot
  (exactly what MS x64 / AAPCS64 do for >16-byte aggregates: by reference to
  a caller copy). Probe-verified locally for the 1/2/3/7/9-argument shapes
  (repro: `docs/repro/bindings-pilot/ros2-abi/`). x86-64 System V hosts are
  refused typed (`ROS2_ABI_HOST`) at load -- supported live legs are Windows
  x64 and AArch64/ARM (to re-verify on the Pi).
- **XIOM bitops on Ints >= 2^31 miscompile (B-29).** All slot I/O goes
  through the `xiom.ffi` C-side byte helpers (`ptr_write/read_*_le`), never
  `>>`/`&` on addresses; the suite pins large-value round-trips (B-29
  witness `0xBAD00000`, address-like values) as regression checks.

Transcribed layout pin (x64; oracles in PROVENANCE.md):

| Structure | Offset | Field | Oracle |
|---|---|---|---|
| `rcl_allocator_t` | 0/8/16/24/32 | allocate/deallocate/reallocate/zero_allocate/state | rcutils `allocator.h` |
| `rmw_qos_profile_t` | 0 | history (i32) | rmw `types.h` |
| | 8 | depth (u64) | |
| | 16 / 20 | reliability / durability (i32) | |
| | 24..39 | deadline {sec,nsec} (UNSPECIFIED 0,0) | |
| | 40..55 | lifespan (UNSPECIFIED) | |
| | 56 | liveliness (i32) | |
| | 64..79 | liveliness lease (UNSPECIFIED) | |
| | 80 | avoid_ros_namespace_conventions (u8) | |
| `rcl_publisher_options_t` / `rcl_subscription_options_t` | 0 / 88 | qos / allocator | rcl `publisher.h`, `subscription.h` |
| `rcl_node_options_t` | 0 | allocator (rest zeroed: no global args, no rosout) | rcl `node_options.h` |
| `rcl_context_t` | 0/8/16 | global_arguments, impl, instance_id | rcl `context.h` |
| `rcl_wait_set_t` | 0..103 | subscriptions/size, guard_conditions/size, timers/size, clients/size, services/size, events/size, impl | rcl `wait.h` |

Version matrix (checked across clones): qos-first pub/sub options order holds
on humble `b50489ad` / iron `cd6615b4` / jazzy `18d96c9c` / rolling
`e5754f0d`; the wait-set layout is identical; Humble lacks `rcl_timer_init2`
(the loader falls back to `rcl_timer_init`, autostart implicit).

## 4. Contracts

Each public function carries `requires:` clauses (175 total): handle
non-zero checks, slot-capacity checks, `timeout_ms >= 0`, `period_ms > 0`,
set-cardinality, QoS validation (KEEP_LAST depth > 0, SYSTEM_DEFAULT depth
0). None is claimed Z3-provable: `xiom-verify ros2.xi --check` runs but its
Z3 emitter rejects this module's Str-touching shapes (0 proven / 0 violated
/ 140 unknown / 410 emitter errors on v0.64.5; the shared-lane baseline
treats the Z3 column as "no" throughout). Runtime enforcement: contracts
trap in the suite-shaped paths and the pure builders are independently
pinned by golden checks.

## 5. Suite (`tests/test_conformance.xi`)

- Deterministic on every host (no ROS 2 needed): loader ABSENT
  classification via a bogus soname; kind/ret/QoS name catalogs; ABI-host
  gate expectation; allocator/QoS/options byte goldens (all transcribed
  offsets asserted); custom-QoS validation; large-value slot round-trips
  (B-29 witness); soname list text.
- Live arm (runs when librcl + host ABI are available, e.g. the Pi leg):
  context init/queries, node name/namespace read-back, std_msgs/String type
  support, pub/sub roundtrip with caller-owned message buffers, wait set
  surface, callback-free `spin_once`, steady-clock timer lifecycle, full
  teardown. Absent -> typed SKIP lines (pass).

## 6. Quality gates

- [x] Syntax/type-check on the pin (`xiom --emit-ir`, exit 0)
- [x] Suite x2 through `scripts/port.ps1 -Package xiom.ros2 -TimeoutSec 300`
- [x] ABI probes before writing the module (repro committed)
- [x] Safety audit recorded (`--sandbox`: 44 HIGH type_punning / 39 MEDIUM
      unsafe-in-public-api / 2 LOW; parity with the shipped `xiom.ssl`
      baseline 34/39 -- loader modules are fn-pointer casts by construction)
- [x] Contracts runtime-checked; Z3 emitter limitation recorded (section 4)
- [x] PROVENANCE (3 upstream clones pinned, Apache-2.0, nothing vendored)
- [x] Coverage evidence table (AUDIT.md) -- 100% of the declared surface
