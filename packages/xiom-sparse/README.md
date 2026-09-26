# xiom.sparse

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Android sparse image parsing and canonical building:
> the 28-byte file header, 12-byte chunk headers, a flat chunk index and
> strict validation.
> **Deps:** `xiom.std` only. The library module uses `xiom.convert`; the
> tests use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.sparse` decodes Android sparse images (the format produced by
`img2simg`/`mksparse`): a little-endian file header followed by
`total_chunks` chunk headers and bodies. `sparse_parse` validates the magic,
version, header sizes, block size, every chunk header/body and the declared
block and chunk totals, then returns a `SparseImage` index built from five
parallel vectors: chunk types, block counts, body offsets, body lengths and
fill values. The bodies stay in the source buffer and are located by the
recorded spans. `sparse_build` writes a canonical header plus chunk headers
and bodies from the same parallel vectors, so a parsed image can be
re-emitted byte-for-byte (all-raw images are the usual case).

## API

| Function | Returns | Description |
|---|---|---|
| `sparse_parse(data)` | `Result[SparseImage, Str]` | Validate the whole image and index its chunks. |
| `sparse_major_version(t)` | `Int` | Header major version (1 after a parse). |
| `sparse_minor_version(t)` | `Int` | Header minor version (0 after a parse). |
| `sparse_version(t)` | `Str` | Version as `"major.minor"` (e.g. `"1.0"`). |
| `sparse_file_header_size(t)` | `Int` | File header size in bytes (28). |
| `sparse_chunk_header_size(t)` | `Int` | Chunk header size in bytes (12). |
| `sparse_block_size(t)` | `Int` | Block size in bytes (nonzero multiple of 4). |
| `sparse_total_blocks(t)` | `Int` | Header total block count. |
| `sparse_total_chunks(t)` | `Int` | Header total chunk count. |
| `sparse_image_checksum(t)` | `Int` | Stored image checksum, raw. |
| `sparse_chunk_count(t)` | `Int` | Number of index rows (safe minimum of the vectors). |
| `sparse_chunk_type(t, i)` | `Int` | Chunk type (51905/51906/51907/51908) or `-1`. |
| `sparse_chunk_blocks(t, i)` | `Int` | Block count (`0` for crc32) or `-1`. |
| `sparse_chunk_data_offset(t, i)` | `Int` | Body offset in the source buffer or `-1`. |
| `sparse_chunk_data_length(t, i)` | `Int` | Body length in bytes or `-1`. |
| `sparse_chunk_fill_value(t, i)` | `Int` | Fill value for fill chunks; `-1` otherwise. |
| `sparse_chunk_block_offset(t, i)` | `Int` | Running block offset before chunk `i` or `-1`. |
| `sparse_expanded_size(t)` | `Int` | `total_blocks * block_size`, or `-1` on overflow. |
| `sparse_build(block_size, types, blocks, bodies, checksum)` | `Result[Vec[UInt8], Str]` | Build a canonical image from parallel vectors. |

Chunk type constants: `SPARSE_CHUNK_RAW` (0xCAC1), `SPARSE_CHUNK_FILL`
(0xCAC2), `SPARSE_CHUNK_DONT_CARE` (0xCAC3), `SPARSE_CHUNK_CRC32` (0xCAC4),
plus `SPARSE_MAGIC` (0xED26FF3A), `SPARSE_FILE_HEADER_SIZE` (28) and
`SPARSE_CHUNK_HEADER_SIZE` (12).

Errors: `sparse: bad block size`, `sparse: bad chunk blocks`,
`sparse: bad chunk body`, `sparse: bad chunk header size`,
`sparse: bad chunk size`, `sparse: bad chunk total size`,
`sparse: bad file header size`, `sparse: bad image checksum`,
`sparse: bad magic`, `sparse: block count mismatch`,
`sparse: chunk count mismatch`, `sparse: chunk overruns buffer`,
`sparse: chunk vector mismatch`, `sparse: nonzero chunk reserved`,
`sparse: too many blocks`, `sparse: trailing bytes`,
`sparse: truncated chunk header`, `sparse: truncated header`,
`sparse: unknown chunk type`, `sparse: unsupported version`
(see SPEC.md for the full catalog and exact conditions).

## Usage

```xi
use xiom.sparse;
use xiom.io;

// Build an all-raw image: 2 blocks of 4 bytes each, no checksum.
var blocks = Vec[Int].new();
blocks.push(2);
var bodies = Vec[Vec[UInt8]].new();
var raw = Vec[UInt8].new();
var k = 0;
while k < 8 {
  raw.push(222 as UInt8);
  k = k + 1;
}
bodies.push(raw);
var types = Vec[Int].new();
types.push(SPARSE_CHUNK_RAW);
let built = sparse_build(4, &types, &blocks, &bodies, 0);

// Parse it back.
if built.is_ok {
  let bytes: Vec[UInt8] = built.value;
  let parsed = sparse_parse(&bytes);
  match parsed {
    Ok(t) => {
      io.println("blocks: " + xiom.convert.int_to_string(sparse_total_blocks(&t)));
      io.println("chunks: " + xiom.convert.int_to_string(sparse_chunk_count(&t)));
      let off: Int = sparse_chunk_data_offset(&t, 0);
      let len: Int = sparse_chunk_data_length(&t, 0);
      io.println("first raw span: " + xiom.convert.int_to_string(off) + ".." + xiom.convert.int_to_string(off + len));
    },
    Err(e) => { io.println("parse error: " + e); },
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.sparse
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No expansion to raw.** The codec indexes and validates chunks; it does
  not write the expanded image (fill/don't-care materialization is a
  non-goal). `sparse_expanded_size` reports the expanded size only.
- **The image checksum is opaque.** `image_checksum` is stored and returned
  raw; the codec never computes or verifies it, and crc32 chunks count as
  **0 blocks** in the header totals.
- **Strict trailing bytes.** Any bytes after the last declared chunk are
  `Err("sparse: trailing bytes")`; no padding tolerance.
- **Version 1.0 only.** Major 1 / minor 0 is required; other versions are
  rejected.
- **Block size is only range-checked** (nonzero, multiple of 4); no
  power-of-two or sector-size policy.
- **Spans borrow the source buffer.** `SparseImage` stores offsets into
  `data`; keep that buffer alive to read bodies.
- **First failure wins.** Validation is deterministic but stops at the
  first problem; one `Err` message is reported, not a list.
- Not thread-safe; `SparseImage` is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
