<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Enum payload `Str` reads -- in-situ evidence, minimal repro pending (v0.62.3)

Found while restoring `xiom.graphql`. In `validate_operation`, the field
name read out of a `GraphQLSelection.Field(selection)` payload is
corrupt, so a valid query reports `field_check` failures:

```
VO field=|0|          (in-situ instrumentation, v0.62.3)
DBG fs.name=|hello|   (the source struct local is correct)
DBG sel0.name=|0|     (read back from op.selection_set.selections[0] -- corrupt)
DBG localmatch=||     (constructed + matched in the test module -- empty)
DBG vecstruct=|vec|   (Vec[StructType] Str read -- correct, control)
```

## Standalone reproduction attempts (all PASS so far)

| Shape | Result |
|---|---|
| Single module: `Inner{name,n}` + `enum Wrap { Has(inner) }`, match `x.name` | `str=ok` |
| Same + `derive[Clone]` on both types | `str=ok` |
| Recursive: payload `->` nested struct `-> Vec[enum]` | `str=ok` |
| Plus `&mut Op` + nested-field `push`, read back, match | `str=ok` |
| Two-module scratch package (library defs + non-nested test module) | `str=ok` |

So the corruption is reproducible **only in the full graphql types so far**
(suspects: the 5-field payload with two `Vec` fields and the
`selection_set` recursion, or the number/size of payload variants). The
minimal repro is still pending; `probe_enum_payload_str.xi` is kept as
the passing control that any future repro should flip.

**Guidance meanwhile:** if a payload `Str` read misbehaves, avoid reading
`Str` fields out of enum payloads directly; route names through a
parallel `Vec[Str]`/id scheme, or park the package.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\enum-payload-str\probe_enum_payload_str.xi
# control on v0.62.3: int=ok str=ok bad=0 (the graphql case still corrupts)
```
