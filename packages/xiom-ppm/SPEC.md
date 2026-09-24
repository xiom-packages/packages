# xiom.ppm SPEC

## Scope

Pure-XIOM parsing and building of the two Netpbm RGB PPM variants: P3 (ASCII) and P6 (binary), with a fixed 8-bit sample model for pixel access and canonical builder output.

## Non-goals

PGM (P2/P5), PBM (P1/P4), PAM (P7), 16-bit pixel access, compression, palettes, streaming, scaling, color management.

## API

```xiom
pub type PpmImage = {
  format: Int;      // 3 = ASCII (P3), 6 = binary (P6)
  width: Int;
  height: Int;
  maxval: Int;      // 1..65535
  data_offset: Int; // first pixel byte (P6) or first sample token (P3)
}

pub fn ppm_parse_header(data: &Vec[UInt8]) -> Result[PpmImage, Str]
pub fn ppm_pixel_rgb(data: &Vec[UInt8], x: Int, y: Int) -> Result[Int, Str]
pub fn ppm_build_p6(rgb: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str]
pub fn ppm_build_p3(rgb: &Vec[UInt8], width: Int, height: Int, samples_per_line: Int) -> Result[Vec[UInt8], Str]
pub fn ppm_sample_count(img: &PpmImage) -> Int
```

## Header grammar

```
header   := magic ws+ width sep height sep maxval p6_tail | p3_tail
magic    := "P3" | "P6"
width    := digit{1,9}          ; value 1..1000000
height   := digit{1,9}          ; value 1..1000000
maxval   := digit{1,5}          ; value 1..65535
sep      := ( whitespace | comment )+
ws       := SPACE | TAB | LF | CR | VT | FF   ; bytes 32, 9, 10, 13, 11, 12
comment  := '#' <any byte except LF>* LF?     ; runs to the end of the line
p6_tail  := ws1 "raw raster: width*height*3 bytes (1 each), or
              width*height*3*2 bytes (2 each) when maxval > 255"
p3_tail  := sep? "sample tokens: width*height*3 decimal integers separated by sep"
```

After the magic there must be at least one whitespace byte (a comment is not accepted directly after the magic). For P6, exactly one whitespace byte separates maxval from the raster; the first raster byte is `data_offset`. For P3, `data_offset` is the index of the first decimal sample token after maxval (whitespace and comments are skipped to reach it).

## Semantics

- Pixels are row-major, top-left origin, three samples per pixel (R, G, B); PPM has no row padding.
- `ppm_pixel_rgb` accepts only P6 with `maxval <= 255`; the raster position is `data_offset + (y * width + x) * 3`. P3 returns `ppm: pixel accessor requires P6`; `maxval > 255` returns `ppm: 16-bit samples unsupported`.
- `ppm_build_p6` writes `"P6\n"` + decimal width + `" "` + decimal height + `"\n255\n"`, then the RGB bytes verbatim.
- `ppm_build_p3` writes `"P3\n"` + decimal width + `" "` + decimal height + `"\n255\n"`, then decimal samples separated by single spaces; after every `samples_per_line` samples (values `< 1` clamp to 1) it writes LF, and it always ends with exactly one LF.
- `ppm_sample_count` is `width * height * 3`.

## Validation and errors

| Condition | Message |
|---|---|
| buffer shorter than the magic/header | `ppm: truncated header` |
| bytes 0-1 not `P3`/`P6` | `ppm: bad magic` |
| byte 2 is not whitespace | `ppm: missing whitespace after magic` |
| width token missing / non-decimal | `ppm: missing width` |
| width <= 0, > 1,000,000, or 10+ digits | `ppm: invalid width` |
| height token missing / non-decimal | `ppm: missing height` |
| height <= 0, > 1,000,000, or 10+ digits | `ppm: invalid height` |
| maxval token missing / non-decimal | `ppm: missing maxval` |
| maxval <= 0, > 65,535, or 6+ digits | `ppm: invalid maxval` |
| P6: maxval followed by a non-whitespace byte | `ppm: missing whitespace after maxval` |
| P6: raster bytes exceed the buffer | `ppm: truncated pixel data` |
| P3: no sample tokens, or fewer than width*height*3 | `ppm: truncated pixel data` |
| P3: a remaining token is not decimal | `ppm: malformed sample` |
| pixel accessor on P3 | `ppm: pixel accessor requires P6` |
| pixel accessor with maxval > 255 | `ppm: 16-bit samples unsupported` |
| pixel coordinate outside the image | `ppm: pixel out of range` |
| builder rgb length != width*height*3 | `ppm: pixel buffer size mismatch` |
| builder width/height <= 0 | `ppm: invalid width`, `ppm: invalid height` |

## Test plan

18 checks: P6 header fields and offset 11 from the canonical builder; hand-built P3 header fields and offset 11; comments before/between/after tokens on both formats with exact offsets; CR/LF/TAB/SPACE/VT/FF separators; maxval 0 and 65536 rejected; bad magic, P7 and 1-byte buffers rejected; truncation after maxval for P6 (short raster, non-whitespace raster byte, EOF) and P3 (2 of 6 samples, header only); exact padding-free 2x2 P6 raster bytes and four-pixel round-trip; out-of-range coordinates and message; 16-bit maxval (512, 1000) header parse plus pixel-accessor rejection; P3 accessor rejection; exact 1x1/2x2 `build_p6` headers and lengths; size-mismatch and non-positive-dimension errors; pinned `build_p3` outputs for samples_per_line 2, 0 (clamped to 1) and 100; sample counts 12, 3 and 36; all-pixel 5x7 P6 byte and coordinate round-trip.

## Known limitations

- P3 tokens are validated for shape and count; sample values are not range-checked against `maxval`.
- P3 accepts extra trailing tokens after the expected sample count (they are ignored); a non-decimal trailing token is still an error.
- P6 with `maxval > 255` is header-parsed with 2 bytes per sample but has no pixel accessor.
- No streaming; the whole raster is in memory.
