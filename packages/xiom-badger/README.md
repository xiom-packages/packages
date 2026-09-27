# xiom.badger

Pure-XIOM, parse-only reader for BadgerDB (dgraph-io/badger) file-format
structures. No filesystem access, no writes, no storage-engine behaviour: the
caller passes the whole file (or a block) as a `Vec[UInt8]` and receives
scalars plus offset/size spans into that buffer.

> **Status:** `0.1.0`, port green (`port: PASS (passed=20 failed=0
> program_exit=0 exit=0)`).
> **Scope:** value-log entry headers and walks, versioned keys, SST table
> header/data-block/index/bloom/footer, manifest header and file lists, and a
> local CRC32C (Castagnoli) implementation.
> **Deps:** `xiom.std` only (`xiom.convert.int` for decimal offsets).

See `SPEC.md` for the byte-level layouts actually implemented, the verified
subset and the upstream deviations. The layouts follow the port brief and are
NOT byte-compatible with upstream Badger files (upstream uses an 18-byte
big-endian or varint vlog header, a `MaxUint64 - version` key suffix, and
protobuf-based table index/checksum records).

## What is implemented

| Area | API |
|------|-----|
| CRC32C | `badger_crc32c` (Castagnoli, reflected `0x82F63B78`, no LevelDB mask) |
| Value log | `badger_parse_vlog_header`, `badger_vlog_entry_total`, `badger_vlog_walk`, `badger_vlog_count`, `badger_vlog_field`, `badger_vlog_key_bytes`, `badger_vlog_value_bytes` |
| Meta bits | `badger_meta_bit_name`, `badger_meta_names`, `badger_meta_has`, `badger_meta_known` and the six `BADGER_META_*` constants |
| Keys | `badger_key_decode`, `badger_key_version`, `badger_key_deleted`, `badger_key_tagged`, `badger_key_user_size`, `badger_key_user_bytes` |
| SST header | `badger_sst_magic_ok`, `badger_parse_sst_header` |
| SST blocks | `badger_parse_sst_block_entry`, `badger_sst_block_entries` plus key/shared/value/offset accessors, `badger_parse_sst_block_trailer`, `badger_sst_block_trailer_ok` |
| SST index | `badger_sst_index_parse`, `badger_sst_index_count/offset/size/key`, `badger_sst_index_lookup` |
| SST footer | `badger_sst_footer_parse`, `badger_sst_footer_ok` |
| Bloom | `badger_fnv1a32`, `badger_bloom_hash_pair`, `badger_bloom_parse`, `badger_bloom_has` |
| Manifest | `badger_manifest_header_parse`, `badger_manifest_entry_parse`, `badger_manifest_files_parse`, flag/field accessors |
| Misc | `badger_version` |

Sanity caps: 1 MiB per value-log key/value/entry and per SST key/value, 8 MiB
block size, 8 Mi bits and 64 hashes per bloom filter, 100 000 index entries
and manifest files. Errors carry decimal byte offsets and, for manifest
entries, the file id.

## Usage

```xiom
module example
use xiom.io;
use xiom.badger;

fn main() -> Int {
  // Parse a 20-byte value log entry header at offset 0.
  let hr = badger_parse_vlog_header(&buf, 0);
  if !hr.is_ok {
    io.println(hr.error); // "badger: vlog header truncated at 0"
    return 1;
  }
  let h = hr.value;

  // Walk every entry of a value log file region.
  let wr = badger_vlog_walk(&buf, 0, buf.len(), 1024);
  if wr.is_ok {
    let w = wr.value;
    io.println("entries: " + badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_COUNT).value);
    let key = badger_vlog_key_bytes(&buf, &w, 0);
    let kr = badger_key_decode(&key, 0, key.len());
    if kr.is_ok {
      let k = kr.value;
      if badger_key_deleted(&k) {
        io.println("tombstone version " + badger_key_version(&k));
      }
    }
  }

  // CRC32C of bytes [start, start + size).
  let crc = badger_crc32c(&buf, 0, 16);

  // SST: header, one data block, its trailer.
  let sh = badger_parse_sst_header(&file);
  let block = badger_sst_block_entries(&body, body.len());
  let tr = badger_parse_sst_block_trailer(&trailer, 0);
  return 0;
}
```

All functions are free functions returning `Result[..., Str]` except the
pure accessors and `badger_crc32c`/`badger_meta_*` (plain values; -1 for an
invalid CRC range). Buffers are borrowed, never copied wholesale; only key,
value and span-copy helpers allocate.

## Tests

`tests/test_conformance.xi` builds every fixture in-test (no external data)
and prints `[PASS]`/`[FAIL]` per check: 20 tests covering the CRC32C vectors,
the vlog header matrix and multi-entry walk, the meta bit table, key
version/delete decode, SST header/entries/trailer/index/footer, the bloom
filter (hash known answers and membership), manifest header/file-list errors
and a composite 131-byte SST file. Run with:

```powershell
& .\scripts\port.ps1 -Package xiom.badger
```

## License

MIT OR Apache-2.0.
