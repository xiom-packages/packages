# vulkan-slot-recycle -- repro for finding B-11 (OPEN, v0.64.2)

Out-param slot memory written by a Vulkan-heavy C call is recycled before
XIOM can read it. The C side is correct: the bridge's own volatile readback
inside the call shows `*size=65536` at return. The first XIOM read of the
middle slot then returns 0; byte and u32 reads can even disagree within a
single call (a concurrent/recycled write is the leading hypothesis).

## Run

```
xiom --run probe.xi --c-source <repo>/packages/xiom-vma/src/vma_bridge.cpp
```

(workdir = this directory; `vmaprobe_run` is the slot-call variant that
`xiom.vma` keeps in its bridge solely as this reproduction.)

## Observed (2026-10-09, RTX 3070 Ti host, v0.64.2)

- Expected (without the bug): `inside: a=3 b=65536 c=1 rc=0`
- Observed: `inside: a=3 b=0 c=1 rc=0` (every run; pre-filled sentinels are
  also destroyed, so it is not a stale-load)

## What does and does not reproduce

| Variant | Result |
|---|---|
| trivial C write (111/222/333) | clean |
| malloc-churn + Sleep(20) C function | clean |
| `LoadLibraryA("vulkan-1.dll")` + GetProcAddress only | clean |
| Vulkan instance + device enumeration | clean |
| full device + VMA allocator + map/verify sequence | **corrupted** |

Runtime lead: unsafe blocks install a process-wide VEH and run through a
guard arena that is discarded wholesale on exit/retry; the NVIDIA loader
spawns threads and raises/handles its own exceptions. The interaction is not
yet isolated to a single mechanism -- the evidence above is the handoff.

## Workaround

`xiom.vma` 0.2.0 ships the packed-return shape (`vmaprobe_run_packed`:
`(heap << 20) | (verify << 28) | size`, negative = `-classification`) and
reads no out-param slots from the driver-heavy call. Suite green 5/5 x2.
