# xiom.mediandk -- SPEC

Android NDK media bindings for XIOM -- the **A7 core media head** of the
Android SDK100 program (`docs/ANDROID-SDK100.md`), backed by a runtime
`libmediandk.so` bridge with SKIP semantics.

## Scope (NDK r27b oracle)

Headers (`sysroot/usr/include/media/`, pinned NDK `27.1.12297006`):

| Header | Declared surface bound | Export-set (runtime) |
|---|---|---|
| `NdkMediaCodec.h` | AMediaCodec_* (30) + action codes (2) + AMediaCodecCryptoInfo_* (9) | all 41 |
| `NdkMediaCrypto.h` (codec include set) | AMediaCrypto_* (4) | all 4 |
| `NdkMediaFormat.h` | AMediaFormat_* functions (21) + 136 AMEDIAFORMAT_KEY_* data symbols | all 21 + 136 |
| `NdkMediaExtractor.h` | AMediaExtractor_* (21) + seek/sample enums | all 21 |
| `NdkMediaMuxer.h` | AMediaMuxer_* (11) + output/append enums | all 11 |
| `NdkMediaDataSource.h` | AMediaDataSource_* (9) | all 9 |
| `NdkMediaDrm.h` | AMediaDrm_* (26) + event/key/status enums + property strings | all 26 |
| `NdkMediaCodec.h` keys | 7 AMEDIACODEC_KEY_* data symbols | all 7 |

**Declared export set = 276 symbols** (133 functions + 143 key data
symbols), cross-checked 2026-10-16 with `llvm-readelf` against the
API-35 link stub **and** the API-36 device library: identical
intersection.

## Design

- `src/mediandk_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile): `dlopen` on
  Android/Linux, `LoadLibraryA` on Windows (where the probe classifies
  ABSENT -> SKIP).  Every declared symbol is resolved; missing names are
  reported; a present-but-broken install maps to `MEDIANDK_LOAD_ABI` =
  FAIL, never a silent SKIP.
- Pointers never cross the boundary (B-25 discipline): format/codec
  handles cross as `Int`; buffer payloads are staged into a bridge-owned
  byte slot on the way in and read back one byte at a time on the way
  out; key data symbols are read C-side and copied immediately with
  `Str::from_c_str`.
- Functional heads (0.1.0):
  - `AMediaFormat`: `format_new/delete`, `set/get` Int32, Float32,
    String, Buffer, `format_to_string` -- exact roundtrips proven
    on-device (see `docs/repro/mediandk-probe/`).
  - `AMediaCodec`: `codec_create_decoder("audio/opus")` + `codec_delete`
    probe.  A null decoder is a **typed, non-fatal** outcome: the suite
    records the verdict and stays green (exit 0) either way.
- Extractor / Muxer / DRM / DataSource are symbol-bound + ABI-checked;
  live wrappers need real media assets (later wave).

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| lib absent (Windows, bogus soname) | `MEDIANDK_LOAD_ABSENT` | SKIP (green) |
| exports missing / broken install | `MEDIANDK_LOAD_ABI` | FAIL |
| full export set + working format/codec | Ok | live checks |

## Key string constants -- provenance

The `AMEDIAFORMAT_KEY_*` / `AMEDIACODEC_KEY_*` values are defined by the
**runtime library**, not the headers (the headers only declare
`extern const char*`).  The 143 shipped values were dumped from
`libmediandk.so` on the API-36 x86_64 emulator (2026-10-16); the
on-device driver re-verifies every pair against the runtime `dlsym`
value (`gen-keys-expected.ps1` generates the fidelity table from this
package's constants -- 143/143 exact).

## Declared-but-unshipped keys (documented exclusion)

16 key data symbols are declared by the r27b headers but exported by
neither the API-35 stub nor the API-36 runtime (llvm-readelf evidence,
2026-10-16): `AMEDIAFORMAT_VIDEO_QP_*` (8),
`AMEDIAFORMAT_KEY_AUDIO_PRESENTATION_PRESENTATION_ID`,
`..._AUDIO_PRESENTATION_PROGRAM_ID`, `..._BUFFER_BATCH_MAX_OUTPUT_SIZE`,
`..._BUFFER_BATCH_THRESHOLD_OUTPUT_SIZE`, `..._IMPORTANCE`,
`..._PICTURE_TYPE`, `..._VIDEO_ENCODING_STATISTICS_LEVEL`,
`..._VIDEO_QP_AVERAGE`.  They are excluded from the export set and the
constant cluster (no runtime oracle for their values); documented, not
silently missing.

## Color formats

The NDK media headers contain **no numeric color-format constants**
(verified: no `COLOR_Format*` definitions under the sysroot `media/`
headers; numeric values are a Java-platform fact).  The color surface
bound here is the key cluster: `AMEDIAFORMAT_KEY_COLOR_FORMAT`,
`..._COLOR_RANGE`, `..._COLOR_STANDARD`, `..._COLOR_TRANSFER`.

## API-floor caveat

The declared surface spans API 21..33 (e.g. `AMediaMuxer_append` API 31,
`AMediaDrm_getKeyRequestWithDefaultUrlAndType` API 33).  A device below
an introduced level reports those symbols missing -> `MEDIANDK_LOAD_ABI`
(FAIL by design: never a silent SKIP).  The reference device is API 36
(0 missing).

## Exclusions

- `NdkImage.h` / `NdkImageReader.h` (AImage_* / AImageReader_*):
  separate A7 image head, later wave.
- No JNI-route functions exist in the seven oracle headers (no
  `NdkMedia*_jni.h`); the A11 seam is empty for this head.
- The API-36 lib exports 37 symbols beyond the r27b declared surface
  (`AMediaCodecInfo_*`, `AMediaCodecStore_*`, `*ForClient`, mangled
  forms): out of scope by header oracle.

## Build

`scripts/port.ps1 -Package xiom.mediandk` (compiles
`src/mediandk_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android hosts).  On-device evidence:
`docs/repro/mediandk-probe/` (`build-probe.ps1`).
