# xiom.git2

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.2` on the XIOM registry.

Pure-XIOM Git object and pack-file codec with a self-contained
DEFLATE/zlib decoder. No FFI, no stdlib compression modules: every byte
layout is parsed and decoded inside this package over flat `Vec[UInt8]`
buffers.

## Scope

| Area | Implemented |
|------|-------------|
| zlib (RFC 1950) | 2-byte header (CM, CINFO, FCHECK, FDICT, FLEVEL), DEFLATE payload, big-endian Adler-32 trailer (verified) |
| DEFLATE (RFC 1951) | stored (BTYPE 00), fixed-Huffman (01), dynamic-Huffman (10), full LZ77 length/distance tables, overlapping copies |
| Loose objects | `<type> <size>\0` header (blob/tree/commit/tag), canonical size form, payload |
| Tree payloads | octal mode + name + NUL + raw id (20 or 32 bytes), Git sort order (directories sort as `name + "/"`) |
| Commit/tag payloads | header lines with folded continuations (`tree`, `parent*`, `author`, `committer`, `encoding`, `gpgsig`, tag `object`/`type`/`tag`/`tagger`, unknown keys), blank-line message boundary |
| Packs | `PACK` header (v2/v3), entry headers (types 1-4, 6, 7), big-endian size groups, OFS_DELTA negative-offset varint, REF_DELTA base id, full entry walk with per-entry inflate, raw 20-byte trailer |
| Deltas | source/target size varints, copy/insert opcode table with offset/size byte bit encodings |
| Pack index v2 | fanout, sorted ids, CRC-32 table, 4-byte offsets + 64-bit offset table, raw pack/idx checksums, binary-search lookup, CRC verification |

## Non-goals

- SHA-1 / SHA-256 hashing and object-id computation (pack and idx trailer
  checksums are preserved raw, never verified).
- REF_DELTA resolution: a REF_DELTA's base id must be resolved through the
  pack index by the caller; `git2_pack_resolve` follows OFS_DELTA chains
  only.
- Repository layout, refs, staging index files, object writing.

## Usage

```xiom
use xiom.git2;

// Inflate one zlib stream (e.g. a loose object body).
let r = git2_zlib_decode(&zdata);
if r.is_ok {
  let raw: Vec[UInt8] = r.value;
  // ...
}

// Decode a loose object end to end.
let obj = git2_loose_parse(&zdata);          // <type> <size>\0 payload
// obj.value.object_type / .type_name / .declared_size / .payload

// Walk a tree and a pack.
let tree = git2_tree_walk(&tree_payload, 20); // 20 = SHA-1, 32 = SHA-256
let pack = git2_pack_walk(&pack_bytes, 20);
let resolved = git2_pack_resolve(&pack.value, 1);   // follows OFS deltas

// Look an object up in a pack index and verify its CRC.
let idx = git2_idx_parse(&idx_bytes, 20);
let i = git2_idx_lookup(&idx.value, &raw_id, 20);    // -1 when absent
let ok = git2_idx_verify_crc(&idx.value, &pack_bytes, i);
```

Decoders that need to append into an existing buffer use
`git2_deflate_decode_into(data, start, &mut out)` (raw DEFLATE, returns the
offset just past the final block) and `git2_zlib_decode_into(z, &mut out)`
(strict: the whole buffer must be exactly one zlib stream).

## Errors

Every fallible function returns `Result[T, Str]`; malformed input produces a
`"git2: ..."` message carrying the byte offset of the problem
(`"git2: bad zlib fcheck at 0"`, `"git2: entry overruns pack trailer at 29"`).
No partial result is returned.

## Testing

```
.\scripts\port.ps1 -Package xiom.git2
```

The suite (`tests/test_conformance.xi`) builds every fixture in memory --
including DEFLATE bit streams emitted by an independent test-side bit writer
with its own copy of the RFC 1951 code tables -- and cross-checks the CRC-32
implementation against a second, independent table-less implementation and
the `"123456789"` check vector.

See `SPEC.md` for the exact byte layouts, the DEFLATE subset details and the
error catalog.
