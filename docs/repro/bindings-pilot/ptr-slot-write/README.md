# ptr-slot-write -- B-16 repro (v0.64.3)

`ffi.ptr_write_*` into an XIOM-owned byte slot at a NON-ZERO offset
(`buf.as_mut_ptr() + 4`) does not land; only the write at the base pointer
survives. Byte-indexed stores (the lane's standard slot discipline) work.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
```

## Observed (2026-10-11, v0.64.3, RTX 3070 Ti host)

```
ptr_write_sum=11      <- only the u32 at offset 0 landed (11 + 0 + 0)
byte_index_sum=66     <- byte-indexed writes: 11 + 22 + 33
```

## How it surfaced

`ixom.sdl3` 0.12.0 built the 12-byte `SDL_AudioSpec` ({format, channels,
freq}) with three `ffi.ptr_write_u32_le` calls; the runtime rejected it
("Parameter 'src_spec->channels' is invalid" -- SDL read garbage/0 at the
+4 field). Switching to byte-indexed stores (`sdl3_write_u32_le`) made the
same call succeed (7680 B queued, device resumed). A same-block-first-write
survival pattern matches this probe's `11`.

## Impact / guidance

- Never build foreign in-params with `ptr_write_*` at `base + N`; use
  byte-indexed stores into a `Vec[UInt8]` (or write on the C side).
- The lane's B-11 discipline (byte slots + byte-wise reads/writes) remains
  correct; this is the write-side counterpart of that family.
- Also verified on the earlier side: with only the offset-0 write landing,
  a foreign call still sees the OTHER fields as zeros -- silent, no trap.
