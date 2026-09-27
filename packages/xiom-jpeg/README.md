# xiom.jpeg

> **Status:** `stable` -- conformance-tested green on compiler v0.61.3 (16/16); NOT published yet (publish pending, wave-34 batch).
> **Scope:** JPEG (ITU-T T.81 / ISO/IEC 10918-1) marker and segment layer over
> flat `Vec[UInt8]` buffers: SOI/EOI framing, APP0 JFIF header, APP1 EXIF
> presence, every APP0..APP15 indexed, DQT, SOF0/SOF1/SOF2 frames, DHT counts,
> SOS scan headers, DRI restart interval, COM index, and raw entropy spans with
> FF00 stuffing and RST0..RST7 counting. Entropy-coded data is never decoded.
> **Deps:** `xiom.std` only (`xiom.convert` for the offset-carrying error
> messages). No FFI.

## What it is

`xiom.jpeg` is a pure-XIOM **structure parser and validator** for JPEG
interchange-format files. It works on a flat `Vec[UInt8]` and walks the real
byte stream:

- the `FF D8` SOI, the marker grammar `FF (FF)* code` (fill bytes accepted),
  and the segment framing `FF code BE16(length) payload[length-2]`;
- APP0 JFIF decode (version, density units, density, thumbnail dimensions) and
  APP1 `Exif\0\0` presence; every APP0..APP15 segment indexed by marker
  offset, declared length and payload offset;
- DQT quantization tables (8-bit and 16-bit precision, 64 nonzero values each);
- SOF0/SOF1/SOF2 frames: precision, dimensions, per-component id, sampling
  factors, quantization table id, progressive flag;
- DHT Huffman table **counts** (class, id, 16 code counts, symbol count);
  symbol bytes are validated for presence but stay opaque;
- SOS scans: component selectors, DC/AC table selectors, spectral selection
  `Ss`/`Se`, successive approximation `Ah`/`Al`;
- DRI restart interval and per-scan RST0..RST7 counting;
- COM comments (span indexed, payload opaque);
- EOI, with any trailing bytes counted.

Huffman-coded entropy data is **opaque**: the parser finds the exact scan span,
consumes `FF 00` stuffing, counts restart markers inside it, and exposes the
raw (still stuffed, still containing RST markers and fill FFs) bytes as an
offset/length pair. There is no Huffman decode, no inverse DCT, no pixels, and
no encoder in this package (v0.1 scope). See `SPEC.md` for the byte layout, the
validation order and the full 45-message error catalog.

Parsing returns `Result[JpegImage, JpegError]`. Every failure message starts
with `jpeg: ` and carries an absolute byte offset, e.g.
`jpeg: invalid segment length at 20` or `jpeg: missing EOI at 146`.

## Format coverage

| Element | Supported |
|---|---|
| SOI / EOI framing | yes; `FF D8` at bytes 0..1, EOI required after at least one SOS |
| Marker grammar `FF (FF)* code` | yes; fill FF runs between segments accepted |
| Segment framing | yes; length includes the 2 length bytes, minimum 2 (empty payload legal) |
| APP0 JFIF | version, units (0..2), nonzero density, thumbnail dimensions and 3*tw*th bytes validated |
| APP1 EXIF | presence of `Exif\0\0` plus the marker offset; TIFF body opaque |
| APP0..APP15 | every segment indexed in stream order (marker, offset, declared length, payload offset) |
| DQT | table id + precision + 64 values (8/16-bit big-endian, each value nonzero) |
| SOF0 / SOF1 / SOF2 | precision, dimensions, components (id, H/V 1..4, Tq 0..3), progressive flag |
| SOF family variants (C3, C5..C7, C9..CB, CD..CF) | rejected `jpeg: unsupported frame type`; C8 JPG and CC DAC rejected `jpeg: unsupported marker` |
| DHT | class (DC/AC), id, 16 code counts, symbol count <= 256; symbol bytes opaque |
| SOS | selectors, Ss/Se/Ah/Al; interleaved and non-interleaved scans accepted |
| Scan data | exact raw span; FF00 stuffing consumed, RST0..RST7 counted, never interpreted |
| DRI | restart interval (last segment wins), segment count |
| COM | span index (offset + declared length), payload opaque |
| Entropy decode, Huffman code building, IDCT, pixels, encoder | **not implemented** |

## Package layout

```
packages/xiom-jpeg/
  package.xi                  manifest: name xiom.jpeg, version 0.1.0, deps xiom.std
  src/jpeg.xi                 the whole codec (1443 lines, pure XIOM, no FFI)
  tests/test_conformance.xi   16 conformance checks over synthetic fixtures
  STATUS.json                 stage stable, compiler v0.61.3, 16/16 pass
  README.md                   this file
  SPEC.md                     implemented byte format, error catalog, test matrix
```

## Build and test

From the repository root (`E:\xiom-packages\packages`):

```
# compile + run the conformance suite
& .\scripts\port.ps1 -Package xiom.jpeg

# compile/type-check only (no suite run)
& .\scripts\port.ps1 -Package xiom.jpeg -NoRun
```

`port.ps1` resolves the toolchain, enforces the namespace rule and runs
`xiom --run tests/test_conformance.xi`. A green run ends with:

```
port: PASS (passed=16 failed=0 program_exit=0 exit=0)
```

The suite builds every fixture as a synthetic byte buffer in-test; no external
data files are used.

## Usage

```xiom
use xiom.jpeg;

// `data` is a complete JPEG file loaded into a flat byte buffer.
fn jpeg_summary(data: &Vec[UInt8]) -> Int {
  if (!jpeg_is_jpeg(data)) { return -1; }
  match jpeg_parse(data) {
    Ok(img) => {
      let w = jpeg_width(&img);                 // 1..65535
      let h = jpeg_height(&img);                // 1..65535
      let progressive = jpeg_is_progressive(&img);

      if (jpeg_has_jfif(&img)) {
        let units = jpeg_jfif_units(&img);      // 0 aspect, 1 dpi, 2 dpcm
        let dx = jpeg_jfif_density_x(&img);     // always > 0
      }
      if (jpeg_has_exif(&img)) {
        let exif_at = jpeg_exif_offset(&img);   // marker offset of the APP1
      }

      let n = jpeg_scan_count(&img);
      var s = 0;
      while (s < n) {
        let span_off = jpeg_scan_data_offset(&img, s);  // raw entropy bytes
        let span_len = jpeg_scan_data_length(&img, s);  // still stuffed
        let restarts = jpeg_scan_restart_count(&img, s);
        s = s + 1;
      }
      return n;
    },
    Err(e) => {
      // Deterministic message plus an absolute byte offset, e.g.
      // "jpeg: invalid segment length at 20".
      let msg = jpeg_error_message(&e);
      let off = jpeg_error_offset(&e);
      return -1;
    },
  }
}
```

## API

73 public functions, two public types (`JpegImage`, `JpegError`). Accessors
take `&JpegImage` / `&JpegError` and return `-1` (or `false`) when an index is
out of range, so a drifted call can never panic.

| Entry point(s) | Returns | Description |
|---|---|---|
| `jpeg_parse(data)` | `Result[JpegImage, JpegError]` | Parse and validate a whole buffer; never decodes entropy data. |
| `jpeg_is_jpeg(data)` | `Bool` | `FF D8` at bytes 0..1; `false` (not an error) for short/malformed buffers. |
| `jpeg_soi()`, `jpeg_eoi()`, `jpeg_sos()`, `jpeg_frame_baseline()`, `jpeg_frame_extended()`, `jpeg_frame_progressive()`, `jpeg_restart_first()`, `jpeg_restart_last()`, `jpeg_min_segment_length()`, `jpeg_no_offset()` | `Int` | Marker-code and limit constants: 216, 217, 218, 192, 193, 194, 208, 215, 2, -1. |
| `jpeg_width(img)`, `jpeg_height(img)`, `jpeg_precision(img)` | `Int` | Validated SOF fields. |
| `jpeg_frame_marker(img)`, `jpeg_is_progressive(img)` | `Int`, `Bool` | 192/193/194; progressive means SOF2. |
| `jpeg_component_count(img)` | `Int` | Frame component count (1..255). |
| `jpeg_component_id(img, i)`, `jpeg_component_h(img, i)`, `jpeg_component_v(img, i)`, `jpeg_component_quant(img, i)` | `Int` | Component id, H/V sampling (1..4), quant table id (0..3); -1 out of range. |
| `jpeg_has_jfif(img)` | `Bool` | JFIF APP0 parsed. |
| `jpeg_jfif_version_major(img)`, `jpeg_jfif_version_minor(img)`, `jpeg_jfif_units(img)`, `jpeg_jfif_density_x(img)`, `jpeg_jfif_density_y(img)`, `jpeg_jfif_thumb_w(img)`, `jpeg_jfif_thumb_h(img)` | `Int` | Decoded JFIF header; 0 fields when absent. |
| `jpeg_has_exif(img)`, `jpeg_exif_offset(img)` | `Bool`, `Int` | EXIF APP1 presence and marker offset; -1 when absent. |
| `jpeg_quant_table_count(img)`, `jpeg_quant_id(img, t)`, `jpeg_quant_precision(img, t)`, `jpeg_quant_value_offset(img, t)` | `Int` | DQT index: id (0..3), precision (0 = 8-bit, 1 = 16-bit), flat-store offset. |
| `jpeg_quant_value(img, t, k)` | `Int` | Value `k` (0..63, stream order) of table `t`; -1 outside the table window. |
| `jpeg_dht_table_count(img)`, `jpeg_dht_class(img, t)`, `jpeg_dht_id(img, t)`, `jpeg_dht_symbol_count(img, t)`, `jpeg_dht_count_offset(img, t)` | `Int` | DHT index: class (0 DC, 1 AC), id (0..3), symbol sum (0..256), flat-store offset. |
| `jpeg_dht_count(img, t, k)` | `Int` | Code count `k` (0..15) of table `t`; -1 outside the table window. |
| `jpeg_scan_count(img)`, `jpeg_scan_ss(img, s)`, `jpeg_scan_se(img, s)`, `jpeg_scan_ah(img, s)`, `jpeg_scan_al(img, s)` | `Int` | Per-SOS header: scan count, spectral selection, successive approximation. |
| `jpeg_scan_component_count(img, s)`, `jpeg_scan_component_offset(img, s)` | `Int` | Selector count (1..4) and flat-store offset for scan `s`. |
| `jpeg_scan_component_id(img, s, k)`, `jpeg_scan_component_dc(img, s, k)`, `jpeg_scan_component_ac(img, s, k)` | `Int` | Selector `k` of scan `s`: component id, DC table, AC table. |
| `jpeg_scan_data_offset(img, s)`, `jpeg_scan_data_length(img, s)`, `jpeg_scan_restart_count(img, s)`, `jpeg_scan_marker_offset(img, s)` | `Int` | Raw entropy span, RST count, and offset of the terminating marker. |
| `jpeg_app_segment_count(img)`, `jpeg_app_marker(img, i)`, `jpeg_app_offset(img, i)`, `jpeg_app_length(img, i)`, `jpeg_app_data_offset(img, i)` | `Int` | APP0..APP15 index in stream order (declared length includes its 2 length bytes). |
| `jpeg_comment_count(img)`, `jpeg_comment_offset(img, i)`, `jpeg_comment_length(img, i)` | `Int` | COM index; payload opaque. |
| `jpeg_restart_interval(img)`, `jpeg_has_dri(img)`, `jpeg_dri_count(img)` | `Int`, `Bool`, `Int` | Latest DRI interval (-1 when none), DRI presence, DRI segment count. |
| `jpeg_eoi_offset(img)`, `jpeg_total_bytes(img)`, `jpeg_trailing_bytes(img)` | `Int` | EOI FF offset, buffer size, bytes after EOI. |
| `jpeg_error_message(e)`, `jpeg_error_offset(e)` | `Str`, `Int` | Failure message and offset (for `Err` values; offset is always >= 0). |

`JpegImage` stores everything as parallel `Vec[Int]` fields (there are no
`Vec[Str]` fields at all): the frame component list, the quant table index with
a flat 64-values-per-table store, the Huffman index with a flat
16-counts-per-table store, the scan index with a flat selector store, plus the
APP and COM indexes. `JpegError` carries `message` and `offset`.

## Errors and limits

- Every `Err` from `jpeg_parse` carries a non-empty message of the form
  `<what> at <absolute byte offset>`; the offset is the offending field byte,
  the marker FF, or the buffer length for end-of-input truncation.
  The internal success sentinel (offset -1) never escapes.
- Accessors are total: `-1` / `false` for out-of-range indexes; the flat stores
  are window-checked against their table's 64/16 values.
- No entropy decoding: Huffman code tables are never built from DHT symbols,
  DC/AC coefficients are never decoded, and no pixel buffer exists.
- No encoder, no transcoder, no thumbnail extraction (JFIF thumbnail bytes are
  validated for length only).
- Only SOF0/SOF1/SOF2 are accepted; lossless, differential and arithmetic
  frames (C3, C5..C7, C9..CB, CD..CF) are rejected, as are JPG (C8), DAC (CC),
  DNL (DC), DHP (DE), EXP (DF) and JPG0..JPG13 (F0..FD).
- Restart markers are counted per scan but not validated against the DRI
  interval or checked for RSTn ordering; cross-scan component coverage and
  progressive refinement ordering are not enforced.
- Bytes after EOI are allowed and counted by `jpeg_trailing_bytes`; the whole
  buffer must be in memory (no streaming interface).

## Conformance (16/16)

`tests/test_conformance.xi` runs 16 checks, all green on compiler v0.61.3:

| # | Pinned behaviour |
|---|---|
| 1 | canonical 146-byte baseline fixture decodes every field and offset exactly |
| 2 | SOI validation and `jpeg_is_jpeg` classification sentinels |
| 3 | APP index order/offsets, JFIF decode, EXIF presence, malformed JFIF variants |
| 4 | DQT 8/16-bit tables, values and malformed payloads |
| 5 | SOF0/SOF1/SOF2 acceptance and every SOF rejection rule |
| 6 | SOS selection, approximation and ordering rules |
| 7 | stuffing, restart markers and a DHT between scans |
| 8 | marker grammar, segment bounds, fill bytes |
| 9 | EOI presence, trailing bytes, missing-SOF/SOS precedence |
| 10 | COM segments indexed without interpretation |
| 11 | DRI interval, replacement and length rules |
| 12 | DHT counts, symbol sums and malformed payloads |
| 13 | constants, accessor sentinels and error accessors |
| 14 | 4:2:0 frame and its scan selectors |
| 15 | scan spans, zero-length scans and in-scan EOF |
| 16 | stuffing, fill bytes and all RST0..RST7 markers |

See `SPEC.md` for what each test pins down to the byte offset.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
