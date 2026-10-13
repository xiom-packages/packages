# xiom.opus -- SPEC (0.1.0)

libopus bindings for XIOM: streaming audio encode/decode built on the
vendored upstream C library, with a disciplined FFI boundary and a
generated 1:1 binding of the public C surface.

## Identity

| Field | Value |
|-------|-------|
| Package | `xiom.opus` / `packages/xiom-opus` |
| Version | 0.1.0 |
| Stage | incubating (first landing) |
| Compiler pin | v0.64.4 (bindings lane) |
| Upstream | libopus (**Opus codec**, RFC 6716) |
| Upstream pin | tag `v1.6.1` = `22244de5a79bd1d6d623c32e72bf1954b56235be` |
| License (upstream) | BSD-3-Clause (`vendor/COPYING`, `vendor/LICENSE_PLEASE_READ.txt`) |
| License (this package) | MIT OR Apache-2.0 (original files) |

## Scope

Declared surface: **100% of the functions declared with an export macro in
the pinned public headers**:

| Header | Declared | Bound | Skips |
|--------|---------:|------:|------:|
| `opus.h` (incl. the repacketizer API -- there is no separate `opus_repacketizer.h` in v1.6.1) | 50 | 50 | 0 |
| `opus_defines.h` | 2 | 2 | 0 |
| `opus_multistream.h` | 19 | 19 | 0 |
| `opus_custom.h` | 18 | 18 | 0 |
| `opus_projection.h` | 16 | 16 | 0 |
| **total** | **105** | **105** | **0** |

Plus 86 public integer constants, 48 ctl macros (exposed as request
constants + per-class `_set`/`_get` pairs; 9 variadic ctl functions), and
4 documented companion entry points for the pointer-argument ctl requests
(`OPUS_SET_DNN_BLOB`, `OPUS_MULTISTREAM_GET_ENCODER/DECODER_STATE`,
`OPUS_PROJECTION_GET_DEMIXING_MATRIX`).

`docs/COVERAGE.md` (generated) is the authoritative function map;
`docs/gen_manifest.json` carries the machine-readable ledger and the
pinned-header SHA256s.

## Build configuration (vendored C)

The upstream sources compile from `vendor/opus/` (byte-identical, flat
tree -- see PROVENANCE.md) through four generated unity units:

| Unit | Upstream source list | Files |
|------|----------------------|------:|
| `src/opus_vendor_celt.c` | `celt_sources.mk` `CELT_SOURCES` | 18 |
| `src/opus_vendor_silk.c` | `silk_sources.mk` `SILK_SOURCES` | 77 |
| `src/opus_vendor_silk_float.c` | `silk_sources.mk` `SILK_SOURCES_FLOAT` | 28 |
| `src/opus_vendor_src.c` | `opus_sources.mk` `OPUS_SOURCES` + `OPUS_SOURCES_FLOAT` | 14 |

Defines pin the upstream float build: `OPUS_BUILD`,
`PACKAGE_VERSION "1.6.1"` (CMake writes `PACKAGE_VERSION` from
`git describe`; `opus_get_version_string()` therefore reports
`libopus 1.6.1`), `CUSTOM_MODES` (Opus Custom API compiled in, matching an
upstream `--enable-custom-modes` build), `ENABLE_HARDENING` (upstream
default), `VAR_ARRAYS` (clang VLA support, as the upstream CMake probe
does), and `CELT_C`/`CELT_ENCODER_C`/`CELT_DECODER_C` **in the celt unit
only** (selects the in-header `celt_fatal` definition and the custom-mode
declarations; defining them in every unit duplicates `celt_fatal` at
link).

Documented deviations from the upstream *default* build:

* **No x86 intrinsics / RTCD** (portable C). The API surface is identical;
  only decode/encode speed differs. The XIOM `--c-source` pipeline has no
  per-file flags, so the arch trees (`celt/x86`, `silk/x86`, ...) are not
  compiled. Revisit if engine profiling demands it.
* **DRED / OSCE / Deep-PLC off** (upstream defaults are off; enabling
  needs model tarballs from `media.xiph.org`, not in git). Their entry
  points are compiled and bound; without `ENABLE_DRED` they report
  `OPUS_UNIMPLEMENTED` (`-5`) or zero sizes -- covered by the suite.
* **Opus Custom is ON**: `opus_custom.h` is a public header whose
  declarations upstream gates behind `CUSTOM_MODES`; enabling it makes the
  18 custom-mode functions real and bound.

## ABI shape (bridge discipline)

`src/opus_bridge.c` exposes one `xo_*` entry point per declared function
(generated prototypes in `src/opus_abi_protos.h`):

* every entry point returns `int64_t` (no narrow-return sign ambiguity);
* opaque handles (`OpusEncoder*`, `OpusDecoder*`, `OpusMS*`,
  `OpusProjection*`, `OpusCustom*`, `OpusDRED*`, `OpusCustomMode*`) cross
  as `int64_t`/XIOM `Int` and are cast to their pointer type inside C --
  XIOM never casts a pointer to a handle (finding B-25);
* byte buffers cross as XIOM-owned `Vec[UInt8]` pointers: C reads inputs
  and writes outputs into owned slots; XIOM reads slots byte-indexed
  (B-20/B-24). One owned slot per scalar out-param;
* variadic ctl functions become `_set(handle, request, value)` /
  `_get(handle, request, slot)` pairs; no varargs cross the boundary;
* string-returning functions copy into an owned slot and return the byte
  count (no foreign pointer is ever read from XIOM);
* `opus_encoder_init`/`opus_decoder_init`/`opus_repacketizer_init`/
  `opus_custom_*_init`/`opus_multistream_*_init`/`opus_projection_*_init`/
  `opus_dred_decoder_init` take the caller's owned `Vec[UInt8]` as `mem`
  plus a capacity, validate `capacity >= get_size(...)`, and return the
  same address as the handle -- no `Int -> *UInt8` conversion on either
  side. Keep the Vec alive and do not resize it while the handle is in use;
  **do not call destroy on init-over-memory handles** (upstream destroy
  frees the pointer).
* NULL-requiring upstream calls are expressed without passing null:
  decode of an EMPTY packet is the packet-loss-concealment path (upstream
  treats `len == 0` as PLC; verified in `opus_decoder.c`).

Error mapping: any negative libopus return becomes
`Err(OpusError{ code; message })` where `message` is the upstream
`opus_strerror` text. Zero or positive returns are `Ok`.

## Module layout

| Module | File | Role |
|--------|------|------|
| `xiom.opus` | `src/opus.xi` | facade: `Encoder`/`Decoder`/`Repacketizer` types + methods, `version()`, `strerror()`, packet helpers |
| `xiom.opus.ffi` | `src/opus_ffi.xi` | **the only module with `unsafe`**: typed wrappers around every `xo_*` entry point; generated extern block inside markers |
| `xiom.opus.abi` | `src/opus_abi.xi` | generated public constants (`OPUS_*`, `OPUS_*_REQUEST`) + coverage ledger constants |
| `xiom.opus.types` | `src/opus_types.xi` | `OpusError`, `PacketFrames`, `EncoderOutcome` (flat outcome structs; never `Result[Option[T]]`, B-26) |

The facade is intentionally thin: the complete 1:1 surface (multistream,
custom, projection, DRED, packet utilities, padding, soft clip,
init-over-memory) is `xiom.opus.ffi`; constants are `xiom.opus.abi`.

## Data conventions

* s16 PCM: interleaved signed 16-bit little-endian bytes.
* 24-bit PCM: `opus_int32` carrier, little-endian; note upstream's float
  build scales the carrier as `float * 2^23` on decode.
* f32 PCM: interleaved IEEE-754 single, little-endian bytes.
* Packets: opaque byte vectors; `packet_parse` reports frame payload sizes
  (excluding the TOC byte) and byte offsets within the packet.

## Tests (`tests/test_conformance.xi`, 26 checks)

Pin identity; coverage ledger; error strings; encoder size/create + error
paths; ctl round-trips; s16 tone encode->decode with lag-aligned SNR and
energy sanity; deterministic buffer-too-small; invalid-packet decode; PLC;
FEC; packet utilities + parse; padding; repacketizer merge/split + errors;
multistream explicit + surround + sub-state ctls + multistream pad;
Opus Custom round-trip + errors; init-over-owned-memory for
encoder/decoder/repacketizer/custom + capacity rejection; 24-bit and f32
paths (cross-consistency with the s16 decode, energy match); pcm soft
clip; ambisonics FOA projection with demixing-matrix round trip; DRED
default-build stub behavior; DNN-blob ctl error in the default build.

## Non-goals (0.1.0)

* Ogg encapsulation/decapsulation (`OpusHead`/`OpusTags` parsing, seeking):
  compose with `xiom.ogg` (0.2.0 adds the libogg packet layer).
* File/stream I/O and ring buffers: consumer-side.
* Encoder-side DRED/OSCE weights (needs the model tarballs).

## Re-pin procedure

1. Fetch the new tag into `E:\repos\opus` (shallow fetch of the tag).
2. `python tools/vendor_opus.py` (verifies HEAD == PIN, re-copies the flat
   tree, rewrites `vendor/MANIFEST.sha256`).
3. `python tools/gen_opus.py --headers E:\repos\opus\include --package .`
   (regenerates `src/opus_abi.xi`, the extern block, `src/opus_abi_protos.h`,
   the four unity units, `docs/COVERAGE.md`, `docs/gen_manifest.json`; fails
   if any declared function lacks a mapping or the bridge misses an entry).
4. Update `PACKAGE_VERSION`/`PIN` constants in both tools, the header
   SHA256 expectations in `docs/gen_manifest.json` regenerate itself, bump
   the package version, run the suite twice, record STATUS.
