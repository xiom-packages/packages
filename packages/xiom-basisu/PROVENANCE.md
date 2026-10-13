# PROVENANCE: xiom.basisu

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

## 1. Upstream

| Field | Value |
|-------|-------|
| Upstream project | Basis Universal -- `https://github.com/BinomialLLC/basis_universal` |
| Verified canonical remote | `origin https://github.com/BinomialLLC/basis_universal` (git protocol, 2026-10-13) |
| Pin | tag `v2_50` = commit `9bebe16726b3a61c8c213eeee3b7cffb462ef34e` (2026-07-22) |
| Library version at pin | `BASISU_LIB_VERSION 250` / `BASISD_LIB_VERSION 250` ("2.50") |
| Clone of record | `E:\repos\basis_universal` (owner-provided shared clone space; **shallow**, `--depth 1` at the tag) |
| Clone ledger | `E:\repos\CLEANUP.md`, row `basis_universal` (lane=bindings, review after 2026-12-01) |

Upstream-first: this package was written against the clone at the pin above, not from
memory. The declared C API surface was read from the pinned headers themselves; the
canonical usage model (`example_capi/example_capi.c`) and the build composition
(`CMakeLists.txt`) were studied in the same clone.

## 2. License (verified in the clone)

| Component | License | Evidence |
|-----------|---------|----------|
| basis_universal core (transcoder + encoder) | Apache-2.0 | `LICENSE`, `NOTICE`; `.reuse/dep5` `Files: *` |
| `zstd/` (vendored Zstandard) | BSD-3-Clause (chosen from BSD-3/GPLv2 dual) | `zstd/LICENSE`; `.reuse/dep5` `Files: zstd/*` |
| `encoder/3rdparty/qoi.h` | MIT | `.reuse/dep5`; header comment |
| `encoder/3rdparty/tinydds.h` | MIT | `.reuse/dep5`; header comment |
| `encoder/3rdparty/tinyexr.h` (+ `exr_reader.hh`, `streamreader.hh`) | BSD-3-Clause | `.reuse/dep5`; header comment |
| `encoder/3rdparty/android_astc_decomp.cpp` | Apache-2.0 (AOSP) | `.reuse/dep5` (`2016 The Android Open Source Project`) |
| `LICENSES/{Apache-2.0,BSD-3-clause,MIT}.txt` | REUSE license texts | vendored verbatim |
| `test_files/` | "not copyrighted or owned by Binomial LLC" (`test_files/license.txt`) | **not vendored** (see section 5) |

Class: permissive throughout -- verbatim vendoring is allowed. The package itself stays
MIT OR Apache-2.0; every vendored file keeps its upstream license text in `vendor/`.

## 3. What was studied, what was derived

**Studied (read for the surface and behavior model)**

- `encoder/basisu_wasm_transcoder_api.h` -- the 68-function transcoder C API (`bt_*`).
- `encoder/basisu_wasm_api.h`, `encoder/basisu_wasm_api_common.h` -- the 13-function
  encoder C API (`bu_*`) and every constant (BTF_*, TF_*, DECODE_FLAGS_*, BU_*).
- `encoder/basisu_wasm_transcoder_api.cpp`, `encoder/basisu_wasm_api.cpp` -- the native
  implementation of the "wasm memory offset" convention (on native builds the offset is
  the pointer value; `bt_alloc` = `malloc`).
- `example_capi/example_capi.c` -- canonical C usage: `bu_init` -> `bu_new_comp_params`
  -> `bu_comp_params_set_image_rgba32` -> `bu_compress_texture` ->
  `bu_comp_params_get_comp_data_size/ofs`, then `bt_ktx2_open` -> `bt_ktx2_start_transcoding`
  -> `bt_ktx2_transcode_image_level`.
- `CMakeLists.txt` -- target composition: `ENCODER_LIB_SRC_LIST` (the static encoder
  library) and the transcoder-only module (`basisu_wasm_transcoder_api.cpp` +
  `basisu_transcoder.cpp` + `zstd/zstddeclib.c`); `BASISU_ZSTD=ON` default,
  `BASISU_SUPPORT_ASTCENC=OFF` default, `BASISU_DISABLE_ANDROID_ASTC_DECOMP=OFF`
  default (so the encoder links `3rdparty/android_astc_decomp.cpp`).
- `transcoder/basisu_file_headers.h`, `transcoder/basisu_transcoder.h`,
  `encoder/basisu_comp.h` -- enum values and flag semantics confirmed against the C
  define set (BTF_*/TF_*/BU_COMP_FLAGS_* match exactly).

**Vendored verbatim (byte-identical to the clone; SHA256 per file in SPEC.md section 2)**

- `vendor/transcoder/**` -- 26 files (transcoder class + tables + helpers).
- `vendor/encoder/**` -- 72 files: the five C API files, the canonical
  `ENCODER_LIB_SRC_LIST` TUs and their headers, `basisu_astc_ldr_pseudoinv_tab.inl`,
  `basisu_bc15_spmd_kernels.inl`, and `3rdparty/**` (6 files).
- `vendor/zstd/**` -- 4 files (`zstd.c` amalgamated compress+decompress, `zstd.h`,
  `zstd_errors.h`, `LICENSE`).
- `vendor/LICENSE`, `vendor/NOTICE`, `vendor/LICENSES/**` -- 5 files.

Verification: all 113 vendored files were re-hashed against the clone on 2026-10-13 and
are byte-identical (`.gitattributes` pins `vendor/** -text`).

**Original XIOM work (MIT OR Apache-2.0)**

- `basisu.xi` -- the raw declaration of all 81 C API functions + constants, the flat
  result shapes and the safe wrappers (no upstream code).
- `src/basisu_bridge.cpp` -- the reviewable buffer bridge: it is the only place foreign
  pointers are touched, keeps every handle/state inside C, and copies the one C-owned
  region (the compressor's `comp_params` payload) into XIOM-owned memory.
- `src/basisu_zstd_all.c` -- 13-line compile shim (`#define STATIC_BMI2 0` + include of
  the vendored `zstd.c`), mirroring the proven `xiom.zstd` shim (`src/zstd_all.c`);
  the vendored file itself is unmodified.
- `tests/test_conformance.xi`, `SPEC.md`, `README.md`, `PROVENANCE.md`.
- Optional build input: `--cxx-standard 17` (the encoder uses C++17 CTAD:
  `std::pair(a, b)`, `std::lock_guard g(m)`).

## 4. Upstream finding (recorded for re-carve)

`bt_ktx2_create_transcode_state()` value-initializes its wrapper struct, so the embedded
`ktx2_transcoder_state::m_uncomp_data_level_index` starts at `0` instead of the `-1` set
by `ktx2_transcoder_state::clear()`. Transcoding **level 0 of a KTX2_SS_ZSTANDARD
payload** with such a fresh state skips the level decompression cache and trips the
transcoder assert (`basisu_transcoder.cpp`: `uncomp_level_data_size ==
m_levels[level_index].m_uncompressed_byte_length`), i.e. a debug-build abort.

Handling in this package: the bridge still creates and destroys a state handle (covering
both C API functions), but the transcode call itself passes `state_handle = 0`, which the
C API documents as valid and which routes to the transcoder's internal default state
(cleared by `ktx2_transcoder::init`). See `src/basisu_bridge.cpp` and SPEC.md section 4.
On re-carve, re-test the zstd path with a created state; if upstream fixes the init, the
workaround can be revisited without surface changes.

## 5. Test data

No upstream test vectors were imported. `test_files/*.ktx2` exists at the pin (and
`test_files/license.txt` states the images are not copyrighted/owned by Binomial), but
the smallest fixture is ~95 KB and this suite does not depend on external binaries:
the encoder C API is part of the declared surface, so the suite **builds its own tiny
payload at runtime** (deterministic 32x32 RGBA gradient -> UASTC/ETC1S/zstd KTX2) and
then transcodes it. Parity evidence is structural and content-based (dimensions, mip
chain, block counts, byte sizes, mean-absolute-error against the source).

## 6. Re-carve procedure

1. Fetch the new upstream tag/commit from the canonical remote into
   `E:\repos\basis_universal` (the clone is shallow: `git fetch --depth 1 origin tag <t>`).
2. Re-verify `LICENSE`, `NOTICE`, `LICENSES/**`, `zstd/LICENSE`, and `.reuse/dep5`.
3. Re-read the C API headers; diff the function set against SPEC.md section 3 (the
   declared surface must stay 100% of the C API; new functions join the same commit).
4. Re-copy the vendored set (same file list; re-check `CMakeLists.txt` for new TUs,
   `.inl` tables and `3rdparty/**` additions); regenerate the SHA256 table in SPEC.md
   section 2; keep `.gitattributes -text`.
5. Re-run `scripts/port.ps1 -Package xiom.basisu -TimeoutSec 1500` (x2), update the
   test matrix in SPEC.md, record via `scripts/status.ps1 -Action update`.
