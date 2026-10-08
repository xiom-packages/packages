# SPEC: xiom.odbc -- ODBC driver-manager bindings (dynamic loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.odbc` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | ODBC driver manager (Windows system component; Microsoft `odbc32.dll`) |
| Upstream license | proprietary system API; nothing vendored -- the module declares constants locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system `odbc32.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + entry-point set + constants

**Soname (runtime contract):** `odbc32.dll`. Resolved at runtime via
`xiom.ffi.dl` (`LoadLibraryA`/`GetProcAddress`); no import library, no
headers, nothing vendored.

**Resolved entry points:** `SQLAllocHandle`, `SQLSetEnvAttr`, `SQLDrivers`,
`SQLDataSources`, `SQLGetInfo`, `SQLFreeHandle`.

**ODBC constants pinned** (declared locally from the spec):
`SQL_SUCCESS=0`, `SQL_SUCCESS_WITH_INFO=1`, `SQL_NO_DATA=100`,
`SQL_NULL_HANDLE=0`, `SQL_HANDLE_ENV=1`, `SQL_HANDLE_DBC=2`,
`SQL_ATTR_ODBC_VERSION=200`, `SQL_OV_ODBC3=3`, `SQL_FETCH_FIRST=2`,
`SQL_FETCH_NEXT=1`, `SQL_ODBC_VER=10`.

**Local runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `System32\odbc32.dll` | 794,624 bytes, FileVersion 10.0.26100.9549, SHA256 `8A120C65049E31B26CF1608E9D9E3253F386D29539A508B345E30390542B88D7` |
| Runtime report | manager version `03.80.0000`; 7 drivers (`SQL Server`, `SQL Server Native Client 11.0`, `ODBC Driver 11 for SQL Server`, ...); 3 configured DSNs |

### Re-pin procedure

1. Re-verify the entry-point names/constants against the ODBC spec before
   touching the module (they are the ABI).
2. Update the DLL sample and version rows in `README.md`/`AUDIT.md` in one
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.odbc` (x2) and record the matrix.

## 3. Design and safe boundary (G5)

`odbc.xi` is the only module with `unsafe`: an `OdbcLibrary` loader struct
plus fn-pointer-cast wrappers. `odbc_probe(lib)` runs the connection-free
flow (env handle -> ODBC3 env attribute -> DBC handle -> `SQL_ODBC_VER` ->
`SQLDrivers` scan -> `SQLDataSources` scan) and returns `OdbcInfo`;
`odbc_load_named` / `odbc_probe_named` give the deterministic SKIP-path test
on any host.

**Naming rule (compiler finding B-10):** local fn-pointer variables inside
confined blocks must NOT be named `alloc` -- the guard pass rewrites
`alloc(...)` calls to the guard allocator, silently discarding the intended
callee. The bridge locals use an `f_` prefix (`f_alloc`, `f_setenv`, ...).

Out-params use XIOM-owned `Vec[UInt8]` slots read byte-wise; no malloc/free
in confined blocks (B-05).

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| odbc32 present (System32) | `scripts/port.ps1 -Package xiom.odbc` | **PASS 5/5 x2** -- SKIP classification (bogus soname), manager `03.80.0000`, 7 drivers + head, 3 DSNs |
| Driver manager absent | not reproducible on Windows; the bogus-soname classification runs every suite invocation | SKIP path exercised + code-reviewed |

## 5. Scope

Pilot: driver-manager identification and driver/DSN enumeration.
Connection handling (`SQLConnect`/`SQLDriverConnect`), statement execution,
diagnostics text (`SQLGetDiagRec`) and async are Phase 2 (`ROADMAP.md`);
they need a reachable data source to be meaningfully tested.
