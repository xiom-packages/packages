# PROVENANCE: xiom.slang

Upstream-first record (policy: `docs/UPSTREAM-FIRST.md`). This package is a
**binding**: it contains no upstream code; it binds the public C API of the
Slang compiler DLL shipped with the pinned Vulkan SDK, generated from the
upstream headers and verified against the DLL's export table.

## 1. Upstream pin

| Field | Value |
|-------|-------|
| Upstream | https://github.com/shader-slang/slang |
| Tag | **v2026.8** |
| Commit | `d88cc8fff35baf96cf30d242b2572564cf8043b6` |
| Clone | `E:\repos\slang` (shallow, `--depth 1 --branch v2026.8`, 2026-10-11; shared clone space, disposable) |
| License | **Apache-2.0 WITH LLVM-exception** (permissive; whitelist OK; no code compiled, vendored, or copied -- bindings only) |
| Runtime artifact | `C:\VulkanSDK\1.4.350.0\Bin\slang.dll` (runtime build tag `2026.8` via `spGetBuildTagString`) |

## 2. Pin verification (headers byte-identical to upstream)

The Vulkan SDK 1.4.350.0 `Include\slang\` headers are **byte-identical** to
the upstream tag v2026.8 sources (after newline normalization; the local
clone working tree is CRLF on this host due to git `core.autocrlf`, while
the SDK ships LF -- the git blob content is LF and equals the SDK bytes):

| File | Upstream git blob (LF) | SHA256 (LF-normalized == SDK bytes) |
|------|------------------------|-------------------------------------|
| `include/slang.h` | `955c510a099593e9041ab8989254d3c2fb02ca24` | `80CA5B8DBFC6061AAF9D28D376FD4625FEFE3B36272597BA97FF1384EC84C94D` |
| `include/slang-deprecated.h` | `765e32838f56d8979afea2385e897531a3114bce` | `A764D633FEA9FF3DBCC30DA1E9551E671B2D684BBB1CAFFC3903853B78580C60` |
| `include/slang-image-format-defs.h` | `5e7922f44ef4f6cc412f2470d0909cf54c628f5a` | (X-macro source; 43 `SLANG_FORMAT(...)` entries) |

`Include\slang\slang-tag-version.h` (`#define SLANG_TAG_VERSION "2026.8"`) is
a build-generated artifact (not present in the upstream tree); it confirms
the SDK build matches the cloned tag.

Verification command (re-runnable):

```powershell
git -C E:\repos\slang rev-parse v2026.8   # d88cc8fff35baf96cf30d242b2572564cf8043b6
python - <<'PY'
import hashlib
d = open(r'C:\VulkanSDK\1.4.350.0\Include\slang\slang.h','rb').read()
print(hashlib.sha256(d.replace(b'\r\n', b'\n')).hexdigest().upper())
PY
```

## 3. Files studied / oracle source

- `include/slang.h` -- the C API declarations (`SLANG_API` functions incl.
  the `slang_*` API; 21 `slang_*` declarations), enums, integer macros;
  `SlangImageFormat` is an X-macro enum built from
  `slang-image-format-defs.h` (the generator expands that include exactly
  like the preprocessor -- 43 entries verified against the upstream file's
  43 `SLANG_FORMAT(...)` invocations).
- `include/slang-deprecated.h` -- the legacy `sp*` compile API (265
  declarations) and `#include "slang.h"`.
- `C:\VulkanSDK\1.4.350.0\Bin\slang.dll` **export table** -- the runtime
  oracle for what is actually callable (pure-forwarder proxy to
  `slang-compiler.dll`); parsed with a pure-Python PE reader in
  `tools/gen_slang.py`.

## 4. Derived vs independent

| Artifact | Provenance |
|----------|------------|
| `tools/gen_slang.py` | Independently implemented generator (header declaration parser + C constant-expression evaluator + PE export reader + XIOM emitter). No upstream code copied. |
| `slang.xi`, `src/*` | Generated from the pinned header declarations (an API surface description: names, signatures, enum values). The loader/wrapper code shape is the lane's own dynamic-loader idiom, not Slang implementation code. |
| Constants (`src/gen_const_1.xi`) | Enum values evaluated from the pinned headers' expressions (literals). |
| Runtime link | None at build time; `slang.dll` is loaded by name at run time (`xiom.ffi.dl`). |

No upstream source files, no compiled Slang artifacts, and no upstream test
vectors are stored in this package (binding parity = export coverage:
oracle N == bound N == runtime resolved N; see `docs/COVERAGE.md`).

## 5. Re-carve procedure

1. New SDK: re-hash `Include\slang\slang.h` / `slang-deprecated.h` /
   `slang.dll`; compare with the pins above.
2. `git -C E:\repos\slang fetch --depth 1 origin tag <matching upstream tag>`
   (or re-clone shallow at the tag); verify the header hashes match
   (LF-normalized).
3. `python packages\xiom-slang\tools\gen_slang.py` -- the generator fails
   hard on any mismatch (export-only names, unexpanded X-macros, etc.);
   review `tools/oracle_manifest.json` deltas.
4. Re-run the suite x2 with the new DLL on PATH; update SPEC.md/COVERAGE.md
   pin tables and `scripts/status.ps1` record in one commit.
5. Update the `E:\repos\CLEANUP.md` row (review-after date) via the lane's
   procedure (this lane reports the row; it does not edit the ledger).
