# xiom.gif

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (20/20); NOT published yet.
> **Scope:** GIF87a/GIF89a container structure parser: header, logical screen
> descriptor, global/local color tables, image descriptors, opaque LZW
> sub-block payloads, extensions (graphic control, comment, plain text,
> application incl. NETSCAPE loop count), trailer. Frame count, per-frame
> metadata and every validation error come with absolute byte offsets.
> **Deps:** `xiom.std` only (uses `xiom.convert` for offset-carrying error
> messages). No FFI.

## What it is

`xiom.gif` is a pure-XIOM **structure parser/validator** for GIF over a flat
`Vec[UInt8]` buffer. It walks the real byte stream:

- a 6-byte header (`GIF87a` or `GIF89a`);
- a 7-byte logical screen descriptor (canvas size, packed fields,
  background color index, pixel aspect);
- an optional global color table, `3 * 2^(N+1)` bytes;
- a block stream of image descriptors (with optional local color tables and
  an LZW minimum code size of 2..8) and extensions;
- the `0x3B` trailer, which must be the last byte.

LZW image data is **opaque**: sub-block framing is validated and the raw
concatenated bytes are copied out (`gif_lzw_data`), but no code is decoded
and no pixel is produced. Color tables are copied verbatim and exposed as
`0xRRGGBB` lookups.

Parsing returns `Result[Gif, Str]`. Every error message starts with `gif: `
and carries the absolute offset where parsing failed, for example
`gif: truncated image descriptor at offset 23` or
`gif: unknown block id at offset 13`. See `SPEC.md` for the full catalog and
the documented permissiveness.

## Format coverage

| Element | Supported |
|---|---|
| Header 87a/89a | yes, version reported (`87`/`89`) |
| Logical screen descriptor | yes (all fields exposed) |
| Global / local color tables | yes (verbatim, RGB lookup, 2..256 entries) |
| Interlace flag | yes (reported; de-interlacing left to callers) |
| LZW minimum code size + sub-block chain | framing validated, payload opaque |
| Graphic control extension | delay, disposal, user input, transparency, index |
| Comment extension | text bytes (multi/empty chains) |
| Plain text extension | 12-byte header + text bytes |
| Application extension | identifier, auth code, data; NETSCAPE/ANIMEXTS loop count |
| Trailer | required, must be final byte |
| LZW decode / pixels / rendering / encoding | **not implemented** |

## API

| Function | Returns | Description |
|---|---|---|
| `gif_parse(data)` | `Result[Gif, Str]` | Validate and parse the whole container. |
| `gif_version(g)` / `gif_width(g)` / `gif_height(g)` | `Int` | 87 or 89; canvas size. |
| `gif_has_gct(g)` | `Bool` | Global color table flag. |
| `gif_color_resolution(g)` / `gif_sort_flag(g)` | `Int` | Packed screen fields. |
| `gif_gct_size(g)` / `gif_bg_index(g)` / `gif_aspect(g)` | `Int` | Table entries, background, aspect. |
| `gif_global_color(g, i)` | `Int` | `0xRRGGBB` or -1. |
| `gif_frame_count(g)` / `gif_extension_count(g)` / `gif_is_animated(g)` | counts | Stream summary. |
| `gif_frame(g, i)` | `Result[GifFrame, Str]` | Full per-frame metadata. |
| `gif_frame_left/top/width/height/delay/disposal/transparent/trans_index/lzw_min/lzw_offset/lzw_size(g, i)` | `Int` | Field accessors, -1 out of range. |
| `gif_lzw_data(g, i)` | `Result[Vec[UInt8], Str]` | Opaque raw LZW payload bytes. |
| `gif_local_color_count(g, i)` / `gif_local_color(g, i, ci)` | `Int` | Local table size / `0xRRGGBB` or -1. |
| `gif_extension(g, i)` | `Result[GifExtension, Str]` | Kind, source offset, header/data ranges. |
| `gif_extension_header_byte(g, i, k)` / `gif_extension_data_byte(g, i, k)` | `Int` | Byte or -1. |
| `gif_extension_data_copy(g, i)` | `Result[Vec[UInt8], Str]` | Copy of the data chain. |
| `gif_application_loop_count(g, i)` | `Int` | NETSCAPE/ANIMEXTS loop count, or -1. |

`GifFrame` carries `index, left, top, width, height, interlace, has_lct,
lct_size, lzw_min, lzw_min_offset, data_offset, data_bytes, block_end,
delay, disposal, user_input, transparent, trans_index, from_gce`.
`GifExtension` carries `index, kind, offset, hdr_offset, hdr_size,
data_offset, data_size`; `GIF_EXT_KIND_CONTROL/COMMENT/PLAIN_TEXT/APPLICATION`
name the kinds.

## Usage

```xiom
use xiom.gif;

match gif_parse(bytes) {
  Ok(g) => {
    // Canvas
    let w = gif_width(&g);
    let h = gif_height(&g);
    let animated = gif_is_animated(&g);

    // Frames
    let n = gif_frame_count(&g);
    var i = 0;
    while (i < n) {
      let fr = gif_frame(&g, i);
      if (fr.is_ok) {
        let f: GifFrame = fr.value;
        // f.delay (1/100 s), f.disposal, f.transparent, f.trans_index,
        // f.left/top/width/height, f.interlace, f.lzw_min, source offsets.
      }
      let raw = gif_lzw_data(&g, i);   // opaque LZW bytes, no decode
      i = i + 1;
    }

    // NETSCAPE loop count (0 = forever)
    if (gif_extension_count(&g) > 0) {
      let loop = gif_application_loop_count(&g, 0);
    }
  },
  Err(e) => {
    // Deterministic message with a byte offset, e.g.
    // "gif: truncated lzw sub-block at offset 24"
  },
}
```

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.gif
```

20 conformance tests build every fixture as a synthetic byte buffer in-test
(no external data files): trailer-only 87a; 89a with global table, graphic
control and one frame; a two-frame NETSCAPE animation; local table and
interlace; GCE scoping and reset; comments; plain text; application
extensions; header/signature/version failures; global and local table
truncation; descriptor and sub-block truncation; missing trailer, trailing
data and unknown block ids; unknown extension labels; malformed graphic
control variants; LZW code-size bounds and empty payloads; a 255+45-byte
multi-chunk payload; accessor sentinels; and byte-offset agreement with the
raw fixtures.

## Limitations

- Whole file in memory; no streaming.
- No LZW decode, no pixels, no rendering, no encoding.
- LZW minimum code size is enforced to 2..8 (some decoders accept 1).
- Screen/frame geometry is reported but not range-checked.
- Unknown block ids and extension labels are rejected rather than skipped.
- De-interlacing, disposal application, transparency compositing and palette
  conversion are left to callers.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
