<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `Vec[Float64]` + bitcast probe (v0.62.2)

Split follow-up to the 2026-09-26 finding "No `Vec[Float64]`; no
`Int <-> Float64` bitcast" (blocking float-bearing formats from full
fidelity; `avro`/`mkv`/`amqp` expose floats as raw LE octets).

## Result (2026-10-03, installed v0.62.2)

| Half | Status |
|---|---|
| `Vec[Float64]` (push / len / indexed compare / arithmetic) | **WORKS** -- `len=3`, `v0>1`, `v1<0`, `sum<0` |
| `Int <-> Float64` bitcast | **STILL MISSING** -- `xiom.num.float.float_bits`/`bits_to_float` are documented fallback stubs (`TODO(compiler)`, `ensures: result == 0`); the probe prints `float_bits(1.5)=0` (expected `0x3FF8000000000000` = 4609434218613702656) |

Net: `probe_float_vec.xi` reports `bad=2` (the two bitcast checks) while
every `Vec[Float64]` check is green. Packages keep raw-octet float
encodings until a bitcast intrinsic lands; new code may use
`Vec[Float64]` freely.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\float-vec\probe_float_vec.xi
# bad=2 (expect 0 after the bitcast intrinsic lands)
```
