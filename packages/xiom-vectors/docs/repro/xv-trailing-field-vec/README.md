<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-08 -- trailing scalar after a Vec-bearing field reads as garbage

**Status: FIXED on compiler v0.64.2** (2026-10-09 re-test: `probe.xi` exit 0
-- "hydration-guard: green"; `variants.xi` all 14 variants green; the suite's
hydration mirror test is restored and asserts the trailing `has_payload`
flags again, suite 168 -> 169 checks). Found 2026-10-08 on v0.64.1 by the
XVECTOR lane while adding `with_payload` hydration; kept as a regression
repro.

## Summary

In a `Vec[Struct]` where the element struct has a trailing scalar field after
a Vec-bearing field (`has_payload: Bool` after `payload: Payload` / `Vec[T]`),
reading that trailing field **can return uninitialized garbage** (observed:
`true`) instead of the stored value -- depending on the surrounding
compilation unit. The same source (`src/query/search_service.xi`
`hydrate_hits`) is correct in its own unit (`tests/probes/probe_search_request.xi`
green 8/8 fresh builds) but miscompiles in the big conformance-suite unit
(reads `true` for a hit that was never hydrated) and in this bundle.

It is a **silent wrong-result** defect: hydration flags (and by extension any
trailing scalar after a Vec field in a Vec element) cannot be trusted in
affected units.

## Bundle

- `probe.xi` -- the full `hydrate_hits` shape. With `with_payload=false` no
  hit may carry a payload, yet one reads as payload-bearing.
  Expected: exit 0. Observed: **exit 1 (`BAD detach count`), 5/5 builds.**
- `variants.xi` -- the minimization matrix. Exit code names the first failing
  variant. Observed on v0.64.1 (Windows, 1 build, deterministic):

  | Variant | Shape | Verdict |
  |---|---|---|
  | V1 scalar | `{ id; flag }` | green |
  | V2 bool-first | `{ id; flag; nodes: Vec }` | green |
  | V3 vec-first (no f32) | `{ id; nodes: Vec; flag }` | green |
  | V4 wrap-first | `{ id; wrap: Wrap; flag }` | green |
  | V5 hydrate-off | `{ id; distance; payload: Vec; flag }` + dead `if/match` | **RED (code 2)** |
  | V6 shape-only | V5 literal, no `if/match` | green |
  | V7 hydrate-wrapped | V5 with `payload: Wrap` | **RED (code 2)** |
  | V8 simple-if | `var have=false; if cond { have=true; }` | green |
  | V10 branch-split | pushes inside `if/match` branches | **RED (code 2)** |
  | V11 index-lookup | `if` + `if pos >= 0` (no Option/match) | **RED (code 2)** |
  | V12 two-phase | plain pushes + second attach loop | **RED (code 2)** |
  | V13 flag-first | `{ id; distance; flag; payload }` | green (in this unit) |
  | V14 int-flag | `{ id; distance; payload; flag: Int }` | **RED (code 2)** |

  `code 2` = the **second** element's flag reads `true`; the first reads
  correctly. V14 shows the trigger is not Bool-specific.
- `min.xi` -- scalar-only control (`Int` + `Bool`), green: plain struct
  pushes are fine; the defect needs the Vec-bearing field.

## Workaround (was adopted by the lane; reverted on v0.64.2)

- v0.64.1: trailing-scalar reads were unassertable in affected units. The
  engine's hydration gate was the real-module probe
  (`tests/probes/probe_search_request.xi`, green 8/8 fresh builds); the
  conformance-suite mirror did not assert hydration flags.
- v0.64.2: the suite mirror asserts the flags again (`test_request_hydration`,
  restored 2026-10-09) and passes in the large unit -- 169/169 x2 battery.
- Declaring the scalar **before** the Vec field (V13) was green in this bundle
  on v0.64.1 but NOT a general fix (the same reorder access-violated the suite
  unit), so it was never adopted. v0.64.2 fixes the layout directly (m234).

## Repro recipe

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-trailing-field-vec\probe.xi -Name t08 -NoIcon
.\out\t08.exe; "exit=$LASTEXITCODE"      # v0.64.2: 0 (was 1 on v0.64.1)
.\scripts\build.ps1 docs\repro\xv-trailing-field-vec\variants.xi -Name t08v -NoIcon
.\out\t08v.exe; "exit=$LASTEXITCODE"     # v0.64.2: 0 (was 5 on v0.64.1)
```

WSL: `bash scripts/build.sh docs/repro/xv-trailing-field-vec/probe.xi t08` then
`./out/t08`.

## Impact

On v0.64.1 (historical): silent wrong query metadata -- a hydrated search
result could report a payload it did not have (or read any trailing scalar
after a Vec-bearing field incorrectly), with no compiler diagnostic.
