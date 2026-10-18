<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xv-object-key-iter -- XVC-C-18 repro (v0.64.5)

**Finding:** JSON object Map-key reads through a `match` enum binding
return garbage Strs; the inferred local also rejects method calls at
compile time. Filed `REL-20261016-1541-xvector` (high).

**Symptom (in the wild):** `router_mapping_load` (`src/api/router.xi`,
L-3 slice) iterated `entries.keys[i]` where `entries` was bound by
`match cv { Object(entries) => ... }`; every key failed the `Str` charset
validator ("collection name invalid") although the mapping file's keys
are `docs`/`logs` -- a VALID mapping was refused. Copying
`entries.keys`/`entries.values` into locals BEFORE the loop (the lane's
copy-out discipline) fixed it; `probe_router_2shards` is 72/72 green with
the workaround.

**Minimal shape:**

```xiom
match cv {
  Object(entries) => {
    var i: Int = 0;
    while i < entries.keys.len() {
      var name = entries.keys[i];           // <- inferred local
      if !name_ok(name) { return -1; }      // <- reads garbage
      i = i + 1;
    }
  }
  _ => {}
}
```

Observed on v0.64.5 windows-x64 (this probe): `key=[1946864332608]`
(pointer-shaped garbage) -> exit 1. Expected: `key=[docs]`,
`key=[logs]`, exit 0.

**Extra datum:** `name.len()` on the same inferred local is rejected at
COMPILE time -- `error[T001]: cannot call 'len' on this expression`
(the receiver type is not resolved) -- while the same value still
coerces into a `Str` parameter, so affected units get silent garbage
instead of a type error.

**Controls (green):** (a) explicitly-typed single read
(`var nn: Str = ""; nn = ent.keys[0];`); (b) the copy-out workaround
(`var ks = entries.keys; var name = ks[i];`).

**Run:**

```
.\scripts\build.ps1 docs\repro\xv-object-key-iter\probe.xi -Name xv_object_key_iter
.\out\xv_object_key_iter.exe     # v0.64.5 Windows: exit 1 (garbage key)
```

**Provenance:** v0.64.5 windows-x64, lane stdlib checkout, 2026-10-16
(found during the L-3 router slice). No v0.64.4 A/B (tree
incompatibility); suspected family XVC-C-09/C-14/C-16
(context-sensitive struct/field lowering). The repro is the regression
gate for the next archive.
