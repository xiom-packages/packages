# xiom.webp

> **Status:** `stable` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** WebP (RIFF) container parsing and validation: `RIFF`/`WEBP` header, little-endian chunk stream with padding, VP8/VP8L uncompressed headers, VP8X extended header, ALPH, ANIM, ANMF with nested sub-chunks, and opaque ICCP/EXIF/XMP presence. Structure only; no pixel or metadata decode.
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.convert`). No FFI in v0.1.

## What it is

`xiom.webp` is a pure-XIOM container parser for the WebP image format. It
works on flat `Vec[UInt8]` buffers and validates:

- the 12-byte file header `RIFF` + `u32 LE (length - 8)` + `WEBP`, with the
  declared size required to match the buffer exactly;
- the chunk grammar `fourcc[4] u32le(size) payload[size] pad[1]`, including
  the zero padding byte after every odd-size chunk and printable-ASCII
  fourccs;
- the VP8 (lossy) uncompressed header: 3-byte frame tag, start code
  `0x9D 0x01 0x2A`, 14-bit width/height, key-frame/version/partition rules;
- the VP8L (lossless) header: `0x2F` signature, 14-bit width-1/height-1,
  alpha hint, version 0;
- the VP8X extended header: flag bits for ICC/alpha/EXIF/XMP/animation,
  reserved bits and bytes, 24-bit canvas dimensions, the 2^32-1 canvas
  product cap, first-chunk and uniqueness rules;
- ALPH, ANIM (background color and loop count) and ANMF frames: x/y,
  width/height, duration, blend/dispose bits, frame-in-canvas bounds and the
  nested padded sub-chunk stream (at most one ALPH before exactly one
  VP8/VP8L, then unknown chunks);
- ICCP, EXIF and XMP as opaque presence + size, unique per file, with ICCP
  required before the image data.

The parser exposes one parsed value: container kind (simple / extended /
animated), canvas dimensions, the VP8X flag bits, a top-level chunk index
(fourcc, offsets, size, padding, kind) and a per-frame index (x/y, size,
duration, blend/dispose, format, data offsets, nested counts). Unknown
chunks are kept opaque and bounded: they are indexed but never interpreted,
and their payloads are never copied.

## Format notes

| Part | Bytes | Encoding |
|---|---|---|
| `RIFF` | 0..3 | ASCII |
| file size | 4..7 | unsigned 32-bit little-endian, counts from offset 8 |
| `WEBP` | 8..11 | ASCII |
| chunk fourcc | +0..3 | four printable ASCII bytes |
| chunk size | +4..7 | unsigned 32-bit little-endian, payload only |
| chunk payload | +8.. | `size` bytes |
| chunk padding | +8+size | one `0x00` byte when `size` is odd |

| Chunk | Role | Rules enforced |
|---|---|---|
| `VP8 ` | lossy bitstream | length >= 10, key frame, version <= 3, start code, partition fits, non-zero 14-bit dimensions |
| `VP8L` | lossless bitstream | length >= 5, `0x2F` signature, version 0 |
| `VP8X` | extended header | first chunk, once, exactly 10 bytes, reserved fields 0, canvas product <= 2^32-1 |
| `ALPH` | alpha sub-chunk | once per scope, before the bitstream, at least 1 byte, payload opaque |
| `ANIM` | animation parameters | once, exactly 6 bytes, before the first frame |
| `ANMF` | animation frame | length >= 16, reserved bits 0, frame inside canvas, nested padded sub-chunks with exactly one bitstream |
| `ICCP` | color profile | once, before image data, opaque |
| `EXIF` | Exif metadata | once, opaque |
| `XMP ` | XMP metadata | once, opaque |
| other | vendor chunk | printable fourcc, size fits, indexed opaque |

## API

| Function | Returns | Description |
|---|---|---|
| `webp_parse(data)` | `Result[WebpImage, Str]` | Full structural validation; returns kind, canvas, flags, chunk index and frame index. |
| `webp_is_webp(data)` | `Bool` | `RIFF`/`WEBP` magic check only. |
| `webp_kind` / `webp_size` / `webp_riff_size` | `Int` | Container kind (0/1/2), buffer size, declared size. |
| `webp_has_vp8x` / `webp_vp8x_offset` / `webp_flags` | `Bool`/`Int` | VP8X presence, chunk offset and raw flags byte. |
| `webp_flag_icc` / `webp_flag_alpha` / `webp_flag_exif` / `webp_flag_xmp` / `webp_flag_animation` | `Int` | Decoded VP8X bits (0/1). |
| `webp_canvas_width` / `webp_canvas_height` | `Int` | Canvas dimensions. |
| `webp_has_image` / `webp_image_format` | `Bool`/`Int` | Top-level image presence; 0 none, 1 VP8, 2 VP8L. |
| `webp_image_offset` / `webp_image_data_offset` / `webp_image_size` | `Int` | Image chunk fourcc offset, payload offset, payload size. |
| `webp_image_width` / `webp_image_height` | `Int` | Decoded 14-bit image dimensions. |
| `webp_vp8_version` / `webp_vp8_show_frame` / `webp_vp8_first_part_size` | `Int` | VP8 frame-tag fields (-1 when not VP8). |
| `webp_vp8l_alpha` / `webp_vp8l_version` | `Int` | VP8L hint and version (-1 when not VP8L). |
| `webp_has_alph` / `webp_alph_offset` / `webp_alph_size` | `Bool`/`Int` | ALPH presence, offset, size. |
| `webp_has_iccp` / `webp_iccp_offset` / `webp_iccp_size` | `Bool`/`Int` | ICCP presence, offset, size. |
| `webp_has_exif` / `webp_exif_offset` / `webp_exif_size` | `Bool`/`Int` | EXIF presence, offset, size. |
| `webp_has_xmp` / `webp_xmp_offset` / `webp_xmp_size` | `Bool`/`Int` | XMP presence, offset, size. |
| `webp_has_anim` / `webp_anim_offset` / `webp_anim_loop_count` | `Bool`/`Int` | ANIM presence, offset, loop count (0 = forever). |
| `webp_anim_background` + `_blue`/`_green`/`_red`/`_alpha` | `Int` | Background color as raw LE32 or per-channel bytes. |
| `webp_chunk_count(img)` | `Int` | Top-level chunks in the index. |
| `webp_chunk_fourcc(img, i)` | `Str` | Fourcc, `""` out of range (compare with `str_compare`). |
| `webp_chunk_offset` / `webp_chunk_size` / `webp_chunk_data_offset` / `webp_chunk_padding` / `webp_chunk_kind(img, i)` | `Int` | Index fields; -1 out of range. |
| `webp_frame_count(img)` | `Int` | ANMF frames. |
| `webp_frame_x` / `webp_frame_y` / `webp_frame_width` / `webp_frame_height` / `webp_frame_duration` | `Int` | Per-frame metadata in pixels/milliseconds. |
| `webp_frame_blend` / `webp_frame_dispose` | `Int` | ANMF flag bits. |
| `webp_frame_offset` / `webp_frame_size` | `Int` | ANMF chunk offset and payload size. |
| `webp_frame_format` / `webp_frame_data_offset` / `webp_frame_data_size` | `Int` | Nested bitstream format (1 VP8, 2 VP8L) and payload location. |
| `webp_frame_has_alpha` / `webp_frame_nested_count` / `webp_frame_unknown_count` | `Int` | Nested ALPH presence and sub-chunk counts. |
| `webp_header_size` / `webp_chunk_header_size` / `webp_vp8x_size` / `webp_anim_size` / `webp_anmf_header_size` | `Int` | 12, 8, 10, 6, 16. |
| `webp_max_canvas_dimension` / `webp_max_dimension_14` | `Int` | 16,777,216 and 16,384. |
| `webp_kind_*`, `webp_chunk_*`, `webp_format_*`, `webp_mask_*` | `Int` | Documented constants (see SPEC.md). |

## Usage

```xi
use xiom.io;
use xiom.convert;
use xiom.webp;
use xiom.string.compare;

fn main() -> Int {
  let data = ...;  // Vec[UInt8] holding a .webp file
  match webp_parse(data) {
    Ok(img) => {
      io.println("kind: " + convert.int_to_string(webp_kind(img)));
      io.println("canvas: " + convert.int_to_string(webp_canvas_width(img))
        + "x" + convert.int_to_string(webp_canvas_height(img)));
      if (webp_has_image(img)) {
        io.println("image: " + convert.int_to_string(webp_image_width(img))
          + "x" + convert.int_to_string(webp_image_height(img)));
      }
      var i = 0;
      while (i < webp_frame_count(img)) {
        io.println("frame duration: "
          + convert.int_to_string(webp_frame_duration(img, i)));
        i = i + 1;
      }
      return 0;
    },
    Err(e) => {
      io.println("rejected: " + e);
      return 1;
    },
  }
}
```

The fourcc accessor returns a `Str` read from a `Vec[Str]`, so compare it
with `xiom.string.compare.str_compare`, never with `==`:

```xi
let name: Str = webp_chunk_fourcc(img, 0);
if (compare.str_compare(name, "VP8X") == 0) { ... }
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: twenty `[PASS]` lines, then `xiom.webp: all tests passed`, exit 0.
The suite builds every fixture in-test (no external data files) and covers
the simple, extended and animated layouts plus malformed, truncated and
padding-violating inputs.

## Caveats

- Structure only: the parser validates the VP8/VP8L uncompressed headers but
  never decodes the bitstreams, alpha planes, ICC profiles, Exif or XMP.
- The declared RIFF size must equal the buffer length; files with trailing
  bytes are rejected (`webp: riff size mismatch at 4`).
- Padding bytes must be `0`; the RIFF "MUST be 0" rule is enforced.
- `VP8 ` scale bits are ignored; the recorded dimensions are the 14-bit
  values.
- Extended static image dimensions are recorded but not required to equal the
  VP8X canvas; animated frame rectangles are bounds-checked.
- ALPH inside a VP8L frame is accepted (the container specification says
  SHOULD NOT, not MUST).

## Install / publish

```
xiom pkg install xiom.webp@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
