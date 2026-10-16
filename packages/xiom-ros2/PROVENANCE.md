# xiom.ros2 -- Provenance

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

## Upstream (oracles, not vendored)

All three clones are **Apache-2.0** (LICENSE verified in-clone), read-only
declaration oracles; nothing is copied into this repository.

| Project | Clone | Pin | License | Use |
|---|---|---|---|---|
| ros2/rcl | `E:\repos\rcl` (shallow, `--depth 1`) | **rolling `e5754f0d6fa3313669271a76e116bf9b01ba7f15`** (2026-10-10) | Apache-2.0 | `rcl/include/rcl/*.h` entry-point names/signatures; struct layouts (`context.h`, `node_options.h`, `publisher.h`, `subscription.h`, `timer.h`, `wait.h`, `time.h`, `types.h`); semantics from `src/rcl/{node,node_options,wait,timer,arguments}.c` |
| ros2/rcutils | `E:\repos\rcutils` (shallow) | **rolling `0f55f24e9baa0640b2335b690ba96207852e2cb4`** (2026-10-13) | Apache-2.0 | `include/rcutils/allocator.h` struct layout; `src/allocator.c` default-allocator semantics (wraps malloc/free/realloc/calloc, state NULL) |
| ros2/rmw | `E:\repos\rmw` (shallow) | **rolling `4158e1ed0edb9ba4723619b156ce90a2a19b36e3`** (2026-09-25) | Apache-2.0 | `include/rmw/types.h` (rmw_qos_profile_t layout + enum values), `qos_profiles.h` presets, `ret_types.h` codes |
| ros2/rcl distro branches (same clone) | fetched refs `origin-distro/{humble,iron,jazzy}` | humble `b50489ad`, iron `cd6615b4`, jazzy `18d96c9c` | Apache-2.0 | version matrix: qos-first pub/sub options order + wait-set layout stable; Humble lacks `rcl_timer_init2` (fallback) |

Commits are recorded here per the clone protocol (repo `CLEANUP.md` rows
registered: rcl/rcutils/rmw, review-after 2026-12-15, use = xiom.ros2
re-carve oracle).

## Files studied (declaration oracle)

| Oracle file | What was taken |
|---|---|
| `rcl/include/rcl/types.h` + `rmw/include/rmw/ret_types.h` | the `rcl_ret_t` catalog transcribed into constants (`RCL_RET_OK`..`RCL_RET_WAIT_SET_FULL`) |
| `rcl/include/rcl/init.h`, `init_options.h`, `context.h` | `rcl_init`/`rcl_shutdown`/`rcl_context_*` prototypes; `rcl_context_t` layout; zero-init-by-construction rationale |
| `rcl/include/rcl/node.h`, `node_options.h` + `src/rcl/node.c`, `node_options.c` | `rcl_node_t`/options layouts; options copy path (`arguments.impl == NULL` -> no copy) that makes the zeroed-arguments fabrication safe |
| `rcl/include/rcl/publisher.h`, `subscription.h` + `src/rcl/publisher.c` | options layouts (**qos first**, allocator @88); NULL-options is rejected -> fabrication; publish/take prototype shapes |
| `rcl/include/rcl/timer.h`, `time.h` | `rcl_timer_init2` (rolling) vs `rcl_timer_init` (humble); NULL-callback semantics ("no callback is fired ... should still be called"); `rcl_clock_t` layout; `rcl_clock_init` takes the allocator **by pointer** |
| `rcl/include/rcl/wait.h` + `src/rcl/wait.c` | `rcl_wait_set_t` layout (13 fields); init validates allocator + context; per-entity pointer slots read as fired-state |
| `rmw/include/rmw/types.h`, `qos_profiles.h` | `rmw_qos_profile_t` field offsets + enum values (history/reliability/durability/liveliness) and the preset definitions re-encoded in `ros2_qos_write` (default/sensor-data/parameters); `RMW_DURATION_UNSPECIFIED {0,0}` |
| `rcutils/include/rcutils/allocator.h`, `src/allocator.c` | `rcutils_allocator_t` = 5 pointers {allocate, deallocate, reallocate, zero_allocate, state}; the default allocator wraps malloc/free/realloc/calloc with state ignored -- exactly the `ros2_allocator_build` fabrication |

**Derived vs independent:** the *constants, offsets and prototypes* are
transcribed from the pinned headers (each one asserted by a suite golden
where readable). The *code* is independent: hand-written XIOM wrappers over
resolved symbols, XIOM-owned byte slots, fabricated default structures, and
typed-error classification -- no C is compiled, nothing is linked at build
time, and no upstream source file is copied.

## Compiler realities pinned by this package (evidence committed)

- **B-33**: record-by-value through fn-cast calls faults silently on
  v0.64.5; the module uses the pointer-pretend channel
  (`docs/repro/bindings-pilot/ros2-abi/` -- local DLL probes for the
  1/2/3/7/9-arg shapes, exact values recorded).
- **B-29**: XIOM bitops on Ints >= 2^31 miscompile on this pin; slot I/O is
  routed through the `xiom.ffi` C-side byte helpers and the suite pins
  large-value round-trips (0xBAD00000 witness + address-like values).

## Test fixtures

None beyond the suite itself (the live roundtrip builds its std_msgs/String
message in an XIOM-owned slot; no upstream data or secrets are used).

## Re-carve procedure

1. `git fetch` the target distro branch/tag in `E:\repos\rcl` (and the
   matching rcutils/rmw) and re-verify: entry-point set (39 + optional
   `rcl_timer_init2`), option-struct field order, `rmw_qos_profile_t`
   offsets, wait-set layout.
2. Update `ros2.xi` constants/builders + SPEC section 3 + this file in one
   commit; run the suite x2 (SKIP arm is enough on dev hosts; the live arm
   must be re-run on the Pi/Windows legs).
3. Update the CLEANUP.md pin rows.

## Rejected alternatives (recorded)

- **Vendoring a C bridge (`ros2_bridge.c`)**: rejected -- the lane's
  dynamic-loader doctrine (`xiom.ssl`) ships zero C; a shim would add a
  build step and a per-distro compile matrix for what pointer-pretend
  already conveys.
- **Depending on `librclc` for support/executor helpers**: rejected -- rclc
  is not part of a stock ROS 2 install; `librcl` alone is the portable
  floor. (Humble `rcl_timer_init` fallback covers the older ABI.)
- **Calling struct-returning helpers** (`rcl_get_default_allocator`,
  `rcl_*_get_default_options`, `rcl_get_error_string`): rejected -- sret
  calls are not expressible through portable fn-casts (x8 hidden-pointer on
  AArch64) and their by-value twins fault (B-33); defaults are fabricated
  from the pinned layouts instead and error strings are mapped ret codes.
- **Fabricating the allocator from `ucrtbase`/`msvcrt`/`libc` malloc
  family**: retained only as the companion-resolution step -- the exported
  addresses ARE the documented default allocator (rcutils wraps exactly
  these four functions with state ignored), so the fabricated struct is
  the default allocator by construction on any dynamic-CRT host.
- **Attempting live calls on x86-64 System V anyway**: rejected -- typed
  `ROS2_ABI_HOST` refusal beats heap corruption.
