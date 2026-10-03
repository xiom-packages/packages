<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `Vec[StructType]` re-verification (v0.62.2)

Original finding (trap 10, 2026-09-27): "No `Vec[StructType]` -- struct
payload lists need parallel `Vec` fields"; `nats` parsed op streams
op-by-op and `i2c` modeled transaction events as two mirrored
`Vec[Int]` arrays.

## Result (2026-10-03, installed v0.62.2)

`probe_vec_struct.xi` -- **`bad=0`, exit 0**:

| Operation | Result |
|---|---|
| `Vec[Row].new()` + 3 pushes | len=3 |
| Indexed read `v[1]` (Int + Str fields) | `code=2`, name "two" |
| Str field content via `str_compare` | correct |
| Field write through the index (`v[0].code = 9`) | propagates |
| Runtime push in a loop (`code: 100 + i`) | len=6, `v[5].code=102` |
| `&Vec[Row]` parameter read | correct |

**Trap 10 is NOT reproducible on v0.62.2** in any tested shape. Existing
parallel-Vec sites stay as-is (no drive-by refactors) and may simplify at
their next touch; full retirement is a candidate for the next release
sweep.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\vec-struct\probe_vec_struct.xi
# bad=0
```
