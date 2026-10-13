# xiom.basisu

Basis Universal v2_50 bindings for XIOM: KTX2 supercompressed texture **transcoding**
(BC/ETC/PVRTC/ASTC/RGBA at runtime) and cook-time **encoding** (ETC1S/UASTC/XUASTC/
ASTC/XUBC7 via the upstream `bu_*` C API). The upstream sources are vendored into
`vendor/` (Apache-2.0 + zstd BSD-3) and compiled into the test binary with
`--c-source` -- no system library, no DLL, no SDK.

> **Status:** `incubating` -- vendored C API path, owned-buffer bridge and the
> transcode/encode families green on the pin (xiom v0.64.4; 31/31 x2 native).
> **Lane:** bindings.
> **Surface:** 81/81 functions of the pinned public C API (68 `bt_*` transcoder +
> 13 `bu_*` encoder), all constants, 100% declared.

## Quick start

```xiom
use xiom.io;
use xiom.basisu;

fn main() {
  basisu_init();                        // bu_init + bt_init, debug printf off
  let v = basisu_versions();            // transcoder_lib / encoder_lib = 250 (v2_50)
  let f = basisu_format_report();       // block sizes, alpha/astc/hdr predicates, sizes
  io.println("basisu " + v.encoder_lib);
  if f.bytes_per_block_bc1 == 8 { io.println("BC1 helper OK"); }
}
```

Encode + transcode (the suite's flow): build an RGBA8 buffer, call
`basisu_encode_ktx2(...)` into an owned `Vec[UInt8]`, inspect with
`basisu_ktx2_info` / `basisu_ktx2_level_info`, then `basisu_transcode(...)` a level to
the target format. Every result is an owned buffer or a flat struct; failures are typed
`Err(Str)` (`invalid or truncated KTX2 payload`, `output buffer too small (need N bytes)`,
...).

## API

| Area | Functions |
|------|-----------|
| Raw surface | 81 pinned C API declarations (100%: `bt_*` transcoder + `bu_*` encoder) + all `BTF_*`/`TF_*`/`DECODE_FLAGS_*`/`BU_COMP_FLAGS_*` constants |
| Lifecycle | `basisu_init`, `basisu_versions`, `basisu_alloc_probe` |
| Format helpers | `basisu_format_report` -> `BasisuFormatReport` (bytes/block, alpha, ASTC/HDR/LDR predicates, transcoded sizes, support matrix) |
| Encoder helpers | `basisu_encoder_float_probe` -> `Result[BasisuEncoderHelpers, Str]` (float RGBA upload + `comp_params_clear`) |
| Encode (cook) | `basisu_encode_ktx2` -> `Result[BasisuEncodeResult, Str]` (ETC1S, UASTC LDR/HDR, XUASTC LDR, ASTC LDR/HDR, XUBC7; KTX2 output, mip generation, zstd supercompression) |
| Inspect | `basisu_ktx2_info` -> `Result[BasisuKtx2Info, Str]` (dims, levels, faces/layers, mode, DFD, sRGB); `basisu_ktx2_level_info` -> `Result[BasisuLevelInfo, Str]` (orig/actual dims, block counts, flags) |
| Transcode (runtime) | `basisu_transcode` -> `Result[BasisuTranscodeResult, Str]` (any `TF_*` target: BC1-BC7, ETC1/ETC2, PVRTC, ASTC LDR/HDR, RGBA32, RGB565, half) |
| Corrupt input | `basisu_can_open` + typed errors from `basisu_ktx2_info` / `basisu_transcode` |

Full detail: `SPEC.md` (surface matrix, pin table, bridge layout);
provenance/pins: `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.basisu -TimeoutSec 1500
```

Expected: 31 `[PASS]`, exit 0, ~70-80 s (the vendored encoder+transcoder+zstd compile
dominates). The suite encodes its own deterministic 32x32 RGBA gradient to UASTC and
ETC1S KTX2 (plus a zstd-supercompressed UASTC payload), verifies dimensions/mip chain
(32x32 + 16x16 levels, 6 mips), transcodes to BC1/ETC1/ASTC 4x4/RGBA32 with exact byte
sizes, checks the decoded image against the source, covers the remaining encoder
helpers (float RGBA upload, `comp_params_clear`), and asserts typed errors for
corrupt/truncated payloads.
