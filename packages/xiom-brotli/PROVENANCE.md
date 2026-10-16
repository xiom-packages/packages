# PROVENANCE -- xiom.brotli

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Owner policy: `docs/UPSTREAM-FIRST.md` (upstream-first, 100% of the declared
surface). This package is an FFI binding (lane gates G6/G7): it compiles the
upstream implementation and wraps it -- no upstream code is copied into the
XIOM modules.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | Brotli -- `https://github.com/google/brotli` |
| License | MIT -- Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors (`vendor/brotli/LICENSE`, sha256 `3D180008E36922A4E8DAEC11C34C7AF264FED5962D07924AEA928C38E8663C94`, verified in-clone 2026-10-16) |
| Delivered pin | tag **v1.2.0** -- commit `028fb5a23661f123017c060daa546b55cf4bde29` (2025-10-27; latest stable release at clone time) |
| Study clone | `E:\repos\brotli` (shallow, tag `v1.2.0`; `E:\repos\CLEANUP.md` row `brotli`, review-after 2026-12-01) |

## 2. Vendored artifact (G2 pin)

107 files vendored from the pinned clone's `c/` tree (layout stripped of the
`c/` level) plus `LICENSE`: the 5 public headers, `common/`, `dec/`, `enc/`
sources and internal headers. Not vendored (not part of the C build;
documented, not silent): `common/dictionary.bin` + `dictionary.bin.br`
(dictionary rebuild inputs; `dictionary.c` embeds the data through
`dictionary_inc.h`) and `enc/static_init_lazy.cc` (experimental C++
static-init variant; the default build compiles `static_init.c`).

| Artifact | Value |
|----------|-------|
| Vendored tree digest | sha256 over sorted `relpath:sha256` lines (LF): `C3D54D20A17A3AF26BE29CC4E8EF15AC5CA72C1614173788CBBEE8852E23C642` |
| Delta vs upstream | **exactly 24 lines in 16 files** -- the mechanical angle-include rewrite (below); verified byte-identical otherwise against the raw `git archive` bytes of the pin on 2026-10-16 |
| Public header hashes | `SPEC.md` section 2 (per-file SHA256 table; `port.h`/`types.h`/`LICENSE` are byte-identical to upstream, the other three differ only by the rewrite) |
| Tooling | `tools/gen_brotli.py` (`--write` / `--verify` / `--print-tree`); regeneration is deterministic and asserts the 24-line count |

### The mechanical rewrite

The xiom `--c-source` link line adds no `-I` path, and the upstream sources
include the public headers in angle form; each `<brotli/NAME.h>` include is
rewritten to `"NAME.h"` (from `include/brotli/`) or
`"../include/brotli/NAME.h"` (from `common|dec|enc/`). 24 lines, 16 files,
no other change. Precedent: `xiom.exr` (`<miniz.h>` -> `"miniz.h"`) and
`xiom.openpgl` (include rewrite + LF normalization) record the same class of
documented vendor normalization.

Re-carve: `SPEC.md` section 2 (re-pin procedure).

## 3. What was studied; derived vs independent

**Upstream code (vendored, 24 include lines normalized):** the brotli
v1.2.0 RFC 7932 decoder (`dec/`), encoder (`enc/`), common runtime
(`common/`) and the public headers, compiled into the test binary through
the 35 upstream translation units + the bridge.

**Independent (XIOM Authors, MIT OR Apache-2.0):**

* `brotli.xi` -- every `extern "C"` declaration (16 upstream functions,
  transcribed from the pinned headers) and every safe wrapper, the stream
  loops (`brotli_decompress`/`_auto`), the module-local slot/byte helpers,
  and the RFC 9110 `Content-Encoding: br` helpers.
* `src/brotli_bridge.c` -- the NULL-allocator creation helpers, the stream
  cursor/slot shims, the `TakeOutput`/error-string copies and the
  sign-correct error-code return. No upstream logic is reimplemented; every
  bridge body calls the vendored upstream function directly.
* `tools/gen_brotli.py` -- the vendoring/re-verification tool.

## 4. Test vectors / golden data

8 compressed/uncompressed pairs were imported from the pinned clone's
`tests/testdata/` (upstream MIT) into `tests/fixtures/` and decode
byte-identically in the suite:

| Vector | Raw | .compressed |
|--------|-----|-------------|
| `10x10y` | 20 B `41BD4C89...` | 12 B `D666AFC0...` |
| `64x` | 64 B `BE4D3ED1...` | 10 B `F0273C38...` |
| `empty` | 0 B `E3B0C442...` | 1 B `67586E98...` |
| `quickfox` | 43 B `D7A8FBB3...` | 47 B `319F52F0...` |
| `monkey` | 843 B `937AD127...` | 425 B `37BCDD7A...` |
| `ukkonooa` | 119 B `1FB2529B...` | 69 B `92F59FC5...` |
| `cp852-utf8` | 706 B `37465D30...` | 362 B `38F328AC...` |
| `x` | 1 B `4B68AB38...` | 5 B `CD094A62...` |

(Fixture sha256 full values in the package history; recomputable with
`Get-FileHash -Algorithm SHA256 tests/fixtures/*`.)

Beyond the vectors, all other checks are live round trips through the real
vendored codec: quality 0..11, 128 KiB inputs, chunked streaming, corrupt/
truncated typed errors, and the corrupt-header witness
(`_ERROR_FORMAT_EXUBERANT_NIBBLE` at pin time) pinned in the suite.

## 5. Declared surface (100% implemented)

16 upstream functions are declared and wrapped (7 decoder, 9 encoder; the
full table with binding paths is `SPEC.md` section 4); every declared extern
has a public safe wrapper (16/16; 0 skips). The rest of the brotli C API
(dictionaries, decoder parameters, metadata callbacks, Large-Window, CLI) is
an explicit non-goal list in `SPEC.md` section 7, not a silent gap.

## 6. Link model

Static: `port.args.json` passes `src/brotli_bridge.c` + the 35 vendored
translation units to `--c-source` at port time (single clang invocation,
`--opt-level 0` for port-time link speed, `--timeout 1800`). No system
libbrotli*, no runtime DLL, no dl-load, no soname probe. License split:
`vendor/brotli/` is MIT; everything outside `vendor/` is MIT OR Apache-2.0.

## 7. Evidence

`tests/test_conformance.xi` (26 checks) through
`scripts/port.ps1 -Package xiom.brotli -TimeoutSec 2400`; the x2 run on the
feat commit (toolchain `v0.64.5`, counts + commit) is recorded in
`STATUS.json` and `SPEC.md` section 6.
