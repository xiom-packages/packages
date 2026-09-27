# xiom.badger

Pure-XIOM, parse-only reader for **BadgerDB v1.6.2** (`dgraph-io/badger`
@ v1.6.2) file formats. No filesystem access, no writes, no storage-engine
behaviour: the caller passes the whole file (or a block) as a `Vec[UInt8]`
and receives scalars plus offset/size spans into that buffer.

> **Status:** `0.1.0`, port green (`port: PASS (passed=21 failed=0
> program_exit=0 exit=0)`).
> **Byte-compatible with:** BadgerDB **v1.6.2** only. Badger v2/v3/v4
> (`github.com/dgraph-io/badger/v2` and later) are explicitly **out of
> scope** and are not parsed.
> **Deps:** `xiom.std` (`xiom.convert.int`, `xiom.string`,
> `xiom.hash.siphash`).

See `SPEC.md` for the byte-level layouts, the upstream v1.6.2 files they were
verified against, the error catalog and the explicit unverified list.

## What is implemented

Byte-compatible with the v1.6.2 sources (all fetched and cited in SPEC.md
section 9):

| Area | API |
|------|-----|
| CRC32C | `badger_crc32c` (Castagnoli, init/final `0xFFFFFFFF`, known-answer tested) |
| Value log | `badger_parse_vlog_header` (18-byte BE header), `badger_vlog_entry_total`, `badger_vlog_entry_crc`, `badger_vlog_entry_crc_ok`, `badger_vlog_walk` (CRC-verified multi-entry walk), `badger_vlog_txn_prefix` (upstream `bitTxn`/`bitFinTxn` grouping), field/key/value accessors |
| Meta bits | `badger_meta_bit_name`, `badger_meta_names`, `badger_meta_has`, `badger_meta_known`; the upstream table `DELETE`/`VALUE_POINTER`/`DISCARD_EARLIER_VERSIONS`/`MERGE_ENTRY`/`TXN`/`FIN_TXN` |
| Keys | `badger_key_decode` (user key + BE `MaxUint64 - ts`), `badger_key_parse_ts`, version/tag/user accessors. The delete marker is the `DELETE` meta bit, not a key bit |
| Value pointers | `badger_value_pointer_decode` (12-byte BE `fid/len/offset`) |
| SST blocks | `badger_sst_value_struct_decode`, `badger_parse_sst_block_entry`, `badger_sst_block_walk` (key-diff reconstruction, `plen=0/klen=0` terminator) and accessors |
| SST index | `badger_sst_index_parse` (u32 BE block-end offsets + count), block start/end/size accessors |
| SST tail | `badger_sst_tail_parse` (bloom length last, index before bloom; v1.6.2 has **no** table header/footer) |
| Bloom | `badger_bloom_parse` (bbloom JSON envelope), `badger_bloom_bit`, `badger_bloom_has` (fixed-key SipHash-2-4 membership, matching upstream bbloom) |
| Table checksum | `badger_sst_checksum`, `badger_sst_checksum_hex`, `badger_sst_checksum_ok` (SHA-256 over the whole file, as `loadToRAM` computes) |
| Files | `badger_sst_filename` (`%06d.sst`) |
| Manifest | `badger_manifest_header_parse` (`Bdgr` + version 4), `badger_manifest_record_parse`, `badger_manifest_records_parse` (length + CRC32C framing, truncation semantics), `badger_manifest_changeset_parse` (protobuf `ManifestChangeSet`), `badger_manifest_replay` (create/delete semantics, final table set) |
| Misc | `badger_version` |

Sanity caps (local guards, documented in SPEC.md section 8): 1 MiB per
value-log value/entry, 65536-byte value-log key bound (upstream),
100 000 block/index/manifest entries, 8 MiB bloom bit set. Errors carry
decimal byte offsets.

The v2-era layouts once implemented by this package (16-byte `BDGR` table
header, block CRC trailer, 16-byte footer, 20-byte LE vlog header, key
delete bit, 40-byte manifest entries) **do not exist in v1.6.2** and were
removed.

## Usage

```xiom
module example
use xiom.io;
use xiom.badger;

fn main() -> Int {
  // Parse an 18-byte value log entry header at offset 0.
  let hr = badger_parse_vlog_header(&buf, 0);
  if !hr.is_ok {
    io.println(hr.error); // "badger: vlog header truncated at 0"
    return 1;
  }
  let h = hr.value;

  // Walk every CRC-verified entry of a value log file region.
  let wr = badger_vlog_walk(&buf, 0, buf.len(), 1024);
  if wr.is_ok {
    let w = wr.value;
    io.println("entries: " + badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_COUNT).value);
    let key = badger_vlog_key_bytes(&buf, &w, 0);
    let kr = badger_key_decode(&key, 0, key.len());
    if kr.is_ok {
      let k = kr.value; // k.version = MaxUint64 - suffix
      if badger_meta_has(badger_vlog_field(&w, 0, BADGER_VLOG_FIELD_META).value, BADGER_META_DELETE) {
        io.println("tombstone version " + k.version);
      }
    }
  }

  // SST: tail -> index -> block -> ValueStruct; bloom membership.
  let t = badger_sst_tail_parse(&file).value;
  let ix = badger_sst_index_parse(&file, t.index_offset, t.index_size).value;
  let end = badger_sst_index_block_end(&ix, 0).value;
  let block = file; // block spans [0, end) for block 0
  let wr2 = badger_sst_block_walk(&block, end).value;
  let vsr = badger_sst_value_struct_decode(&block, 0, 0);
  let bloom = badger_bloom_parse(&file, t.bloom_offset, t.bloom_size).value;
  let hit = badger_bloom_has(&file, &bloom, 0, 5); // user key, no timestamp

  // Whole-table SHA-256 (the digest MANIFEST stores for this table id).
  let ok = badger_sst_checksum_ok(&file, &expected_digest);
  return 0;
}
```

All functions are free functions returning `Result[..., Str]` except the
pure accessors and `badger_crc32c` (plain values; -1 for an invalid CRC
range). Buffers are borrowed, never copied wholesale; only key, value and
span-copy helpers allocate.

## Tests

`tests/test_conformance.xi` runs 21 checks. Four fixtures are byte-for-byte
outputs of the upstream v1.6.2 code, generated by compiling
`dgraph-io/badger @ v1.6.2` with Go and embedded in the test as hex/JSON
(no external data files at run time):

- three value-log entries (plain, `TXN`, `FIN_TXN`) per `structs.go`;
- a MANIFEST header plus two records from the real
  `pb.ManifestChangeSet` protobuf and `y.CastagnoliCrcTable`;
- a 237-byte SST from the real `table.NewTableBuilder()`, including its
  bbloom JSON filter;
- the SHA-256 digest `loadToRAM` computes over that table.

Every other fixture (error cases, caps, synthetic indexes) is assembled byte
by byte in-test; the reference CRC32C is an independent bit-serial
implementation. Run with:

```powershell
& .\scripts\port.ps1 -Package xiom.badger
```

## License

MIT OR Apache-2.0.
