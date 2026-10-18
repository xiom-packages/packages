<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Status: **OPEN -- re-tested unchanged on v0.64.3 and v0.64.4** (2026-10-12:
clang/opt store mismatch at `xiominput.ll:850`, Windows + WSL) (found
2026-10-10, xiom.metrics adoption slice; relayed via
`docs/RELAY-COMPILER.md` Addendum 10).

# XVC-C-14 repro: two same-named struct types across modules -- one layout takes over the other

Found while adopting the registry package `xiom.metrics` 0.2.0: the
xvector program carried its own `Counter` type (the `xiom.vector.core.shim`
stand-in) **and** the package's `Counter`. After wiring the package, the
`probe_metrics` build failed at **clang**, after all XIOM-level checks had
passed:

```
error: clang failed with exit code 1
  stderr: xiominput.ll:20528:38: error: '%tmp24' defined with type
  '%struct.xiom.vector.core.shim.Counter = type { ptr, i64 }'
  but expected '%struct.xiom.metrics.Counter = type { i64 }'
```

`VectorEngine` (declared in `xiom.vector.engine.core`, which imports only
the shim) had picked up the **package** layout for its `upserts`/`deletes`
fields, while `engine_new` still produced **shim** values.

## Summary (mechanism)

Two distinct struct types across modules share one short name (`Counter`).
The compiler emits the field layout of a struct from the shared short name
instead of the declaring module's own resolution, so at least one module
gets the **other** type's layout; the mismatch only surfaces when the two
layouts differ (clang store reject). In the repro the **shim** layout wins
for the `repro.tally` struct even though `repro.tally` imports
`xiom.metrics`; in the original xvector build the **metrics** layout won for
`VectorEngine` even though `xiom.vector.engine.core` imports only the shim.
The winning side is program-order dependent.

The minimal trigger (tested): two modules each declare a **struct field
typed by the same short name**, resolving to different same-named types
from different modules. A single such struct in the program (all other
imports present) compiles green.

## Minimal repro (4 modules + manifest)

- `src/shim.xi` (`repro.shim`): its own `Counter { name: Str; value: Int; }`
  + `counter_new`/`counter_inc`.
- `src/engine.xi` (`repro.engine`): `Eng { upserts: Counter; }` (resolves to
  the shim type) + `eng_new`/`eng_up`.
- `src/tally.xi` (`repro.tally`): imports `xiom.metrics`;
  `Tally { hits: Counter; }` (resolves to the package type) +
  `tally_new`/`tally_hit`/`tally_hits`.
- `src/main.xi` (`repro.main`): imports `repro.engine` + `repro.tally`.

The embedded `xiom.toml` declares `[dependencies] xiom.metrics = "0.2.0"`;
the resolver reads it from this directory (run with the bundle as cwd).

```powershell
. .\scripts\dev-env.ps1
Push-Location docs\repro\xv-counter-type-shadow
& $env:XIOM_COMPILER -o $env:TEMP\xv_counter_shadow.exe src\main.xi
Pop-Location        # v0.64.2: clang exit 1 (see below)
```

```bash
cd docs/repro/xv-counter-type-shadow
~/.local/share/xiom/bin/xiom -o /tmp/xv_counter_shadow src/main.xi
```

Observed (v0.64.2, Windows **and** WSL -- identical):

```
xiominput.ll:850:36: error: '%tmp4' defined with type
'%struct.xiom.metrics.Counter = type { i64 }'
but expected '%struct.repro.shim.Counter = type { ptr, i64 }'
  850 |   store %struct.repro.shim.Counter %tmp4, %struct.repro.shim.Counter* %tmp5
```

The failing function is `repro.tally.tally_new`: the `metric_counter_new()`
call returns the correct `xiom.metrics.Counter`, but the struct slot it is
stored into was emitted as `repro.shim.Counter`. On WSL the pipeline's
`opt` pass reports the same mismatch first ("LLVM IR verification failed --
proceeding with compilation", IR kept at `/tmp/xv_counter_shadow.ll`,
same line 850).

Control: dropping `src/tally.xi` and having `main` import `xiom.metrics`
directly (so only **one** struct field is `Counter`-typed) compiles and runs
green -- the trigger is the second same-named struct declaration, not the
mere presence of both types.

## Impact

Type identity by short name in struct-layout emission. When the two layouts
happen to be compatible, a program can compile and run with **silently
wrong fields** (the clang error only catches incompatible shapes). Any
consumer that defines its own type sharing a short name with a consumed
package (or stdlib) type is exposed: e.g. a program defining its own
`Counter`, `Histogram` or `Registry` next to `xiom.metrics`. XVECTOR hit it
immediately because the shim `Counter` predated the adoption.

## Lane workaround (adopted)

One type name, one type: the engine's stat counters moved onto
`xiom.metrics` and the shim `Counter` was **retired** in the adoption slice
(`docs/XIOM-METRICS-ADOPTION.md`; commits `feat(observability)` /
`fix(observability)` on 2026-10-10). The full batteries (suite 171/171 x2 +
sbom + 34 probes x2 + bench smoke, Windows + WSL) are green with a single
`Counter` type in the program. Keep this repro as the regression gate; when
the compiler fix lands, the bundle should compile and print
`shim counter=1 tally hits=1`.
