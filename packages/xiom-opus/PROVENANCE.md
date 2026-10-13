# xiom.opus -- PROVENANCE

Vendoring chain for the first landing (0.1.0). Everything here is
re-derivable from the pinned clone plus `tools/vendor_opus.py` and
`tools/gen_opus.py`.

## 1. Upstream and pin

| Item | Value |
|------|-------|
| Upstream | libopus (Opus codec, RFC 6716) |
| Canonical | `https://gitlab.xiph.org/xiph/opus` (mirror: `github.com/xiph/opus`) |
| Tag | `v1.6.1` |
| Commit | `22244de5a79bd1d6d623c32e72bf1954b56235be` |
| Local clone | `E:\repos\opus` (shallow, registered in `E:\repos\CLEANUP.md`; verified at vendor time: `git rev-parse HEAD` == pin) |
| License | BSD-3-Clause -- `vendor/COPYING`; patent/IP notes: `vendor/LICENSE_PLEASE_READ.txt` (both copied verbatim from the clone) |

## 2. Vendored tree (`vendor/opus/`)

* **Verbatim, flat layout.** The XIOM `--c-source` pipeline compiles all C
  sources in one clang invocation **without `-I`/`-D` support**, so the
  upstream directory split (celt/, silk/, silk/float/, silk/fixed/, src/,
  include/) cannot be compiled in place: cross-directory quoted includes
  (`"celt.h"` from `src/`, `"float/structs_FLP.h"`) only resolve relative
  to the including file. `tools/vendor_opus.py` copies the needed files
  **byte-identical** into one flat directory plus `float/` and `fixed/`
  subdirectories for the two prefixed include spellings; there are no
  basename collisions across the six upstream directories (verified by the
  script, which aborts otherwise).
* **Content set.** All headers from `celt/`, `silk/`, `silk/float/`,
  `silk/fixed/`, `src/`, `include/` + the exact build sources from the
  upstream source lists: `CELT_SOURCES` (18), `SILK_SOURCES` (77),
  `SILK_SOURCES_FLOAT` (28), `OPUS_SOURCES` + `OPUS_SOURCES_FLOAT` (14).
  Fixed-point sources are not vendored (the float build is the upstream
  default).
* **Integrity.** `vendor/MANIFEST.sha256` records `sha256  upstream-path
  vendored-path` for every file (206 entries + 2 license files);
  regeneration is deterministic. `.gitattributes` sets `vendor/** -text`
  so Git never rewrites line endings.
* No upstream file is modified. The only code added at vendoring time are
  our own wrapper/generation files listed below.

## 3. Generated files (never hand-edited)

| File | Generator | Notes |
|------|-----------|-------|
| `src/opus_vendor_celt.c`, `src/opus_vendor_silk.c`, `src/opus_vendor_silk_float.c`, `src/opus_vendor_src.c` | `tools/gen_opus.py` | unity units over the flat tree; pin build defines + upstream source lists |
| `src/opus_abi_protos.h` | `tools/gen_opus.py` | C prototypes included by the bridge (compiler-enforced ABI) |
| `src/opus_abi.xi` | `tools/gen_opus.py` | module `xiom.opus.abi`: constants + coverage ledger |
| extern block inside `src/opus_ffi.xi` | `tools/gen_opus.py` | marker-delimited (`GENERATED-EXTERNS-BEGIN/END`) |
| `docs/COVERAGE.md`, `docs/gen_manifest.json` | `tools/gen_opus.py` | declared/bound ledger + pinned-header SHA256s |

## 4. Original files (MIT OR Apache-2.0)

`src/opus.xi`, `src/opus_ffi.xi` (wrappers; extern block generated),
`src/opus_types.xi`, `src/opus_bridge.c`, `tests/test_conformance.xi`,
`tools/vendor_opus.py`, `tools/gen_opus.py`, docs, `package.xi`.

## 5. Provider chain note

All ABI knowledge derives from the pinned headers in the clone; the
bridge and wrappers are written against those declarations only. The
suite is self-contained (no external test vectors); RFC 8251 vector
parity is a ROADMAP item that would fetch `opus_testvectors` separately
(not in git upstream).
