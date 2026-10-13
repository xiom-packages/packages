# xiom.ogg -- PROVENANCE (0.2.0)

Vendoring chain for the libogg packet layer added in 0.2.0. The 0.1.x pure
page layer is original XIOM code and requires no upstream.

## 1. Upstream and pin

| Item | Value |
|------|-------|
| Upstream | libogg (Ogg reference implementation) |
| Canonical | `https://gitlab.xiph.org/xiph/ogg` (mirror: `github.com/xiph/ogg`) |
| Tag | `v1.3.6` |
| Commit | `be05b13e98b048f0b5a0f5fa8ce514d56db5f822` |
| Local clone | `E:\repos\ogg` (shallow, registered in `E:\repos\CLEANUP.md`; verified at vendor time: `git rev-parse HEAD` == pin) |
| License | BSD-3-Clause -- `vendor/COPYING` (copied verbatim) |

## 2. Vendored tree (`vendor/ogg/`)

Five source files (`bitwise.c`, `framing.c`, `crctable.h`, `ogg.h`,
`os_types.h`) + `COPYING`, in a flat directory.

**The four-line include rewrite (the ONLY delta).** The XIOM `--c-source`
pipeline compiles C in one clang invocation without `-I` flags, and includes
of the form `<ogg/ogg.h>` / `<ogg/os_types.h>` are angle includes: they are
not resolved relative to the including file, so upstream cannot compile in
place (verified by direct clang runs). `tools/vendor_ogg.py` applies these
exact-string rewrites (aborting if a pattern is missing):

```
src/bitwise.c      #include <ogg/ogg.h>        -> #include "ogg.h"
src/framing.c      #include <ogg/ogg.h>        -> #include "ogg.h"
include/ogg/ogg.h  #include <ogg/os_types.h>   -> #include "os_types.h"
src/crctable.h     #include <ogg/os_types.h>   -> #include "os_types.h"
```

`vendor/MANIFEST.sha256` records **both** the upstream SHA256 and the
vendored SHA256 per file, so the delta stays auditable; `.gitattributes`
pins `vendor/** -text`. `framing.c`'s `#include "config.h"` is guarded by
`HAVE_CONFIG_H` (not defined) and is untouched.

## 3. Generated / original files

| File | Kind | Notes |
|------|------|-------|
| `src/ogg_abi_protos.h` | generated (`tools/gen_ogg.py`) | C prototypes included by the bridge |
| extern block in `src/ogg_ffi.xi` | generated | marker-delimited (`GENERATED-EXTERNS-BEGIN/END`) |
| `src/ogg_abi.xi` | generated | coverage ledger |
| `docs/COVERAGE.md`, `docs/gen_manifest.json` | generated | declared/bound ledger + header SHA256 |
| `src/ogg_bridge.c` | original (MIT OR Apache-2.0) | bridge over the vendored tree |
| `src/ogg_ffi.xi`, `src/ogg_types.xi`, `src/ogg_mux.xi` | original | safe wrappers + facade |
| `tools/vendor_ogg.py`, `tools/gen_ogg.py`, `tools/make_ogg_fixture.xi`, `tools/gen_fixture.ps1` | original | vendoring, generation, fixture |
| `tests/fixtures/tone.ogg` | generated artifact | produced by the generator from a live `xiom.opus` encode + this package's mux path (committed as evidence) |

## 4. Re-pin procedure

1. Fetch the new tag into `E:\repos\ogg` (shallow fetch of the tag).
2. `python tools/vendor_ogg.py` (verifies HEAD == PIN, re-applies the
   rewrite, rewrites `vendor/MANIFEST.sha256`; fails if a rewrite pattern
   moved).
3. `python tools/gen_ogg.py --headers E:\repos\ogg\include --package .`
   (regenerates protos/externs/ledger; fails on any uncovered symbol).
4. Regenerate the fixture (`tools/gen_fixture.ps1`) if the opus path
   changed; bump the package version; run the suite twice; record STATUS.
