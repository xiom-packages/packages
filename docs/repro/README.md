<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Repro bundle index

Minimal, runnable evidence for every compiler finding the packages lane
has filed or re-verified. Each bundle has its own README with the exact
matrix; run from the repo root, e.g.:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\<bundle>\<file>.xi
```

Status below is the last re-verification per bundle; the current pin is
**v0.64.0 (2026-10-05)**: `runtime-link` and `crypto-link` are RESOLVED
with no overrides, grpc m192 is unchanged (both probes now crash
`0xC0000005`), graphql is 9/10 unchanged (C001 `4bf8cf1e` is in the pin;
GraphQL needs a distinct root cause).

| Bundle | Purpose | v0.63.0 status |
|---|---|---|
| `arity-laxness` | wrong-argument-count calls | **FIXED** (re-verified v0.63.0) -- control green; missing/extra both `error[T001]` |
| `byte-at-128` | `byte_at >= 128` threshold compares | **FIXED** (re-verified v0.63.0 `bad=0`) -- widen+mask workaround retired |
| `child-parent-calls` | child module calls into direct parent | **RE-SCOPED** -- works with `pub` (acyclic, cyclic, alias all pass); without `pub` T001 |
| `const-tables` | module-level const arrays | **FIXED** (v0.62.4; re-verified v0.63.0 `bad=0`) -- Int/Str/struct tables correct; runtime builders can be dropped at next touch |
| `const-match` | `const` values as match arms | **FIXED** (v0.62.4; v0.63.0 probe exit 0, W004 overlap warning) -- const arms match; literals can return to named constants |
| `tuple-vec-set` | `Vec[(Str,Str)]` read-after-mutation | **OPEN (v0.64.0 unchanged)** -- `probe_suite_min.xi` crashes `0xC0000005`; `probe_direct.xi` now also crashes (previously hung); the m192 candidate did not clear it |
| `struct-clone` | `Vec[Struct].clone()` codegen | **OPEN (v0.64.0)** -- crash `0xC0000005`; push/read control green; copy element-wise |
| `enum-payload-str` | enum payload struct `Str` reads | **OPEN (v0.63.1 unchanged)** -- graphql 9/10 (`|0|` read persists); needs a distinct root cause (C001 is already in v0.63.1); minimal repro pending |
| `uninit-local` | uninitialized local + later assignment | **FIXED** (v0.63.0) -- standalone probe `bad=0`; graphql no longer hangs (its remaining 9/10 failure is the enum-payload case) |
| `crypto-link` | stdlib `xiom.crypto` SHA-256/HMAC linkability | **RESOLVED (v0.64.0)** -- both probes link with no overrides (NIST KAT `ba7816bf...15ad`); `aws`/`saml` hand-rolled copies retire in Tier-2 |
| `runtime-link` | AOT runtime C coverage (`async_runtime.c`) | **RESOLVED (v0.64.0)** -- `probe_async_now` green with no overrides and no `XIOM_STDLIB` (install-layout discovery fixed); workaround retired |
| `float-vec` | `Vec[Float64]` + `Int<->Float64` bitcast | **SPLIT** -- `Vec[Float64]` works; bitcast is a documented stdlib stub (`bad=2`) |
| `generic-fnptr` | fn-value / generic-mono ABI family | **FIXED** -- all 7 probes exit 0 |
| `loop-carry-cse` | loop-carried CSE correctness | **CLEAN** -- `bad=0` |
| `mut-int-write-through` | `&mut Int` plain-local calls | **FIXED** (v0.62.3; v0.63.0 matrix `bad=0`) -- deref and bare assignment, both call forms (matrix in `v0622-regressions`) |
| `sign-bit-ops` | sign-bit arithmetic identities | **CLEAN** -- exit 0 |
| `str-vec-eq` | `Str` equality / `str_len` on `Vec[Str]` elements | **NOT REPRODUCED** -- `bad=0` (probe kept as retirement evidence) |
| `struct-field-vec` | `&r.value` empty-vector read on `Result` payloads | **FIXED** -- `result payload: 3`; all 3 probes exit 0 |
| `v0622-regressions` | the v0.62.2 regression packet (Vec[Str].push, mut-int matrix, expat/nbt) | **FIXED** (v0.62.3; re-verified v0.63.0) -- Vec[Str].push probes run; mut-int matrix `bad=0`; expat/nbt resolved (25/25, 26/26) |
| `vec-struct` | `Vec[StructType]` (trap 10) | **NOT REPRODUCED** -- push/read/field-write/loop-push/`&Vec` all correct |
| `kv-get-str-corruption` | `xiom.kv` `kv_get` Str corruption (C-PULSE-10) | **LINUX-TARGET RED / WINDOWS GREEN (v0.64.0)** -- PULSE repro red on WSL Linux; packages-lane Windows probe `packages\xiom-kv\tests\probe_kv_get_str.xi` fully green (single + multi-key); compiler-lane Linux bisect |
