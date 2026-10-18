<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-15 -- literal stores into `Vec[Float32]` slots skip narrowing

Found 2026-10-11 on compiler **v0.64.3** (lane-local) during the Q-a
quantization slice: `probe_quantization`'s constant-dimension check failed
because `c[1] = 7.0` on a local `Vec[Float32]` stored **0**, and reading the
slot back directly confirmed it. Bisected to the store lowering with the
matrix in `probe.xi`.

## Shape

| # | Code | Observed on v0.64.3 | Expected |
|---|---|---|---|
| A | `a[1] = 7.0;` (`Vec[Float32]`) | **0** (low 32 bits of the f64 constant) | 7.0 |
| B | `b[1] = 7;` (`Vec[Float32]`) | **9.80908925027372e-45** (raw int bits as an f32 pattern) | 7.0 |
| C | `var v: Float32 = 7.0; c[1] = v;` | 7.0 (control) | 7.0 |
| E | `e.data[1] = 7.0;` (`Vector.data`, struct field) | **0** | 7.0 |
| F | `f.push(7.0);` | 7.0 (control) | 7.0 |
| G | `g[1] = 7.0;` (`Vec[Float64]`) | 7.0 (control) | 7.0 |

Diagnosis: an indexed/field store into a `Vec[Float32]` element does not
insert the numeric narrowing conversion for **literal** sources. A Float64
literal stores its raw low 32 bits (7.0 = `0x401C000000000000` -> low word
`0` -> 0.0f32); an Int literal stores its raw bits as the f32 pattern (7 ->
subnormal 9.8e-45). Variables of type Float32 (or an explicit
`... as Float32`) store correctly, and `push` converts at the call
boundary. Silent data corruption wherever a float literal is written into
a float vector slot.

## Repro (revision-pinned)

```
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-f32-slot-literal-write\probe.xi -Name repro_f32_slot_literal
.\out\repro_f32_slot_literal.exe
```

Pre-fix status (v0.64.3, Windows **and WSL**, identical): exit **3** --
shapes A, B, E corrupt; controls C, F, G green. **Post-fix (v0.64.4,
m271 `f69b542e`, 2026-10-12): exit 0 on Windows + WSL -- all six shapes
narrow.**

## Workaround in the lane (retired)

Explicit narrow on literal writes (`c[1] = 7.0 as Float32;`) or write from
a typed variable. The lane's own store paths write computed Float32 values
(no literal index stores), so `probe_quantization` was the only affected
call site and carried the cast until v0.64.4. **The cast was dropped
2026-10-12** after the fix verified (23 checks green x2; the
constant-dimension assertion is now the unguarded regression line). Keep
this repro as the regression gate.
