# xiom.git2 -- specification

Byte-level layouts actually implemented, the DEFLATE subset, error catalog
and limits. Everything below is enforced by `src/git2.xi` and exercised by
`tests/test_conformance.xi`.

## 1. zlib stream (RFC 1950)

```
offset  size  field
0       1     CMF:  CM = CMF % 16 (must be 8 = deflate)
                   CINFO = CMF / 16 (window; must be <= 7)
1       1     FLG:  FCHECK = (CMF*256 + FLG) % 31 (must be 0)
                   FDICT  = (FLG / 32) % 2 (must be 0; preset dictionary rejected)
                   FLEVEL = FLG / 64 (recorded only)
2..n-5  ...   DEFLATE stream (RFC 1951)
n-4..  4      ADLER-32, big-endian, over the uncompressed bytes (verified)
```

`git2_zlib_decode` / `git2_zlib_decode_into` require the buffer to be
exactly one stream (no trailing bytes). `_zlib_inflate_at` (used by the pack
walk) allows bytes after the trailer and returns the offset just past it.

## 2. DEFLATE (RFC 1951) subset

Bit order: values (BFINAL, BTYPE, extra bits, stored LEN/NLEN) are read
LSB-first; Huffman codes are read MSB-first (bit-reversed canonical codes).
All bit arithmetic uses multiplication/division, never shifts.

Block loop: `BFINAL` (1 bit) + `BTYPE` (2 bits) until the final block.

| BTYPE | Layout | Status |
|-------|--------|--------|
| 00 stored | align to byte boundary; LEN u16 LE; NLEN u16 LE (LEN + NLEN == 65535); LEN raw bytes | full |
| 01 fixed | RFC fixed literal/length table (288 codes: 0-143 len 8, 144-255 len 9, 256-279 len 7, 280-287 len 8) and fixed distance table (30 codes, len 5) | full |
| 10 dynamic | HLIT+257 literal codes, HDIST+1 distance codes, HCLEN+4 code-length codes in the transmitted order 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15; repeats 16 (3-6, needs a previous length), 17 (3-10 zeros), 18 (11-138 zeros); symbol 256 must have a non-zero length | full |
| 11 | -- | rejected: `invalid deflate block type` |

Literal/length symbol ranges: 0-255 literals; 257-285 lengths with bases
3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,
195,227,258 and extra bits 0x8,1x4,2x4,3x4,4x4,5x4,0; 256 ends the block;
286/287 rejected. Distance symbols 0-29 with bases
1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,
3073,4097,6145,8193,12289,16385,24577 and extra bits 0x4 then 1..13 in pairs.
Copies are byte-by-byte and may overlap (distance < length); a distance of 0
or a distance larger than the output produced so far is rejected.

End offset: after the final block the returned offset is the first byte after
the last byte carrying stream bits (remaining padding bits in that byte are
ignored, as RFC 1951 requires).

Narrowing / limits: dynamic blocks reject HLIT > 286 and HDIST > 30 (RFC
forbids 286/287 and 30/31 anyway); stored LEN is naturally <= 65535; no
window-size enforcement beyond the zlib CINFO <= 7 check.

## 3. Loose objects

```
"<type> <size>\0<payload>"
```

Canonical types and codes: blob = 3, tree = 2, commit = 1, tag = 4 (pack
numbering). The size is decimal ASCII, non-empty, no sign, and leading zeros
are rejected except for the single digit `0`; it must equal the payload
length exactly. `header_size` counts the bytes up to and including the NUL.

## 4. Tree entries

```
<mode ASCII-octal> SP <name> NUL <raw-id: 20 or 32 bytes>
```

- mode: 1..6 octal digits, first digit non-zero; named values
  `40000` (tree), `100644`, `100755`, `120000`, `160000`.
- name: non-empty, NUL-terminated, no `/` and no NUL inside.
- ordering: strictly increasing under the Git tree sort order. Directory
  entries (mode `40000` only) compare as if a trailing `/` were appended, so
  `sub.txt` (`.` = 0x2E) sorts before the tree `sub` (`.` < `/` = 0x2F).
  Duplicate names and out-of-order entries are rejected with offsets.
- id size 20 (SHA-1) or 32 (SHA-256) is supplied by the caller; ids are kept
  raw (flattened in `GitTree.entry_id`).

## 5. Commit and tag headers

Lines are LF-separated; a line starting with a space is a folded
continuation of the previous value (joined with LF, the leading space
stripped). NUL bytes inside header lines are rejected. The first empty line
ends the header; if there is none, `header_end` is the payload length and the
message is empty. Header keys must be non-empty printable ASCII without
spaces; values may be empty.

Commit: `tree` must be first and exactly once (40-hex SHA-1 or 64-hex
SHA-256; the id size is inferred), `parent` 0+ (same length as tree),
`author` and `committer` required exactly once, `encoding` and `gpgsig`
optional exactly once, other keys collected in `other_keys`.

Tag: `object` first and unique (hex id), `type` unique
(blob/tree/commit/tag), `tag` unique and non-empty, `tagger`/`gpgsig`
optional unique, other keys collected.

## 6. Deltas

```
source-size varint | target-size varint | opcode stream
```

Size varints: base-128 little-endian (7-bit groups, low group first, max 8
continuation groups). Copy opcode (bit 7 set): bit 0 selects offset byte 1,
bit 1 -> byte 2, bit 2 -> byte 3, bit 3 -> byte 4 (little-endian order);
bit 4 selects size byte 1, bit 5 -> byte 2, bit 6 -> byte 3; a copy size of 0
means 65536. Insert opcode 1..127: that many literal bytes follow. Opcode 0
is reserved and rejected. The source size must equal `base.len()`, copies
must lie inside the base, and the output must reach exactly the target size.

## 7. Pack files

```
"PACK" | version u32 BE (2 or 3) | object-count u32 BE | entries | 20-byte trailer
```

Entry header: byte 0 has bits 0-3 = size low group, bits 4-6 = type
(1 commit, 2 tree, 3 blob, 4 tag, 6 OFS_DELTA, 7 REF_DELTA; 0/5 rejected),
bit 7 = continuation. Each continuation byte contributes a 7-bit group in
big-endian order (`size += (byte % 128) * mult; mult *= 128`), at most 8
groups.

- OFS_DELTA: Git negative-offset varint with the +1 rule:
  `value = byte0 % 128; while cont { value = (value + 1) * 128 + (byte % 128) }`.
  Distance 0 and bases before offset 12 are rejected; `base_offset` is the
  absolute offset of the base header.
- REF_DELTA: raw `id_size`-byte base id (20 or 32), preserved for the caller.

Each entry's zlib stream is inflated (Adler verified); the decompressed size
must equal the declared size and `entry_end` includes the 4-byte trailer. The
walk requires exactly `object_count` entries ending at the trailer and
preserves the 20-byte trailer checksum raw. `git2_pack_resolve` follows
OFS_DELTA chains (depth <= 64); REF_DELTA resolution is caller-side.

## 8. Pack index v2

```
0      magic 0xFF744F63 (BE u32; 4285812579)
4      version = 2 (BE u32)
8      256 x u32 BE fanout, cumulative and monotonic; fanout[255] == count
1032   count x id_size raw ids, strictly increasing
       count x u32 BE CRC-32
       count x u32 BE offsets; an offset >= 2^31 selects slot (value - 2^31)
         of the 64-bit table
       large-count x u64 BE offsets (large-count = highest referenced slot + 1;
         every slot must be referenced exactly once; bit 63 is rejected)
       20-byte pack checksum (raw, not verified)
       20-byte idx checksum (raw, not verified)
```

The file must end exactly after the idx checksum. Lookup is a binary search
bounded by `fanout[first_byte]`. CRCs use the table-less reflected CRC-32
(init 0xFFFFFFFF, poly 0xEDB88320, final XOR 0xFFFFFFFF; check value
`0xCBF43926` for `"123456789"`) computed over the raw entry span
`[entry_offset, entry_end)`.

## 9. Error catalog (all messages are `"git2: <what> at <byte offset>"`)

zlib: `truncated zlib header`, `unsupported zlib method`, `invalid zlib
window size`, `bad zlib fcheck`, `zlib preset dictionary unsupported`,
`truncated zlib trailer`, `adler mismatch`, `trailing bytes after zlib
stream`.

DEFLATE: `truncated deflate block header`, `invalid deflate block type`,
`truncated stored block`, `stored block length check failed`, `truncated
huffman block`, `invalid literal/length code`, `invalid length symbol`,
`invalid distance code`, `truncated length extra bits`, `truncated distance
extra bits`, `distance too far back`, `truncated dynamic header`, `too many
literal/length codes`, `too many distance codes`, `invalid code length`,
`truncated dynamic lengths`, `invalid code length symbol`, `repeat with no
previous length`, `code length repeat overflow`, `missing end-of-block code`.

Loose: `empty loose header`, `loose header missing NUL`, `loose header
missing type separator`, `loose header missing type`, `unknown loose object
type`, `loose header missing size`, `loose size is not decimal`, `loose size
has leading zero`, `loose size overflow`, `loose size mismatch`.

Trees: `bad id size`, `tree mode has leading zero`, `invalid tree mode`,
`tree mode too long`, `truncated tree entry`, `missing tree mode separator`,
`tree name contains slash`, `unterminated tree name`, `empty tree name`,
`truncated tree id`, `duplicate tree entry`, `tree entries out of order`.

Headers: `NUL byte in header line`, `continuation without header`, `header
line without value`, `header line without key`, `invalid header key byte`,
empty-header errors, `commit tree must be first`, `invalid tree id`, `invalid
tree id length`, `duplicate tree header`, `commit parent before tree`,
`invalid parent id`, `parent id length mismatch`, duplicate author/committer/
encoding/gpgsig, `commit missing tree`/`author`/`committer`, `NUL byte in
commit message`, tag equivalents including `tag object must be first`,
`unknown tag object type`, `empty tag name`, `tag missing object`/`type`/
`tag name`, `NUL byte in tag message`.

Deltas: `truncated delta size`, `oversized delta size`, `delta source size
mismatch`, `delta target size mismatch`, `reserved delta opcode`, `truncated
delta copy`, `delta copy out of range`, `truncated delta insert`, `delta
output exceeds target size`.

Packs: `truncated pack header`, `bad pack magic`, `unsupported pack
version`, `truncated pack`, `pack object count exceeds file size`, `truncated
pack entry`, `truncated pack entry header`, `oversized pack entry size`,
`invalid pack entry type`, `truncated ofs delta`, `oversized ofs delta
offset`, `invalid ofs delta distance`, `ofs delta base out of range`,
`truncated ref delta id`, `entry overruns pack trailer`, `pack entry size
mismatch`, `pack length does not match object count`, `delta chain too deep`,
`ofs delta base not found`, `ref delta needs external base`, `unknown entry
type`.

Index: `truncated idx`, `bad idx magic`, `unsupported idx version`,
`truncated idx fanout`, `idx fanout not monotonic`, `truncated idx tables`,
`idx ids not sorted`, `idx fanout mismatch`, `idx large offset index out of
range`, `idx duplicate large offset index`, `truncated idx large offsets`,
`idx unused large offset slot`, `idx large offset out of range`, `trailing
bytes in idx`, `index out of range` for accessors.

## 10. Explicit limits

- Int arithmetic is signed 64-bit: 64-bit pack offsets with bit 63 set are
  rejected; pack sizes above 2^60 - 1 (more than 8 size continuation groups),
  delta sizes above 2^56 - 1 (more than 8 groups) and ofs distances above
  2^60 - 1 are rejected as oversized.
- Messages and header values are materialized as `Str`; a NUL byte in a
  header line or a commit/tag message is rejected (rule 15 discipline).
- The pack walk inflates every entry, so peak memory is O(pack +
  decompressed size); the caller controls persistence.
