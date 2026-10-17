# xiom.nvenc

NVIDIA hardware video **encode (NVENC)** and **decode (NVDEC/cuvid)** bindings
for XIOM. The three driver libraries -- `nvEncodeAPI64.dll`, `nvcuvid.dll` and
`nvcuda.dll` (for the shared CUDA context) -- ship with the NVIDIA display
driver and are loaded at run time; **nothing is vendored**.

> **Status:** `incubating` -- conformance suite green on the v0.64.6 pin
> (67/67 x2; live RTX 3070 Ti: NVENC API 13.1, H.264 + HEVC encode, NVDEC
> decode of the produced bitstream). Published in `eco-v0.1.197` (sha256
> `9ff4eb1d...`, 2026-10-17). **Lane:** bindings
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.nvenc;

fn main() {
  let p = nvenc_probe();
  if p.is_ok {
    io.println(nvenc_caps_summary(&p.value));
  } else if nvenc_is_skip(&p.error) {
    io.println("SKIP: " + p.error.message);
  }

  let s = nvenc_open(NVE_CODEC_H264);
  if s.is_ok {
    let h = s.value;
    let i = nvenc_initialize(h, 320, 240, 30, 1, NVE_PRESET_P1);
    // ... register / fill / encode / lock / copy / unlock / destroy
  }
}
```

## API

| Area | Functions |
|------|-----------|
| NVENC probe | `nvenc_probe` -> `NvencCaps` (API version, GUID count, H.264/HEVC, width/height/engine caps), `nvenc_probe_named(dll)` |
| NVENC session | `nvenc_open(codec)`, `nvenc_initialize(session,w,h,fps_num,fps_den,preset)`, `nvenc_register_resource`, `nvenc_fill_frame`, `nvenc_create_bitstream`, `nvenc_encode_frame(force_idr)`, `nvenc_lock_bitstream` -> `NvencLock`, `nvenc_copy_bitstream`, `nvenc_unlock_bitstream`, `nvenc_destroy` |
| NVDEC probe | `nvdec_probe` -> `NvdecCaps`, `nvdec_probe_named(dll)` |
| NVDEC decode | `nvdec_create(codec,w,h,surfaces)`, `nvdec_parse(data)`, `nvdec_map`, `nvdec_copy_frame`, `nvdec_unmap`, `nvdec_destroy` |
| Types | `NvError` (kind/stage/code/message), `NVE_CODEC_H264`, `NVE_CODEC_HEVC`, `NVE_PRESET_P1..P7`, `NVE_LOAD_ABSENT` / `NVE_NO_DEVICE` / `NVE_UNSUPPORTED` (SKIP class) |

The declared subset is documented exactly in `SPEC.md`; every declared
function is exercised by `tests/test_conformance.xi`. The exact ABI pin and
the MIT provenance of the declaration oracle are in `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.nvenc -TimeoutSec 300
```

Expected on an NVIDIA host: 67 `[PASS]`, exit 0 (both H.264 and HEVC
encode -> decode pipelines). On a host without an NVIDIA driver, the probe
and pipeline groups report SKIP and the suite still exits 0; the two
deterministic skip-path checks and the typed-error checks always run.
