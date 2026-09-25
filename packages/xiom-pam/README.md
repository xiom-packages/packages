# xiom.pam

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (20/20); NOT published yet.
> **Scope:** Netpbm PAM (P7): header parsing with comments and ordered TUPLTYPE lines, raster span access, and canonical building for flat tuple images (1- and 2-byte samples).
> **Deps:** `xiom.std` only. No FFI in v0.1.

## Overview

`xiom.pam` reads and writes the Netpbm PAM format on flat `Vec[UInt8]`
buffers. PAM is the "portable arbitrary map": a header describing a
rectangular grid of tuples, followed immediately by the uncompressed raster.

- The header is `P7` and then `WIDTH`, `HEIGHT`, `DEPTH`, `MAXVAL`,
  zero or more `TUPLTYPE` lines, and `ENDHDR`, one field per line.
- `#` lines are comments and blank lines are legal; fields may appear in any
  order, but each required field appears exactly once.
- The raster is `width * height * depth` samples, row-major with no padding:
  one byte per sample when `maxval <= 255`, two bytes big-endian when `maxval`
  is 256..65535.
- The parser validates the complete raster span up front; `PamImage` records
  `data_offset` and `raster_len` so callers can slice the raster without
  copying. TUPLTYPE values are preserved in header order but never
  interpreted -- PAM assigns no meaning to the samples.

## Install / use

```
xiom pkg install xiom.pam@0.1.0     # consumer, once published
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xiom
use xiom.pam;

// A 1x1 8-bit grayscale pixel.
let gray = Vec[UInt8].new();
gray.push(128);

let types = Vec[Str].new();
types.push("GRAYSCALE");

match pam_build(1, 1, 1, 255, &types, &gray) {
  Ok(bytes) => {
    // bytes is a complete, self-contained PAM image.
    match pam_parse_header(bytes) {
      Ok(img) => {
        // pam_width(&img) == 1, pam_depth(&img) == 1, pam_maxval(&img) == 255
        let off: Int = pam_raster_offset(&img);
        let span = pam_raster_copy(bytes, &img); // Result[Vec[UInt8], Str]
      },
      Err(e) => { /* pam: ... */ },
    }
  },
  Err(e) => { /* pam: invalid tuple type, pam: raster buffer size mismatch, ... */ },
}

// Parse anything a producer writes (comments, CRLF, free field order):
let raw = pam_parse_header(file_bytes); // file IO is the caller's job
```

## API summary

| Function | Description |
|----------|-------------|
| `pam_parse_header(data)` | Validates a P7 header and the exact raster; returns `PamImage{width, height, depth, maxval, bytes_per_sample, data_offset, raster_len, tupltypes}` |
| `pam_bytes_per_sample(maxval)` | `1` for `1..255`, `2` for `256..65535`, `0` outside the PAM range |
| `pam_width(img)` / `pam_height(img)` / `pam_depth(img)` / `pam_maxval(img)` | Parsed header fields (`1..1000000`, `1..1000000`, `1..1000000`, `1..65535`) |
| `pam_raster_offset(img)` | Index of the first raster byte in the parsed buffer |
| `pam_raster_len(img)` | `width * height * depth * bytes_per_sample` |
| `pam_raster_copy(data, img)` | Copies exactly the raster span out of `data`; `pam: raster out of range` guards forged/stale images |
| `pam_tupltype_count(img)` | Number of TUPLTYPE header lines (`0` or more) |
| `pam_tupltype(img, index)` | The `index`-th TUPLTYPE value in header order, or `""` when out of range (parsed values are never empty) |
| `pam_tuple_type(img)` | The TUPLTYPE values joined with one SPACE, or `""` when there were none |
| `pam_build(width, height, depth, maxval, tupltypes, raster)` | Canonical single-image PAM: `P7`, WIDTH, HEIGHT, DEPTH, MAXVAL, one TUPLTYPE line per value, `ENDHDR`, then the raster verbatim |

`tupltypes` is a `&Vec[Str]` of zero or more values; `raster` must be exactly
`width * height * depth * bytes_per_sample` bytes long. `data_offset` is the
first byte after the LF that terminates `ENDHDR`.

## Error model

Every fallible function returns `Result[..., Str]` with a deterministic,
`pam: `-prefixed message:

| Message | Trigger |
|---|---|
| `pam: truncated header` | buffer shorter than `P7` + one line ending |
| `pam: bad magic` | bytes 0-1 are not `P7` |
| `pam: missing newline after magic` | `P7` is not followed by LF (or CRLF) |
| `pam: missing ENDHDR` | EOF before a complete `ENDHDR` line |
| `pam: unknown header key` | a line's first token is not one of the six fields |
| `pam: malformed header line` | extra tokens after a numeric value, or after `ENDHDR` |
| `pam: duplicate width` / `height` / `depth` / `maxval` | a required field appears twice |
| `pam: missing width` / `height` / `depth` / `maxval` | field absent, or its value token is absent/non-decimal |
| `pam: invalid width` / `height` / `depth` | value `<= 0`, `> 1000000`, or 10+ digits |
| `pam: invalid maxval` | value `<= 0`, `> 65535`, or 10+ digits |
| `pam: invalid tuple type` | empty TUPLTYPE value, or any byte `< 32` or `== 127` |
| `pam: truncated raster` | fewer raster bytes than `width*height*depth*bytes_per_sample` |
| `pam: extra raster bytes` | more bytes after the computed raster (single-image only) |
| `pam: raster buffer size mismatch` | builder `raster` length != the computed size |
| `pam: raster out of range` | `pam_raster_copy` span invalid against `data` |

## Format notes

- Header fields: `WIDTH n`, `HEIGHT n`, `DEPTH n`, `MAXVAL n`, `TUPLTYPE s`,
  `ENDHDR`. Field names are case-sensitive upper case. A line whose first
  non-blank byte is `#` is a comment; blank lines are ignored.
- The magic must be followed by a line ending; every header line is
  LF-terminated (CRLF is accepted and normalized away; a bare CR is not a line
  terminator).
- A numeric value is a single decimal token of at most 9 digits, optionally
  surrounded by SPACE/TAB; a sign or a second token is an error. A token that
  does not start with a digit (including `-1`) is reported as *missing*; a
  numeric value outside the allowed range is *invalid*.
- A TUPLTYPE value is the rest of the line, trimmed of leading/trailing
  SPACE/TAB; interior spaces are part of the value. Every byte must be
  32..126 or `>= 128`, so comments cannot be injected and a parsed value can
  always be rebuilt. Multiple `TUPLTYPE` lines are preserved in order and
  `pam_tuple_type` joins them with a single blank, per the PAM specification.
- Sample size is `1` byte for `maxval <= 255` and `2` bytes big-endian for
  `maxval 256..65535`; there is no per-row or per-tuple padding.
- Rasters are raw bytes, so trailing whitespace after the raster is data:
  the parser requires the buffer to end exactly at `data_offset + raster_len`.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.pam
```

20 conformance tests cover built and hand-built headers, exact header/raster
spans, comments and blank lines, CRLF, 8-bit and 16-bit samples, the
255/256 byte-size boundary, up to 1,000,000-wide rasters, multiple and
interior-space TUPLTYPE values, free field order, byte-exact 16-bit and high
byte round-trips, bad magic and truncation, missing/duplicate keys, range and
malformed-line errors, exact raster shorter/longer errors, builder validation,
canonicalization of odd-order commented input, and `pam_raster_copy` sentinel
guards.

## Limitations

- One image per buffer: concatenated PAM streams are rejected with
  `pam: extra raster bytes`; there is no streaming and no file IO.
- Dimensions are capped at 1,000,000 per axis; the whole raster is in memory.
- `MAXVAL` is capped at 65,535 (PAM limit); `MAXVAL 1` and other low maxima
  are stored as-is and never rescaled.
- TUPLTYPE values are opaque strings: no official tuple types are validated
  against `DEPTH`, and no sample values or tuple semantics are interpreted.
- Control bytes (`< 32`, `127`) are rejected in TUPLTYPE; non-ASCII bytes
  (`>= 128`) are preserved unchanged.
- No scaling, dithering, gamma or color-space conversion; callers move
  samples through the raster span plus `pam_build`.
