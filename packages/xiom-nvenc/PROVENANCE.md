# PROVENANCE: xiom.nvenc

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | FFmpeg **nv-codec-headers** -- https://github.com/FFmpeg/nv-codec-headers |
| Contents | NVIDIA Video Codec SDK interface declarations (`nvEncodeAPI.h`, `dynlink_cuviddec.h`, `dynlink_nvcuvid.h`, `dynlink_cuda.h`, `dynlink_loader.h`) |
| Upstream license | **MIT** -- the header file notice reads "Copyright (c) 2010-2026 NVIDIA Corporation ... Permission is hereby granted, free of charge ..." (MIT text). The repository has no separate LICENSE file; the README states "Corresponds to Video Codec SDK version 13.1.15." |
| Policy | **Reference-only. NEVER vendored.** The shipped package contains no header, no import library, and no NVIDIA code. `nvEncodeAPI64.dll`, `nvcuvid.dll` and `nvcuda.dll` are system components of the installed NVIDIA display driver and are loaded at run time. |
| Reference clone | `E:\repos\nv-codec-headers` -- pinned commit `eddcea9e27f6b772057c9b3f87de2cc1737faffc` (2026-07-15, "Bump for (in-dev) 13.1.15.1"); light clone (`--depth 1`) retained locally, not committed |
| Package license | MIT OR Apache-2.0 (no upstream code copied into this package) |

The shipped surface is **independent XIOM + C code** written against the public
interface declarations in the pinned clone (the "declaration oracle" below).
The C bridge is original XIOM-side code; it encodes only interface facts
(struct field order, GUID values, version constants, enum values) and asserts
every offset it relies on at compile time, so a header move breaks the build
loudly instead of corrupting a driver call.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `include/ffnvcodec/nvEncodeAPI.h` | `D170E56D5CE873440D7FA7E284E665BE2A938F918F3A1691F9E95BFC806FAFD1` |
| `include/ffnvcodec/dynlink_cuviddec.h` | `CC1909B5C86827DF5936ECE4846218D38F7047A7AC8BE23C7139619508C37609` |
| `include/ffnvcodec/dynlink_nvcuvid.h` | `2430ED4BC6CE869ED7D390321E7FEEAEC7D9D9442FA4662C5BF1F163E7466321` |
| `include/ffnvcodec/dynlink_cuda.h` | `D8CFAB3F51C765EF93772D37FE50C2C71D39D88C9FF878DAF1A15A82F650ADF1` |
| `include/ffnvcodec/dynlink_loader.h` | `C739F09BDCD9DEE54CD810E575D77D29325049A962893184602EA14420C07F6D` |

What the bridge takes from each file:

- `nvEncodeAPI.h` -- `NVENCAPI_VERSION` 13.1 and the `NVENCAPI_STRUCT_VERSION`
  packing; `NV_ENCODE_API_FUNCTION_LIST` pointer order; the
  open-session-ex / caps / preset-config / initialize / register-resource /
  map-input / create-bitstream / pic-params / lock-bitstream struct layouts;
  `NVENCSTATUS` numeric values used for classification; device type, buffer
  format, resource type, picture type/struct/flags, tuning-info and caps enum
  values; the H.264/HEVC codec GUIDs and P1-P7 preset GUIDs.
- `dynlink_cuviddec.h` -- `CUVIDDECODECAPS`, `CUVIDDECODECREATEINFO`,
  `CUVIDEOFORMAT`, `CUVIDPROCPARAMS`, `CUVIDPICPARAMS` (opaque pass-through),
  `CUVIDPARSERDISPINFO`; `cudaVideoCodec`, `cudaVideoChromaFormat`,
  `cudaVideoSurfaceFormat`, `cudaVideoCreateFlags`, deinterlace enum values.
- `dynlink_nvcuvid.h` -- `CUVIDPARSERPARAMS`, `CUVIDSOURCEDATAPACKET`, parser
  callback signatures and the `CUVID_PKT_*` packet flags.
- `dynlink_cuda.h` -- the CUDA driver entry-point names/signatures used for a
  context and a host-device copy (`cuInit`, `cuCtxCreate_v2`,
  `cuCtxDestroy_v2`, `cuCtxSetCurrent`, `cuMemAllocPitch_v2`,
  `cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2`).
- `dynlink_loader.h` -- confirmation of the exported NVDEC symbol set
  (`cuvidGetDecoderCaps`, `cuvidCreateDecoder`, ..., `cuvidCtxLockCreate`).

## Derived vs independent

- `src/nvenc.xi` (root module; all `unsafe`/`extern`): **independent** XIOM
  code -- typed errors, handle registry semantics, the declared surface.
- `src/nvenc_bridge.c`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0), compiled with `--c-source`; it never links NVIDIA code. It
  resolves every entry point with `GetProcAddress` and keeps all foreign
  memory access in C. The struct declarations are hand-written interface
  facts from the oracle above, guarded by `_Static_assert` offsets/sizes.
- Test frame: **synthetic** -- Y = `(x + y) & 0xFF`, UV = 96 for a 320x240
  NV12 surface generated inside the bridge; no upstream test vector or media
  file is imported.

## Local runtime samples (present-path evidence; not the pin)

Host: NVIDIA GeForce RTX 3070 Ti, driver 616.92 (Windows driver version
32.0.16.1692), CUDA UMD 13.4.

| Module | SHA256 |
|--------|--------|
| `C:\Windows\System32\nvEncodeAPI64.dll` | `06A9F8E8DFCC64C71F00735DD0063E8A69EA4FC1F2CA7B1469CA47BDAF12F00E` |
| `C:\Windows\System32\nvcuvid.dll` | `B28BC3F70E60F59AD4B7DE9404331350E36DD3A6F66329398238DD6DC6BEA06F` |
| `C:\Windows\System32\nvcuda.dll` | `F2B550E83F56B7B819EFE382D712D125EE180341F012BD0ABA2288320609A45A` |

The suite reports the driver's negotiated NVENC API version (13.1 on this
host), the H.264/HEVC GUID set and width/height/engine caps, then performs a
real H.264 and HEVC encode and a real NVDEC decode of that bitstream.

## Re-carve procedure (upstream moves)

1. Refresh `E:\repos\nv-codec-headers` at the new tag/commit; update the pin
   and the `E:\repos\CLEANUP.md` review date.
2. Re-hash the oracle files into the table above; re-verify the struct
   offsets/sizes, GUIDs and version constants against the new headers.
3. Update the `_Static_assert` block and the version macros in
   `src/nvenc_bridge.c` in the same commit as the pin update.
4. `scripts/port.ps1 -Package xiom.nvenc -TimeoutSec 300` x2 (live RTX host);
   `scripts/status.ps1 -Action update`; conventional commit; sync
   `SPEC.md`/`AUDIT.md` counts in the same commit.
