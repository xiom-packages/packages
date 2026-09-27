<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Sign-bit bit-ops repro (v0.61.3)

Battery for the "bit tests on values with the sign bit set are unreliable"
trap family. **No reduction has triggered on the installed v0.61.3**; every
identity is correct, including negative and wrapped values. Family evidence
is package-level: `xiom.radiotap` and `xiom.can` compute bitfields with
divisor/modulo end-to-end, and `xiom.bolt` implements FNV-1a-64 XOR as an
8-step arithmetic loop with the note "bitwise operations on values with bit
31 set are miscompiled in v0.61.3" (precautionary, inferred from the trap
list rather than observed in its own runs).

Run from the repository root:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\sign-bit-ops\probe_sign_bit.xi
```

## Checks (all correct on v0.61.3, 2026-09-27)

| Expression | Expected | Observed |
|---|---|---|
| `a & 255`, `a = 2^31 + 7` (runtime) | 7 | correct |
| `a \| 8` | 2^31 + 15 | correct |
| `a ^ 3` | 2^31 + 4 | correct |
| `h & 255`, `h = 1099511628211 * 2^20 + 5` (bit 62) | `h % 256` | correct |
| `(-1) & 255` | 255 | correct |
| `(-1) ^ 3` | -4 | correct |
| `(-2^31) & 255` | 0 | correct |
| `(-2^31) \| 1` | -2147483647 | correct |
| `(2^63 + 5) & 255` (wrapped negative) | 5 | correct |

Exit code: 0 today; 11..21 identify the first failing identity.

## What would make this a true repro

A minimal failing expression from the original `xiom.radiotap`/`xiom.can`
port (wave 24) or from a future build. Until then this probe serves as the
regression control for the family.
