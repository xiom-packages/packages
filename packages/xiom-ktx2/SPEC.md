# SPEC: xiom.ktx2

**Version**: 0.1.0 | **Compiler pin**: xiom v0.64.4 | **SPDX**: MIT OR Apache-2.0

KTX2 texture container and Basis Universal transcode bindings for XIOM,
backed by a vendored build of Khronos **libktx** (KTX-Software v4.4.2,
commit `4d6fc70eaf62ad0558e63e8d97eb9766118327a6`, Apache-2.0).

`xiom.ktx` (the pure-XIOM KTX1 package) is untouched by this package; this
is the KTX2/Basis lane. The two can coexist: `xiom.ktx` parses KTX1 in pure
XIOM, `xiom.ktx2` wraps the real libktx (KTX1 + KTX2 + Basis + ASTC).

## 1. Declared surface (oracle)

The declared surface is the public API of the pinned `include/ktx.h`, plus
the `KHR/khr_df.h` enums and the `VK_FORMAT_*` values the package names.

`tools/oracle_ktx.py` parses the vendored headers (they are the single
source of truth; there are no manual lists) and drives both the module
generation and the coverage check:

| Oracle item | Declared | Bound | Skips |
|---|---|---|---|
| `KTX_API` functions in `include/ktx.h` | 93 | 93 | 0 |
| Enum values in `include/ktx.h` + `include/KHR/khr_df.h` | 517 | 517 | 0 |
| Numeric macros in `include/ktx.h` | 5 | 5 | 0 |
| `VK_FORMAT_*` subset (from `lib/vkformat_enum.h`) | 7 | 7 | 0 |

* **Declared functions** are emitted as `extern "C"` declarations in
  `ktx2.xi` (they document the pinned ABI; runtime calls go through the
  bridge).
* **Bound in the bridge** means every function's address is taken in the
  `kx2_symbols` table of `src/ktx2_bridge.c`. Linking the suite therefore
  *fails* if any declared function is missing from the vendored build; the
  suite additionally asserts `x2_symbol_count() == 93` and round-trips all
  93 names through `x2_symbol_name` / `x2_symbol_lookup`.
* `python tools/oracle_ktx.py check ktx2.xi src/ktx2_bridge.c` re-verifies
  all four rows (exit 1 on any gap).

### Headers excluded from the declared set (documented carve-outs)

| Header | Reason |
|---|---|
| `include/ktxvulkan.h` | Vulkan upload helper layer (`ktxVulkanTexture`, `ktxVulkanTexture_UploadFromStream`). It requires Vulkan headers plus a live `VkDevice`/`VkQueue`; the engine owns its own Vulkan path via `xiom.vulkan`. `ktxLoadOpenGL`/`ktxTexture_GLUpload` from `ktx.h` stay in scope (GL loader only). |
| `lib/ktxvulkan_impl` sources (`lib/vkloader.c`, `lib/vk_funcs.c`) | Private implementation of the header above; not compiled. No `ktx.h` function references them when the Vulkan helper layer is not built. |
| `external/etcdec/` (Ericsson ETC software unpacker) | Carries the Ericsson ETC SLA reference; excluded to keep the wave Apache-2.0-clean (`SUPPORT_SOFTWARE_ETC_UNPACK 0`). Consequence: GL-side "unpack ETC to RGBA" and the `KTX_UNSUPPORTED_FEATURE` path for it are off. Basis transcode **to** `ETC1_RGB`/`ETC2` targets still works (basisu's own writers; exercised by the suite). |
| `external/astc-encoder` CLI, `utils/`, `tools/`, test assets, `docs/` | Build-system/CLI-only; not part of the C API. |
| `lib/gl_funclist.inl` | Included by `gl_funcs.c` (data table), not a standalone header. |

## 2. Vendoring (G2 pin)

* **Source**: `git clone` of `https://github.com/KhronosGroup/KTX-Software`
  at tag **v4.4.2** = `4d6fc70eaf62ad0558e63e8d97eb9766118327a6` (verified by
  `tools/vendor_ktx.py` on every run; mismatch aborts).
* **Extraction**: `git cat-file blob <pin>:<path>` — canonical LF bytes from
  the clone's object store (no working-tree EOL conversion).
* **Mirror**: 202 files under `vendor/ktx/` (libktx `include/` + `lib/`,
  `external/dfdutils`, `external/basisu/transcoder` + `encoder` + `zstd`,
  `external/astc-encoder/Source`, `other_include/GL*`, root licences).
  Byte-verbatim apart from the two mechanical transformations below.
* **Transformation 1 — include rewriting**: every `#include` that resolves
  to a vendored header becomes an exact relative path, using the upstream
  CMake search order (own directory first for quoted includes; angled
  includes resolve only through the search list, matching clang semantics).
  The XIOM link line has no `-I` passthrough, so this is what makes the
  tree compilable. `<strings.h>` (absent from the Windows clang target) is
  mapped to `src/compat/strings.h`, a 20-line package-local shim.
* **Transformation 2 — build-config prologue**: each compiled libktx/Basis
  TU gets a two-line prologue including `vendor/ktx/xiom_build_config.h`:

  ```c
  #define KHRONOS_STATIC 1   /* static link: KTX_API is empty */
  #define LIBKTX 1           /* upstream private define; skips jpgd/pvpngreader */
  #define KTX_FEATURE_WRITE 1  /* writer1.c/writer2.c + Deflate* */
  #define KTX_FEATURE_KTX1 1   /* ktxTexture1_* surface */
  #define KTX_FEATURE_KTX2 1
  #define SUPPORT_SOFTWARE_ETC_UNPACK 0  /* wave-B licence carve-out */
  #define BASISD_SUPPORT_KTX2 1
  #define BASISD_SUPPORT_KTX2_ZSTD 0     /* upstream ktx-target setting */
  #define BASISD_SUPPORT_FXT1 0          /* upstream ktx-target setting */
  #define BASISU_SUPPORT_SSE 0           /* no per-TU -msse4.1 on the xiom line */
  #define BASISU_SUPPORT_OPENCL 0
  ```

  The Arm ASTC TUs get **no** prologue: `astcenc_mathlib.h` auto-detects the
  baseline SSE2 backend from the compiler macros (no extra ISA flags).
* **Generated file**: `vendor/ktx/lib/version.h` (`LIBKTX_VERSION v4.4.2`)
  mirrors upstream `scripts/mkversion` output, which CMake would generate;
  the source tree does not ship it.
* **Pin artefacts**: `vendor/FILES.sha256` (sha256 + size for all 202 files,
  post-transform) and the aggregate tree sha256 quoted in
  `PROVENANCE.md`. `tools/vendor_ktx.py --hash` recomputes it.
* **Re-pin procedure**: update `PIN_COMMIT`/`PIN_TAG`/`LIBKTX_VERSION` in
  `tools/vendor_ktx.py`, run it against a clone checked out at the new tag,
  then `python tools/sync_consts.py ktx2.xi` and re-run the oracle check and
  the suite.

### Compiled translation units (69)

* **libktx C (19)**: checkheader, filestream, glformat_str, hashlist, info,
  memstream, strings, swap, texture, texture1, texture2, vkformat_check,
  vkformat_check_variant, vkformat_str, vkformat_typesize, gl_funcs,
  glloader, writer1, writer2.
* **dfdutils C (6)**: createdfd, colourspaces, interpretdfd, printdfd,
  queries, vk2dfd.
* **libktx/Basis C++ (20)**: astc_codec, basis_transcode, basis_encode,
  miniz_wrapper, basisu_transcoder + the 15 basisu encoder TUs.
* **Arm ASTC C++ (22)**: the `astcenc-sse2`-equivalent static-lib sources
  (no CLI, no `astcenc_platform_isa_detection`).
* **Package code (2)**: `src/ktx2_bridge.c` (probe surface + symbol table),
  `src/zstd_shim.c` (vendored zstd 1.5.5 amalgamation with `STATIC_BMI2 0`;
  the xiom C line passes `-mavx2` but no `-mbmi2`, so zstd's auto-detected
  BMI2 intrinsics path must be pinned off — same shim as `xiom.zstd`).

Compile model: `--cxx-standard 17` (C++ TUs compile in dedicated
invocations), `--timeout 1800` in `port.args.json`.

## 3. Safe boundary (G5) and probe records

All `extern "C"` is confined to `ktx2.xi`. XIOM never dereferences a foreign
pointer and never casts a handle (B-20/B-25): a texture handle lives as an
opaque 8-byte token in a caller-owned slot, and every `x2_*` bridge call
re-reads it in C. Out-parameters are caller-owned byte slots read
little-endian (B-11/B-16/B-17); statuses travel as C return values (B-24);
fallible results are flat structs or `Result[_, Int]`, never
`Result[Option[_]]` (B-26).

Record layouts (little-endian; every slot is zero-filled by the bridge):

| Probe | Record | Fields |
|---|---|---|
| `x2_read_info` (128 B) | KTX1/KTX2 parse | class_id, vk_format, dims, levels/layers/faces, flags, supercompression, components, needs_transcoding, data_size u64, format codes, video fields |
| `x2_roundtrip_probe` (128 B) | in-memory write/read (modes 0/1/2) | write/read rc+len, class/vk/levels, data_size, level0 len+cmp, iterate stats, scheme, row pitch/element size, copy rc, tf/oetf/color model/primaries getters+setters (`KHR_DF_TRANSFER_LINEAR` for UNORM), num_components |
| `x2_named_file_probe` (64 B) | `%TEMP%` round trip | create/write/read rc, class, data_size, file bytes, removed, path len |
| `x2_deflated_probe` (96 B) | deflated-load path | deflate/write rc, scheme, deflated size, `LoadDeflatedImageData` rc, raw byte-compare vs the captured deflate output, `pData` null, fresh-read inflate rc + pixel compare, file bytes, removed |
| `x2_ktx1_probe` (96 B) | KTX1 + conversion | create/set/write/read rc, class, data_size, `LoadImageData` + compare, GL trims, `WriteKTX2ToMemory` rc/len, re-read scheme/vk/level0 |
| `x2_stream_probe` (96 B) | custom `ktxStream` + stdio | write/read rc + len, class, data_size, pixel compare, `getsize` equal to written, stdio write/rewind/read rc, KTX1 stream + `WriteKTX2ToStream` |
| `x2_basis_probe` (128 B) | Basis encode/transcode | encode rc, needs_transcoding, transcode rc, vk after, scheme, data_size, level0, components, second-transcode typed error, payload write + re-read vk |
| `x2_astc_probe` (64 B) | ASTC encode/decode | compress rc, vk after, is_compressed, data_size, level0, write rc/len, decode rc, vk after decode, decoded bytes len |
| `x2_hashlist_probe` (96 B) | metadata API | create/add/find rc, value len + 4 value bytes, Next count, sort/serialize rc + len, deserialize/find rc, value bytes, key len + 4 key bytes, GetValue rc, delete/destroy/copy rc + entry counts, construct/destruct |
| `x2_c_string` (`len` u64) | string tables | selector 0/1/2 copies `ktxErrorString` / `ktxSupercompressionSchemeString` / `ktxTranscodeFormatString` into an owned buffer |
| `x2_gl_probe` (32 B) | GL loader | load rc, upload rc (`0xFFFFFFFF` = not attempted), gl error, texture id, target, class id |
| `x2_corrupt_probe` (32 B) | corrupt input | typed status, then class_id/data_size/levels when the buffer parses |

## 4. Suite

`tests/test_conformance.xi` — **41 checks** in 11 sections, 100 % passing
twice on the pin (`scripts/port.ps1 -Package xiom.ktx2 -TimeoutSec 1800`):

1. Constants (4): error codes, supercompression + create flags, transcode
   formats, DFD/VK format values.
2. Declared surface (4): symbol count 93, representative lookups, all-name
   round trip, unknown-name rejection.
3. KTX2 in-memory round trip (11): 4x4 RGB8 write → read (levels/format/
   bytes/identifier), info record, row pitch + `IterateLevelFaces`, copy +
   color setters, ZSTD + ZLIB supercompression, lifecycle primitives over
   owned handle slots (incl. double-destroy typed error), deflated-load
   file path for both schemes.
4. Named file (2): `%TEMP%` round trip + cleanup.
5. KTX1 + conversion (3): KTX1 write/read round trip, GL trims,
   `WriteKTX2ToMemory` → parseable KTX2.
6. Streams (3): custom `ktxStream` KTX2 round trip + `getsize`, tmpfile
   stdio round trip (base + typed create), KTX1 stream + KTX1→KTX2 stream.
7. Basis transcode (4): ETC1S→BC1, UASTC→BC7, ETC1S→ETC1, ETC1S→RGBA32.
8. ASTC (2): `CompressAstcEx` (4x4 LDR fastest) + `DecodeAstc`.
9. Hash list (2): full metadata API (create/add/find/next/sort/serialize/
   deserialize/entry getters/delete/destroy/construct/construct-copy).
10. Strings + GL (2): the three string tables; `ktxLoadOpenGL(NULL)` in a
    console process returns `KTX_LIBRARY_NOT_LINKED` (upstream contract:
    the loader is only resolved when the application has already loaded GL).
11. Corrupt input (4): 4-byte buffer (`KTX_FILE_UNEXPECTED_EOF`), broken
    identifier (`KTX_UNKNOWN_FILE_FORMAT`), half-truncated file (7), KTX1
    identifier on a KTX2 body (15).

## 5. What is enabled at build time (honest report)

| Capability | State |
|---|---|
| KTX1 create/write/read | On (`KTX_FEATURE_KTX1`), `ktxTexture1_*` all bound |
| KTX2 create/write/read | On (`KTX_FEATURE_WRITE`), incl. ZSTD/ZLIB supercompression (vendored zstd 1.5.5 + miniz) |
| ETC1S encode (Basis) | On (`BASISD_SUPPORT_KTX2`, encoder TUs compiled; portable kernels — `BASISU_SUPPORT_SSE 0`) |
| UASTC encode (Basis) | On |
| Basis transcode targets | On: BC1/BC3/BC7, ETC1/ETC2 family, ASTC, RGBA32 (basisu transcoder defaults minus FXT1) |
| ASTC encode/decode (Arm) | On (full `astcenc` library, SSE2 auto-detect backend) |
| ETC software unpack (Ericsson etcdec) | **Off** — wave-B licence carve-out; `ktxTexture_GLUpload` of ETC data and `ktxUnpackETC` paths return typed errors |
| OpenGL upload | Loader compiled; `ktxLoadOpenGL(NULL)` returns `KTX_LIBRARY_NOT_LINKED` unless the process already loaded GL (documented upstream behaviour) |
| Vulkan upload helper (`ktxvulkan.h`) | Not compiled (excluded header, see §1) |
| Basis SSE/OpenCL kernels | Off (portable paths; determinism over speed for a binding layer) |

## 6. Known limitations

* `basisu` encoder TUs compile in the dedicated `-std=c++17` invocation at
  `-O0` (the xiom C++ path passes no optimisation flags); the binding is
  correct but the encoder is not tuned for speed. Encode of a 4x4 texture is
  instantaneous; large texture encodes will be slower than an upstream
  release build.
* The suite is Windows x64 (the tested host). The vendored tree is portable
  (no platform code outside `glloader.c`/`filestream.c`), but other
  platforms are untested until a runner exists.
* `ktxHashList_*` keys are stored with their NUL terminator upstream
  (`keyLen == strlen + 1`); the suite pins that behaviour.
* zstd 1.5.5 is vendored twice in the ecosystem (`xiom.zstd` and here, as
  libktx requires its own copy). See `PROVENANCE.md`.
