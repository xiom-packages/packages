<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Codec/container wave B -- clone-protocol prep (PREP-ONLY)

Relay: `REL-20261013-1926-packages` (owner-prioritized for the engine). Lane: bindings.
Policy: `docs/UPSTREAM-FIRST.md` sec. 6 (clone hygiene) is enforced for this wave: every
candidate upstream was cloned into `E:\repos\<name>`, pinned to a release tag, license-
verified on touch, and registered in `E:\repos\CLEANUP.md`. No orphan clones.

This document is research output only: no package was created or modified, no build was
run, no compiler work is implied. All pins were resolved on 2026-10-13 against the
canonical remotes (git protocol); all license files were read in the clones themselves.

## 0. Summary

| # | Candidate | Upstream + exact pin | License (class) | Recommendation |
|---|-----------|----------------------|-----------------|----------------|
| 1 | Streaming audio | `gitlab.xiph.org/xiph/opus` v1.6.1 = `22244de5a79bd1d6d623c32e72bf1954b56235be`; `gitlab.xiph.org/xiph/ogg` v1.3.6 = `be05b13e98b048f0b5a0f5fa8ce514d56db5f822` | BSD-3-Clause (permissive) | Pick Opus + libogg; Vorbis evaluated, not selected |
| 2 | Spatial audio | `github.com/ValveSoftware/steam-audio` clone @ `480dd64` (`v4.8.1-10-g480dd64`; package pin stays v4.8.1) | Apache-2.0 (permissive; third-party notices) | Extend `xiom.phonon` full-surface; no new lib |
| 3 | Volumetric container | `github.com/AcademySoftwareFoundation/openvdb` v13.1.0 = `e26f5a569201d3236e0c30580572101022d3d754` | Apache-2.0 (permissive; MPL->Apache re-license note) | Build a minimal own reader; OpenVDB stays oracle |
| 4 | Splat compression | `github.com/nianticlabs/spz` v3.0.0 = `5bf2945de1a003cee07133b1e495fe9c6ffdc7e7` | MIT (permissive) | Bind at pin (read/unpack; pack optional at cook) |
| 5 | Texture container + transcode | `github.com/KhronosGroup/KTX-Software` v4.4.2 = `4d6fc70eaf62ad0558e63e8d97eb9766118327a6`; `github.com/BinomialLLC/basis_universal` v2_50 = `9bebe16726b3a61c8c213eeee3b7cffb462ef34e` | Apache-2.0 (+ per-component; zstd BSD-3; ETC ref) | libktx for read/transcode; resolve one-basisu policy |
| 6 | Text shaping + subset | `github.com/harfbuzz/harfbuzz` 14.6.0 = `c7a7457b7385f33178e8cf87615ca077a810bbe7` | Old MIT-class (permissive) | Bind at pin; cook-time surface (shape + subset) |

All eight clones are **shallow** (`--depth 1` at the pinned tag). Re-carve must fetch the
tag/commit from the canonical remote before studying diffs.

Existing packages this wave must compose with (no edits made here):

- `xiom.ogg` 0.1.2 (stable, pure-XIOM): Ogg **page layer** only; packet reassembly is an
  explicit non-goal -- relevant to the libogg proposal below.
- `xiom.ktx` 0.1.2 (stable, pure-XIOM): **KTX 1** structural codec; KTX2 unsupported.
- `xiom.phonon` 0.2.0 (incubating, runtime-load): 3 pilot entry points bound; Steam Audio
  is the upstream.
- `xiom.meshopt` 0.4.0 (shipped): vendored-C++ precedent for the vendoring model below.

## 1. Streaming audio codec -- pick: libopus + libogg (libvorbis evaluated)

**Upstreams + exact pins**

| Repo | Canonical | Pin | Commit | Clone |
|------|-----------|-----|--------|-------|
| opus | `gitlab.xiph.org/xiph/opus` (GitHub mirror `xiph/opus`) | tag `v1.6.1` | `22244de5a79bd1d6d623c32e72bf1954b56235be` | `E:\repos\opus` (shallow) |
| ogg | `gitlab.xiph.org/xiph/ogg` | tag `v1.3.6` | `be05b13e98b048f0b5a0f5fa8ce514d56db5f822` | `E:\repos\ogg` (shallow) |
| vorbis | `gitlab.xiph.org/xiph/vorbis` | tag `v1.3.7` | `0657aee69dec8508a0011f47f3b69d7538e9d262` | `E:\repos\vorbis` (shallow) |

**License + class**: all three BSD-3-Clause (`COPYING` verified in each clone). opus also
ships `LICENSE_PLEASE_READ.txt`: contributions under Modified BSD or Clear BSD and the
IETF/Zen IPR statements (royalty-free patent posture). Class: permissive -- port/derive OK.

**Why Opus over Vorbis (size/SIMD story, measured in the clones)**

- SIMD: opus has runtime CPU detection (RTCD) with arch trees `celt/x86`, `celt/arm`,
  `silk/x86`, `silk/arm`, `silk/fixed/x86`, `silk/float/x86`, `dnn/x86`, `dnn/arm`
  (SSE2/SSE4.1/AVX on x86 via `celt/x86/x86cpu.c`, `pitch_sse2/4_1`, `pitch_avx`,
  `vq_sse2`, `celt_lpc_sse4_1`; NEON on ARM). Intrinsics are ON by default in both build
  systems (CMake `OPUS_DISABLE_INTRINSICS=OFF`; autotools `enable_intrinsics=yes`).
  libvorbis has no arch trees or intrinsics (pure C: `mdct.c`, `smallft.c`); libogg has
  none either (0 SIMD hits in `src/`).
- Size: measured sources -- opus `celt/`+`silk/`+`src/` = 3,658,814 bytes; vorbis `lib/`
  = 2,229,905 bytes; ogg `src/` = 125,739 bytes. Comparable source mass, but Opus is the
  modern streaming/real-time codec (RFC 6716; interactive latency, PLC, wide bitrate
  range) while Vorbis is legacy-only and offers no SIMD decode acceleration.
- Default opus build needs **no model downloads**: `OPUS_DRED`, `OPUS_OSCE`,
  `OPUS_DEEP_PLC` all default OFF in CMake (and `--enable-dred/--enable-osce` default
  `no`), so the git clone builds cleanly. Vorbis-only would save no meaningful weight
  versus the Opus + libogg pair.
- Verdict: **Opus + libogg**. The `vorbis` clone is retained as a wave-B evaluation
  fallback (legacy `.ogg` music) only; if a concrete consumer appears, add libvorbis as
  an optional binding later. Do not dual-codec now.

**What it gives the engine**: `.opus`/`.ogg`/`.oga` decode (Ogg-encapsulated), raw packet
decode for low-latency/WebRTC-style streaming, packet-loss concealment, and granulepos-
based seeking; Ogg gives page framing, packet reassembly and seek primitives.

**Proposed binding surface (surface-first: read/decode/seek/stream)**

- read: `ogg_sync_init/ogg_sync_buffer/ogg_sync_pageout` -> `ogg_stream_init/ogg_stream_pagein/
  ogg_stream_packetout` (pages -> packets), identification/comment header parse
  (`OpusHead`/`OpusTags`: channels, pre-skip, gain, mapping).
- decode: `opus_decoder_create` + `opus_decode_float` per packet; `opus_multistream_decoder_*`
  for >2 channels; `opus_packet_get_nb_samples`/`opus_packet_parse` for framing;
  concealment via `opus_decode(..., NULL)` plus `opus_decoder_ctl(GET_FINAL_RANGE)`.
- seek: bisect byte offsets using `ogg_sync_pageout` + `ogg_page_granulepos`
  (canonical algorithm lives in libvorbisfile/opusfile); map granulepos -> sample time,
  honor `pre-skip` and end trim (gapless).
- stream: pull model -- feed chunks to `ogg_sync_buffer`, drain pages/packets, decode
  into a PCM ring buffer; no threads required in the library.

**Vendoring model**: vendor `libopus` and `libogg` C sources verbatim (`src/**` + `COPYING`)
and compile at port time -- the `xiom.meshopt` pattern (`vendor/**` byte-pinned,
`.gitattributes -text`). No canonical Windows system Opus exists, so a dynamic-loader-only
binding has no reliable present path. Optional dynamic variant (`opus.dll`) is possible but
not the primary.

**Dependency risks**

- None beyond C99 + optional intrinsics; `OPUS_HARDENING` is ON by default.
- DRED/OSCE/Deep-PLC are OFF by default and, if ever enabled, require model tarballs from
  `media.xiph.org` (not in git; `dnn/download_model.sh` fetches them) -- treat as
  out-of-scope until a use case exists.
- Upstream test vectors are not in git; import `opus_testvectors` (RFC 8251 set) at port
  time for parity (`tests/run_vectors.sh` documents the expected layout).

## 2. Spatial audio -- extend `xiom.phonon` (Steam Audio); no new lib

**Upstream + pin**: `github.com/ValveSoftware/steam-audio`, clone at `480dd64`
(`v4.8.1-10-g480dd64`, full clone). Note: the last 10 commits are **not** in tag v4.8.1,
including `480dd64` "Fix ambisonic conversion; (#544)" -- directly relevant to ambisonics.
`xiom.phonon` 0.2.0 pins v4.8.1, so the wave must re-pin to a tag/commit containing #544
when extending (record in PROVENANCE at that time).

**License + class**: Apache-2.0 (`LICENSE.md`). Third-party notices in `core/THIRDPARTY.md`
(incl. Intel IPP binary license, FFTS, MySOFA) -- relevant only if the engine **redistributes**
a Valve-built `phonon.dll`; the binding itself vendors nothing.

**What it covers (verified in `core/src/core/phonon.h`)**

- Ambisonics: `iplAmbisonicsEncodeEffect*`, `iplAmbisonicsDecodeEffect*` (speaker/binaural
  decode), `iplAmbisonicsPanningEffect*`, and N3D/SN3D/FUMA conversion via
  `iplAudioBufferConvertAmbisonics`.
- HRTF: `iplHRTFCreate` with `IPL_HRTFTYPE_DEFAULT` or `IPL_HRTFTYPE_SOFA`
  (`sofaFileName` or in-memory `sofaData` buffer) + norm types; binaural rendering via
  `iplBinauralEffect*` with interpolation modes.

**Proposal -- extension, not a new library**

- Extend `xiom.phonon` from its 3 pilot entry points to the full ambisonics + HRTF +
  binaural groups (encode/decode/panning effects, audio buffers, HRTF create/SOFA).
  Dynamic-loader model stays (`phonon.dll`, runtime-resolved via `xiom.ffi.dl`; runtime
  SKIP when absent is a platform state, not a gap).
- Ambisonic **container**: Steam Audio processes, it does not store. Spec the container
  engine-side (small cook-time format: channel order, N3D/SN3D, sample rate, snapshots)
  rather than adopting a new upstream; IAMF-style containerization is a spec-only fallback
  if a consumer ever needs it. No new clone needed.
- HRTF **rendering data**: already covered by the API (SOFA file/buffer -> `iplHRTFCreate`).
  Do **not** add an HDF5/SOFA reader of our own (SOFA is HDF5-backed; the SDK reads it
  internally via MySOFA). Dataset licenses vary per SOFA file -- verify before bundling any
  default HRTF.

**Dependency risks**: IPP notice on redistributed Valve binaries; SOFA dataset licensing;
Windows-x64-only soname today (matches the package's declared platform).

## 3. Volumetric container -- recommend: minimal own reader (OpenVDB as oracle)

**Upstream + pin**: `github.com/AcademySoftwareFoundation/openvdb` v13.1.0 =
`e26f5a569201d3236e0c30580572101022d3d754` (shallow clone, 24.9 MB).

**License + class**: Apache-2.0 (`LICENSE`; `RE-LICENSE_NOTE.txt` records the MPL-2.0 ->
Apache-2.0 re-license). nanoVDB headers are SPDX `Apache-2.0` in-tree. Class: permissive
-- copying is allowed, but the dependency tree is the problem, not the license.

**What it gives**: the reference sparse-volumetric tree/format (root + internal/leaf
nodes, tiles, per-grid transforms), file I/O (`openvdb/openvdb/io/`:
`Archive`, `GridDescriptor`, `Compression`, `Stream`, delayed-load metadata), optional
Blosc/zlib compression, half support via Imath, plus nanoVDB (`nanovdb/`) as a
read-mostly GPU-friendly serialization of sparse volumes.

**Dependency tree assessment (from CMake)**: core requires Boost (iostreams), TBB,
Log4cplus, zlib and Imath; optional Blosc, jemalloc, OpenEXR/OpenImageIO (tools), CUDA
(nanoVDB tools), Python/nanobind (bindings). That is not an acceptable runtime dependency
set for the engine, and the engine's actual needs (dense grid + sparse brick + compressed
variant + mip/LOD, seek/stream) are a subset that an engine-native format can express
more directly (mmap-friendly header, per-brick index, async reads).

**Recommendation**: build the engine's **own minimal reader** with a cook-side writer; keep
OpenVDB as the semantic reference and test oracle (tree/tile/mip design, empty-tile
semantics, compression lessons), shipping no OpenVDB code and no dependencies. If DCC
`.vdb` interop becomes a hard requirement later, the middle path is a nanoVDB read path
(header-mostly, Apache-2.0) with OpenVDB used only at cook -- deferred.

**Proposed surface (own reader)**: open/metadata -> grid enumeration + transforms ->
dense tile read -> sparse brick read (all codec variants) -> LOD select -> streaming
cursor (async job per brick). This is a native package, not a binding -- coordinate the
package name/spec with the packages lane.

**Dependency risks**: do not re-implement the `.vdb` binary format (complex, versioned);
brick quantization/packing decisions belong to the native reader spec.

## 4. Splat compression -- nianticlabs/spz

**Upstream + pin**: `github.com/nianticlabs/spz`, tag `v3.0.0` =
`5bf2945de1a003cee07133b1e495fe9c6ffdc7e7` (latest plain release; metadata-variant tags
`+adobe.*`/`+lucas.*` exist and were deliberately not pinned). Observed: `CMakeLists.txt`
still declares project `VERSION 1.1.0` (stale vs tag; the format header version is 4).

**License + class**: MIT (`LICENSE`, Niantic Labs 2024). `third_party/nanobind` (BSD-3
style) is only for the optional Python bindings -- not needed. Class: permissive.

**What it gives the engine**: `.spz` = compressed 3D Gaussian splats (quantized
position/scale/rotation + SH): fixed-point positions (`fractionalBits`), smallest-three
quaternion packing, SH up to degree 4 (24 coeffs; `DEFAULT_SH1_BITS=5`,
`DEFAULT_SH_REST_BITS=4`), per-version flags (`usesFloat16`, `antialiased`), coordinate
conversion (RUB internal; RDF/LUF/RUF converters), and an extensions mechanism (Adobe
safe-orbit-camera lives in `extensions/`, `SPZ_BUILD_EXTENSIONS=OFF` by default).
Upstream reports ~10x smaller than `.ply`.

**Proposed binding surface (surface-first: read/decode/seek/stream)**

- read/decode: `spz::loadSpz(path|istream)` -> `GaussianCloud` (`src/cc/load-spz.h`;
  also C surface in `splat-c-types.h`); unpack expands quantized fields to floats.
- seek: **none by design** -- the file is a single compressed blob (header version 4 =
  zstd; earlier = zlib). Random access requires decompressing the stream up to the target.
- stream: feed the decompressor sequentially and emit splats in blocks; budget the SH
  expand cost at load/stream time.
- cook: pack (`PackOptions`: `fractionalBits`, coordinate system) -- optional; Python
  bindings upstream exist if the cook prefers them.

**Vendoring model**: vendor `src/cc` at pin + zlib + zstd. Upstream CMake falls back to
`FetchContent` of zlib 1.3.1 and zstd 1.5.6 when not found -- vendor instead; builds must
not fetch at configure time.

**Dependency risks**: format churn across v1..v4 headers (interop readers vary); zstd is
shared with other packages -- single-vendored-copy policy applies; young format, pin hard.

## 5. Texture container + Basis/BCn transcode -- KTX-Software (+ basisu alignment)

**Upstreams + pins**

| Repo | Pin | Commit | Notes |
|------|-----|--------|-------|
| KTX-Software | tag `v4.4.2` | `4d6fc70eaf62ad0558e63e8d97eb9766118327a6` | emergency fix release replacing withdrawn v4.4.1 |
| basis_universal | tag `v2_50` | `9bebe16726b3a61c8c213eeee3b7cffb462ef34e` | `BASISU_LIB_VERSION_STRING "2.50"`, tag commit 2026-07-22 |

**License + class**: KTX-Software Apache-2.0 (`LICENSE.md`; per-component `LICENSES/` via
REUSE: Zstd BSD-3, Zlib, MIT, BSL-1.0, CC-BY for docs/test data; `etcdec/` carries the
Ericsson ETC SLA ref -- **exclude ETC output** from wave B to stay Apache-2.0-clean; BC/
ASTC/Basis paths are fine). basis_universal Apache-2.0 (+ zstd BSD-3, MIT in `LICENSES/`).
Class: permissive with one conditional ETC carve-out.

**Version-skew finding**: KTX v4.4.2 vendors basisu as a git-subrepo at commit
`1f4b564ae0b8ec1e67f21f058e53112d0405a25a` (**2022-02-24**, via `external/basisu/.gitrepo`),
trimmed (transcoder tree 2.36 MB vs upstream 4.07 MB; upstream ASTC-HDR work absent).
Runtime transcode quality/features therefore come from the older in-KTX copy; the newer
v2.50 encoder exists only standalone.

**What it gives the engine**: KTX2 container read (UASTC/Basis supercompression, zstd
deflate, mips, arrays/cubemaps; KTX1 read too) and GPU-format transcode at runtime
(BC1/BC3/BC4/BC5/BC7/ASTC/...), plus an encode path for cook.

**Compose with the existing package**: `xiom.ktx` 0.1.2 covers KTX1 structure in pure
XIOM only (KTX2 explicitly out of scope). Proposal: extend `xiom.ktx` (v0.2) with the
KTX2 + transcode surface via vendored libktx, keeping the pure-XIOM KTX1 path as-is --
or split a new `xiom.ktx2`. Owner decision; recommended: extend (one texture-container
package, same domain).

**Proposed binding surface (surface-first: read/decode/seek/stream)**

- read: `ktxTexture_CreateFromMemory` / `ktxTexture_CreateFromNamedFile` (KTX1+2);
  `ktxTexture_IterateLevels`/`ktxTexture_GetImageOffset` for mips/subimages; `ktxTexture2_
  NeedsTranscoding`; metadata via `ktxHashList`.
- decode: `ktxTexture2_TranscodeBasis(fmt, ...)` to the engine's GPU formats;
  `ktxTexture2_DeflateZstd` for supercompressed level access.
- seek: KTX2's level index allows direct per-mip offset access from the header -- no full
  sequential decode needed for mip selection.
- stream: libktx operates on caller-owned buffers; the engine feeds from its streaming/
  mmap layer.

**Vendoring model**: vendor `lib/**` + `include/**` + the needed `external/**` components
verbatim; do not initialize submodules (the only submodule is `tests/cts`); no
FetchContent in the KTX build. basis_universal standalone is the encoder/aligned-pin
reference; the **one-version policy** recommendation is to use libktx's transcoder +
encoder at runtime/cook so a single basisu lineage ships -- adopting upstream v2.50 for
encode only if its gains justify a second lineage.

**Dependency risks**: dual-basisu skew (decide the policy before packaging); big tree
(162 MB shallow clone incl. test content -- vendor only lib/include/external subset);
ETC license carve-out; vendored zstd overlap with other packages.

## 6. Text shaping + subsetting -- harfbuzz

**Upstream + pin**: `github.com/harfbuzz/harfbuzz`, tag `14.6.0` =
`c7a7457b7385f33178e8cf87615ca077a810bbe7` (shallow clone).

**License + class**: "Old MIT" (`COPYING`), per-directory verified: `src/ms-use/COPYING`
= MIT (Microsoft), `test/COPYING` = SIL OFL (test fonts), perf data noted. Class:
MIT-class permissive.

**What it gives the engine (cook-time)**: OpenType shaping (GSUB/GPOS, variations/
instancing, complex scripts), sfnt/ttc parsing, and subsetting (`hb-subset-*` +
instancer verified in `src/`), plus layout/introspection queries.

**Proposed binding surface (surface-first: read/decode/seek/stream)**

- read: `hb_blob_create` (memory/mmap, lazy) -> `hb_face_create` (face index for TTC).
- decode: `hb_font_create` + `hb_shape` (features/variations) -> glyph ids/positions/
  clusters; metrics via `hb_font_get_*`; table inspection via `hb_ot_layout_*` if needed.
- seek: random access over the blob/face (no stream cursor needed for fonts).
- stream: `hb_blob` callback/destroy-based lazy loading if the cook streams assets.
- subset: `hb_subset_input_create_or_fail` -> `hb_subset_or_fail` (face -> face) ->
  serialize via `hb_face_reference_blob`; `hb_subset_preprocess` for shared work.

**Vendoring model**: vendor `src/**` at pin (amalgam `harfbuzz.cc` is the single-TU
option); core + subset have **no required external deps**. Build with explicit
`-Dfreetype=disabled -Dglib=disabled -Dicu=disabled -Dcairo=disabled` (meson options are
`auto` by default and would silently link whatever is present at port time).

**Dependency risks**: optional-dep auto-detection (force off as above); ignore `harfrust`
(Rust implementation, disabled by default); test corpus is large -- import vectors, not
the tree.

## 7. Refresh notes (existing clones)

- **meshoptimizer** (`E:\repos\meshoptimizer`, full clone): keep. Verified 2026-10-13:
  remote `github.com/zeux/meshoptimizer`, HEAD `f843aae0b3070306bd2aeef43ffcf09509fee526`
  (`v1.2-17-gf843aae0`), MIT (`LICENSE.md`). Ledger row refreshed; review date unchanged.
- **FFmpeg** (`E:\repos\FFmpeg`, shallow): reference-only, **never vendor** -- LGPL-2.1+/
  GPL (`COPYING.LGPLv2.1`, `COPYING.GPLv2/v3` verified); the dynamic-loader/system-libs
  model for `xiom.ffmpeg` stays. Verified at `b5902e6` (master 2026-10-07). Ledger row
  refreshed.
- **steam-audio** (`E:\repos\steam-audio`, full clone): verified `v4.8.1-10-g480dd64`,
  Apache-2.0; row refreshed with the #544 re-pin note (see sec. 2).
- **phonon** (`E:\repos\phonon`): corrected ledger row -- this clone is
  `github.com/KDE/phonon` (LGPL-2.1+), which is **not** the `xiom.phonon` upstream
  (Steam Audio is). Flagged as mislabeled; confirm with owner before any sweep.

## 8. Recommended build order

Sequenced by engine value x surface size x risk (prep input; owner may reorder):

1. **libopus + libogg** -- highest engine priority, self-contained vendored C, vectors
   importable; composes with the existing `xiom.ogg` page reader (new package, e.g.
   `xiom.opus`).
2. **`xiom.phonon` full-surface extension** -- no new upstream; unblocks ambisonics +
   HRTF/binaural; re-pin past the #544 ambisonic fix while touching.
3. **nianticlabs/spz** -- tiny surface, self-contained, quick visible win for splats.
4. **KTX-Software (libktx) + basisu policy** -- texture pipeline; medium surface; settle
   the one-basisu policy before packaging; extend `xiom.ktx`.
5. **harfbuzz** -- cook-time text; standalone; schedule with the font pipeline.
6. **Volumetric own reader** -- longest lead (own format spec + cook writer + reader);
   start design early, land after the above; OpenVDB is oracle only.

## 9. Ledger deltas (`E:\repos\CLEANUP.md`, edited in place)

Added rows (lane=bindings, review after 2026-12-01, all shallow clones):

| Clone | Pin |
|-------|-----|
| opus | v1.6.1 = `22244de5` |
| ogg | v1.3.6 = `be05b13e` |
| vorbis | v1.3.7 = `0657aee6` (evaluated -- not selected) |
| OpenVDB | v13.1.0 = `e26f5a56` (oracle; no package planned) |
| spz | v3.0.0 = `5bf2945d` |
| KTX-Software | v4.4.2 = `4d6fc70e` (vendors basisu @`1f4b564a`) |
| basis_universal | v2_50 = `9bebe167` |
| harfbuzz | 14.6.0 = `c7a7457b` |

Refreshed rows: `meshoptimizer` (pin verified), `FFmpeg` (never-vendor note), `steam-audio`
(pin + #544 note), `phonon` (upstream correction: KDE phonon, not Steam Audio).

## 10. Open items / blockers

- Blockers: none. All clones succeeded from canonical remotes (git protocol); no network
  failure to report.
- Decisions owed by the owner/wave: (a) `xiom.ktx` extend vs new `xiom.ktx2`;
  (b) volumetric reader is a native package, not a binding -- lane coordination + name;
  (c) basisu one-version policy (sec. 5); (d) `xiom.phonon` re-pin point (tag vs `480dd64`)
  at extension time; (e) KDE `phonon` clone disposition.
