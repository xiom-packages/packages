# xiom.badger -- SPEC

Byte-compatible, parse-only structure parser for **BadgerDB v1.6.2**
(`github.com/dgraph-io/badger @ v1.6.2`).

Badger v2/v3/v4 (`github.com/dgraph-io/badger/v2` and later, including the
`badger/v4` module layout) is **out of scope**. This package implements the
v1.6.2 on-disk formats only.

## 1. Scope

- Read-only structure parsing. Callers pass the whole file (or a block) as a
  `Vec[UInt8]`; every parsed value is a scalar or an offset/size span into
  that buffer. Nothing is written, nothing is memory-mapped, no
  storage-engine behaviour (transactions, memtable, compaction, GC, value
  indirection) is implemented.
- The module is `xiom.badger`, package `xiom.badger` `0.1.0`.
- Every layout below was **pinned from the upstream v1.6.2 sources** listed in
  section 9 and re-verified by parsing fixtures produced by compiling those
  sources (section 10).
- Error convention: every structural error is `Err("badger: <msg> at
  <offset>")` with a decimal byte offset (and optionally a file id).

## 2. Value log

### 2.1 Entry header (18 bytes, big-endian)

Verified in `structs.go` (`header`, `headerBufSize = 18`, `header.Encode`,
`header.Decode`).

| Offset | Size | Field | Encoding |
|--------|------|-------|----------|
| 0 | 4 | `klen` | u32 big-endian |
| 4 | 4 | `vlen` | u32 big-endian |
| 8 | 8 | `expiresAt` | u64 big-endian (Unix seconds, 0 = no expiry) |
| 16 | 1 | `meta` | meta bit byte (section 3) |
| 17 | 1 | `userMeta` | caller byte |

There are **no reserved bytes** in v1.6.2 (the removed brief layout's
`+2 reserved` bytes do not exist upstream).

### 2.2 Entry body and CRC (22 + klen + vlen bytes)

Verified in `structs.go` `encodeEntry` and `value.go` `safeRead.Entry`.

1. 18-byte header (2.1).
2. `klen` key bytes.
3. `vlen` value bytes.
4. 4-byte **CRC32C** (Castagnoli) over *header, key and value*, stored
   big-endian (`binary.BigEndian.PutUint32`).

`badger_vlog_entry_total(h) = 18 + klen + vlen + 4`, matching
`vp.Len = headerBufSize + len(e.Key) + len(e.Value) + crc32.Size`
(`value.go` iterate).

The same bytes are also the key/value layout stored **inside SST blocks**
(2.2 is the on-disk entry of the value-log file; the LSM stores a
`ValueStruct`, section 5.2).

### 2.3 Structural bounds

- Upstream: `safeRead.Entry` rejects `klen > 1<<16` (65536) with
  `errTruncate` (`value.go`). Implemented as `BADGER_VLOG_KEY_LEN_MAX`
  ("vlog key length exceeds upstream bound").
- Local guard (not upstream): `BADGER_VLOG_ENTRY_CAP = 1 MiB` for the value
  length and the whole entry (18 + k + v + 4). Documented as a parser
  hardening cap; upstream has no per-value cap (the value-log file size
  bounds it).
- The walk verifies every entry CRC and reports a mismatch
  (`badger: vlog entry crc mismatch at <off>`). Upstream `iterate()` instead
  *silently truncates* at the first bad entry; the difference is deliberate
  (parse-only contract) and documented.

### 2.4 Multi-entry walking and transaction grouping

`badger_vlog_walk(data, off, limit, max_entries)` reads consecutive entries
over `[off, limit)`, validates bounds/CRC/caps and returns parallel vectors
(offsets, key/value spans, meta bytes, expiry, CRC) plus `total_bytes`.

`badger_vlog_txn_prefix(data, w)` replays the upstream commit-group rules
(`value.go` iterate, lines 290-345):

- `bitTxn` (0x40) entries must all carry the same key timestamp
  `y.ParseTs(key)`; the group is committed by a `bitFinTxn` (0x80) entry
  whose value is that timestamp in decimal.
- A plain entry inside an open group stops the replay (upstream `break`).
- An open group at the end is not committed.
- Result: `valid_entries` (committed prefix), `groups` (closed groups),
  `closed`, `reason` ("" when the whole walk is a valid committed prefix).

### 2.5 Value pointers

`structs.go` `valuePointer`: `vptrSize = 12`; fields `Fid`, `Len`, `Offset`
as u32 **big-endian**, in that order. Exposed as
`badger_value_pointer_decode`.

## 3. Meta bits (delete marker)

Verified in `value.go` lines 46-54:

| Bit | Value | Name |
|-----|-------|------|
| 0 | 1 | `DELETE` |
| 1 | 2 | `VALUE_POINTER` |
| 2 | 4 | `DISCARD_EARLIER_VERSIONS` |
| 3 | 8 | `MERGE_ENTRY` |
| 6 | 64 | `TXN` |
| 7 | 128 | `FIN_TXN` |

Defined union: `BADGER_META_DEFINED = 207`.

**Where the delete marker lives.** In v1.6.2 the delete marker is *not* part
of the key. `Txn.Delete` sets `Entry.meta = bitDelete` (`txn.go`), and
`Entry.meta` (`structs.go`) is serialized as

- the **value-log header meta byte** (`structs.go` `encodeEntry`), and
- the **ValueStruct meta byte** in SST blocks (`structs.go` Entry ->
  `y.ValueStruct.Meta`, `table/builder.go`).

The `badger_meta_*` helpers implement the bit table; nothing in the key
suffix encodes a tombstone.

## 4. Versioned keys

Verified in `y/y.go` `KeyWithTs`, `ParseTs`, `ParseKey`, `CompareKeys`.

- `KeyWithTs(key, ts) = key || BE64(MaxUint64 - ts)` (8-byte big-endian
  suffix). Sorting is ascending bytes: among equal user keys, larger
  timestamps sort first.
- `ParseTs(key)`: `0` when `len(key) <= 8`; otherwise
  `MaxUint64 - BE64(last 8 bytes)` modulo 2^64.
- `ParseKey(key)`: `key[:len(key)-8]`; upstream asserts `len(key) > 8`.

`badger_key_decode(data, off, size)` rejects `size <= 8`
("key shorter than version tag"); `version` is computed modulo 2^64 so it
equals the original timestamp for every timestamp a real Badger writes.
`badger_key_parse_ts` mirrors `ParseTs` exactly (including the `<= 8 -> 0`
case).

## 5. SST table (v1.6.2 `table` package)

### 5.0 What does NOT exist in v1.6.2

The earlier brief layout implemented by this package was removed because
none of it exists upstream in v1.6.2:

| Removed brief element | v1.6.2 reality |
|-----------------------|----------------|
| 16-byte file header (magic `BDGR`, version, block size, checksum type) | no table header at all; blocks start at offset 0 |
| LEB128 shared/key/value entry encoding | 10-byte big-endian header (5.2) |
| 4-byte CRC32C block trailer | no per-block checksum |
| 16-byte footer (index handle + CRC) | no footer; the file tail is the bloom block (5.5) |
| 40-byte manifest file-list entries | protobuf records (section 7) |
| 20-byte LE value-log header | 18-byte BE header (2.1) |
| LE key tag with a delete bit | BE `MaxUint64 - ts`, no delete bit (section 4) |

Table integrity in v1.6.2 is a **SHA-256 over the whole file**
(`table/table.go` `loadToRAM`), stored in the MANIFEST for that table id
(section 8). No CRC32C is used in the table package.

### 5.1 File layout

```
[data block 0][data block 1]...[data block n-1]
[index: n x u32 BE block-end offsets][u32 BE n]
[bloom JSON bytes][u32 BE bloom length]        <- last 4 bytes of the file
```

Verified in `table/builder.go` (`Finish`, `blockIndex`) and
`table/table.go` (`readIndex`, which reads bloomLen, bloom, restartsLen,
restarts backwards from EOF).

### 5.2 Data block entries

Verified in `table/builder.go` (`header`, `addHelper`) and
`table/iterator.go` (`blockIterator`).

Entry header, 10 bytes big-endian:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 2 | `plen` (overlap with the block base key) |
| 2 | 2 | `klen` (key-diff length) |
| 4 | 2 | `vlen` (ValueStruct encoded length) |
| 6 | 4 | `prev` (offset of the previous entry, relative to block start; `MaxUint32` = 4294967295 for the first entry) |

Then `klen` key-diff bytes and `vlen` ValueStruct bytes.

Key reconstruction (`iterator.go parseKV`): `key = base[:plen] + diff`,
where `base` is the **first key of the block** (the first entry must have
`plen = 0`; `Next` asserts it). `plen > len(base)` is rejected by this
parser instead of panicking.

Block terminator (`builder.go finishBlock`): a dummy entry with
`plen = 0, klen = 0` whose value is an empty ValueStruct
(`vlen = 3`: meta, userMeta, uvarint 0). The block walk stops there;
`end_offset` records its start (or the walk limit when absent, which
upstream iteration tolerates). Blocks are bounded at
`BADGER_SST_RESTART_INTERVAL = 100` entries by the builder.

### 5.3 ValueStruct

Verified in `y/iterator.go`:

| Field | Encoding |
|-------|----------|
| `Meta` | 1 byte (meta bits, section 3) |
| `UserMeta` | 1 byte |
| `ExpiresAt` | uvarint (1 byte for 0) |
| `Value` | remaining bytes of the entry |

### 5.4 Block index

Verified in `builder.go blockIndex` and `table.go readIndex`:

- `n` u32 BE values: the **end offset of each block**; block `i` spans
  `[end(i-1), end(i))` with `end(-1) = 0`.
- one u32 BE `n` (count).

`badger_sst_index_parse` requires `size == 4*n + 4` and monotonic ends.
`badger_sst_index_block_start/end/size` expose the spans.

### 5.5 Bloom filter block

Verified in `builder.go Finish` (`bbloom.New(float64(b.keyCount), 0.01)`,
`JSONMarshal`, u32 BE length written last) and `table.go readIndex`.

- JSON envelope (Go `encoding/json` of
  `bloomJSONImExport{FilterSet []byte, SetLocs uint64}`):
  `{"FilterSet":"<base64>","SetLocs":N}`.
- `FilterSet` is the base64 (standard, padded) of `bit_count / 8` bytes of
  little-endian 64-bit words; `bit_count` is the smallest power of two
  `>= max(8 * keyCount-ish entries, 512)` bits (`bbloom getSize`).
- Probe count `setLocs` comes from bbloom's sizing
  (`ceil(ln(2) * size / entries)` for the 0.01 false-positive default).

Membership (`bbloom Has`, `sipHash.go`):

- `h64 = SipHash-2-4(key, k0 = 0xDEADBEAF, k1 = 0xFAEBDAED)` — bbloom's
  fixed key (its initial constants are pre-XORed with the SipHash IVs).
- `exponent = log2(bit_count)`; `h = h64 >> (64 - exponent)`;
  `l = (h64 << (64 - exponent)) >> (64 - exponent)`.
- probe `i`: bit index `(h + i*l) & (bit_count - 1)`; bit set means
  `bitset[idx>>6] & (1 << (idx%64))`, i.e. on the little-endian layout:
  byte `idx/8`, bit `idx%8`.
- `table.Builder` feeds `y.ParseKey(key)` (the **user key without the
  version suffix**) into the filter, so `badger_bloom_has` takes a user-key
  span.

Implemented with the stdlib `xiom.hash.siphash.siphash24`; membership is
tested against a real bbloom filter (section 10).

### 5.6 Table files and checksum

- Filename: `%06d.sst` (`table.go IDToFilename`), exposed as
  `badger_sst_filename`.
- Checksum: `sha256.Sum256(whole file)` (`table.go loadToRAM`), i.e. the
  digest recorded in the manifest. Implemented locally (section 6) as
  `badger_sst_checksum` / `_hex` / `_ok`.
- `badger_sst_tail_parse` reads the tail backwards: `bloomLen` (last u32 BE),
  bloom JSON, index count, index offsets; it returns both handles plus the
  count so callers can drive `badger_sst_index_parse` /
  `badger_bloom_parse`.

## 6. Checksums

### 6.1 CRC32C (local, Castagnoli)

Upstream uses `crc32.MakeTable(crc32.Castagnoli)` (`y/y.go`
`CastagnoliCrcTable`) through Go's `hash/crc32` (init 0xFFFFFFFF, final xor
0xFFFFFFFF) for value-log entries and manifest records. Implemented as
`badger_crc32c` with known-answer tests and an independent bit-serial
reference in the suite.

Known answers: `"" -> 0x00000000`, `"123456789" -> 0xE3069283`,
32 x `0x00 -> 0x8A9136AA`, 32 x `0xFF -> 0x62A8AB43`,
`0x00..0x1F -> 0x46DD794E`, `0x1F..0x00 -> 0x113FDB5C`.

### 6.2 SHA-256 (local, whole table)

v1.6.2 uses **SHA-256**, not CRC32C, for table integrity
(`table/table.go loadToRAM`). Because the stdlib `xiom.crypto.hash` /
`xiom.crypto.sha` SHA-256 links against a native symbol
(`xiom_sha256_hash`) that the pinned v0.61.3 compiler does not provide
(verified: `lld-link: undefined symbol: xiom_sha256_hash`), this module
carries its own pure-XIOM SHA-256 (`_sha256`), verified against
`""`, `"abc"` and the 237-byte upstream-generated table fixture.

## 7. Manifest

Verified in `manifest.go` and `pb/pb.proto`.

### 7.1 Header (8 bytes at offset 0)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | magic text `Bdgr` (u32 BE 1113876338) |
| 4 | 4 | `magicVersion` u32 BE 4 |

Wrong magic -> `badger: manifest bad magic at 0`; other versions ->
`badger: manifest unsupported version at 4` (upstream's
"manifest has unsupported version" error).

### 7.2 Records

Each record (`manifest.go addChanges` / `ReplayManifestFile`):

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | protobuf message length u32 BE |
| 4 | 4 | CRC32C of the protobuf bytes u32 BE |
| 8 | length | `pb.ManifestChangeSet` protobuf bytes |

A fresh store is written by `helpRewrite` as: header + one record with
length 0 and CRC 0 (the empty change set).

Replay semantics: records are read until EOF; a **partial** trailing record
is ignored and reported (`truncated`, `trunc_offset` = offset to truncate
at, `ReplayManifestFile`); a CRC mismatch or an over-long length is a hard
error. The upstream guard `length > file size` is implemented.

### 7.3 ManifestChangeSet protobuf (pb/pb.proto)

```
message ManifestChangeSet { repeated ManifestChange changes = 1; }
message ManifestChange {
  uint64 Id = 1;
  enum Operation { CREATE = 0; DELETE = 1; }
  Operation Op = 2;
  uint32 Level = 3;    // only for CREATE
  bytes Checksum = 4;  // only for CREATE, SHA-256 of the table file
}
```

Wire-format parser: field 1 of the set is length-delimited; inside a
change, fields 1/2/3 are varints and field 4 is bytes. Proto3 defaults are
reported explicitly (absent `Op` = CREATE, absent `Level` = 0,
`has_checksum` tells whether the bytes field was present). Unknown fields
are skipped by wire type; malformed fields are errors. Every parsed field
is reported; nothing is left unparsed except unknown fields (skipped by
design) and the semantic merge of a table's checksum bytes (exposed as a
span into the caller's buffer).

### 7.4 Replay (applyChangeSet semantics)

`badger_manifest_replay` applies records in order and returns the final live
table set:

- CREATE adds `{id, level, checksum span}`; a duplicate id is an error
  ("manifest table exists").
- DELETE removes the id; an unknown id is an error ("manifest removes
  non-existing table").
- Any other `Op` is invalid ("manifest invalid op").
- Local cap `BADGER_MANIFEST_MAX_TABLES`.

`badger_manifest_records_parse` (framing) and
`badger_manifest_changeset_parse` (one record body) are also public, so
callers can inspect intermediate records.

## 8. Structural caps (local guards)

| Constant | Value | Applies to |
|----------|-------|------------|
| `BADGER_VLOG_ENTRY_CAP` | 1048576 | value-log value length and whole entry |
| `BADGER_VLOG_KEY_LEN_MAX` | 65536 | value-log key length (upstream bound) |
| `BADGER_SST_MAX_BLOCK_ENTRIES` | 100000 | one block walk |
| `BADGER_SST_MAX_INDEX_BLOCKS` | 100000 | index entries |
| `BADGER_BLOOM_MAX_BYTES` | 8388608 | decoded FilterSet |
| `BADGER_MANIFEST_MAX_RECORDS` | 100000 | manifest record walk |
| `BADGER_MANIFEST_MAX_TABLES` | 100000 | replayed live tables |

`BADGER_SST_MAX_KEY_LEN` / `BADGER_SST_MAX_VALUE_LEN` (65535) document the
u16 on-disk fields.

## 9. Upstream sources verified (fetched during this rewrite)

All from `https://raw.githubusercontent.com/dgraph-io/badger/v1.6.2/`:

| File | Used for |
|------|----------|
| `structs.go` | vlog header 18 B BE, `encodeEntry` CRC framing, `valuePointer` 12 B BE, `Entry.meta` |
| `y/y.go` | `KeyWithTs` (MaxUint64-ts BE), `ParseTs`, `ParseKey`, `CompareKeys`, `CastagnoliCrcTable` |
| `y/iterator.go` | `ValueStruct` encode/decode, `EncodedSize` |
| `value.go` | meta bits 46-54, `safeRead.Entry`, `iterate` grouping, `vp.Len` |
| `table/table.go` | `readIndex` tail order, `loadToRAM` SHA-256, `IDToFilename` |
| `table/builder.go` | 10-byte entry header, block/index/bloom assembly, terminator |
| `table/iterator.go` | entry seek/parse, key reconstruction, terminator handling |
| `manifest.go` | `Bdgr`+4 header, record framing, replay/apply semantics |
| `pb/pb.proto` | `ManifestChangeSet` / `ManifestChange` field numbers |
| bbloom `v0.0.0-20190825152654-46b345b51c96` (`bbloom.go`, `sipHash.go`) | JSON envelope, sizing, fixed-key SipHash-2-4, probe |

### Unverified offline

- No dump was captured from a **running** BadgerDB v1.6.2 server or a
  long-lived store. The conformance fixtures were generated by compiling the
  upstream v1.6.2 packages with Go and calling the real
  `table.NewTableBuilder`, `bbloom` and `pb.ManifestChangeSet` APIs (and, for
  the value log, by executing the exact `structs.go encodeEntry` steps with
  `y.CastagnoliCrcTable`) — see section 10. This is a code-level
  reproduction, not a black-box capture.
- Manifest **rewrite** behaviour (`MANIFEST-REWRITE` rename, the 10000
  deletions / ratio-10 trigger) is documented but not implemented; the
  package only replays existing MANIFEST records.
- The bbloom `New(len(bs)<<3, locs)` clamp for malformed FilterSets smaller
  than 512 bits is not reproduced; the parser rejects such filters instead
  ("bloom filter set too small").
- Value-log entries whose `VALUE_POINTER` meta bytes point into another
  file are parsed as bytes; the pointer is not followed (no file layer).

## 10. Conformance fixtures

`tests/test_conformance.xi` (21 checks) embeds byte-for-byte outputs of the
upstream v1.6.2 code and parses them with the public API:

- `VLOG_HEX`: three value-log entries (plain, `TXN`, `FIN_TXN`), built by
  executing the `structs.go encodeEntry` steps with
  `y.CastagnoliCrcTable`.
- `MANIFEST_HEX`, `MANIFEST_BODY1/2`: header + two records produced by the
  real `pb.ManifestChangeSet` protobuf marshalled by `proto.Marshal`, with
  `crc32.Checksum(..., y.CastagnoliCrcTable)`.
- `TABLE_SMALL_HEX`: 237 bytes emitted by the real
  `table.NewTableBuilder()` (three entries: plain, value-pointer meta with
  expiry, delete meta), including the real block index and the real bbloom
  JSON envelope (`bbloom.New(3, 0.01)`, `JSONMarshal`).
- `TABLE_SMALL_SHA256`: the digest `loadToRAM` computes over those bytes.

All other fixtures (error cases, synthetic index/cap buffers) are assembled
byte by byte in-test; the reference CRC32C and hex/base64 handling in the
suite are independent of the module.

## 11. Public API

| Area | Functions |
|------|-----------|
| CRC32C | `badger_crc32c` |
| Meta bits | `badger_meta_bit_name`, `badger_meta_has`, `badger_meta_known`, `badger_meta_names` |
| Value log | `badger_parse_vlog_header`, `badger_vlog_entry_total`, `badger_vlog_entry_crc`, `badger_vlog_entry_crc_ok`, `badger_vlog_walk`, `badger_vlog_count`, `badger_vlog_field`, `badger_vlog_key_bytes`, `badger_vlog_value_bytes`, `badger_vlog_txn_prefix` |
| Value pointer | `badger_value_pointer_decode` |
| Keys | `badger_key_decode`, `badger_key_parse_ts`, `badger_key_version`, `badger_key_tagged`, `badger_key_user_size`, `badger_key_user_bytes` |
| SST block | `badger_sst_value_struct_decode`, `badger_parse_sst_block_entry`, `badger_sst_block_walk`, `badger_sst_block_count`, `badger_sst_block_field`, `badger_sst_block_key`, `badger_sst_block_value`, `badger_sst_block_entries_end` |
| SST index/tail | `badger_sst_index_parse`, `badger_sst_index_count`, `badger_sst_index_block_start/end/size`, `badger_sst_tail_parse` |
| Bloom | `badger_bloom_parse`, `badger_bloom_bit`, `badger_bloom_has` |
| Checksum | `badger_sst_checksum`, `badger_sst_checksum_hex`, `badger_sst_checksum_ok` |
| Files | `badger_sst_filename` |
| Manifest | `badger_manifest_header_parse`, `badger_manifest_record_parse`, `badger_manifest_records_parse`, `badger_manifest_record_count`, `badger_manifest_record_field`, `badger_manifest_changeset_parse`, `badger_manifest_change_count`, `badger_manifest_change_field`, `badger_manifest_change_has_checksum`, `badger_manifest_replay`, `badger_manifest_file_count`, `badger_manifest_file_field` |
| Misc | `badger_version` |

All fallible readers return `Result[T, Str]`; accessors return plain values.
Buffers are borrowed; only the explicit copy helpers allocate.

## 12. Error catalog (selection)

```
badger: vlog header out of bounds at 0
badger: vlog header truncated at <off>
badger: vlog key length exceeds upstream bound at <off>
badger: vlog value length exceeds cap at <off>
badger: vlog entry truncated at <off>
badger: vlog entry crc mismatch at <off>
badger: vlog walk trailing bytes at <pos>
badger: vlog walk exceeds max entries at <pos>
badger: vlog field index out of range at <i>
badger: key shorter than version tag at <off>
badger: key span out of bounds at <off>
badger: value pointer truncated at <off>
badger: value struct too short at <off>
badger: value struct expires: truncated|overflow at <off>
badger: sst entry header truncated at <pos>
badger: sst entry prefix exceeds base key at <pos>
badger: sst entry key truncated at <pos>
badger: sst entry value truncated at <pos>
badger: sst block first entry prefix nonzero at <pos>
badger: sst index too short at <off>
badger: sst index size mismatch at <off>
badger: sst index block offsets not monotonic at <off>
badger: sst index block out of range at <i>
badger: sst index count exceeds cap at <off>
badger: sst bloom length out of bounds at <off>
badger: bloom filter out of bounds at <off>
badger: bloom filter set missing at <off>
badger: bloom filter set unterminated at <off>
badger: bloom filter set: bad base64 length|char|padding at <off>
badger: bloom filter set too small at <off>
badger: bloom filter set size not a power of two at <off>
badger: bloom set locs missing|out of range at <off>
badger: bloom bit index out of range at <idx>
badger: bloom key out of bounds at <off>
badger: manifest header truncated at 0
badger: manifest bad magic at 0
badger: manifest unsupported version at 4
badger: manifest record truncated at <off>
badger: manifest length exceeds file size at <off>
badger: manifest checksum mismatch at <off>
badger: manifest walk exceeds max records at <off>
badger: manifest changeset out of bounds at <off>
badger: manifest changeset wire type at <pos>
badger: manifest change index out of range at <i>
badger: manifest table exists at <pos>
badger: manifest removes non-existing table at <pos>
badger: manifest invalid op at <pos>
badger: manifest exceeds max tables at <pos>
badger: manifest table index out of range at <i>
badger: txn terminator: empty value|not decimal|overflow at <off>
```

## 13. v0.61.3 notes

- Free functions only; no methods, no lambdas, no `Vec[StructType]`; parsed
  tables are flat parallel vectors.
- `Ok`/`Err` construction is confined to leaf helpers.
- Byte reads from `Vec[UInt8]` are widened with `(data[idx] as Int) & 0xFF`.
- Big-endian 64-bit reads accumulate the low seven bytes with a `place`
  factor and apply the top byte separately, so no intermediate overflows and
  the raw two's-complement pattern is exact.
- Shifts appear in the big-endian readers, the SHA-256 core and the UInt64
  bloom probes (all compile and run on the pinned compiler; the module was
  emit-ir compiled and the suite executed).
- `badger_crc32c` and `_sha256` are pure XIOM so the package has no native
  link requirements beyond the stdlib's SipHash (pure XIOM).
- Known benign warning: `--emit-ir` reports
  `warning[E001]: <line>: cannot store borrow in struct` once, on the
  `BadgerManifestChange` literal in `_manifest_change_parse`. The compiler
  exits 0, the warning is absent for identical anonymous probes with a loop
  and Bool state, and every field of the struct is asserted by test 18
  (manifest changesets) against the real upstream protobuf bytes, so the
  generated code is demonstrably correct. It is noted here rather than
  worked around so the toolchain issue can be filed upstream.
