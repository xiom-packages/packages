# ptr-read-stale -- B-24 repro (v0.64.4)

An out-slot write performed by a **C extern call** (`poke8(slot, v)` writing
8 bytes through an owned `Vec[UInt8]` pointer) is intermittently not seen by
a subsequent `ffi.ptr_read_u64_le(slot.as_mut_ptr())` on the SAME slot: the
read returns the stale zero.  In the same run, byte-indexed reads
(`slot[i]`) over the same owned buffer always see the written value.

Observed rate in the dx12 suite: 1-2 bad reads per run across ~15 out-slot
reads; standalone probe: 1 bad read in 40 rounds (round 24); a longer
400-round probe measures the rate.  The failure position moves between
builds (per-build codegen), consistent with load reordering/alias analysis
around the extern call rather than a lost store.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
```

## Observed (2026-10-12, v0.64.4 pin, RTX 3070 Ti host)

```
ffi read  round 24: got=0 want=1024
ffi read  round 280: got=0 want=1280
ptr_read_stale: ffi_bad=2 byte_bad=0 of 400
```

(400 rounds alternating the ffi read and a byte-indexed read over the same
kind of owned slot after the same C write; the byte-indexed path never
failed.  The package-run probe uses the dx12 bridge's `xd12_poke_u64`; the
standalone `probe.xi` here uses `host.c`'s `poke8` -- the same
write-through-pointer shape.)

## How it surfaced

`xiom.dx12` 0.3.0's conformance suite reads out-slot results (COM out
pointers, sret blob pointers) with `ffi.ptr_read_u64_le(...)`.  With the
video slice linked, `CreateCommittedResource`, `D3D12SerializeRootSignature`
and `CreateCommandAllocator` reports intermittently failed with the pointer
read as 0 although the C side had returned `hr=0`; the failing line moved
between runs.  All C-side standalone probes passed, isolating the read to
the XIOM side.

## Workaround (shipped in the suite)

Use byte-indexed reads over the owned slot (`le64(slot, 0)`) -- the lane's
standard slot discipline -- instead of `ffi.ptr_read_u64_le`.  The suite is
green with byte-indexed reads.

## Classification

Same family as B-16 (owned-slot access through ffi helpers); filed as
**B-24**: ffi out-slot reads after a C extern write are not reliably
ordered/observed.
