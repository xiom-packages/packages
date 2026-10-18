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

## Re-attempt on v0.64.6 (2026-10-16, machine slot) -- STILL RED

Re-ran this bundle on the v0.64.6 slot
(`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`, sha256
`EB1F46C2ACBA5B95D46124FA7BB52426508BE5B81256E3ED1819CBFDA6979150`;
`port.ps1 -Package xiom.sqlite -TimeoutSec 300`, tested-on v0.64.6):
17/17 PASS, then the SAME signature at t18 --

```
DBG q1 ok=true
DBG out some=true
DBG cols.len=140702801265104        <-- pointer-like garbage (B-26 signature)
exit code: -1073741819 (0xC0000005)
```

(`port: FAIL (passed=17 failed=0 program_exit=-1073741819)`.)  Controls
on the same slot: `nested-payload/probe.xi` GREEN (nested/flat/option
2/2/2) and `matrix.xi` GREEN (all 8 shapes, shape A included).  B-32
is not fixed by v0.64.6 (m346 covered the isolated shapes only); next
re-verify rides the v0.64.7+ wave.

Evidence (this host): `%TEMP%\kilo\b32\` -- `attempt-1.log`,
`tested-tree.diff` (HEAD + patch, as tested), `probe-1.log`,
`matrix-1.log`, `slot-exe.sha256`.

Bundle caveats (hit on this re-run):

- the committed `restore-0.5.0-attempt.patch` is UTF-16LE -- convert it
  to UTF-8 before `git apply` (`--recount` is safe);
- its `README.md` hunk context predates the 0.4.1 modules-list
  paragraph now in the package README -- re-apply that hunk manually
  (the other 7 files apply cleanly; `src/types.xi` still matches the
  patch's recorded new blob `61eb2d5b`).

## v0.64.7 re-attempt (2026-10-17T23:50Z): STILL RED -- now TYPED

Same in-situ failure on v0.64.7 (scratch slot; SHA256SUMS OK):

    DBG q1 ok=true
    DBG out some=true
    DBG cols.len=140701786528232   <- pointer-like garbage (B-32 signature)
    [FAIL] driver mem: caps, execute/query/query_one, by-name access
    exit code: 1   <- TYPED fault (was 0xC0000005 AV on .5/.6)

So the .7 "Win64 C ABI aggregates + typed confined faults" wave made the
failure SAFE and visible (exit 1, no AV/silent death) but did NOT fix the
in-situ field-chain element loss.  Controls on the same slot:
nested-payload probe + matrix GREEN; B-33 ladder GREEN (m351 verified
fixed -- record-by-value returns 17036, done, exit 0); B-34 vec-alias
probe STILL RED; B-29 bigint-bitops STILL RED.

## Status

- xiom.sqlite STAYS at the flat RowOutcome shape (restore parked; the
  package tree is unchanged from 0.4.1).
- **B-32 filed** to the compiler lane with this bundle (m358 still queued).
- Re-attempt the restore when B-32 is fixed; re-run this bundle first.

## Files

- `restore-0.5.0-attempt.patch` -- the complete restore attempt (sqlite
  src + docs + instrumented suite) as applied 2026-10-15
- `probe-nearmiss/` -- `probe.xi` + `ptypes.xi` (the seven green variants)
