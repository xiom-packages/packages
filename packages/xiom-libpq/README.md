# xiom.libpq

PostgreSQL client-library bindings for XIOM via a **dynamic loader**:
`pq_load()` resolves `libpq.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no headers, no vendored
code -- and the suite reports **SKIP** (green) when libpq is not installed.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 2/2 without
> libpq (SKIP path) and 4/4 with libpq 13.11 (`PQlibVersion` 130011, real
> connect-error path). No PostgreSQL server required.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.libpq;

fn main() {
  let l = pq_load();
  if !l.is_ok {
    io.println("libpq unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: PqLibrary = l.value;
  io.println("libpq " + to_string(pq_libversion(&lib)));
  let p = pq_probe(&lib);
  if p.is_ok {
    io.println("connect status " + to_string(p.value.connect_status) + ": " + p.value.connect_error);
  }
  let cl = pq_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `pq_load`, `pq_load_named(soname)`, `pq_close`, `PqLibrary` |
| Probe | `pq_libversion`, `pq_connect_report(lib, conninfo)`, `pq_probe`, `pq_probe_default`, `PqInfo` |
| Kinds | `PQ_LOAD_ABSENT`, `PQ_LOAD_ABI`, `PQ_PROBE_FAILED` |
| Constants | `CONNECTION_OK/BAD`, `PGRES_*` |

Failure model: library missing -> SKIP; entry points missing -> FAIL; API
present but behaving unexpectedly -> FAIL. The default probe connects to a
closed local port, so the real connect/status/error path is exercised without
infrastructure.

## Tests

```
scripts/port.ps1 -Package xiom.libpq
```

- Without libpq on PATH: 2 `[PASS]` (explicit SKIP labels), exit 0.
- With libpq: 4 `[PASS]` (version + `CONNECTION_BAD` + error text), exit 0.

Result-set APIs (`PQexec`/`PQgetvalue`/...) are Phase 2 (`ROADMAP.md`).
