<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Repro: `xiom.kv` `kv_get` Str corruption (C-PULSE-10)

**Filed:** 2026-10-07 by the PULSE consumer lane (WSL Linux, v0.64.0).
**Packages-lane comparison:** 2026-10-08 on Windows v0.64.0 -- **GREEN**.

## Symptom (PULSE, Linux target)

After `kv_put(&mut store, "k", "abcdefghij")`, `kv_get(&store, "k")` returned a
decimal stack-address-like `Str` (e.g. `97116368003104`) for every key and value
length; multi-key writes additionally truncated `kv_get_bytes` (a 9-byte value read
back as 6). `kv_get_bytes` + `Str::from_utf8` returned the stored text correctly, so
the stored records are intact and the `kv_get` Str reconstruction misbehaves.

## Windows comparison (packages lane, 2026-10-08)

The runnable probe lives in-package (module resolution requires the package context):
`packages/xiom-kv/tests/probe_kv_get_str.xi` (mirrors PULSE's probe plus the multi-key
case). Run from the repo root:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run packages\xiom-kv\tests\probe_kv_get_str.xi
```

Observed on the pinned v0.64.0 Windows build -- all correct:

| Check | Result |
|---|---|
| `kv_get` after `kv_put` (10-byte value) | `[PASS] kv_get      =[abcdefghij]` |
| `kv_get_bytes` len | `len=10` |
| second key (9-byte value), `kv_get_bytes` | `[PASS] k2 bytes    =[123456789]  len=9` |
| first key re-read after the second write | `[abcdefghij]  len=10` |
| local `Vec[UInt8]` -> `Str::from_utf8` control | `[abcdefghij]` |

## Classification

Target-specific: identical package source and probe shape are green on Windows
v0.64.0 and red on WSL Linux v0.64.0. `kv_get` uses the standard idiom
(`kv_get_bytes` -> `match Some(b)` -> `Str::from_utf8(b)`), so the packages side has
no Windows repro to fix; a compiler-lane bisect of the Linux target is required.
Linux consumers should read values through `kv_get_bytes` + `Str::from_utf8`
(PULSE workaround) until the fix ships. Recorded in `docs/COMPILER-FINDINGS.md`
(cross-ref C-PULSE-10).
