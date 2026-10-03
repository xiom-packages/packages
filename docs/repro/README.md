<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Repro bundle index

Minimal, runnable evidence for every compiler finding the packages lane
has filed or re-verified. Each bundle has its own README with the exact
matrix; run from the repo root, e.g.:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\<bundle>\<file>.xi
```

Status below is against the installed pin, **v0.62.3, re-verified
2026-10-03 (post-release)** unless a bundle's README says otherwise.
Re-run every bundle after the next compiler release to diff
fixed/not-fixed.

| Bundle | Purpose | v0.62.2 status |
|---|---|---|
| `arity-laxness` | wrong-argument-count calls | **FIXED** -- control green; missing/extra both `error[T001]` |
| `byte-at-128` | `byte_at >= 128` threshold compares | **FIXED** -- battery `bad=0`; widen+mask workaround retired |
| `child-parent-calls` | child module calls into direct parent | **RE-SCOPED** -- works with `pub` (acyclic, cyclic, alias all pass); without `pub` T001 |
| `const-tables` | module-level const arrays | **OPEN (new)** -- `[N]Int` correct; `Str`/struct tables mis-materialize (`bad=5`, deterministic; still broken on v0.62.3, listed in its release-notes known issues) |
| `crypto-link` | stdlib `xiom.crypto` SHA-256/HMAC linkability | **OPEN** -- `lld-link: undefined symbol: xiom_sha256_hash` |
| `float-vec` | `Vec[Float64]` + `Int<->Float64` bitcast | **SPLIT** -- `Vec[Float64]` works; bitcast is a documented stdlib stub (`bad=2`) |
| `generic-fnptr` | fn-value / generic-mono ABI family | **FIXED** -- all 7 probes exit 0 |
| `loop-carry-cse` | loop-carried CSE correctness | **CLEAN** -- `bad=0` |
| `mut-int-write-through` | `&mut Int` plain-local calls | **FIXED on v0.62.3** -- deref and bare assignment, both call forms (`bad=0`; matrix in `v0622-regressions`) |
| `sign-bit-ops` | sign-bit arithmetic identities | **CLEAN** -- exit 0 |
| `str-vec-eq` | `Str` equality / `str_len` on `Vec[Str]` elements | **NOT REPRODUCED** -- `bad=0` (probe kept as retirement evidence) |
| `struct-field-vec` | `&r.value` empty-vector read on `Result` payloads | **FIXED** -- `result payload: 3`; all 3 probes exit 0 |
| `v0622-regressions` | the v0.62.2 regression packet (Vec[Str].push, mut-int matrix, expat/nbt) | **FIXED on v0.62.3** -- both Vec[Str].push probes PASS; bare `&mut Int` writes propagate (`bad=0`); expat/nbt remain resolved (25/25, 26/26) |
| `vec-struct` | `Vec[StructType]` (trap 10) | **NOT REPRODUCED** -- push/read/field-write/loop-push/`&Vec` all correct |
