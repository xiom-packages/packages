# xiom.exr

OpenEXR reader for XIOM via vendored **tinyexr v3.2.0** (BSD-3; single
header + `exr_reader.hh` + `streamreader.hh` + bundled miniz). Reads
single-part scanline EXR from memory or a file into **owned planar
float32 channel buffers**, with metadata queries and typed errors. The
save path (tinyexr's own writer) is bound for fixtures and round trips.

> **Status:** `incubating` -- conformance suite green on the pin
> (v0.64.4; 12/12 x2). **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.exr;

fn main() {
  let r = exr_load_from_file("plate.exr");
  if r.is_ok {
    let img = r.value;                          // width/height/channels + names/types
    let ir = exr_channel_index(&img, "R");
    if ir >= 0 {
      let px = exr_pixel_f64(&img, ir, 0, 0);   // exact Float64 value
      io.println("R(0,0) = " + convert.float_to_string(px));
    }
  } else {
    io.println(r.error.message);                // typed ExrError
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Detect | `exr_is_exr_from_memory`, `exr_is_exr_from_file` |
| Read | `exr_load_from_memory`, `exr_load_from_file` -> `Result[ExrImage, ExrError]` |
| Metadata | `ExrImage.width/height/channels/compression/window_*`, `names`, `pixel_types` |
| Pixels | `exr_pixel_f64`, `exr_float32_from_bytes` (exact f32->f64) |
| Lookup | `exr_channel_index(img, name)` (str_compare; -1 when absent) |
| Save | `exr_save_to_memory(&ExrSaveSpec)` -> `Result[Vec[UInt8], ExrError]` (fp32/fp16) |
| Errors | `ExrError{code,message}`, `exr_error_name`, `EXR_ERROR_*` consts |

`ExrImage.data` is planar float32 little-endian: channel `c` lives at
`data[c * width * height * 4 ..]`. HALF channels are converted to FLOAT by
tinyexr; UINT channels are widened by the bridge; `pixel_types` always
reports the declared file type. Constants mirror the pinned header
(pixel types, compression, tile modes, error codes).

## Tests

```
scripts/port.ps1 -Package xiom.exr -TimeoutSec 300
```

Expected: 12 `[PASS]`, exit 0. Fixtures are built with tinyexr's own save
path (3x2 float and half, RGBA alpha) and read back with exact value
checks; garbage/truncated inputs must return typed errors.

## Licence

Package code: MIT OR Apache-2.0. Vendored tinyexr: BSD-3-Clause; bundled
miniz: MIT / public domain (`vendor/tinyexr/LICENSE*`, `PROVENANCE.md`).
