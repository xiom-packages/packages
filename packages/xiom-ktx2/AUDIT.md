# AUDIT: xiom.ktx2

## Status (2026-10-13)

New package 0.1.0. `xiom.ktx` (pure-XIOM KTX1) is untouched; this package
vendors the real libktx at the v4.4.2 pin and links the full write build.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Upstream | KTX-Software v4.4.2 (commit `4d6fc70e`), mirrored + transformed by `tools/vendor_ktx.py` (Apache-2.0; per-component licences in `PROVENANCE.md`) |
| Declared surface | `include/ktx.h`: 93/93 functions bound (address-taken in the bridge symbol table); 517/517 enum consts + 5 macros + 7 VK format consts bound; skips 0 (`tools/oracle_ktx.py check`) |
| Link model | `--c-source` (69 vendored TUs + `src/ktx2_bridge.c` + `src/zstd_shim.c`) via `port.args.json`, `--cxx-standard 17`, `--timeout 1800`; no system library |
| FFI confinement | all `extern "C"` in the root module `ktx2.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 41 checks / 11 sections |
| Runs | **PASS 41/41 x2** on the pin (`scripts/port.ps1 -Package xiom.ktx2 -TimeoutSec 1800`) |

## Surface coverage evidence

* **Link-time**: `kx2_symbols` in `src/ktx2_bridge.c` takes the address of
  every declared function, so a missing symbol fails the link. All 93
  functions resolve.
* **Runtime**: `x2_symbol_count()` returns 93; the suite copies all 93 names
  out and round-trips every one through exact lookup, and rejects unknown
  names.
* **Oracle re-check**: `python tools/oracle_ktx.py check ktx2.xi
  src/ktx2_bridge.c` → 93/93 fns in module, 93/93 referenced in bridge,
  517/517 consts, 5/5 macros, exit 0.

## What the suite exercises at runtime (real library calls)

| Family | Examples |
|---|---|
| KTX2 memory write/read | `ktxTexture2_Create`, `SetImageFromMemory`, `WriteToMemory`, `CreateFromMemory`, `GetImageOffset`, `GetLevelSize`, `GetData`, `GetRowPitch`, `GetElementSize`, `IterateLevelFaces` (callback), `CreateCopy` |
| Supercompression | `DeflateZstd`, `DeflateZLIB`, inflated read-back byte-exact, `LoadDeflatedImageData` on a file-stream texture (deflated bytes byte-compared), `LoadImageData` |
| File path | `WriteToNamedFile`, `CreateFromNamedFile`, `WriteToStdioStream`, `CreateFromStdioStream`, `CreateFromStream` (custom `ktxStream`), `WriteToStream`, `getsize` |
| KTX1 + conversion | `ktxTexture1_Create`, `SetImageFromMemory`, `WriteToMemory`, `CreateFromMemory`, `LoadImageData`, `NeedsTranscoding`, `WriteKTX2ToMemory`, `WriteKTX2ToStream` |
| Basis | `CompressBasis` (ETC1S), `CompressBasisEx` (UASTC), `NeedsTranscoding`, `TranscodeBasis` to BC1/BC7/ETC1/RGBA32, second-transcode typed error, transcoded payload re-read |
| ASTC | `CompressAstcEx` (4x4 LDR fastest), `DecodeAstc` (64-byte RGBA8 result) |
| Metadata | `ktxHashList_Create/CreateCopy/Construct/ConstructCopy/AddKVPair/FindEntry/FindValue/Next/Sort/Serialize/Deserialize/Entry_GetKey/Entry_GetValue/DeleteEntry/DeleteKVPair/Destroy/Destruct` |
| Strings | `ktxErrorString`, `ktxSupercompressionSchemeString`, `ktxTranscodeFormatString` |
| Loader | `ktxLoadOpenGL(NULL)` — documented `KTX_LIBRARY_NOT_LINKED` in a console process |
| Errors | typed codes for short buffer (7), broken identifier (15), truncated file (7), KTX1 magic on a KTX2 body (15) |

Not runtime-called (bound + linked only, printer family — they write to
stdout and would pollute suite output): `ktxPrintInfoForStdioStream`,
`ktxPrintInfoForNamedFile`, `ktxPrintInfoForMemory`,
`ktxPrintKTX1InfoTextForStream`, the four `ktxPrintKTX2InfoText*`, the four
`ktxPrintKTX2InfoJSON*`, plus the stream-variant writers
(`ktxTexture1_WriteToStdioStream`, `ktxTexture1_WriteKTX2ToStdioStream`,
`ktxTexture2_WriteToStdioStream` are partially: the stdio path is exercised
via `ktxTexture2`/base create; KTX1 stdio write is bound-only).

## Known limitations

* ASTC encode/decode is lossy: the suite asserts the decoded size/format and
  not pixel equality.
* ETC software unpack is a documented carve-out (`SPEC.md` §1): GL upload of
  ETC data and `ktxUnpackETC` are off with typed errors.
* Basis SSE/OpenCL kernels off; portable kernels only (correct, slower).
* Windows x64 tested; other platforms untested until a runner exists.
* Deflated-record detail fields (`mismatch_index`, bytes) are diagnostics
  populated only when the raw compare fails; on success they stay 0.
