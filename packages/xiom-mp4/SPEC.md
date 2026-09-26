# xiom.mp4 -- implementation specification

This document describes exactly what `src/mp4.xi` implements: the byte
layout it reads, the validation it performs, the error strings it emits and
what it deliberately does not do. It matches the shipped code; where the
code and this document disagree, the code is the bug.

## 1. Scope and non-goals

In scope (ISO/IEC 14496-12 "ISO Base Media File Format"):

- the box (atom) framing model, including 64-bit sizes, `size == 0` boxes
  and `uuid` user types;
- a recursive tree walk over the container set `moov`, `trak`, `mdia`,
  `minf`, `stbl`, `dinf`, `edts`;
- decoding of `ftyp`, `mvhd`, `tkhd`, `mdhd`, `hdlr`, `stsd`, `elst`,
  `stco`, `co64` and `stsz`;
- top-level layout detection (ftyp-first, fragmented `moof`, moov-at-end).

Out of scope:

- any media decoding (no H.264/H.265/AAC bitstream parsing);
- `mdat` payload inspection (media bytes are an opaque span);
- expansion of sample tables (no per-sample or per-chunk lists), and no
  composition-time / decoding-time math;
- fragmented-structure decoding (`mvex`, `traf`, `tfhd`, `trun`, `sidx`
  are not parsed; only top-level `moof` presence is counted);
- `stsc`/`stts`/`ctts`/`stss` and other tables;
- QuickTime-only layouts beyond the seven container types above;
- writing, muxing or editing.

The parser is **strict**: anything that cannot be walked or decoded
according to this document returns `Err(Str)`. It never silently skips a
malformed region. The messages are stable and listed in section 7.

## 2. Buffer model

The input is a single `Vec[UInt8]` holding a whole file. All multi-byte
fields are **big-endian** (ISO BMFF default; the `isom` brand files this
parser targets are big-endian throughout).

### 2.1 Box header

Every box starts with:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `size` (u32 big-endian) |
| 4 | 4 | `type` (four printable ASCII characters, 0x20..0x7E) |

Then, depending on `size`:

| Condition | Meaning | Header size | End of box |
|---|---|---|---|
| `size >= 8` | normal box | 8 | `start + size` |
| `size == 1` | 64-bit `largesize` follows the type at offset 8 (u64 big-endian) | 16 | `start + largesize` |
| `size == 0` | box extends to the end of the enclosing context | 8 | parent end (file end at top level) |
| `type == "uuid"` | 16 user-type bytes follow the header | +16 | as above, after the extra bytes |

Rules enforced:

- `size` in `2..7` is rejected (`mp4: box size below 8`); `size` 0 and 1
  have the special meanings above.
- `largesize < 16` is rejected (`mp4: box size below header`); a `uuid`
  box whose total size is below its (8+16 or 16+16) header size is
  rejected with the same message.
- The box must fit inside the **file** (`mp4: box extends beyond buffer`)
  and inside its **parent container** (`mp4: box overruns parent
  container`), checked in that order.
- `largesize` values with the u64 sign bit set do not fit a signed XIOM
  `Int` and are rejected (`mp4: 64-bit value out of range`). The same
  check applies to the 64-bit `mvhd`/`tkhd`/`mdhd` fields decoded below.
- The four type bytes must all be printable ASCII; otherwise
  `mp4: non-printable box type`.
- A leading fragment (`1..7` bytes) that cannot hold a header is
  `mp4: truncated box header`; a buffer shorter than 8 bytes is
  `mp4: buffer too small for box header`.
- A `size == 1` box with fewer than 16 bytes before the parent end is
  `mp4: truncated largesize`; a `uuid` box with fewer than 16 user-type
  bytes available is `mp4: truncated uuid user type`.

### 2.2 uuid user type

The 16 user-type bytes are rendered as **32 lowercase hex digits** (two
per byte, `0..9a..f`). They are never turned into a `Str` directly: an
embedded `0x00` would truncate the string. `mp4_box_uuid` returns `Err
("mp4: box is not uuid")` for non-uuid boxes.

## 3. Tree walk

`mp4_parse` starts `_walk(start = 0, end = file length, depth = 0,
parent = -1)` and processes boxes in file order until `pos == end`.

For every box the walker appends to eight parallel pools:

| Pool | Meaning |
|---|---|
| `box_types` | fourcc |
| `box_offsets` | absolute start offset |
| `box_sizes` | total size (header + payload) |
| `box_header_sizes` | 8, 16 (largesize) or +16 (uuid) |
| `box_depths` | 0 at top level |
| `box_parents` | index of enclosing box, `-1` at top level |
| `box_uuids` | 32 hex digits or `""` |
| `box_is_container` | 1 when children were walked, else 0 |

A box is a container iff its type is one of
`moov, trak, mdia, minf, stbl, dinf, edts`. A container is descended into
only when it has a non-empty payload (`start + header < end`); the child
walk runs in `[start + header, end)` at `depth + 1` with the parent index
just recorded.

Depth limit: `depth > 32` is rejected (`mp4: nesting depth exceeds
limit`). Because the check happens on entry to each walk level, a
hierarchy may contain at most 33 nested container levels (depths 0..32)
and the innermost container is not entered when it has no payload.

Metadata decoding happens for every box whose type matches, at any depth
(a `mvhd` inside a `trak` would be decoded too, though that never occurs in
valid files). The decoded pools are documented in section 5.

Top-level semantics (`depth == 0`):

- `moov`, `moof`, `mdat` occurrences are counted; the first offset of
  `moov`, `mdat` and `ftyp` is recorded (`-1` when absent);
- `mp4_has_ftyp` is true iff the first `ftyp` offset is 0;
- `mp4_is_fragmented` is true iff at least one top-level `moof` exists;
- `mp4_has_mdat` is true iff at least one top-level `mdat` exists;
- `mp4_is_moov_at_end` is true iff both a `moov` and an `mdat` exist and
  the first `moov` offset is greater than the first `mdat` offset.

## 4. Metadata layouts

Offsets below are **payload-relative** (payload = box start + header). A
"full box" payload begins with a 4-byte version/flags word; `version` is
its most significant byte (`word / 16777216`).

### 4.1 ftyp -- File Type Box

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | major brand (fourcc) |
| 4 | 4 | minor version (u32) |
| 8 | 4*n | compatible brands (fourccs) |

Validation: payload >= 8 (`mp4: ftyp too short`); `(payload - 8) % 4 == 0`
(`mp4: ftyp compatible brands malformed`); every brand printable
(`mp4: ftyp brand not printable`). The brand list is stored in the flat
`brands` pool; ftyp entry `i` owns `[ftyp_brand_offsets[i],
ftyp_brand_offsets[i] + ftyp_brand_counts[i])`.

### 4.2 mvhd -- Movie Header Box

Full box, version 0 or 1 (other versions: `mp4: mvhd unsupported
version`).

| Field | v0 offset | v1 offset |
|---|---|---|
| version/flags | 0 | 0 |
| creation_time | 4 (u32) | 4 (u64) |
| modification_time | 8 (u32) | 12 (u64) |
| **timescale** (u32) | **12** | **20** |
| **duration** | **16** (u32) | **24** (u64) |
| rate, volume, matrix, ... | 20..100 | 32..112 |

Minimum payload: 20 bytes (v0) / 32 bytes (v1), else `mp4: mvhd too
short`.

### 4.3 tkhd -- Track Header Box

Full box, version 0 or 1 (otherwise `mp4: tkhd unsupported version`).

| Field | v0 offset | v1 offset |
|---|---|---|
| version/flags | 0 | 0 |
| creation_time | 4 (u32) | 4 (u64) |
| modification_time | 8 (u32) | 12 (u64) |
| **track_ID** (u32) | **12** | **20** |
| reserved (u32) | 16 | 24 |
| **duration** | **20** (u32) | **28** (u64) |
| reserved[2] | 24..32 | 36..44 |
| layer/alt/volume/reserved | 32..40 | 44..52 |
| matrix | 40..76 | 52..88 |
| **width** (16.16) | **76** | **88** |
| **height** (16.16) | **80** | **92** |

Minimum payload: 84 bytes (v0) / 96 bytes (v1), else `mp4: tkhd too
short`. Width and height are unsigned 16.16 fixed-point values exposed as
whole pixels rounded to the nearest integer, halves up:
`(raw + 32768) / 65536` with integer division (raw is non-negative).

### 4.4 mdhd -- Media Header Box

Full box, version 0 or 1 (otherwise `mp4: mdhd unsupported version`).

| Field | v0 offset | v1 offset |
|---|---|---|
| version/flags | 0 | 0 |
| creation_time | 4 (u32) | 4 (u64) |
| modification_time | 8 (u32) | 12 (u64) |
| **timescale** (u32) | **12** | **20** |
| **duration** | **16** (u32) | **24** (u64) |
| **language** (u16) | **20** | **32** |
| pre_defined | 22 | 34 |

Minimum payload: 24 bytes (v0) / 36 bytes (v1), else `mp4: mdhd too
short`.

Language decoding: the 15 low bits hold three 5-bit values
`c1=(v/1024)%32`, `c2=(v/32)%32`, `c3=v%32`; each must be in `1..26`
(1 = 'a') or the box is rejected (`mp4: mdhd bad language`). The result is
the three lowercase letters, e.g. `5,14,7 -> "eng"`.

### 4.5 hdlr -- Handler Reference Box

Full box; the handler type fourcc sits at payload offset 8 (after
version/flags and `pre_defined`). Minimum payload 24 bytes
(`pre_defined`, handler, 3 reserved u32), else `mp4: hdlr too short`; a
non-printable handler is `mp4: hdlr handler not printable`.

### 4.6 stsd -- Sample Description Box

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | version/flags |
| 4 | 4 | entry_count (u32) |
| 8 | ... | `entry_count` sample-entry boxes |

Minimum payload 8 bytes (`mp4: stsd too short`). Each entry is itself a
box: u32 size + fourcc + payload. For entry `k`:

- the entry size must be >= 8 (`mp4: stsd entry size below 8`), must not
  run past the stsd box (`mp4: stsd entry overruns stsd box`), and the
  entry fourcc must be printable (`mp4: stsd entry type not printable`);
- a declared `entry_count` larger than the bytes present stops at the
  first missing 8-byte entry header (`mp4: stsd entry truncated`);
- after `entry_count` entries the cursor must equal the stsd box end,
  otherwise `mp4: stsd trailing bytes`;
- **visual entries** (`avc1`, `avc3`, `hvc1`, `hev1`, `mp4v`, `vp08`,
  `vp09`, `av01`, `encv`) must be at least 86 bytes; `width` is the u16 at
  entry offset 32 and `height` the u16 at offset 34 (`mp4: visual sample
  entry too short` otherwise);
- all other entries (e.g. `mp4a`) contribute their fourcc with width and
  height recorded as `-1`.

Entry pools are `entry_fourccs`, `entry_offsets`, `entry_widths`,
`entry_heights` and `entry_stsd` (owning stsd ordinal);
`stsd_entry_counts` stores the declared count per stsd box.

Visual sample entry layout (payload-relative, confirmed against the fixed
part of `VisualSampleEntry`):

| Offset | Size | Field |
|---|---|---|
| 8 | 6 | reserved |
| 14 | 2 | data_reference_index |
| 16 | 2 | pre_defined |
| 18 | 2 | reserved |
| 20 | 12 | pre_defined[3] |
| 32 | 2 | **width** |
| 34 | 2 | **height** |
| 36 | 4 | horizresolution |
| 40 | 4 | vertresolution |
| 44 | 4 | reserved |
| 48 | 2 | frame_count |
| 50 | 32 | compressorname |
| 82 | 2 | depth |
| 84 | 2 | pre_defined |
| 86 | ... | child boxes (not walked) |

### 4.7 elst -- Edit List Box

Full box, version 0 or 1 (otherwise `mp4: elst unsupported version`).

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | version/flags |
| 4 | 4 | entry_count (u32) |
| 8 | 12*n (v0) / 20*n (v1) | entries (opaque) |

Validation: payload >= 8 (`mp4: elst too short`); `8 + count * entry_size
<= payload` (`mp4: elst entries exceed box`). Only the count is exposed.

### 4.8 stco / co64 -- Chunk Offset Boxes

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | version/flags |
| 4 | 4 | entry_count (u32) |
| 8 | 4*n (stco) / 8*n (co64) | chunk offsets (opaque) |

Validation: payload >= 8 (`mp4: stco too short` / `mp4: co64 too short`);
`8 + count * width <= payload` (`mp4: stco entries exceed box` /
`mp4: co64 entries exceed box`). Pools: `chunk_offsets`, `chunk_kinds`
(0 = stco, 1 = co64), `chunk_entry_counts`.

### 4.9 stsz -- Sample Size Box

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | version/flags |
| 4 | 4 | sample_size (uniform; 0 = per-sample table) |
| 8 | 4 | sample_count (u32) |
| 12 | 4*n | per-sample sizes, only when sample_size == 0 |

Validation: payload >= 12 (`mp4: stsz too short`); when `sample_size == 0`
also `12 + count * 4 <= payload` (`mp4: stsz entries exceed box`). Pools:
`stsz_offsets`, `stsz_uniform_sizes`, `stsz_sample_counts`.

## 5. Public type summary

`Mp4File` keeps every pool described above as separate `Vec` fields (no
`Vec[StructType]` anywhere; see the module header for the pinned-compiler
constraints). Values are read through the `mp4_*` accessors, which
validate indices:

- `Int` accessors return `-1` out of range;
- `Result` accessors return `Err` with one of
  `mp4: box index out of range`, `mp4: ftyp index out of range`,
  `mp4: brand index out of range`, `mp4: mdhd index out of range`,
  `mp4: hdlr index out of range`,
  `mp4: sample entry index out of range`, or `mp4: box is not uuid`.

`mp4_tree_text` renders one line per box: two spaces per depth level, the
fourcc, optional ` uuid=<32 hex>`, then ` size=<n> off=<n>`, each line
terminated by `"\n"`. An empty file yields `""`.

## 6. Validation order

Within one box, checks run in this order:

1. remaining bytes >= 8 (`truncated box header`);
2. `size`/`type` read, fourcc printable (`non-printable box type`);
3. header computation and its internal checks (`truncated largesize`,
   `box size below header`, `box size below 8`);
4. uuid user type availability (`truncated uuid user type`);
5. box end vs file (`box extends beyond buffer`);
6. box end vs parent (`box overruns parent container`);
7. pool append;
8. payload decode of the matching metadata box (section 4);
9. top-level counters;
10. child walk for containers (depth check on entry).

Reader helpers (`_rd_be16/32/64`) bound-check independently and return
`mp4: truncated field`; on a well-formed box this cannot surface, because
payload checks in section 4 run first.

## 7. Error catalog

| Message | Condition |
|---|---|
| `mp4: buffer too small for box header` | buffer length < 8 |
| `mp4: truncated box header` | 1..7 bytes left at a box boundary |
| `mp4: non-printable box type` | any of the four type bytes outside 0x20..0x7E |
| `mp4: truncated largesize` | `size == 1` with fewer than 16 bytes before the parent end |
| `mp4: truncated uuid user type` | uuid box with fewer than 16 bytes for the user type |
| `mp4: box size below 8` | 32-bit size in 2..7 |
| `mp4: box size below header` | largesize < 16, or uuid size below 24/32 |
| `mp4: 64-bit value out of range` | any decoded u64 with the sign bit set |
| `mp4: box extends beyond buffer` | box end > file length |
| `mp4: box overruns parent container` | box end > parent end (within file) |
| `mp4: nesting depth exceeds limit` | walk level deeper than 32 |
| `mp4: truncated field` | internal reader bounds failure (defensive) |
| `mp4: ftyp too short` | ftyp payload < 8 |
| `mp4: ftyp compatible brands malformed` | `(payload-8) % 4 != 0` |
| `mp4: ftyp brand not printable` | major or compatible brand not printable |
| `mp4: mvhd too short` | payload below 20 (v0) / 32 (v1) |
| `mp4: mvhd unsupported version` | version not 0 or 1 |
| `mp4: tkhd too short` | payload below 84 (v0) / 96 (v1) |
| `mp4: tkhd unsupported version` | version not 0 or 1 |
| `mp4: mdhd too short` | payload below 24 (v0) / 36 (v1) |
| `mp4: mdhd unsupported version` | version not 0 or 1 |
| `mp4: mdhd bad language` | any packed letter outside 1..26 |
| `mp4: hdlr too short` | payload < 24 |
| `mp4: hdlr handler not printable` | handler fourcc not printable |
| `mp4: stsd too short` | payload < 8 |
| `mp4: stsd entry truncated` | fewer than 8 bytes for a declared entry header |
| `mp4: stsd entry size below 8` | entry size < 8 |
| `mp4: stsd entry overruns stsd box` | entry end > stsd payload end |
| `mp4: stsd entry type not printable` | entry fourcc not printable |
| `mp4: visual sample entry too short` | visual entry < 86 bytes |
| `mp4: stsd trailing bytes` | entries do not exactly fill the stsd payload |
| `mp4: elst too short` | payload < 8 |
| `mp4: elst unsupported version` | version not 0 or 1 |
| `mp4: elst entries exceed box` | `8 + count * entry_size > payload` |
| `mp4: stco too short` / `mp4: stco entries exceed box` | stco payload/entry overflow |
| `mp4: co64 too short` / `mp4: co64 entries exceed box` | co64 payload/entry overflow |
| `mp4: stsz too short` / `mp4: stsz entries exceed box` | stsz payload overflow |
| `mp4: box index out of range` / `mp4: ftyp index out of range` / `mp4: brand index out of range` / `mp4: mdhd index out of range` / `mp4: hdlr index out of range` / `mp4: sample entry index out of range` | accessor index out of range |
| `mp4: box is not uuid` | `mp4_box_uuid` on a non-uuid box |

## 8. Test plan

`tests/test_conformance.xi` runs 33 checks on synthetic buffers built in
the test file (no external data):

| # | Check |
|---|---|
| 1 | full movie parses; ftyp first; box count; moov/mdat counts |
| 2 | ftyp major `isom`, minor 512, four compatible brands in order |
| 3 | mvhd v0 timescale 1000 / duration 5000 |
| 4 | mvhd v1 (64-bit) timescale 90000 / duration 300000000 |
| 5 | tkhd v0 track id 1 / duration 5000 / 640.5 -> 641 / height 360 |
| 6 | mdhd v0 timescale 48000 / duration 240000 / language `eng` |
| 7 | hdlr handlers `vide`, `soun`, `text` in order |
| 8 | stsd declared count 2; `avc1` + `mp4a`; visual 640x360; owner index |
| 9 | elst version 0 with two entries |
| 10 | stco kind 0 count 3 and co64 kind 1 count 2 |
| 11 | stsz sample count 3, uniform size 0 |
| 12 | 64-bit `mdat`: header 16, size 26, file length 46 |
| 13 | `size == 0` `mdat`: offset 20, size 24 to EOF |
| 14 | uuid header 24, user type `0001..0f`; non-uuid rejected |
| 15 | walk: stbl depth 4, parent minf, minf parent mdia; tree text indent |
| 16 | `free`/`skip`/`wide` accepted |
| 17 | fragmented: two `moof`, two `mdat`, `is_fragmented` true |
| 18 | moov-at-end detected; not flagged when moov precedes mdat |
| 19-33 | error cases: short buffer, truncated header, size < 8, size past buffer, parent overrun, depth 40, truncated largesize, largesize < header, truncated uuid, ftyp too short, mvhd too short, bad mdhd language, stco overflow, stsd entry overrun, non-printable type |

All fixtures mirror the layouts in section 4 with their sizes recomputed by
patching the box size fields, so a layout regression changes the parsed
values and fails the suite rather than being masked.

## 9. Known limitations

- Nested-box recursion is bounded at 32 levels; deeper (invalid) trees are
  rejected rather than truncated.
- `mdat` is not scanned, so `moof`-based files whose fragments are nested
  inside unknown containers are not detected as fragmented.
- The parser is strict about trailing bytes at top level, which some
  writers append; such files are rejected with `mp4: truncated box
  header`.
- Only the seven container box types are recursed; e.g. `meta`, `ilst`,
  `udta` children are not walked.
- `stco`/`co64`/`stsz`/`elst` values beyond counts (offsets, sizes,
  segment times) are validated for framing but not exposed.
