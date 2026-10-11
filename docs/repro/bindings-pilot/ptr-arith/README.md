# ptr-arith -- B-17 repro (v0.64.3)

Raw-pointer arithmetic on an XIOM-owned buffer pointer is miscompiled:
`buf.as_mut_ptr() + N` does NOT produce `base + N` -- it yields a WILD
address (unrelated heap memory).  `base + 0` is wrong too.  Keeping the
address in `Int` (`buf.as_mut_ptr() as Int + N`) is exact.

This is the ROOT CAUSE of **B-16** (`ffi.ptr_write_*` at `base + N` "loses"
writes): the write does land, just at the wrong address, so a foreign read
of the slot sees only the base write.  It also caused the batch-50
nondeterministic heap corruption described below.

## Run

Pure XIOM -- no C source, no DLL:

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi
```

## Observed (2026-10-11, v0.64.3, RTX 3070 Ti host)

```
base=1727678052592
d0=-55792          <- should be 0
d1=-54576          <- should be 1
d4=-8432           <- should be 4
d8=4912            <- should be 8
d12=5056           <- should be 12
d16=5088           <- should be 16
d24=4928           <- should be 24
d100=5040          <- should be 100
int-typed d12=12   <- Int-typed address math is CORRECT
d12-again=6400     <- second slot, second allocation: different wild value
```

The wild values differ per process (ASLR) and per allocation; only the
Int-typed control is stable.

## How it surfaced (batch 50, `xiom.sdl3` 0.13.0)

`SDL_GetAudioStreamFormat(stream, src_spec, dst_spec)` was called with
`dst = slot.as_mut_ptr() + 12` (one 24-byte slot).  The DLL then wrote the
dst spec into unowned memory: the process died with STATUS_HEAP_CORRUPTION
(`0xC0000374`, faulting module ntdll) on ~30-50 % of runs of the SAME
binary (zero stdout; C-stdio buffers lost).  A pointer-value print showed
`base + 12` = `base - 30929264`.

Bisect (same binary, 10-11 runs each): capture arm removed -> still flaky;
whole 0.13.0 block removed -> 11/11 stable; format call alone -> 7/11
crash; second open+destroy without calls -> 11/11 stable.

## Fix / guidance

- NEVER use pointer arithmetic (`p + N`, `p - N`) anywhere.  Use either:
  - separate owned slots per out-param (two `sdl3_slot(12)` buffers, one
    pointer each -- proven by the fix: 10/10 stable, both specs written), or
  - Int-typed address math `(addr + N) as *UInt8` (the loader idiom,
    proven in `xiom.sdl3`'s joystick array reads since 0.10.0).
- Byte-indexed `Vec[UInt8]` reads/writes are unaffected (B-11/B-16
  discipline stays correct).
- Shipped-workaround audit: `xiom.sdl3` 0.9.0's `SDL_GetMouseState` call
  passed `slot.as_mut_ptr() + 4` -- the y out-param was being written to a
  wild address the whole time (readback stayed 0).  Fixed in 0.13.0 with
  two 4-byte slots; probe with sentinels showed both out-params land.
