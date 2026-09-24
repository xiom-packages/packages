# xiom.ogg

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** Ogg container page structure: page walk, page fields and the
> Ogg CRC-32 checksum. No codec payload parsing.
> **Deps:** `xiom.std` only (the library module imports nothing from it; the
> tests use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).
> No FFI.

## What it is

`xiom.ogg` reads the page layer of the Ogg container, the framing that
carries Vorbis, Opus, Theora and other logical bitstreams. `ogg_parse_pages`
walks the buffer from offset 0, parses every 27-byte page header and its
segment (lacing) table, and returns an `OggPages` index whose `offsets` and
`sizes` locate each page inside the source buffer. `ogg_crc32` implements
the Ogg checksum and `ogg_page_crc_ok` verifies one page against its stored
checksum.

All validation is structural and purely in-memory: the API never touches the
filesystem and never interprets codec payloads. See SPEC.md for the byte
layout, walk rules, CRC parameters, error catalog and test plan.

## API

All functions are free functions in module `xiom.ogg`.

| Function | Returns | Description |
|---|---|---|
| `ogg_parse_pages(data)` | `Result[OggPages, Str]` | Walk and validate the page structure; index every page. |
| `ogg_page_count(p)` | `Int` | Number of parsed pages. |
| `ogg_page_offset(p, i)` | `Int` | Absolute byte offset of page `i`; `-1` out of range. |
| `ogg_page_serial(p, i)` | `Int` | Unsigned 32-bit serial of page `i`; `-1` out of range. |
| `ogg_crc32(data)` | `Int` | Ogg CRC-32 of a whole buffer (always non-negative). |
| `ogg_page_crc_ok(data, page_index)` | `Result[Bool, Str]` | Recompute page `page_index`'s checksum and compare. |

`OggPages = { offsets: Vec[Int]; sizes: Vec[Int]; flags: Vec[Int];
granules: Vec[Int]; serials: Vec[Int]; sequences: Vec[Int]; }` -- one element
per page, in stream order. `flags` is the raw header-type byte (`0x01`
continued packet, `0x02` beginning of stream, `0x04` end of stream);
`granules` is the 8-byte little-endian granule position clamped to Int max
(see SPEC.md); `serials`/`sequences` are the unsigned 32-bit serial and page
sequence fields.

## Ogg page layout

All multi-byte fields are little-endian. Offsets are decimal.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | capture | ASCII `"OggS"` (`4f 67 67 53`); required. |
| 4 | 1 | version | Must be 0. |
| 5 | 1 | header type | Raw flag: `0x01` continued, `0x02` BOS, `0x04` EOS. |
| 6 | 8 | granule position | u64; values >= 2^63 clamp to Int max. |
| 14 | 4 | serial | u32 bitstream serial number. |
| 18 | 4 | sequence | u32 page sequence number. |
| 22 | 4 | checksum | u32; `ogg_parse_pages` does not validate it. |
| 26 | 1 | segment count | `nsegs`, 0..255 lacing values follow. |
| 27 | `nsegs` | segment table | Lacing values; payload size = their sum. |
| 27 + `nsegs` | `sum` | payload | Page body; not interpreted. |

Page size = 27 + segment count + sum of the lacing values.

## CRC

Ogg CRC-32: polynomial `0x04C11DB7`, initial value 0, MSB-first, no input or
output reflection, no final xor. `ogg_crc32("") == 0`; the pinned check over
`"123456789"` is `0x89A1897F` (2309065087). `ogg_page_crc_ok` recomputes the
CRC over exactly the page bytes with the 4 stored checksum bytes treated as
zero and compares it with the stored little-endian u32.

## Errors

`ogg_parse_pages`: `Err("ogg: empty input")`,
`Err("ogg: bad capture pattern")`, `Err("ogg: unsupported version")`,
`Err("ogg: truncated page header")`, `Err("ogg: truncated segment table")`,
`Err("ogg: truncated page data")`, `Err("ogg: trailing garbage")`.
`ogg_page_crc_ok` propagates those and adds
`Err("ogg: page index out of range")`. See SPEC.md for the exact walk rules.

## Usage

```xi
use xiom.ogg;
use xiom.io;
use xiom.convert;

// `oggs` is any Ogg byte buffer (file contents, a socket chunk, ...).
let r = ogg_parse_pages(&oggs);
if r.is_ok {
  let pages = r.value;
  io.println("pages: " + convert.int_to_string(ogg_page_count(&pages)));
  io.println("page 0 offset: " + convert.int_to_string(ogg_page_offset(&pages, 0)));
  io.println("page 0 serial: " + convert.int_to_string(ogg_page_serial(&pages, 0)));
  let crc = ogg_page_crc_ok(&oggs, 0);
  if crc.is_ok {
    if crc.value { io.println("page 0 checksum: OK"); } else { io.println("page 0 checksum: BAD"); }
  } else {
    io.println("checksum check failed: " + crc.error);
  }
} else {
  io.println("not an Ogg page walk: " + r.error);
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ogg
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure and checksum only**: page framing is parsed and the Ogg CRC-32
  is implemented and verified, but codec payloads (Vorbis/Opus/Theora/...)
  are never decoded and the packet/payload content is not exposed. This is
  not an audio decoder.
- **No page builder**: pages cannot be written or checksums set; only
  reading/verification is implemented.
- **Granule clamping**: the granule position is read as an unsigned 64-bit
  value and clamped to Int max (9223372036854775807); in particular the
  common `-1` encoding (`0xFFFFFFFFFFFFFFFF`) of pages with no completed
  packet is reported as Int max, not -1.
- **No stream semantics**: serials are not grouped into logical bitstreams,
  continued-packet reassembly, BOS/EOS pairing and granule ordering are not
  enforced; `flags` is exposed raw.
- **No packet/chunk side-data handling**: the checksum is the only
  integrity check, and the stored checksum is never validated implicitly by
  `ogg_parse_pages` (call `ogg_page_crc_ok`).
- The whole buffer and every index live in memory; all sizes/offsets are
  Int (64-bit).
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
