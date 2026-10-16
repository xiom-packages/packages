# ros2-abi -- record-by-value fn-cast fault (B-33) + pointer-pretend proof

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Pin: **v0.64.5** (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`), Windows x64.
Found 2026-10-16 while building `xiom.ros2` 0.2.0 (rcl's C API takes
`rcl_allocator_t` BY VALUE).

## Build

```powershell
clang -shared -O1 -o probe.dll probe.c     # LLVM clang 22, lld-link
```

The probe binaries are **not committed**; rebuild from `probe.c`.

## Cases

| Fixture | Shape | Expected | v0.64.5 result |
|---|---|---|---|
| `probe_ladder.xi` c1 | pointer to a 40-byte XIOM slot (`fn(*UInt8) -> Int` -> `probe_sum5p`) | `165` | **PASS** |
| `probe_ladder.xi` c2 | **16B record BY VALUE** (`fn(Pair2, Int) -> Int` -> `probe_sum2`) | `17036` | **FAULT** -- process exits silently, code 0, right after `c2 ... calling` |
| `probe_ladder2.xi` c3 | **16B record RETURN** (`fn(Int) -> Pair2` -> `probe_make2`) | `{507,509}` | **FAULT** -- silent exit 0 |
| `probe_pretend.xi` p1 | by-value 40B param passed with the pointer-pretend shape (`fn(*UInt8) -> Int` receiving the slot address -> `probe_sum5` whose C signature is `(Alloc5)`) | `165` | **PASS** (`165`) |
| `probe_pretend.xi` p2 | by-value 16B + scalar (`fn(*UInt8, Int) -> Int` -> `probe_sum2(Pair2,int64)`) | `17036` | **PASS** (`17036`) |
| `probe_multi.xi` m1 | 9-arg shape of `rcl_wait_set_init` (by-value allocator at arg 9) | `8186` | **PASS** (`8186`) |
| `probe_multi.xi` m2 | 7-arg shape of `rcl_timer_init2` (by-value allocator at arg 6) | `2166` | **PASS** (`2166`) |
| `probe_multi.xi` m3 | 3-arg shape of `rcl_clock_init` (by-value allocator at arg 3) | `969` | **PASS** (`969`) |

Run (edit the `probe.dll` path in the `.xi` files first):

```powershell
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
xiom --run probe_ladder.xi    # stops after "c2 ... calling" -- observed fault
xiom --run probe_pretend.xi   # p1/p2 PASS -- the workaround channel
xiom --run probe_multi.xi     # m1/m2/m3 PASS -- the exact rcl call shapes
```

## Mechanism notes

- The failing call is at the confined-block trampoline: the generated IR
  emits `call i64 %f(%struct.Alloc5 %v)` under a correct
  `x86_64-pc-windows-msvc` triple and a correct by-ref-copy lowering is
  expected from LLVM; the observed silent `exit code: 0` matches the IR fault
  path (`confined_faultN: xiom_guard_heap_exit; xiom_guard_page_disarm;
  ret i64 0`), i.e. the trap fires and the recovery path ends the program
  without a report. Marker-counting CI cannot see this class.
- The pointer-pretend channel is ABI-correct by construction where aggregate
  arguments are passed "by reference to a caller copy" (MS x64, AAPCS64):
  the callee reads the same register/stack slot for the aggregate and for a
  pointer. On x86-64 System V such aggregates are MEMORY-class and the
  channel does not apply -- `xiom.ros2` refuses those hosts typed
  (`ROS2_ABI_HOST`) instead of risking a fault.
