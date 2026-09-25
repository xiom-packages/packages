# xiom.xbm

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (20/20); NOT published yet.
> **Scope:** X BitMap (XBM): the `#define` width/height pair plus the packed `static char` byte array, bit-level access, and a canonical builder.
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Overview

`xiom.xbm` reads and writes the C-source 1-bit bitmap format used by X11:

```c
#define sample_width 16
#define sample_height 16
static char sample_bits[] = {
   0x00, 0x01, 0x02, 0x03, /* ... */ };
```

The parser accepts the documented subset of real-world XBM files: the
`<name>_width` / `<name>_height` defines in either order, one
`static char` or `static unsigned char` `<name>_bits[]` array as the final
construct, arbitrary whitespace and `/* ... */` comments between tokens,
1-2 hex digits per byte with upper or lower case, and a trailing comma before
`}`. It validates the full byte list up front, extracts the raster into a flat
`Vec[UInt8]`, and reports deterministic `xbm: ...` errors.

Pixels are LSB-first per byte (bit 0 is the leftmost pixel, the X11
convention) and `1` means foreground. Accessors expose width, height, the
shared base name, the row stride, the packed span, and an `(x, y)` bit lookup.
`xbm_pack` turns row-major `0`/`1` pixels into packed raster bytes and
`xbm_build` emits canonical XBM text.

## Install / use

```
xiom pkg install xiom.xbm@0.1.0     # consumer, once published
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xiom
use xiom.xbm;

match xbm_parse(file_bytes) {          // file IO is the caller's job
  Ok(img) => {
    // xbm_name(&img) == "sample", xbm_width(&img) == 16, xbm_height(&img) == 16
    let fg: Int = xbm_bit(&img, 7, 3); // 1 (foreground), 0, or -1 when out of range
  },
  Err(e) => { /* "xbm: ..." */ },
}

// Build: pixels are row-major 0/1 bytes, width * height of them
let pixels = Vec[UInt8].new();
// ... fill pixels ...
match xbm_pack(pixels, 16, 16) {
  Ok(packed) => {
    match xbm_build("sample", packed, 16, 16) {
      Ok(text) => { /* canonical XBM source */ },
      Err(e) => { /* xbm: invalid name, ... */ },
    }
  },
  Err(e) => { /* xbm: non-binary pixel, ... */ },
}
```

## API summary

| Function | Description |
|----------|-------------|
| `xbm_parse(data)` | Parses defines + array, validates sizes; returns `XbmImage{width, height, name, bits}` |
| `xbm_width(img)` | Width, `1..1000000` |
| `xbm_height(img)` | Height, `1..1000000` |
| `xbm_name(img)` | Shared base name of `<name>_width`, `<name>_height`, `<name>_bits` |
| `xbm_byte_span(img)` | Packed raster size: `xbm_row_bytes(width) * height` |
| `xbm_bit(img, x, y)` | Pixel at a **top-left origin**: `1` foreground, `0` background, `-1` out of range or inconsistent image |
| `xbm_row_bytes(width)` | Row stride `(width + 7) / 8`; `0` for `width <= 0` |
| `xbm_pack(pixels, width, height)` | Packs row-major `0`/`1` pixels into LSB-first raster bytes |
| `xbm_build(name, bits, width, height)` | Canonical XBM text from packed bytes |

`bits` returned by `xbm_parse` and expected by `xbm_build` is a flat
`Vec[UInt8]` of exactly `xbm_row_bytes(width) * height` packed bytes.

## Error model

Every fallible function returns `Result[..., Str]` with a deterministic,
`xbm: `-prefixed message.

| Message | Trigger |
|---|---|
| `xbm: unclosed comment` | a `/*` has no matching `*/` anywhere in the buffer |
| `xbm: missing width define` | no `<name>_width` define was parsed |
| `xbm: missing height define` | no `<name>_height` define was parsed |
| `xbm: missing array` | no `<name>_bits` array was parsed |
| `xbm: duplicate width define` / `xbm: duplicate height define` | a dimension is defined twice |
| `xbm: invalid width` / `xbm: invalid height` | define value `<= 0`, `> 1000000`, or 10+ digits |
| `xbm: malformed define` | `#define` not followed by `<ident>_width` / `<ident>_height` and a 1-9 digit value |
| `xbm: name mismatch` | the three base names are not identical |
| `xbm: malformed array declaration` | not `static [unsigned] char <ident>_bits[] = { ... };` (including a missing `;`) |
| `xbm: non-hex byte` | a byte token is not `0x`/`0X` plus 1-2 hex digits |
| `xbm: malformed byte list` | missing comma between bytes, or the list does not close with `}` |
| `xbm: byte count mismatch` | parsed byte count != `xbm_row_bytes(width) * height` (also `xbm_build` input) |
| `xbm: trailing tokens` | non-trivia bytes after the array's `;` (the array must be last) |
| `xbm: pixel buffer size mismatch` | `xbm_pack` pixel count != `width * height` |
| `xbm: non-binary pixel` | `xbm_pack` pixel value above 1 |
| `xbm: invalid name` | `xbm_build` name is not a C identifier |

`xbm_bit` is the one non-`Result` accessor: it returns `-1` instead of an
error; `xbm_parse` is how callers distinguish "out of range" from "malformed".

## Format notes

- Whitespace is SPACE, TAB, LF, CR, VT, FF. `/* ... */` comments may separate
  any two tokens; they do not nest and must be closed. `//` line comments are
  not part of the supported subset.
- The two defines may come in either order. After `#` any trivia is allowed, so
  `# define` is accepted; the keyword must end on a word boundary.
- The array must be the final construct and must have empty brackets. The
  second dimension of the name must be `_bits`; `char` and `unsigned char` are
  both accepted, every other element type is not.
- A byte token is `0x` or `0X` followed by one or two hex digits (upper or
  lower case). `0x5` and `0x05` are the same byte. Commas separate bytes; a
  single trailing comma before `}` is accepted.
- Bit `x % 8` of byte `y * xbm_row_bytes(width) + x / 8` is pixel `(x, y)`:
  **LSB first**, so `0x01` lights the leftmost pixel. `1` is foreground and
  `0` is background, matching X11.
- Every row is padded independently to a whole byte. Padding bits are ignored
  on read (`0xff` in a 3-pixel row lights exactly three pixels);
  `xbm_pack` always writes them as `0`.
- Canonical build: `#define <name>_width <w>`, `#define <name>_height <h>`,
  `static char <name>_bits[] = {`, then the bytes 12 per line with a
  three-space indent, lowercase `0x%02x`, a comma at the end of every
  continued line, then `};`. Output uses LF endings and ends with one LF.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.xbm
```

Expected: 20 `[PASS]` lines, then `xiom.xbm: all tests passed`, exit 0.

The suite covers built and hand-built parsing with exact names, dimensions and
bit read-back; comments, `# define`, `unsigned char`, `0X` and 1-digit hex;
LSB-first pinning and independent row padding; canonical build literals for
2x2 and a wrapped 100x1 (12 + 1 bytes); deterministic packing boundaries for
1/8/9/16 pixels; a 7x3 pack-build-parse round trip with byte-exact rebuild;
missing, duplicate, malformed and out-of-range defines; name mismatch and
malformed array declarations; the non-hex and malformed byte-list catalog;
byte count mismatches; unclosed comments; trailing tokens; hex case handling;
`xbm_row_bytes` boundaries; builder validation; define order, CRLF and
trailing commas; and the exact 1,000,000 width cap.

## Limitations

- One bit per pixel, XBM only: no XPM (colors, names, extensions), no
  rendering, no file IO.
- Only the documented C subset: no `//` comments, no sized brackets (`[N]`),
  no `static const`, no other element types, and the array must be the last
  construct in the buffer.
- Dimensions are capped at 1,000,000 per axis; the whole text and raster are
  in memory (no streaming), and multi-image files are not supported.
- `xbm_build` always emits `static char` with lowercase hex; other valid
  spellings parse but are not reproduced.
