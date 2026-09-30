<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `byte_at` vs bytes >= 128 repro (v0.61.3)

Minimal probes for the `byte_at(...)` high-byte trap. **Reproduced on the
installed v0.61.3.**

Run from the repository root:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\byte-at-128\probe_byte_at.xi
```

## The defect

Comparing `string.byte_at(...)` **directly** with a `UInt8` constant >= 128
gives the wrong result. Binding the byte to a typed local first, or widening
with `(x as Int) & 0xFF`, is correct. Documented workaround (SESSION.md
wave-31 guidance): *"Never compare `byte_at(...)` directly to a UInt8
constant >= 128; widen `(x as Int) & 0xFF`."*

## Observed on v0.61.3 (2026-09-27)

`probe_byte_at.xi` over the two-byte UTF-8 literal `"é"` (C3 A9):

```
direct b0 mismatch
direct b1 mismatch
direct b0 < 128
bad=3
```

| Check | Path | v0.61.3 observed | After the fix (expected) |
|---|---|---|---|
| `byte_at(s,0) != 195u8` | direct compare | wrong | correct |
| `byte_at(s,1) != 169u8` | direct compare | wrong | correct |
| `byte_at(s,0) < 128u8` | direct compare | wrong | correct |
| `let u0 = byte_at(s,0); u0 != 195u8` | untyped local | correct | must stay correct |
| `let b0: UInt8 = byte_at(s,0); b0 != 195u8` | typed local | correct | must stay correct |
| `(byte_at(s,0) as Int) & 255 != 195` | widen path | correct | must stay correct |

Exit code: `bad` (0 when fixed, 3 today).

## v0.62.1 re-run (2026-09-29, installed 0.62.1)

Still **reproduced**: `bad=3`, exit 3 -- the direct-comparison shape is
unchanged. The compiler-side `COMPILER_BUGS.md` item 10 ("VERIFIED FIXED,
UInt8 as Int zexts") covers the explicit `as Int` cast path (this probe's
path D, which works); the direct `byte_at(...) != 195u8` comparison stays
miscompiled. Keep the widen+mask workaround (`(x as Int) & 0xFF`).

## Compiler main fix (relay 2026-09-29)

The direct-comparison shape is **fixed on compiler main (`f4af5f64`)**;
the fix is not in v0.62.1. Re-run this probe at the next compiler
release and expect `bad=0`; only then retire the widen+mask workaround
from the wave briefs.

## v0.62.2 re-run (2026-09-30, installed 0.62.2) -- FIXED

`bad=0`, exit 0. The direct `byte_at(...) != 195u8` / `< 128u8`
comparisons are correct on **v0.62.2** (and the typed-local and
`as Int`-mask paths stayed correct). **The widen+mask workaround is
retired as of v0.62.2** -- new code may compare `byte_at` results
directly. Existing packages keep their widen+mask forms (green, no
drive-by refactors); they may simplify at their next touch.

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\byte-at-128\probe_byte_at.xi
# bad=0
```

