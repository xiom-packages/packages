<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Generic fn-pointer repros (v0.61.3)

Minimal probes for the fn-value / generic-mono ABI defects confirmed by the
compiler session (main @ `6c3e1cb5`, R66-R72 + m127; fixed as one ABI
unification sprint, not per-bug patches).

Environment: `XIOM Compiler v0.61.3`, `XIOM_STDLIB=E:\xiom-lang\stdlib`.
Run from the repository root:

```powershell
& .\scripts\xiom.ps1 --run docs\repro\generic-fnptr\<file>.xi
```

or directly with the installed compiler (`xiom --run <file>`).

## Matrix

| File | Role | v0.61.3 observed | After fix |
|---|---|---|---|
| `repro_struct_fnfield.xi` | fn-pointer in a struct field, called through the field | compile fails: `clang ... '%tmp16' defined with type 'ptr' but expected 'i64'` (`inttoptr` call setup) | exit 0 |
| `repro_generic_two_param_str.xi` | `[T, U]` scalar generic, callback `fn(&T) -> U`, `U = Str` | compiles; corrupt Str returned (`str_len` 2, content != "7"); exit 23, 5/5 runs | exit 0 |
| `control_generic_two_param_int.xi` | control: same shape, `U = Int` | green, exit 0 | exit 0 |
| `repro_generic_vec_u_str.xi` | `[T, U]` `Vec[U]` map, `U = Str` | compiles; mapped elements corrupted; exit 1, 5/5 runs. Element corruption is layout-dependent: the equivalent simpler probe in the session crashed with an access violation `0xC0000005` (exit -1073741819), 3/3 runs | exit 0 |
| `repro_generic_vec_u_int.xi` | `[T, U]` `Vec[U]` map, `U = Int` | compiles; mapped elements mis-written (`w[0] == 0`); exit 100, deterministic | exit 0 |
| `control_generic_vec_single_t.xi` | control: single-parameter `Vec[T]` map `fn(&T) -> T` | green, exit 0 | exit 0 |
| `control_concrete_vec_str.xi` | control: fully concrete `fn(&Int) -> Str` Vec map | green, exit 0 | exit 0 |

## Findings (as accepted by the compiler session)

1. **fn-typed struct-field load is not coerced for the call path**
   (`repro_struct_fnfield.xi`; compile-time, concrete, highest priority).
2. **The monomorphised closure/return ABI uses the erased/generic type for
   `U`** (`repro_generic_two_param_str.xi`; the `U = Int` control is green).
3. **`Vec[U]` push/element stride is wrong for the monomorphised `U`**
   (`repro_generic_vec_u_int.xi` silent zeros, `repro_generic_vec_u_str.xi`
   access violation; both single-`T` and fully concrete controls are green).

Single-type-parameter generics with fn-pointer parameters (`[T]` scalar,
`Vec[T]` map, `fn() -> T`, returned fn-pointers, inline lambdas, closures)
were all verified green in the same probe session and are not part of this
set.

Hygiene note (queued by the compiler session): `module name;` with a trailing
semicolon is rejected with `P001: expected declaration, found ';'`; a parser
tolerance is planned rather than leaving the natural spelling rejected.
