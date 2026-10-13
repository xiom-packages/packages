# xiom.ktx2 -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Upstream-first carve (KTX-Software v4.4.2 @ 4d6fc70e, object-store extraction, per-component licences) | Done -- 0.1.0 |
| Declared surface 100 % of pinned `ktx.h` (93/93 bound, oracle-checked) | Done -- 0.1.0 |
| Vendored write build (libktx + Basis transcoder/encoder + ASTC + zstd) links | Done -- 0.1.0 |
| KTX2/KTX1 write+read round trips, ZSTD/ZLIB, streams, named file | Done -- 0.1.0 |
| Basis transcode (ETC1S/UASTC -> BC1/BC7/ETC1/RGBA32) | Done -- 0.1.0 |
| ASTC encode/decode | Done -- 0.1.0 |
| Corrupt-input typed errors | Done -- 0.1.0 |
| Suite green x2 on the pin | Done -- 0.1.0 |

## Next (0.2.x candidates)

1. **Ergonomic consumer API** beyond the probe wrappers: a `Ktx2Texture`
   handle type that owns the 8-byte slot, `write_file`/`read_file` helpers,
   and typed enums for formats (the raw 93-function surface stays).
2. **ASTC pixel-quality check** (PSNR threshold vs the source fixture) once
   a deterministic compare policy is agreed; today the decode check is
   size/format-only.
3. **Basis encode quality tiers**: expose `ktxBasisParams` fields (RDO,
   normal maps, selector RDO) through the bridge; today the probe uses
   defaults and `uastcFlags = KTX_PACK_UASTC_LEVEL_DEFAULT`.
4. **Compression-side GL probe**: `ktxTexture_GLUpload` success path needs a
   real GL context; keep it as a context-dependent opt-in probe.
5. **Re-pin** to the next KTX-Software tag (procedure in `SPEC.md` §2).
6. **CLEANUP**: shared-static-lib mechanism to dedupe vendored zstd with
   `xiom.zstd` if the toolchain ever supports it (see `PROVENANCE.md` §4).

## Non-goals

* `ktxvulkan.h` upload helpers (engine owns Vulkan; `xiom.vulkan`).
* Ericsson ETC software unpack (licence carve-out, `SPEC.md` §1).
* Basis SSE/OpenCL kernel parity (portable kernels are the contract).
