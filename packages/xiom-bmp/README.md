# xiom-bmp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** BMP image codec: decoding and encoding of Windows bitmap files.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `decode` | BMP decoder for all bit depths |
| `encode` | BMP encoder with row padding |
| `dib` | DIB header parsing (BITMAPINFOHEADER variants) |
| `compression` | RLE8/RLE4 and BI_BITFIELDS compression |
