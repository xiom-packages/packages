# SPEC: xiom.nvenc 0.1.0

NVIDIA NVENC (encode) + NVDEC/cuvid (decode) bindings, loader-only.
**Nothing is vendored**; the NVIDIA display-driver DLLs are system
components. This document is the exact declared surface for 0.1.0.

## 1. Load model

| Layer | Module | How |
|-------|--------|-----|
| NVENC | `nvEncodeAPI64.dll` | `LoadLibraryA`; `NvEncodeAPIGetMaxSupportedVersion` + `NvEncodeAPICreateInstance`, then the function list |
| NVDEC | `nvcuvid.dll` | `LoadLibraryA`; exported `cuvid*` entry points via `GetProcAddress` |
| CUDA | `nvcuda.dll` | `LoadLibraryA`; `cuInit`, `cuCtxCreate_v2`, `cuCtxDestroy_v2`, `cuCtxSetCurrent`, `cuMemAllocPitch_v2`, `cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2` |

Both APIs need a CUDA context: NVENC receives it as
`NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS.device` (device type CUDA); NVDEC
receives it through `cuvidCtxLockCreate` and the decoder create info.
The package links no import library. `--c-source` compiles
`src/nvenc_bridge.c`, which is original XIOM-side code.

## 2. ABI pin

Declaration oracle: `FFmpeg/nv-codec-headers` at commit
`eddcea9e27f6b772057c9b3f87de2cc1737faffc` (Video Codec SDK 13.1.15.1),
MIT. The bridge encodes the public interface facts and asserts every relied-on
offset/size at compile time:

- NVENC API version 13.1: `NVENCAPI_VERSION = 0x0100000D`;
  `NV_ENCODE_API_FUNCTION_LIST_VER = 0x7102000D`.
- Struct versions: open-session-ex 1, caps-param 1, preset-config 5 (+ MSB),
  config 9 (+ MSB), initialize 7 (+ MSB), register-resource 5,
  map-input 4, create-bitstream 1, pic-params 7 (+ MSB), lock-bitstream 2
  (+ MSB).
- Codec GUIDs: H.264 `6BC82762-4E63-4CA4-AA85-1E50F321F6BF`, HEVC
  `790CDC88-4522-4D7B-9425-BDA9975F7603`; presets P1-P7 as in the header.
- Key offsets (64-bit Windows): `NV_ENC_INITIALIZE_PARAMS.encodeConfig` 88,
  `NV_ENC_PIC_PARAMS.inputBuffer` 40 / `outputBitstream` 48 / `bufferFmt` 64,
  `NV_ENC_LOCK_BITSTREAM.bitstreamSizeInBytes` 36 /
  `bitstreamBufferPtr` 56, `NV_ENC_REGISTER_RESOURCE.registeredResource` 32,
  `NV_ENC_MAP_INPUT_RESOURCE.mappedResource` 24,
  `CUVIDDECODECREATEINFO.vidLock` 72, `CUVIDEOFORMAT.codedWidth` 16 /
  `chromaFormat` 40.
- Version negotiation: the driver's `(major, minor)` must be at least
  `(13, 1)`; the packed value is `(major << 4) | minor` (209 on this host).

Full oracle file hashes: `PROVENANCE.md`.

## 3. Declared surface (100% of 0.1.0)

### 3.1 NVENC

| Function | Contract |
|----------|----------|
| `nvenc_probe() -> Result[NvencCaps, NvError]` | Load default loader, negotiate version, create instance, open a session on a fresh CUDA context, enumerate codec GUIDs, query width/height/engine caps. |
| `nvenc_probe_named(dll: Str)` | Same against a named module (deterministic SKIP path). |
| `nvenc_open(codec: Int) -> Result[Int, NvError]` | `NVE_CODEC_H264` or `NVE_CODEC_HEVC`; session open + codec support check; returns an integer slot handle. |
| `nvenc_initialize(session, width, height, fps_num, fps_den, preset)` | Query the preset config (`NvEncGetEncodePresetConfigEx`, low-latency tuning) and call `NvEncInitializeEncoder`; NV12 input, PTD on, synchronous mode. Presets P1-P7. |
| `nvenc_register_resource(session)` | Allocate a pitched CUDA NV12 buffer and register it as `NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR` / `NV_ENC_INPUT_IMAGE`. |
| `nvenc_fill_frame(session)` | Upload the deterministic synthetic frame (Y = `(x+y)&0xFF`, UV = 96); this is the declared way to drive an encode without a foreign surface. |
| `nvenc_create_bitstream(session)` | `NvEncCreateBitstreamBuffer`. |
| `nvenc_encode_frame(session, force_idr: Bool)` | `NvEncEncodePicture`; maps the registered resource on first use. |
| `nvenc_lock_bitstream(session) -> Result[NvencLock, NvError]` | `NvEncLockBitstream` (blocking); size + picture type. |
| `nvenc_copy_bitstream(session, out, capacity) -> Result[Int, NvError]` | Copy the locked bytes into an XIOM-owned `Vec[UInt8]`; short buffer = `NVE_BUFFER_TOO_SMALL`. |
| `nvenc_unlock_bitstream(session)` | `NvEncUnlockBitstream`. |
| `nvenc_destroy(session)` | Unlock/unmap/unregister/destroy bitstream/encoder, free the CUDA buffer, destroy the context. |
| `nvenc_is_skip(&NvError) -> Bool` | SKIP classifier (loader/device/codec absent). |
| `nvenc_caps_summary(&NvencCaps) -> Str` | Human-readable probe line. |

### 3.2 NVDEC

| Function | Contract |
|----------|----------|
| `nvdec_probe() -> Result[NvdecCaps, NvError]` | Load default loader, create a CUDA context, `cuvidGetDecoderCaps` for H.264/HEVC 4:2:0 8-bit. |
| `nvdec_probe_named(dll: Str)` | Same against a named module. |
| `nvdec_create(codec, width, height, surfaces) -> Result[Int, NvError]` | CUDA context + `cuvidCtxLockCreate` + `cuvidCreateDecoder` (NV12, weave, PreferCUDA); `surfaces` 0 -> 8, clamped to 32. |
| `nvdec_parse(decoder, data, length) -> Result[NvdecInfo, NvError]` | Feed one Annex-B access unit to `cuvidCreateVideoParser`/`cuvidParseVideoData` with `CUVID_PKT_ENDOFSTREAM`; parser callbacks decode each picture and count sequence/decode/display events. Returns geometry + counters. |
| `nvdec_map(decoder, picture_index)` | `cuvidMapVideoFrame64`. |
| `nvdec_copy_frame(decoder, out, capacity) -> Result[NvdecFrame, NvError]` | `cuMemcpyDtoH` the mapped surface, then compact to `width*height*3/2` NV12 (Y plane, then interleaved UV) in the XIOM-owned buffer. |
| `nvdec_unmap(decoder)` | `cuvidUnmapVideoFrame64`. |
| `nvdec_destroy(decoder)` | Unmap if live, then destroy parser/decoder/context lock/context. |

## 4. Typed errors

`NvError { kind, stage, code, message }`; `kind` is one of:

| Kind | Class | Meaning |
|------|-------|---------|
| `NVE_LOAD_ABSENT` (0) | SKIP | `nvEncodeAPI64.dll` / `nvcuvid.dll` missing |
| `NVE_NO_DEVICE` (1) | SKIP | `nvcuda.dll` missing, no GPU, or CUDA context failed |
| `NVE_UNSUPPORTED` (2) | SKIP | driver API too old, no encode/decode device, codec unsupported |
| `NVE_BAD_HANDLE` (3) | FAIL | invalid integer handle |
| `NVE_STATE` (4) | FAIL | call order / argument error / no picture |
| `NVE_ABI` (5) | FAIL | required entry point missing from a present DLL |
| `NVE_API_FAILED` (6) | FAIL | driver rejected a call (NVENCSTATUS/CUresult in `code`) |
| `NVE_BUFFER_TOO_SMALL` (7) | FAIL | caller buffer smaller than the needed size |
| `NVE_INTERNAL` (8) | FAIL | bridge allocation failure |

`stage` names the operation (load, version, device, session, caps, initialize,
resource, bitstream, encode, lock, decode-probe, decoder, parser, map, copy).
`code` is the raw NVENCSTATUS or CUresult where applicable.

## 5. State machine

```
NVENC: open -> initialize -> register_resource -> fill_frame
       -> create_bitstream -> encode_frame -> lock -> copy -> unlock -> destroy
NVDEC: create -> parse (decodes) -> map -> copy_frame -> unmap -> destroy
```

Violating the order is `NVE_STATE` (except `lock` after a successful encode).
`nvenc_destroy` and `nvdec_destroy` are idempotent only in the sense that a
destroyed handle becomes `NVE_BAD_HANDLE` on reuse; they release everything
the session owns even after a mid-pipeline failure.

## 6. Live evidence (v0.64.6, RTX 3070 Ti, driver 616.92)

`scripts/port.ps1 -Package xiom.nvenc -TimeoutSec 300` x2 -> **67/67 pass**.

- NVENC probe: API 13.1, GUID count 2 (H.264 + HEVC), max 4096x4096,
  engines 1.
- H.264: 320x240 forced-IDR frame -> 2442-byte Annex-B bitstream starting
  `00 00 00 01 67 64` (SPS); NVDEC decodes 1 picture, displays 1, coded
  320x240, 4:2:0, 8-bit; compact NV12 frame 115200 bytes; UV = 96; luma
  non-constant.
- HEVC: 320x240 forced-IDR frame -> 3920-byte Annex-B bitstream starting
  `00 00 00 01 40 01` (VPS); NVDEC decodes 1 picture, displays 1, coded
  320x256 (CTU-aligned), 4:2:0, 8-bit; compact NV12 frame 115200 bytes
  (display 320x240); UV = 96; luma non-constant.

## 7. Deliberately not declared in 0.1.0

- Multi-frame/GOP streaming (the surface is one frame per session lifecycle
  in the suite; the encoder itself is not limited by the API).
- AV1 encode/decode, 10-bit profiles, YUV444, B-frames, lookahead, SVC,
  ME-only, async events, D3D/OpenGL interop.
- Caller-supplied surfaces (D3D11/D3D12/CUDA array/textures): only the
  package-owned CUDA device-pointer resource is declared.
- `NvEncReconfigureEncoder`, encoder stats, sequence-param payloads, motion
  vectors.
- Audio decode and container demux (use `xiom.ffmpeg` for those).
- Linux sonames (`libnvidia-encode.so.1`, `libnvcuvid.so.1`); the loader
  names are Windows.
- Pixel-plane copies for arbitrary decoder outputs: the copy-out is NV12.
