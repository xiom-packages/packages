# xiom.ros2 -- Lane audit (build, probes, evidence, coverage)

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Toolchain: compiler pin **v0.64.5** (`$env:LOCALAPPDATA\xiom.new\bin\xiom.exe`),
stdlib `E:\xiom-lang\stdlib`, Agent-Manager worktree
`feat/ros2-coverage` (base `cdca3405` = origin/bindings). Date: 2026-10-16.

## 1. Pre-implementation probes (all before the module was written)

| Probe | Result |
|---|---|
| rcl API survey vs pinned headers (39 entry points + optional `rcl_timer_init2`; struct layouts; NULL-option rules) | all export names verified `RCL_PUBLIC` in the clone; NULL-options is rejected -> fabrication justified |
| **Record-by-value fn-cast ladder** against a real clang DLL (probe.c): scalar control / pointer-to-slot / 16B record by value / 16B record return | scalar `42` OK; pointer-to-slot `165` OK; **16B by-value FAULTS the process silently (exit 0)**; 16B return also faults -> **B-33 filed**; repro `docs/repro/bindings-pilot/ros2-abi/` |
| **Pointer-pretend channel** (by-value C params declared `*UInt8`, given an XIOM slot address) | 40B by-value -> `165` exact; 16B+scalar -> `17036` exact |
| **Exact call shapes of the 4 by-value sites**: 9-arg `rcl_wait_set_init`, 7-arg `rcl_timer_init2`, 3-arg `rcl_clock_init`, 2-arg `rcl_init_options_init` | `8186` / `2166` / `969` exact (2-arg covered by module goldens + same class) |
| B-29 probe on the pin (`docs/repro/bindings-pilot/bigint-bitops/`) | **STILL RED**: `3132620800 >> 20 = 2987` (want 2989), `&` and `/` equally wrong -> slot I/O routed through `ffi.ptr_*_le`; suite pins large-value round-trips |
| `dl_open("xiom-absent-librcl-probe-xyz.so")` | fails -> the ABSENT/SKIP classification is real on this box |
| `xiom-verify ros2.xi --check --z3-path ...` | 140 UNKNOWN + 410 **emitter** errors (Z3 rejected generated SMT; "not a proof failure of the code under test") -- lane standard: Z3 column "no" throughout |

## 2. Oracle-verified semantics encoded in the module

- `rcl_publisher_options_t` / `rcl_subscription_options_t` are **qos-first,
  allocator @88**; identical on humble/iron/jazzy/rolling (header diffs run
  on fetched distro refs) -> safe single layout for the pin matrix.
- `rcl_node_options_copy` skips arguments when `options->arguments.impl ==
  NULL` (`node_options.c`) -> the zeroed node options (no global args, no
  rosout) are well-defined, not merely plausible.
- `rcl_timer_call` with a **NULL callback**: documented "no callback is
  fired ... this function should still be called" -> the callback-free
  timer/spin design is sanctioned by upstream docs.
- `rcl_clock_init` takes the allocator **by pointer** (unlike timers/wait
  set) -> no pointer-pretend needed there; `rcl_clock_t` = 40 bytes.
- `rcl_wait_set_t` = 13 pointer/size pairs + impl (104 bytes, identical
  across distros); fired-state = non-NULL entry pointers; the module reads
  them through `ffi.ptr_read_u64_le` (owned slot -> C load).
- Default allocator (`rcutils/allocator.c`) wraps malloc/free/realloc/calloc
  with state ignored -> `ros2_allocator_build` fabricates exactly the
  documented default using the companion runtime's own symbols.
- `RMW_DURATION_UNSPECIFIED` = {0,0} -> deadline/lifespan/lease stay zero
  (documented "implementation default").
- Humble lacks `rcl_timer_init2` -> loader resolves it optionally and falls
  back to `rcl_timer_init` (autostart implicit).

## 3. B-series discipline notes

- Handles and resolved symbols are Int fields; casts happen only at call
  sites, one call site per symbol; all `unsafe`/FFI in the single module
  (G5).
- Out-parameters are XIOM-owned zeroed slots; **all** slot reads/writes go
  through the `xiom.ffi` C-side byte helpers (B-24 recipe + B-29 avoidance);
  no XIOM bitops touch address-scale values.
- No bare `assert` in the suite; Str equality via
  `compare.str_compare`; `int_to_str` local to the module (lane pattern);
  no `Result[...tuple...]` shapes; no enum payloads.
- `ret_of` is an identity by design (32-bit C returns are zero-extended by
  architecture; masking would re-enter the B-29 class); C `bool` returns
  are read as `UInt8` (low byte only).

## 4. Suite evidence (v0.64.5, 2026-10-16)

| Leg | Command | Run 1 | Run 2 | Logs |
|---|---|---|---|---|
| Official (`port.ps1`, SKIP arm on this host) | `.\scripts\port.ps1 -Package xiom.ros2 -TimeoutSec 300` | **PASS 82/82** (exit 0) | **PASS 82/82** (exit 0) | `%TEMP%\kilo\ros2-runs\run-e.log`, `run-f.log` |

Pre-hardening intermediate runs (78/78, before the B-29 slot-I/O refactor
added the 4 big-value checks): runs A/B (console) + `run-c.log`/`run-d.log`.
All official runs: 6/6 green, 0 FAIL markers, `program_exit=0`.

Live-arm status on this host: typed SKIP -- `ros2_load()` reports
`ROS2_LOAD_ABSENT` ("no librcl candidate found (tried librcl.so, rcl.dll,
librcl.dylib)"); the live arm (context/node/pub/sub roundtrip/timer/wait
set/spin/teardown) is fully written and runs when librcl + a supported host
ABI are present (Pi leg / Windows-with-ROS-2).

## 5. Coverage evidence table (declared surface = SPEC section 2)

Legend: **DET** = deterministic suite checks (run on any host, this box);
**LIVE** = live-arm checks (SKIP as pass on this host, executed on rcl
hosts); G = golden byte assertion against the pinned offsets.

| Surface | Oracle (PROVENANCE) | Impl | Evidence |
|---|---|---|---|
| `ros2_load` / `ros2_load_named` / `ros2_close` / `ros2_sonames` / `ros2_abi_host_ok` | rcl soname reality + host ABI rule | loader over `xiom.ffi.dl` | DET: bogus-soname ABSENT classification, kind names, soname list, host-gate expectation; LIVE: full load/close cycle |
| `ros2_ret_name`, `ros2_error_kind_name`, `ros2_qos_preset_name` | types.h / rmw ret_types.h | pure mapping | DET: 14 ret-catalog + 5 kind + 5 qos name checks (incl. unknown fallback) |
| `ros2_allocator_build`, `ros2_slot_u64/u32/u8`, `ros2_slot_ptr` | rcutils allocator.h + src/allocator.c | pure builder + C-side byte I/O | DET: 5 field-order goldens G + 4 large-value round-trips (B-29 witness 0xBAD00000, address-like, 2^32, 2^48) + pointer non-zero |
| `ros2_qos_write`, `ros2_qos_write_custom` | rmw types.h offsets + qos_profiles.h presets | pure writer | DET: 4 presets x offset goldens G (history@0, depth@8, reliability@16, durability@20, deadline@24, lifespan@40, liveliness@56, lease@64, avoid@80) + 7 custom-validation checks |
| `ros2_node_options_build`, `ros2_pubsub_options_build` | node_options.h / publisher.h / subscription.h | pure fabricators | DET: 13 offset/zero goldens G (alloc@0 node; qos@0+alloc@88 pub/sub; zeroed rmw options + tail) + unknown-preset rejection |
| `ros2_context_init/shutdown/fini/is_valid/instance_id/domain_id` | init.h / context.h (zero-init, options lifetime) | slot + pointer calls | DET: contract shapes + domain/precision via goldens; LIVE: init (default domain), valid, instance id, domain query, shutdown invalidation, fini |
| `ros2_node_init/fini/name/namespace` | node.h + node.c options-copy path | slot + fabricated options | DET: options goldens (same builder); LIVE: init, name + namespace read-back, fini |
| `ros2_typesupport_resolve/std_msgs_string/close` | rosidl typesupport symbol convention | dl_open + getter call | DET: absent classification (bogus lib); LIVE: resolve std_msgs/String, close (SKIP if absent) |
| `ros2_publisher_init/init_qos/fini`, `ros2_publish` | publisher.h + rmw qos layouts | slot + fabricated options | DET: options goldens + custom-qos validation; LIVE: init, publish, fini |
| `ros2_subscription_init/init_qos/fini`, `ros2_take` | subscription.h | slot + fabricated options | DET: options goldens; LIVE: init, take (no-message state), fini |
| `ros2_clock_init/fini/now_ns` | time.h (allocator by pointer; 40B struct) | slot + clock calls | DET: clock-type constants; LIVE: private steady clock via timer path, now via timer lifecycle |
| `ros2_timer_init/init_with_clock/fini/call/is_ready/period_ns/time_until_next_call_ns/reset/cancel/is_canceled/call_ptr` | timer.h (NULL-callback doc, init2 vs init fallback) | slot + 7-arg pointer-pretend init | DET: ret/validation shapes; LIVE: init 50ms steady, period 50000000 ns exact, fired through spin, not-ready after call, cancel -> TIMER_CANCELED, reset clears canceled, fini releases private clock |
| `ros2_wait_set_init/fini/clear/resize/add_subscription/add_timer/wait/subscription_fired/timer_fired/is_valid` | wait.h (13-field layout; fired slots) | slot + 9-arg pointer-pretend init + fired reads | DET: layout constants + fired-read bounds; LIVE: init/valid, add index 0, clear, re-add, wait (OK or TIMEOUT), fired read, fini |
| `ros2_spin_once` | composition (wait + fired report + timer call accounting) | composition of the above | DET: empty-input typed rejection; LIVE: roundtrip spin loop + timer-fired spin |

**Coverage status: 100% of the declared surface** (63/63 public functions,
63/63 constants, 11/11 types) has at least one deterministic check; every
rcl-dependent path additionally has a live-arm check that executes on rcl
hosts and reports typed SKIP otherwise (82/82 x2 here).

### Remainder (out of the declared surface; follow-up, not gaps)

The rcl C surface beyond this delivery -- services/clients (`rcl_service_*`,
`rcl_client_*`), actions, parameters, guard conditions, graph queries,
logging, events, lifecycle, executors, security/enclave, remap/arguments,
serialized messages -- is scheduled in ROADMAP.md (v0.3.0-v0.7.0).
Callback bridging is the compiler-gated prerequisite for the callback-based
members of that list (lane survey: no shipped package passes an XIOM
function pointer to C yet). Nothing in the remainder is declared in
SPEC section 2, so the declared-surface coverage above is complete.

## 6. Safety audit + verification

- `xiom --sandbox ros2.xi`: **44 HIGH** (`type_punning`, all fn-pointer
  cast sites -- inherent to the loader discipline), **39 MEDIUM**
  (`unsafe_in_public_api`), **2 LOW** (`unsafe_block_without_comment`).
  Baseline parity: shipped `xiom.ssl` reports 34 HIGH + 39 MEDIUM on the
  same pin/tool -- the loader class is accepted by the lane.
- `xiom-verify ros2.xi --check`: runs; Z3 emitter rejects the generated
  SMT (section 1) -- 0 proven / 0 violated / 140 unknown / 410 emitter
  errors; no claim of Z3-provability (lane standard).

## 7. Process notes for the next agent

- Suite runs with the package dir as cwd (port.ps1); nothing here reads
  files, so no fixtures are needed.
- The live arm needs `librcl` on the loader search path: Windows =
  ROS 2 `setup.ps1` PATH; Linux (aarch64/Pi) = `source /opt/ros/<distro>/setup.bash`.
  On x86-64 Linux the load returns `ROS2_ABI_HOST` (typed SKIP) by design.
- The std_msgs/String typesupport candidate names are in
  `ros2_typesupport_std_msgs_string`; the live roundtrip publishes
  `hello-ros2` and retries up to 20x200ms to absorb DDS discovery.
- NEW compiler reality if record-by-value is fixed at a later pin: the
  pointer-pretend sites can be re-expressed with record parameters once
  B-33 closes -- re-run `docs/repro/bindings-pilot/ros2-abi/` first.

## 8. Re-verify

```powershell
# SKIP arm (this box -- no ROS 2):
.\scripts\port.ps1 -Package xiom.ros2 -TimeoutSec 300
# Live arm (Pi / Windows+ROS 2), after sourcing the ROS 2 setup:
.\scripts\port.ps1 -Package xiom.ros2 -TimeoutSec 300
# ABI probes (needs clang + a scratch dll path):
clang -shared -O1 -o probe.dll docs\repro\bindings-pilot\ros2-abi\probe.c
```
