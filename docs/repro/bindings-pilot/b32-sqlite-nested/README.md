# B-32: B-26 residual -- nested payload corruption survives IN the xiom.sqlite context (v0.64.5)

Found 2026-10-15 attempting the planned 0.5.0 restore of
`Result[Option[SqliteRow]]` (retire the flat RowOutcome workaround; see
`REL-20261015-1955-bindings`).  The isolated B-26 repro
(`../nested-payload/`) is GREEN on the v0.64.5 pin, and SEVEN near-miss
variants (see `probe-nearmiss/`) are also GREEN -- but the real package
context is RED.

## In-situ evidence (v0.64.5 pin, instrumented suite)

After `q1 = SqlDriver.query_one(&drv, "SELECT name FROM t;")`:

```
DBG q1 ok=true
DBG out some=true
DBG cols.len=140697731719824        <-- pointer-like garbage (B-26 signature)
```

then ACCESS VIOLATION (exit 0xC0000005) reading the first column.

At the same pin, the identical extraction in every isolated probe reads 2.
The trigger is compilation-unit sensitive (B-01/B-26 family signature):
the 1400-line suite + 8 package modules + the vendored sqlite3.c TU.

## Reproduce

1. Apply `restore-0.5.0-attempt.patch` to the repo (full restore +
   the DBG instrumentation used above).
2. Set the pinned toolchain and run:
   `$env:XIOM_COMPILER=<slot>\bin\xiom.exe` then
   `.\scripts\port.ps1 -Package xiom.sqlite -TimeoutSec 300`
3. Observe the DBG lines above, then the AV (program exit 0xC0000005).

## Near-miss probes (all GREEN on the pin, in `probe-nearmiss/`)

- same-module helper-built and inline-built rows (flat + nested)
- cross-module builders (types/builders in `ptypes`)
- query_one-shaped construction (var row + add loop + has_row + two exits)
- the exact `SqliteValueKind` variant set (Integer(Int), Real(Float64),
  Text(Str), Blob(Vec[Int]))
- struct error type `E{code,msg}` + in-function `Err` paths

None reproduce it.  (Run: `xiom --run probe.xi` from `probe-nearmiss/`.)

## Status

- xiom.sqlite STAYS at the flat RowOutcome shape (restore parked; the
  package tree is unchanged from 0.4.1).
- **B-32 filed** to the compiler lane with this bundle.
- Re-attempt the restore when B-32 is fixed; re-run this bundle first.

## Files

- `restore-0.5.0-attempt.patch` -- the complete restore attempt (sqlite
  src + docs + instrumented suite) as applied 2026-10-15
- `probe-nearmiss/` -- `probe.xi` + `ptypes.xi` (the seven green variants)
