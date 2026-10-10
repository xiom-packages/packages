# xiom.stb

stb image codecs for XIOM: the single-header **stb_image** +
**stb_image_write** are vendored (public domain / MIT) and compiled into
the test binary with `--c-source` -- no system library, no SDK.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2; 5/5 x2: real in-memory PNG encode + decode round trip and a BMP
> decode). **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.stb;

fn main() {
  let p = stb_probe();
  if p.is_ok {
    io.println("stb codecs ok");   // p.value.png_size / checksum / bmp_ok
  } else {
    io.println(p.error);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Version | `stb_version` (STBI_VERSION) |
| Probe | `stb_probe` -> `StbProbe` (png_size/checksum/roundtrip_ok/bmp_ok) |

Typed decode/encode wrappers (`Image` helpers, file paths, error strings)
and the wider format set are Phase 2 (`ROADMAP.md`); the pure-XIOM
`xiom.image` pipeline (BMP/PPM + conversions) composes with this package.

## Tests

```
scripts/port.ps1 -Package xiom.stb
```

Expected: 5 `[PASS]`, exit 0 (PNG encoded to 85 bytes; checksum 8400).
