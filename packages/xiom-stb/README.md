# xiom.stb

stb image codecs for XIOM: the single-header **stb_image** +
**stb_image_write** are vendored (public domain / MIT) and compiled into
the test binary with `--c-source` -- no system library, no SDK. 0.3.0
adds the **full HDR class surface** (Radiance `.hdr`): the `stbi_loadf`
family, the `stbi_is_hdr` family, and the HDR/LDR conversion knobs, all
with owned-buffer interop and typed errors.

> **Status:** `incubating` -- conformance suite green on the pin
> (v0.64.4; 18/18 x2). Published in `eco-v0.1.139` (sha256
> `41a205f7...`). **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.3.0` in `eco-v0.1.179` (sha256 `690d8c5e...`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.stb;

fn main() {
  // Probe (PNG encode/decode round trip + BMP decode)
  let p = stb_probe();
  if p.is_ok { io.println("stb codecs ok: " + convert.int_to_string(p.value.png_size)); }

  // HDR: load a Radiance file into owned float pixels
  let r = stb_loadf("sky.hdr", STBI_RGB_ALPHA);
  if r.is_ok {
    let img = r.value;                       // width/height/channels
    let px = stb_pixel_f64(&img, 0, 0, 0);   // exact Float64 value
    io.println("r = " + convert.float_to_string(px));
  } else {
    io.println(r.error.message);             // typed StbError
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Version | `stb_version` (STBI_VERSION) |
| Probe | `stb_probe` -> `StbProbe` (png_size/checksum/roundtrip_ok/bmp_ok) |
| HDR detect | `stb_hdr_is`, `stb_hdr_is_from_file`, `stb_hdr_is_from_memory`, `stb_hdr_is_from_callbacks` |
| HDR load (float) | `stb_loadf`, `stb_loadf_from_file`, `stb_loadf_from_memory`, `stb_loadf_from_callbacks` -> `Result[StbFloatImage, StbError]` |
| HDR->LDR remap | `stb_load_rgba8_from_memory` (8-bit path) |
| Conversion knobs | `stb_hdr_to_ldr_gamma/_scale`, `stb_ldr_to_hdr_gamma/_scale` |
| Exact reads | `stb_float32_from_bytes`, `stb_f32_at`, `stb_pixel_f64` |
| Diagnostics | `stb_failure_reason`, `StbError{code,message}` |

Constants: `STBI_DEFAULT/GREY/GREY_ALPHA/RGB/RGB_ALPHA`,
`STBI_MAX_DIMENSIONS`, `STB_ERR_LOAD/ARG/STATE`.

Every loader returns owned data (interleaved float32 little-endian in
`StbFloatImage.data`; 8-bit bytes in `StbByteImage.data`). The
`*_from_callbacks` entries run on a bridge-provided memory cursor
(arbitrary XIOM callbacks are a documented non-goal, compiler B-13).

## Tests

```
scripts/port.ps1 -Package xiom.stb
```

Expected: 18 `[PASS]`, exit 0 (PNG 85 bytes / checksum 8400; the in-test
`.hdr` fixture decodes to exact powers of two; gamma remaps byte-exact).
