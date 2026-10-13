# PROVENANCE: xiom.ktx2

## 1. Vendored upstream

| Field | Value |
|---|---|
| Project | Khronos KTX-Software (libktx + Basis Universal transcoder/encoder + dfdutils + Arm ASTC Encoder + zstd) |
| Repository | `https://github.com/KhronosGroup/KTX-Software` |
| Pin | tag **v4.4.2** = commit `4d6fc70eaf62ad0558e63e8d97eb9766118327a6` |
| Licence | Apache-2.0 (project `LICENSE.md`; per-component texts under `vendor/ktx/LICENSES/` and in each `external/` subtree) |
| Clone verified | `git -C E:\repos\KTX-Software rev-parse HEAD` → pin (checked by `tools/vendor_ktx.py` on every run) |
| Extraction | `git cat-file blob <pin>:<path>`, canonical LF bytes from the object store |
| Mirror | 202 files under `vendor/ktx/`, transformed by `tools/vendor_ktx.py` (include rewriting + build-config prologue + generated `lib/version.h`); `vendor/FILES.sha256` is the post-transform manifest |
| Tree sha256 | `B8321FD3410AB89762D184802E0B32489FDE4DC5F1FBB5861FC393F8158CC14D` |

The per-component licences that govern the vendored subtrees:

| Subtree | Licence | Text |
|---|---|---|
| `vendor/ktx/lib`, `vendor/ktx/include` | Apache-2.0 | `vendor/ktx/LICENSE.md`, `vendor/ktx/LICENSES/Apache-2.0.txt` |
| `vendor/ktx/external/dfdutils` | Apache-2.0 | `vendor/ktx/external/dfdutils/LICENSE.adoc` |
| `vendor/ktx/external/basisu` (transcoder + encoder) | Apache-2.0 | `vendor/ktx/external/basisu/LICENSES/Apache-2.0.txt` (plus BSD/Zlib component texts mirrored alongside) |
| `vendor/ktx/external/astc-encoder` | Apache-2.0 | `vendor/ktx/external/astc-encoder/LICENSE.txt` |
| `vendor/ktx/external/basisu/zstd` | BSD-3-Clause | `vendor/ktx/external/basisu/zstd/LICENSE` |
| `vendor/ktx/other_include/GL*`, `KHR` | Khronos/OGC header licences (MIT-style + Apache-2.0) | headers carry SPDX tags; mirrored verbatim |
| `vendor/ktx/LICENSE.md`, `NOTICE.md`, `LICENSES/`, `REUSE.toml` | REUSE metadata | mirrored verbatim |

## 2. Wave-B licence carve-out (ETC software unpack)

The upstream tree contains `external/etcdec/etcdec.cxx` (Ericsson ETC
software unpacker, `LicenseRef-ETCSLA.txt`). It is **not vendored and not
compiled**; `SUPPORT_SOFTWARE_ETC_UNPACK` is pinned to 0 in the build config.
This keeps the wave Apache-2.0-clean. ETC remain reachable as Basis
transcode *targets* (basisu's own writers); `ktxTexture_GLUpload` of ETC
data and `ktxUnpackETC` paths return typed errors instead of decoding.

`include/ktxvulkan.h` and the Vulkan helper implementation
(`lib/vkloader.c`, `lib/vk_funcs.c`) are not in the declared set for
architectural reasons (see `SPEC.md` §1).

## 3. Package-local code

| Path | Licence | Notes |
|---|---|---|
| `ktx2.xi` | MIT OR Apache-2.0 (XIOM Authors) | generated consts block + declarations + wrappers |
| `src/ktx2_bridge.c` | MIT OR Apache-2.0 (XIOM Authors) | probe bridge + symbol table |
| `src/zstd_shim.c` | MIT OR Apache-2.0 (XIOM Authors) | `STATIC_BMI2 0` shim over the vendored amalgamation (same pattern as `xiom.zstd`) |
| `src/compat/strings.h` | MIT OR Apache-2.0 (XIOM Authors) | minimal `<strings.h>` for the Windows clang target |
| `tools/vendor_ktx.py`, `tools/oracle_ktx.py`, `tools/sync_consts.py` | MIT OR Apache-2.0 (XIOM Authors) | vendoring + oracle + consts regeneration |

## 4. Overlap notes (CLEANUP)

* **zstd 1.5.5** is now vendored twice in the ecosystem: `xiom.zstd`
  (standalone) and `xiom.ktx2` (libktx requires its own copy in
  `external/basisu/zstd`). Inlining `xiom.zstd`'s zstd into this package
  would change upstream's include topology and risk divergent behaviour;
  scope note for the CLEANUP row: dedupe only if a shared static-lib
  mechanism lands in the toolchain.
* **xiom.ktx** (pure-XIOM KTX1) is untouched. `xiom.ktx2` also handles KTX1
  through libktx; the pure-XIOM package remains the dependency-free parser.
* **ARM ASTC Encoder** is also used by nothing else in the workspace at
  this time (no overlap).
