# xiom.gif -- implemented byte format (SPEC)

> **Status:** implemented and conformance-tested on XIOM v0.61.3 (20/20).
> **Scope:** GIF87a/GIF89a container structure: header, logical screen
> descriptor, global/local color tables, image descriptors, opaque LZW
> sub-block payloads, extensions, trailer. No pixel decoding, no LZW decode,
> no rendering, no encoder.

This file documents the byte layout the parser in `src/gif.xi` actually
accepts and rejects. All offsets are absolute byte offsets into the input
buffer. All integer fields are unsigned and little-endian unless stated
otherwise.

## 1. Overall layout

```
GIF file := Header LSD [GCT] Block* Trailer
Block    := ImageDescriptor [LCT] LZWCodeSize SubBlock* 0x00
          | Extension
Extension:= 0x21 Label Body
```

The trailer must be the final byte; anything after it is an error.

## 2. Header (6 bytes)

| Offset | Size | Field | Accepted values |
|---|---|---|---|
| 0 | 3 | signature | ASCII `GIF` = `47 49 46` |
| 3 | 3 | version | ASCII `87a` = `38 37 61` or `89a` = `38 39 61` |

Rejected: any other version (`gif: bad version at offset 3`), any other
signature (`gif: bad signature at offset 0`), fewer than 6 bytes
(`gif: truncated header at offset <n>`, where `<n>` is the buffer length,
i.e. the first missing byte).

The declared version does **not** gate extensions: an 87a file carrying a
graphic control extension parses and reports version 87.

## 3. Logical Screen Descriptor (7 bytes, offset 6)

| Offset | Size | Field | Interpretation |
|---|---|---|---|
| 6 | 2 | width | logical screen width, 0..65535 |
| 8 | 2 | height | logical screen height, 0..65535 |
| 10 | 1 | packed | see below |
| 11 | 1 | background color index | exposed verbatim |
| 12 | 1 | pixel aspect ratio | exposed verbatim |

`packed` bits:

| Bits | Meaning | Exposure |
|---|---|---|
| 7 | global color table flag | `gif_has_gct` |
| 6..4 | color resolution | `gif_color_resolution` (0..7) |
| 3 | sort flag | `gif_sort_flag` (0/1) |
| 2..0 | GCT size exponent N | entries = 2^(N+1), `gif_gct_size` |

Fewer than 13 bytes with a valid 6-byte header is
`gif: truncated screen descriptor at offset 6`.

Width, height, background index and aspect are **not** range-checked
(0 is accepted for every one of them); the reserved bits of `packed` are
read but not validated.

## 4. Color tables

Global color table (only when packed bit 7 is set), starting at offset 13:
`3 * 2^(N+1)` bytes, three bytes per entry (R, G, B). If the table does not
fit: `gif: truncated global color table at offset 13`.

Local color table (only when the image descriptor packed bit 7 is set),
immediately after the 10-byte image descriptor: `3 * 2^(M+1)` bytes with M
from the descriptor packed bits 2..0. If it does not fit:
`gif: truncated local color table at offset <LCT start>`.

Tables are copied verbatim. `gif_global_color(g, i)` and
`gif_local_color(g, frame, ci)` return packed `0xRRGGBB` values or -1 when
the index is out of range. No palette conversion, transparency application
or rendering is performed.

## 5. Image descriptor (from a 0x2C byte)

| Offset | Size | Field |
|---|---|---|
| +0 | 1 | `0x2C` introducer |
| +1 | 2 | left position |
| +3 | 2 | top position |
| +5 | 2 | frame width |
| +7 | 2 | frame height |
| +9 | 1 | packed |

Descriptor `packed` bits: bit 7 local color table flag, bit 6 interlace
flag, bit 5 sort flag, bits 4..3 reserved (ignored), bits 2..0 LCT size
exponent M. Fewer than 10 bytes from the introducer is
`gif: truncated image descriptor at offset <introducer>`.

Frame geometry is **not** checked against the logical screen.

## 6. LZW image data (opaque)

After the descriptor (and optional local table) comes:

| Size | Field |
|---|---|
| 1 | LZW minimum code size, enforced 2..8 |
| var | sub-block chain |

Sub-block chain: a length byte `L`, exactly `L` payload bytes, repeated;
`L = 0` terminates the chain. The parser concatenates all payload bytes and
exposes them through `gif_lzw_data`. Length bytes and the terminator are not
part of the payload; the recorded `data_bytes` is the concatenated length.
The code is never decoded.

Errors: missing code-size byte `gif: truncated lzw code size at offset <n>`;
code size outside 2..8 `gif: invalid lzw code size at offset <n>`; a length
byte whose payload does not fit or a chain that ends before the 0x00
terminator `gif: truncated lzw sub-block at offset <length byte or buffer
end>`. An empty chain (`0x00` immediately after the code size) is valid and
yields a zero-byte payload.

Note: some decoders tolerate a code size of 1 for two-color images; this
parser deliberately enforces 2..8 and documents that as a limitation.

## 7. Extensions (from a 0x21 byte)

Generic: `0x21`, one label byte, then a label-specific body. Unknown labels
are rejected (`gif: unknown extension label at offset <label>`); fewer than
two bytes from the introducer is
`gif: truncated extension at offset <introducer>`.

### 7.1 Graphic control (label 0xF9)

| Size | Field |
|---|---|
| 1 | block size, must be 0x04 |
| 1 | packed: bits 7..5 reserved (ignored), bits 4..2 disposal, bit 1 user input, bit 0 transparency |
| 2 | delay in hundredths of a second |
| 1 | transparent color index |
| 1 | terminator, must be 0x00 |

Any of: block size != 4, terminator != 0, or fewer than 8 bytes from the
introducer is `gif: malformed graphic control extension at offset
<introducer>`.

Scope semantics: the extension applies to the **next** image descriptor
only. The values are attached to that frame and then reset to defaults
(delay 0, disposal 0, user input 0, transparency 0, transparent index 0).
Two consecutive GCEs before one frame: the last one wins. A GCE with no
following frame is recorded in the extension list but attached to nothing.

### 7.2 Comment (label 0xFE)

No fixed body; the body is a sub-block chain whose concatenation is exposed
as comment text. Empty comment (`0x00`) is valid.

### 7.3 Plain text (label 0x01)

| Size | Field |
|---|---|
| 1 | block size, must be 0x0C |
| 12 | header: left LE16, top LE16, width LE16, height LE16, cell width, cell height, foreground index, background index |
| var | sub-block text chain |

Block size != 0x0C or a truncated 12-byte body is
`gif: malformed plain text extension at offset <introducer>`. The header is
copied verbatim into the extension record and readable byte by byte; no
text-grid rendering is performed.

### 7.4 Application (label 0xFF)

| Size | Field |
|---|---|
| 1 | block size, must be 0x0B |
| 8 | application identifier |
| 3 | application authentication code |
| var | sub-block data chain |

Block size != 0x0B or a truncated 11-byte body is
`gif: malformed application extension at offset <introducer>`.

`gif_application_loop_count` decodes the standard animation loop payload for
identifiers `NETSCAPE` / `2.0` and `ANIMEXTS` / `1.0` when the data is
exactly the three bytes `01 <count LE16>`; it returns the count verbatim
(0 means loop forever) or -1 for anything else, including wrong identifiers,
wrong data length, or a first byte other than 0x01.

Sub-block overruns or a missing terminator in comment/plain text/application
data are `gif: truncated extension sub-block at offset <length byte or
buffer end>`.

## 8. Trailer (0x3B)

Must be the last byte of the buffer. End of input before it is
`gif: missing trailer at offset <buffer length>`; any byte after it is
`gif: trailing data at offset <first byte after the trailer>`. Any other
byte in block position is `gif: unknown block id at offset <byte>`.

## 9. Validation order

1. length >= 6, then signature, then version;
2. length >= 13 (screen descriptor);
3. global color table fit;
4. block stream in file order; blocks are fully validated as encountered,
   so the first error in file order is the reported one;
5. trailer position.

## 10. Error catalog (exact messages)

| Message | Condition |
|---|---|
| `gif: truncated header at offset N` | N = buffer length, fewer than 6 bytes |
| `gif: bad signature at offset 0` | bytes 0..2 not `GIF` |
| `gif: bad version at offset 3` | bytes 3..5 not `87a`/`89a` |
| `gif: truncated screen descriptor at offset 6` | fewer than 13 bytes with a valid header |
| `gif: truncated global color table at offset 13` | flagged table does not fit |
| `gif: truncated image descriptor at offset N` | N = 0x2C introducer, fewer than 10 bytes |
| `gif: truncated local color table at offset N` | N = LCT start |
| `gif: truncated lzw code size at offset N` | N = position after descriptor/LCT |
| `gif: invalid lzw code size at offset N` | code size < 2 or > 8 |
| `gif: truncated lzw sub-block at offset N` | N = failing length byte or buffer end |
| `gif: truncated extension at offset N` | N = 0x21 introducer |
| `gif: unknown extension label at offset N` | N = label byte |
| `gif: malformed graphic control extension at offset N` | N = introducer |
| `gif: malformed plain text extension at offset N` | N = introducer |
| `gif: malformed application extension at offset N` | N = introducer |
| `gif: truncated extension sub-block at offset N` | N = failing length byte or buffer end |
| `gif: unknown block id at offset N` | N = offending byte |
| `gif: missing trailer at offset N` | N = buffer length |
| `gif: trailing data at offset N` | N = first byte after 0x3B |

Offset conventions: for truncation the offset is the position of the first
missing byte (the buffer length when the stream ends); for malformed fixed
bodies it is the extension introducer; for sub-block failures it is the
length byte that cannot be satisfied.

## 11. Documented permissiveness and limitations

- The whole buffer must be in memory; there is no streaming interface.
- No LZW decoding, no pixel buffers, no rendering, no encoder.
- Screen geometry, background index, aspect and frame geometry are exposed
  but not range-checked; frame rectangles may exceed the canvas.
- Reserved bits/bytes are ignored, not validated.
- Unknown block ids and extension labels are rejected (a permissive decoder
  would skip unknown extensions instead).
- A file with no image descriptor (header + trailer) is valid and reports
  frame count 0.
- Multiple sub-blocks per frame and per extension are concatenated in order.
- Trailing bytes after the trailer are rejected.

## 12. Test matrix (tests/test_conformance.xi)

| Test | Covers |
|---|---|
| t1 | minimal 87a stream, canvas fields, zero frames |
| t2 | 89a + GCT + GCE + one frame: all frame metadata and offsets |
| t3 | two frames, NETSCAPE loop 5, per-frame GCE metadata |
| t4 | local color table + interlace, no global table |
| t5 | GCE scope: next frame only, defaults reset, dangling GCE |
| t6 | comment extensions, multi/empty data, sentinels |
| t7 | plain text 12-byte header, text bytes, malformed variants |
| t8 | application id/auth/data, NETSCAPE loop validation |
| t9 | empty/short input, bad signature, bad version, descriptor truncation |
| t10 | GCT truncation, 2-entry and 256-entry bounds |
| t11 | truncated image descriptor, missing code-size byte |
| t12 | truncated local color table |
| t13 | sub-block overrun, missing terminator |
| t14 | missing trailer, trailing data, unknown block ids |
| t15 | unknown extension label, truncated extension, truncated GCE |
| t16 | GCE size/terminator/extent validation |
| t17 | LZW code size 1/9 rejected, 2/8 accepted, empty payload |
| t18 | 255+45-byte sub-block chain concatenation, offsets |
| t19 | accessor range sentinels |
| t20 | offset chain agreement with raw fixture bytes |
