# xiom.woff

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM structural codec for the WOFF 1.0 font container:
> the 44-byte header, the 20-byte table directory entries, metadata/private
> block spans and a canonical uncompressed builder.
> **Deps:** `xiom.std` only (`xiom.string`; the tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.woff` validates and indexes a WOFF 1.0 container without touching the
font payload: `woff_parse` checks the signature, the exact-length policy,
the reserved field, every directory entry (tag bytes, `compLength <=
origLength`, 4-byte alignment, in-bounds spans), the `totalSfntSize`
arithmetic and the metadata/private block spans, then returns a flat `Woff`
index. The accessors, `woff_find_tag` / `woff_find_tag_str`, the span
copiers and `woff_build` (canonical uncompressed layout) read and write
that index.

Deliberately, no zlib is involved: a table with `compLength < origLength`
is flagged by `woff_table_is_compressed` and its bytes are copied raw.
Metadata and private bytes are likewise opaque.

## API

| Function | Returns | Description |
|---|---|---|
| `woff_parse(data)` | `Result[Woff, Str]` | Validate and index a complete container. |
| `woff_max_tables()` | `Int` | Documented `numTables` cap (4096). |
| `woff_flavor(w)` | `Int` | sfnt version of the wrapped font. |
| `woff_length(w)` | `Int` | Declared file size (equals the parsed buffer). |
| `woff_num_tables(w)` | `Int` | Directory entry count. |
| `woff_total_sfnt_size(w)` | `Int` | `12 + 16*numTables + padded origLengths`. |
| `woff_major_version(w)` / `woff_minor_version(w)` | `Int` | WOFF version fields. |
| `woff_table_tag(w, i)` | `Int` | 4-byte tag as a big-endian `Int`; `-1` out of range. |
| `woff_table_offset(w, i)` | `Int` | Data offset; `-1` out of range. |
| `woff_table_comp_length(w, i)` | `Int` | Stored length; `-1` out of range. |
| `woff_table_orig_length(w, i)` | `Int` | Uncompressed length; `-1` out of range. |
| `woff_table_checksum(w, i)` | `Int` | sfnt checksum (never verified); `-1` out of range. |
| `woff_table_is_compressed(w, i)` | `Bool` | `compLength < origLength`; `false` out of range. |
| `woff_find_tag(w, tag)` | `Int` | First entry with the 32-bit tag, else `-1`. |
| `woff_find_tag_str(w, tag)` | `Int` | Same for a 4-character tag string. |
| `woff_tag_of(s)` | `Int` | 4 printable-ASCII bytes to tag `Int`; `-1` otherwise. |
| `woff_has_metadata(w)` / `woff_has_private(w)` | `Bool` | Block presence. |
| `woff_meta_offset(w)` / `woff_meta_length(w)` / `woff_meta_orig_length(w)` | `Int` | Metadata span. |
| `woff_priv_offset(w)` / `woff_priv_length(w)` | `Int` | Private span. |
| `woff_table_data(data, w, i)` | `Result[Vec[UInt8], Str]` | Raw stored bytes (zlib kept raw). |
| `woff_meta_copy(data, w)` | `Result[Vec[UInt8], Str]` | Raw compressed metadata. |
| `woff_priv_copy(data, w)` | `Result[Vec[UInt8], Str]` | Raw private bytes. |
| `woff_build(flavor, tags, datas, checksums)` | `Result[Vec[UInt8], Str]` | Canonical uncompressed container. |

## Container layout

Header, 44 bytes, all big-endian:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | signature `wOFF` (0x774F4646) |
| 4 | 4 | flavor (sfnt version) |
| 8 | 4 | length (total file size) |
| 12 | 2 | numTables |
| 14 | 2 | reserved (must be 0) |
| 16 | 4 | totalSfntSize |
| 20 | 2 | majorVersion |
| 22 | 2 | minorVersion |
| 24 | 4 | metaOffset |
| 28 | 4 | metaLength |
| 32 | 4 | metaOrigLength |
| 36 | 4 | privOffset |
| 40 | 4 | privLength |

Each directory entry is 20 bytes: tag (4), offset (4), compLength (4),
origLength (4), origChecksum (4). Table data starts after the directory and
each table is zero-padded to a 4-byte boundary.

## Pinned policies

- **Exact length.** The header `length` must equal `data.len()`; both a
  truncated buffer and trailing bytes are `woff: length mismatch`.
- **`compLength <= origLength`.** Equal means stored uncompressed; less
  means the bytes are zlib data kept raw (`woff_table_is_compressed`).
  A zero `compLength` requires a zero `origLength` (an empty table).
- **`totalSfntSize`** must equal `12 + 16*numTables + sum(align4(origLength))`.
- **No overlap.** Table spans must be 4-byte aligned, in
  `[directory end, buffer end]`, and must not overlap each other, the
  metadata block or the private block; metadata and private must not
  overlap each other.
- **Tolerated, documented:** directory entries need not be sorted by tag;
  tags may repeat (`woff_find_tag` returns the first match); gaps between
  table spans and nonzero padding bytes are not inspected; a zero
  `metaLength`/`privLength` ignores the matching offset field; the private
  block need not end at EOF.
- **Rejected by design:** WOFF2 (`wOF2` is a bad signature), zero
  `compLength` with nonzero `origLength`, `numTables > 4096`.

## Usage

```xi
use xiom.woff;

let r = woff_parse(&bytes);
if r.is_ok {
  let w: Woff = r.value;
  let n = woff_num_tables(&w);
  let gi = woff_find_tag_str(&w, "glyf");
  if gi >= 0 {
    let raw = woff_table_data(&bytes, &w, gi);
    if raw.is_ok {
      let stored: Vec[UInt8] = raw.value; // zlib bytes when is_compressed
    }
  }
}
```

Building the canonical uncompressed layout:

```xi
var tags = Vec[Int].new();
tags.push(woff_tag_of("glyf"));
var datas = Vec[Vec[UInt8]].new();
datas.push(index_data);
var sums = Vec[Int].new();
sums.push(0xAABBCCDD);
let built = woff_build(0x00010000, &tags, &datas, &sums);
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.woff
```

Expected: the namespace check passes, 24 `[PASS]` lines, and a final
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No zlib.** Tables with `compLength < origLength` and metadata blocks are
  copied raw; nothing is inflated or re-deflated.
- **No sfnt semantics.** No table parsing, no checksum verification, no
  head/DSIG handling; `origChecksum` is exposed unchecked.
- **No WOFF2.** The `wOF2` signature is rejected as a bad signature.
- **Structural, not canonicalising.** Gaps between tables, padding byte
  values and directory order are accepted as-is and not normalised.
- **Writer is uncompressed-only.** `woff_build` emits `compLength ==
  origLength` for every table, `majorVersion`/`minorVersion` 0 and no
  metadata/private blocks.
- **In-memory only.** No streaming over files or sockets; no thread
  safety guarantees beyond plain value semantics.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
