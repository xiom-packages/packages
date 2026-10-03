<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Uninitialized-local struct assignment -- pending minimal repro (v0.62.3)

Found while restoring `xiom.graphql`. In `validate_operation`, the pattern

```xi
var root: GraphQLType;          // no initializer
match root_type {
  Some(rt) => { root = rt; },
  None => { ...return Err... },
};
type_find_field(&root, ...)     // runs away / reads garbage
```

corrupted the copied value on v0.62.3:

- `root.name` read as a garbage pointer: concatenating it **hung** the
  suite (memory scan for a terminator);
- `root.fields.len()` read as `4294967295`, so `type_find_field`'s
  `while i < t.fields.len()` **ran away** (suite timeout);
- in-situ probes: reading the same schema directly (`Some(t)` binding,
  pass-through `&GraphQLSchema` params, `match`-expression `Str` locals)
  all returned correct values (`Query/fields=1`);
  **pre-initializing the local** (`var root: GraphQLType = type_new(...)`)
  also read correctly -- but the validator call in that same shape still
  returned a corrupted `Err` payload, so at least one more distinct
  defect is involved.

This standalone probe currently **crashes before printing** on v0.62.3
(`exit code: -1073741795`), so it is not yet a clean RED/GREEN battery:
it is kept as the starting point for a minimal repro. Treat the in-situ
`xiom.graphql` observations above as the primary evidence.

**Guidance meanwhile:** always initialize locals at declaration
(`var x: T = <default>;`) instead of `var x: T;` + later assignment.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\uninit-local\probe_uninit_local.xi
# v0.62.3: crash before output; expected after the fix: preinit=ok uninit=ok bad=0
```
