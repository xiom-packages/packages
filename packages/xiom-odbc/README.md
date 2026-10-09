# xiom.odbc

ODBC driver-manager bindings for XIOM via a **dynamic loader**: `odbc_load()`
resolves `odbc32.dll` at runtime and every call goes through resolved
function pointers. No link-time dependency, no headers, no vendored code --
and the suite reports **SKIP** (green) when the manager is absent.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 5/5 with
> real driver-manager evidence (ODBC `03.80.0000`, 7 drivers, 3 DSNs);
> published in `eco-v0.1.117`.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.odbc;

fn main() {
  let p = odbc_probe_default();
  if !p.is_ok {
    io.println("ODBC unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: OdbcInfo = p.value;
  io.println("manager " + info.version + ", " + to_string(info.driver_count) + " drivers");
  io.println(info.driver_head);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `odbc_load`, `odbc_load_named(soname)`, `odbc_close`, `OdbcLibrary` |
| Probe | `odbc_probe(lib)`, `odbc_probe_default`, `odbc_probe_named(soname)`, `OdbcInfo` |
| Kinds | `ODBC_LOAD_ABSENT`, `ODBC_LOAD_ABI` |
| Constants | `SQL_*` (handles, attributes, fetch directions, `SQL_ODBC_VER`) |

Failure model: manager missing -> SKIP; entry points missing (or the manager
refusing the basic calls) -> FAIL. A bogus soname exercises the SKIP path
deterministically.

## Tests

```
scripts/port.ps1 -Package xiom.odbc
```

Expected: 5 `[PASS]`, exit 0 (version + drivers + DSNs). Connections and
statement execution are Phase 2 (`ROADMAP.md`).
