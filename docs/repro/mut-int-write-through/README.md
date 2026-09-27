<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `&mut` parameter write-through repro (v0.61.3)

Minimal probes for the `&mut Int` write-through miscompile family (xiom.upnp
replaced its out-parameters with a value-returning `VersionParts`; the
optimizer notes are referenced from its source). **Reproduced on the
installed v0.61.3.**

Run from the repository root:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\mut-int-write-through\probe_out_params.xi
```

## The defect

A call to a function taking a `&mut T` parameter with a **plain local
argument** (no explicit `&mut` at the call site) compiles silently and
operates on a copy: every write through the parameter is lost. Passing the
local explicitly (`set_one(&mut x)`) works. No diagnostic is emitted for the
Int case; a struct-state variant emitted E001 "use of moved value" advisories
and additionally **corrupted memory** (a `&mut Bag` push wrote a garbage
value into the bag).

## Observed on v0.61.3 (2026-09-27)

`probe_out_params.xi` runs all variants and returns the number of failures:

```
plain set_one: 0
plain split2: 0,0
bump: 41
set_even: 0 ok
loop bump: 0
explicit set_one: 7
explicit split2: 5,5
bad=6
```

| Variant | Call form | v0.61.3 observed | After the fix (expected) |
|---|---|---|---|
| plain single out-param | `set_one(x)` | write lost (`x` stays 0) | either a compile error (move/no-borrow) or a correct borrow |
| plain two out-params | `split2(10, a, b)` | both writes lost (`0,0`) | same |
| read-modify-write | `bump(c)` | write lost (`c` stays 41) | same |
| branch + returned Bool | `set_even(d, 8)` | returns `ok`, write lost (`d` stays 0) | same |
| repeated plain call | `bump(acc)` in a loop | write lost | same |
| explicit `&mut` single | `set_one(&mut e)` | correct (`7`) | must stay correct |
| explicit `&mut` two | `split2(10, &mut g, &mut h)` | correct (`5,5`) | must stay correct |

Exit code: `bad` (0 when fixed, 6 today).

## Cross-references

- The CSE/write-through class is accepted as a compiler-lane candidate
  (repro-first); this probe is the requested reduction.
- Related: `docs/repro/loop-carry-cse/` (same decoder family) and the
  "no auto-borrow" E001 advisory row in `docs/COMPILER-FINDINGS.md`.
- The struct-bag corruption variant was observed while reducing the amqp
  decoder (`_bag_push(bag, ...)` produced `bag.vs[1] = 1859382800640` instead
  of the pushed value); it is the same root family, not a separate finding.
