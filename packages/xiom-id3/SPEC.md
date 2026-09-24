# xiom.id3 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.id3`, version `0.1.0`).
Module: `src/id3.xi` (`module xiom.id3`).
Depends on `xiom.std` (`xiom.string.builder`, `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) read-only inspector for a complete in-memory ID3v2
tag:

- `id3_has_tag` detects the `"ID3"` magic at offset 0;
- `id3_version` returns the major version byte;
- `id3_tag_size` decodes the syncsafe 28-bit header size and returns it
  plus the 10 header bytes;
- `id3_text_frames` walks the frames and collects text frames into
  `Id3Tags{ ids, texts }`;
- `id3_frame` / `id3_frame_count` query the collected frames;
- `id3_title` / `id3_artist` / `id3_album` are TIT2 / TPE1 / TALB
  convenience accessors.

## Non-goals

- ID3v1 (the trailing 128-byte block) and APE/Lyrics3 tags.
- Unsynchronisation (header or frame level), compression, encryption,
  grouping identity, data-length indicator and all other frame flags.
- The ID3v2.3/2.4 extended header and the v2.4 footer.
- Binary frames (APIC/PRIV/GEOB/...) and non-text structured frames.
- UTF-16 text (encodings 1 and 2), multi-string separators, null
  termination trimming beyond the stored size.
- Writing, rebuilding, transcoding or re-encoding any part of a tag.
- Streaming; the API works on an in-memory `Vec[UInt8]`.

## Tag header layout (10 bytes)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 3 | Magic | ASCII `"ID3"` (`49 44 33`). |
| 3 | 1 | Major version | 3 = ID3v2.3, 4 = ID3v2.4; returned as stored by `id3_version`. |
| 4 | 1 | Revision | Ignored (never validated). |
| 5 | 1 | Flags | Ignored. |
| 6 | 4 | Size | Syncsafe 28-bit size of everything after the header (excludes the 10 header bytes). |
| 10 | `size` | Frames / padding | Frame records followed by zero padding. |

Worked example -- a v2.3 tag holding one 13-byte TIT2 frame (id 4 + size 4
+ flags 2 + payload 3; payload = encoding 0 + `"Hi"`), total 23 bytes:

```
49 44 33 03 00 00 00 00 00 0d
54 49 54 32 00 00 00 03 00 00 00 48 69
```

`id3_tag_size` returns 23; the syncsafe size field is 13.

## Frame layout (v2.3/v2.4)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | Frame id | ASCII; a text frame starts with `'T'` (0x54). |
| 4 | 4 | Frame size | v2.3: plain big-endian u32. v2.4: syncsafe 28-bit. |
| 8 | 2 | Flags | Ignored; any value is accepted. |
| 10 | `size` | Payload | Text frame: 1 encoding byte + text bytes. |

The frame walk (`id3_text_frames`):

1. Start at offset 10, end at `tag_total = header_size + 10`.
2. While at least 10 bytes remain (`pos + 10 <= tag_total`):
   - if the 4 id bytes are all zero (padding), stop;
   - read the 4 size bytes with the version's layout;
   - a zero frame size stops the walk;
   - if `pos + 10 + frame_size > tag_total`,
     `Err("id3: frame size beyond tag")`;
   - if the id starts with `'T'`, record the id and the decoded text;
   - advance `pos += 10 + frame_size`.
3. Trailing bytes shorter than a frame header are ignored.

## Size encodings

| Field | Encoding | Value |
|---|---|---|
| Tag header size (bytes 6..9) | Syncsafe 28-bit: `b0*2^21 + b1*2^14 + b2*2^7 + b3` | Size of the tag after the 10-byte header. |
| v2.3 frame size (bytes 4..7) | Plain big-endian u32: `b0*2^24 + b1*2^16 + b2*2^8 + b3` | Payload byte count. |
| v2.4 frame size (bytes 4..7) | Syncsafe 28-bit (same formula as the header) | Payload byte count. |

The major version selects the frame layout: 4 -> syncsafe, anything else ->
plain big-endian (v2.3). `id3_tag_size` returns the header size **+ 10**;
a declared total larger than the buffer is
`Err("id3: tag size beyond buffer")`, while trailing bytes after the tag
are ignored (never an error).

The v2.4 syncsafe field is material in the 128..255 range: e.g. a 201-byte
payload is stored as `00 00 01 49` (syncsafe) but `00 00 00 C9` (plain
big-endian); a parser using the wrong layout misreads the size and fails
the bounds check.

## Text encoding table

The first payload byte of a text frame:

| Byte | Standard meaning | This module |
|---|---|---|
| 0 | ISO-8859-1 (latin1) | Decoded: payload bytes copied verbatim (byte-exact). |
| 1 | UTF-16 with BOM | Unsupported: frame id recorded, text `""`. |
| 2 | UTF-16BE without BOM | Unsupported: frame id recorded, text `""`. |
| 3 | UTF-8 | Decoded: payload bytes copied verbatim (byte-exact). |
| >= 4 | Reserved | Unsupported: frame id recorded, text `""`. |

"Copied verbatim" means no transcoding, no validation and no
null-termination handling: a latin1 `0xE9` stays `0xE9` and UTF-8 passes
through unchanged. The frame id is recorded for unsupported encodings so
`ids` and `texts` stay index-aligned and `id3_frame_count` reflects every
text frame seen.

## API signatures

All functions are free functions in module `xiom.id3`:

```xi
pub type Id3Tags = { ids: Vec[Str]; texts: Vec[Str]; }

pub fn id3_has_tag(data: &Vec[UInt8]) -> Bool
pub fn id3_version(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn id3_tag_size(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn id3_text_frames(data: &Vec[UInt8]) -> Result[Id3Tags, Str]
pub fn id3_frame(tags: &Id3Tags, id: Str) -> Option[Str]
pub fn id3_frame_count(tags: &Id3Tags) -> Int
pub fn id3_title(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn id3_artist(data: &Vec[UInt8]) -> Result[Str, Str]
pub fn id3_album(data: &Vec[UInt8]) -> Result[Str, Str]
```

## Semantics

`id3_has_tag(data)`
: True iff `len >= 3` and bytes 0..3 are `"ID3"`. Only the three magic
  bytes are checked, so a truncated 3-byte buffer still reports true.

`id3_version(data)`
: Validates the 10-byte minimum and the magic, then returns byte 3 as
  stored (3, 4, or e.g. 2/5 for other majors).

`id3_tag_size(data)`
: Validates the 10-byte minimum and the magic; decodes the syncsafe size
  from bytes 6..9 and returns `size + 10`. Err when the declared total
  exceeds the buffer length. Never validates the frame region.

`id3_text_frames(data)`
: Runs the `id3_tag_size` validation, then the frame walk of the
  "Frame layout" section. Returns `Ok(Id3Tags)` with `ids`/`texts`
  index-aligned; an empty tag yields two empty vectors. A text frame with
  an unsupported encoding contributes its id and `""`. Non-text frames
  contribute nothing.

`id3_frame(tags, id)`
: Walks `ids` from index 0 and returns `Some(texts[i])` for the first
  byte-exact `str_compare` match; `None` when no frame matches. `Some("")`
  is possible (empty text, or unsupported encoding).

`id3_frame_count(tags)`
: `ids.len()` (equal to `texts.len()` by construction).

`id3_title` / `id3_artist` / `id3_album`
: Run `id3_text_frames` (propagating structural errors) and return the
  first TIT2 / TPE1 / TALB text as `Ok(...)`, or `Ok("")` when the tag has
  no such frame. No frame id is hard-coded anywhere else.

## Error string catalog

| Condition | Error text | Reported by |
|---|---|---|
| Buffer shorter than 10 bytes | `id3: truncated header` | `id3_version`, `id3_tag_size`, `id3_text_frames`, `id3_title`/`artist`/`album` |
| Bytes 0..3 are not `"ID3"` | `id3: bad magic` | same as above |
| `header_size + 10 > len` | `id3: tag size beyond buffer` | `id3_tag_size` and `id3_text_frames` (propagated by the accessors) |
| `pos + 10 + frame_size > tag_total` | `id3: frame size beyond tag` | `id3_text_frames` (propagated by the accessors) |

The validation order is: truncation, magic, declared tag size, then the
frame walk (first failure wins). `id3_has_tag` never errors (it returns
`false`). All error strings start with `"id3: "`.

## Complexity

| Operation | Complexity |
|---|---|
| `id3_has_tag` | O(1) |
| `id3_version` / `id3_tag_size` | O(1) |
| `id3_text_frames` | O(tag_total) bytes walked + O(total text bytes) copied |
| `id3_frame` | O(frame count) comparisons (each O(id length)) |
| `id3_frame_count` | O(1) |
| `id3_title` / `id3_artist` / `id3_album` | O(tag_total), same as `id3_text_frames` |

## Test plan

`tests/test_conformance.xi` (`module id3_tests`, 21 named tests). Every
tag is built in-test by pushing bytes; there are no fixtures and no hex
imports. The hello-style `main` prints `[PASS]`/`[FAIL]` per test, a
summary line and returns the failure count. Coverage:

1. `has_tag`: magic at offset 0 only (empty, junk, 3-byte `"ID3"` true).
2. `version`: major returned for 3, 4 and 5.
3. `tag_size`: fixture total, a hand-pinned syncsafe header
   (`00 00 02 01` -> 267), trailing audio bytes ignored.
4. v2.3 tag: TIT2/TPE1/TALB collected in order, ids/texts aligned.
5. `frame`: first duplicate match wins; absent id is `None`.
6. `title`/`artist`/`album`: values present; absent frames are `Ok("")`.
7. Encoding 3 (UTF-8): non-ASCII `Café` preserved byte-for-byte.
8. Encoding 0 (latin1): `0xE9 0xFC` bytes preserved verbatim.
9. Encoding 1 (unsupported): id recorded, text `""`, count includes it.
10. Padding: zero frame id stops the walk; tag size still exact.
11. Zero frame size stops the walk (later frame ignored).
12. Empty tag: zero frames, size 10.
13. Junk (`len >= 10`, no magic): `false` / `Err("id3: bad magic")`.
14. Truncated header (0 / 3 / 9 bytes): `Err("id3: truncated header")`.
15. Declared tag size beyond the buffer is
    `Err("id3: tag size beyond buffer")`.
16. Frame size beyond the tag total is
    `Err("id3: frame size beyond tag")`.
17. v2.4 syncsafe frame size: 201-byte payload (size bytes differ from
    plain big-endian) plus a following frame parsed correctly.
18. Non-text frames (APIC, COMM) skipped; the walk continues to TIT2.
19. Nonzero frame flag bytes are ignored.
20. Trailing zero padding shorter than a frame header is ignored.
21. v2.4 tag: `title`/`artist`/`album` accessors.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.id3
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- ID3v2.3/v2.4 frame layouts only; the extended header and the v2.4
  footer are not skipped, so tags using them will misparse (usually
  `id3: frame size beyond tag`).
- No unsynchronisation reversal; an unsynchronised tag is read as stored.
- No ID3v1, APE or Lyrics3 support; only a tag at offset 0 is inspected.
- Text encodings 1 and 2 (UTF-16) are not decoded; multi-string
  separators are not split; no null-terminator trimming beyond the stored
  frame size.
- Binary frames are skipped entirely; no images, lyrics, comments or
  chapter support.
- Read-only and no transcoding: latin1 bytes are not converted to UTF-8.
- No thread safety; plain value types only.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_str`/`_err_str`/`_ok_tags`/`_err_tags`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All multi-byte size decoding is arithmetic (division/modulo), because
  `& 0xFF` on operands with bit 31 set miscompiles (same bug documented in
  `xiom.msgpack`, `xiom.wav` and `xiom.convert.base58`).
- Byte comparisons go through `data[pos] as Int` against small Int
  constants; UInt8 constants >= 128 are never used in comparisons.
- Frame ids and text payloads are materialized with
  `xiom.string.builder.sb_to_str` (one allocation, raw byte copy).
- Str equality goes through `xiom.string.compare.str_compare` with typed
  locals (BUG 17: `==` on Str values read from a `Vec[Str]` lowers to a
  pointer comparison).
- The module declares no `extern "C"` blocks (no FFI) and uses free
  functions only: no methods, no lambdas, no `Vec[StructType]`.
