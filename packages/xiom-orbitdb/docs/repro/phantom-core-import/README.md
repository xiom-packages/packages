<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-06 repro: phantom import silently accepted; foreign twin turns it hard

**Compiler:** v0.64.2 (Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL twin).
**Found by:** the ORBITDB <-> XVECTOR hybrid probe composition (2026-10-10):
`xiom.db.error` (ORBITDB) imported the non-existent module `xiom.core.error`
and used its `CoreError` in a signature; the composite program also contains
`xiom.vector.core.shim`'s inline `CoreError` stand-in (XVECTOR). The composed
build failed T001 in `xiom.db.error` while every standalone ORBITDB build had
silently passed.

## Files

- `probe_alone.xi` -- the phantom shape in isolation (no same-named type
  anywhere).
- `probe_with_twin.xi` -- identical, plus `use twin;`.
- `twin.xi` -- the foreign same-named `CoreError` (mirrors the XVECTOR shim).

## Commands and observed results (v0.64.2)

```
xiom --check docs/repro/phantom-core-import/probe_alone.xi
  warning[W004]: 29:5: unreachable match arm (an earlier arm already matches these values)
  warning[W004]: 30:5: unreachable match arm (an earlier arm already matches these values)
  Type check PASSED (no errors)            # exit 0 -- module `xiom.core.error` does not exist

xiom --check docs/repro/phantom-core-import/probe_with_twin.xi
  error[T001]: 30:5: match pattern 'Corruption' belongs to 'DbError', not 'CoreError'
  error: compilation failed                # exit 1
```

## What is wrong (three observations)

1. `use xiom.core.error;` for a module that exists nowhere is silently
   ignored; an undeclared type name (`CoreError`) in a parameter position is
   silently accepted (error-recovery type), and a `match` on it produces
   bogus `W004 unreachable match arm` warnings instead of a diagnostic.
2. When any reachable module declares a type with that name (any package in
   the same program), the name binds across module boundaries -- even though
   the file never imports the declaring module (`probe_with_twin.xi` only
   imports `twin` for reachability of the type; resolution ignores the
   selective import).
3. With the scrutinee resolved, the bare pattern `Corruption` still resolves
   to the same-module enum (`DbError`) -> hard T001 with no ambiguity note.
   This is the C-ORBIT-04/m225 consumer-scope caveat family: the earlier fix
   covered the declaring module, not this declaration-vs-foreign-twin mix.

## Impact

- A consumer lane can ship code that never type-checks in any composition
  that contains a same-named type (multi-package programs are the norm:
  ORBITDB + XVECTOR + a driver). Standalone "green" means nothing here.
- The W004 warnings are misleading (they point at match arms, not at the
  unresolvable import/type).

## Suggested fixes (compiler lane's call)

- Error on an unresolvable `use` (or at least on an undeclared type used in a
  signature/field access) -- one diagnostic at the import site would have
  caught this in Phase 0.
- Prefer the scrutinee's enum for bare pattern variants over the same-module
  enum; emit an ambiguity diagnostic when both exist.

## ORBITDB-side resolution (already applied, 2026-10-10)

The dead `db_error_from_core` fold and `database_config_from_core` projection
(plus their phantom `xiom.core.*` imports) were retired in `src/error.xi` /
`src/config.xi`; the suite is green (123/123 x2, Windows + WSL) and the
composite hybrid probe builds and passes. Re-introduce the folds when the
`xiom-core` package publishes.

## Verdict on v0.64.4 (2026-10-12): FIXED (batch 3, m266/m267)

Both probes now fail with exactly ONE clear error from the repo root:

```
error[T001]: 19:5: unresolved import 'xiom.core.error'
  ... = note: Unresolved names prevent the compiler from generating correct code.
note: 1 type errors -- aborting codegen
```

The silent acceptance (probe_alone used to PASS with 2x bogus W004
unreachable-arm warnings) and the with-twin `match pattern 'Corruption'
belongs to 'DbError'` T001 are gone. Windows exits 1 for both files on the
official artifact (sha256 `44a41aea...`). CAVEAT: the Linux build's
`--check` exits 0 despite the error text -- new finding **C-ORBIT-10**
(`docs/repro/check-exit-code/`, bus `REL-20261012-1358-orbitdb`); verdicts
here are text-based + Windows exit codes. Bus: `REL-20261010-1802-orbitdb`
verified + closed; the `packages-4` release-check row carries the verdict.
