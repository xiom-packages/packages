# xiom.badger -- SPEC

Byte-level layouts, validation order, error catalog and the verified subset of
`src/badger.xi`. Everything described here is implemented; anything not
described here is not implemented.

## 1. Scope

Read-only STRUCTURE parsing for BadgerDB (dgraph-io/badger) on-disk formats.
Callers pass a buffer (`Vec[UInt8]`) and receive scalars plus offset/size
spans into it. There is no filesystem access, no writes, no compression
decoding, no transaction/memtable/compaction behaviour, and no attempt to
parse upstream files verbatim (see section 10).

Conventions used throughout:

* All integer fields are little-endian unless a layout says otherwise.
* Every byte read is widened with `(data[pos] as Int) & 0xFF`.
* 64-bit fields are decoded to the raw two's-complement pattern: the low seven
  bytes accumulate with a `place` factor and the top byte is applied
  separately, so bit 63 set decodes as a negative Int. Version fields reject
  such patterns; expiry/creation fields return them raw.
* Flags and meta bits are tested with division/modulo, never shifts.
* Errors carry the decimal byte offset (and file id where known) and start
  with `badger: `.

## 2. Value log entry (brief layout)

Header: 20 bytes.

| offset | size | field       | notes                                   |
|-------:|-----:|-------------|-----------------------------------------|
|      0 |    4 | keyLen  u32 | LE; capped at `BADGER_VLOG_ENTRY_CAP`   |
|      4 |    4 | valLen  u32 | LE; capped at `BADGER_VLOG_ENTRY_CAP`   |
|      8 |    8 | expiresAt   | u64 LE, raw pattern; 0 = no expiry      |
|     16 |    1 | meta        | meta bit table below                    |
|     17 |    1 | userMeta    | caller byte, uninterpreted              |
|     18 |    2 | reserved    | must be zero                            |

Then `keyLen` key bytes and `valLen` value bytes follow immediately.

`BADGER_VLOG_ENTRY_CAP` = 1 048 576 (1 MiB). It bounds each key length, each
value length, and the whole entry (`20 + keyLen + valLen`); a declared length
above the cap is rejected before any span arithmetic.

Meta bits (`badger_meta_bit_name`, `badger_meta_has`, `badger_meta_names`,
`badger_meta_known`):

| value | name          |
|------:|---------------|
|  0x01 | DELETE        |
|  0x02 | VALUE_POINTER |
|  0x04 | TRANSACTION   |
|  0x08 | FIN_TXN       |
|  0x10 | BIT_TXN       |
|  0x20 | MERGE_ENTRY   |

`BADGER_META_ALL` = 63 (all six bits). Unknown bits are not rejected by the
parser; `badger_meta_known` reports them.

`badger_vlog_walk(data, off, limit, max_entries)` walks consecutive entries
over `[off, limit)`. It stops exactly at `limit`; a partial trailing header
(fewer than 20 bytes left) is an error. Each entry must fit inside `limit`,
its total size must not exceed the 1 MiB cap, and at most `max_entries`
entries are accepted. The result is a `BadgerVlogWalk` with parallel vectors
(offsets, key/value spans, metas, user metas, raw expiries) and `total_bytes`
consumed. Empty walks (`off == limit`) are valid.

## 3. Versioned keys (brief layout)

`badger_key_decode(data, off, size)`:

```
| user key (size - 8 bytes) | version tag (8 bytes u64 LE) |
```

* `tagged` = raw u64 pattern of the trailing 8 bytes.
* `deleted` = bit 0 of `tagged` (accessor `badger_key_deleted`).
* `version` = `tagged / 2` (truncating division; the delete tag removed),
  accessor `badger_key_version`.
* A tag with bit 63 set is rejected as out of Int range (real versions are
  wall-clock seconds).
* A key shorter than 8 bytes, a negative offset or an out-of-buffer span are
  rejected. `badger_key_user_bytes` copies the user key.

## 4. CRC32C (Castagnoli)

`badger_crc32c(data, start, size)` computes the raw CRC32C in a local
bit-serial implementation: reflected polynomial `0x82F63B78` (2197175160),
init `0xFFFFFFFF`, final xor `0xFFFFFFFF`; a value in `[0, 2^32)` or -1 for a
negative/out-of-buffer range. The LevelDB rotation mask is NOT applied.
Verified known answers (test t2):

| input                    | CRC32C       |
|--------------------------|--------------|
| `""`                     | `0`          |
| `"123456789"`            | `3808858755` |
| 32 x `0x00`              | `2324772522` |
| bytes `0x00..0x1F`       | `1188919630` |
| 32 x `0xFF`              | `1655221059` |

plus a cross-check against an independent bit-serial reference over a 256-byte
sequence (whole and offset ranges).

## 5. SST table (brief layout)

### 5.1 File header (16 bytes at offset 0)

| offset | size | field        | notes                                     |
|-------:|-----:|--------------|-------------------------------------------|
|      0 |    4 | magic u32 LE | `BADGER_SST_MAGIC` = 1380402242 ("BDGR")  |
|      4 |    4 | version u32  | `BADGER_SST_VERSION` = 1                  |
|      8 |    4 | blockSize    | 1 .. 8388608                              |
|     12 |    1 | checksumType | 0 = none, 1 = CRC32C                      |
|     13 |    3 | reserved     | must be zero                              |

### 5.2 Data-block entry

```
varint shared_len | varint key_len | varint val_len | key diff (key_len bytes) | value (val_len bytes)
```

* The brief names the entry `keyLen, valLen, key diff, value`; a diff without
  its prefix length is not decodable, so the implemented layout makes the
  diff self-describing with an explicit shared-prefix varint (LevelDB-style).
* `shared_len` must not exceed the previous key's length; the reconstructed
  key is `prev_key[0..shared_len] + diff`.
* varints are LEB128 u32: at most five bytes, the fifth with payload <= 15;
  over-long encodings are rejected as overflow.
* `BADGER_SST_MAX_KEY_LEN` / `BADGER_SST_MAX_VALUE_LEN` = 1 MiB each.
* `entry_bytes = header varints + key_len + val_len`; every entry consumes at
  least the three varint bytes.

`badger_sst_block_entries(body, limit)` walks entries until `limit` (normally
the body length, excluding the trailer). Keys are concatenated in `key_data`
with `key_offsets`/`key_sizes`; `value_offsets`/`value_sizes` locate values in
the body; `entry_offsets` records where each entry starts.

### 5.3 Block trailer (4 bytes)

Raw CRC32C u32 LE of the block body (the entry region, trailer excluded).
`badger_sst_block_trailer_ok` verifies a stored value against a body span.

### 5.4 Block index

```
count u32 LE
count x { blockOffset u64 LE, blockSize u32 LE, keyLen u32 LE, key bytes }
crc32c u32 LE over everything before it
```

`size` must match the buffer span exactly. `blockSize` counts the data-block
body only (trailer excluded). Keys are assumed sorted ascending;
`badger_sst_index_lookup(key_data, index, key_off, key_size)` returns the
index of the first separator key >= the target, or -1 when every key is
smaller or the target span is out of bounds. `BADGER_SST_MAX_INDEX_ENTRIES` =
100000.

### 5.5 Table footer (16 bytes at the end of the file)

| offset from base | size | field            |
|-----------------:|-----:|------------------|
|                0 |    8 | indexOffset u64  |
|                8 |    4 | indexSize u32    |
|               12 |    4 | crc32c u32 LE over the first 12 bytes |

The index range must satisfy `indexOffset >= 16` and
`indexOffset + indexSize <= base` (the footer cannot overlap the index).
`badger_sst_footer_ok` re-checks a parsed footer against a file size.

### 5.6 Bloom filter block

```
nbits u32 LE | nhashes u32 LE | ceil(nbits / 8) bit-array bytes | crc32c u32 LE
```

* `nbits` in `[1, 8388608]` (`BADGER_BLOOM_MAX_BITS`); `nhashes` in
  `[1, 64]` (`BADGER_BLOOM_MAX_HASHES`).
* `size` must match exactly (`8 + bits_size + 4`).
* Hashing is domain-separated FNV-1a-32 (offset basis 2166136261, prime
  16777619, mod 2^32): `h1` absorbs domain byte 1 then the key bytes, `h2`
  domain byte 2; `h2` is forced non-zero (0 and 2^32-1 map to 1).
  `badger_fnv1a32` is the plain (no domain byte) variant.
* Double hashing: `badger_bloom_has(bloom_data, key_data, b, key_off,
  key_size)` probes bit `(h1 + i*h2) mod nbits` for `i` in `[0, nhashes)`.
  False = definitely absent, true = possibly present. The bit array is read
  from `bloom_data`; the key bytes from `key_data`.
* The bloom block is a standalone block: the footer/index do not reference it
  in this module's layout.

Verified hash values (test t12):

| input        | value                  |
|--------------|------------------------|
| FNV-1a-32("")        | 2166136261    |
| FNV-1a-32("a")       | 3826002220    |
| FNV-1a-32("foobar")  | 3214735720    |
| h1("apple", domain 1)| 4230784436   |
| h2("apple", domain 2)| 1993265727   |

## 6. Manifest

### 6.1 Header (20 bytes at offset 0)

| offset | size | field        | notes                                     |
|-------:|-----:|--------------|-------------------------------------------|
|      0 |    4 | magic u32 LE | `BADGER_MANIFEST_MAGIC` = 1296516162 ("BDGM") |
|      4 |    4 | version u32  | `BADGER_MANIFEST_VERSION` = 1             |
|      8 |    8 | creation     | u64 LE raw pattern; 0 = unused            |
|     16 |    4 | reserved     | must be zero                              |

### 6.2 File-list entry (40 bytes)

| offset | size | field      | notes                                        |
|-------:|-----:|------------|----------------------------------------------|
|      0 |    8 | id u64     | must fit a positive Int                      |
|      8 |    4 | checksum   | stored u32, uninterpreted                    |
|     12 |    8 | size u64   | must fit a positive Int                      |
|     20 |    4 | flags u32  | known bits 0x01 DELETED, 0x02 KEY_RANGE      |
|     24 |    8 | minVersion | key-range lower bound, raw pattern rejected if bit 63 |
|     32 |    8 | maxVersion | key-range upper bound, raw pattern rejected if bit 63 |

`consumed` is always 40. Unknown flag bits are rejected; the error names the
file id: `badger: manifest entry unknown flags for file <id> at <off+20>`.

### 6.3 File list

```
count u32 LE | count x 40-byte entries | crc32c u32 LE over count + entries
```

`BADGER_MANIFEST_MAX_FILES` = 100000. `total_bytes = 4 + count * 40 + 4`.

## 7. Error catalog

Vlog:
`badger: vlog header out of bounds at 0`, `badger: vlog header truncated at
<off>`, `badger: vlog key length exceeds cap at <off>`, `badger: vlog value
length exceeds cap at <off+4>`, `badger: vlog header reserved bytes nonzero
at <off+18>`, `badger: vlog walk start out of bounds at 0`, `badger: vlog
walk limit out of bounds at <limit>`, `badger: vlog walk limit before start
at <limit>`, `badger: vlog walk max entries must be positive at <off>`,
`badger: vlog walk trailing bytes at <pos>`, `badger: vlog entry truncated at
<pos>`, `badger: vlog entry exceeds cap at <pos>`, `badger: vlog walk exceeds
max entries at <pos>`, `badger: vlog field index out of range at <i>`.

Keys: `badger: key shorter than version tag at <off>`, `badger: key span out
of bounds at <off>`, `badger: key version exceeds Int range at <tag_off>`.

SST: `badger: sst header truncated at 0`, `badger: sst bad magic at 0`,
`badger: sst unsupported version at 4`, `badger: sst block size out of range
at 8`, `badger: sst unknown checksum type at 12`, `badger: sst reserved bytes
nonzero at 13`, `badger: sst block entry: truncated at <pos>`, `badger: sst
block entry: overflow at <pos>`, `badger: sst block entry shared beyond
previous key at <pos>`, `badger: sst block entry key length exceeds cap at
<pos>`, `badger: sst block entry value length exceeds cap at <pos>`, `badger:
sst block entry key overrun at <pos>`, `badger: sst block entry value overrun
at <pos>`, `badger: sst block limit out of bounds at 0`, `badger: sst block
trailer truncated at <pos>`, `badger: sst index truncated at <off>`, `badger:
sst index count exceeds cap at <off>`, `badger: sst index entry overruns at
<pos>`, `badger: sst index block offset exceeds Int range at <pos>`, `badger:
sst index key length exceeds cap at <pos>`, `badger: sst index length
mismatch at <off>`, `badger: sst index checksum mismatch at <crc_off>`,
`badger: sst footer truncated at 0`, `badger: sst footer checksum mismatch at
<base>`, `badger: sst footer index offset exceeds Int range at <base>`,
`badger: sst footer index handle out of range at <base>`.

Bloom: `badger: bloom truncated at <off>`, `badger: bloom nbits zero at
<off>`, `badger: bloom bit count exceeds cap at <off>`, `badger: bloom hash
count out of range at <off+4>`, `badger: bloom bit array overrun at <off>`,
`badger: bloom length mismatch at <off>`, `badger: bloom checksum mismatch at
<crc_off>`, `badger: bloom bits out of bounds at <boff>`, `badger: hash span
out of bounds at <off>`.

Manifest: `badger: manifest header truncated at 0`, `badger: manifest bad
magic at 0`, `badger: manifest unsupported version at 4`, `badger: manifest
creation exceeds Int range at 8`, `badger: manifest reserved nonzero at 16`,
`badger: manifest entry truncated at <off>`, `badger: manifest entry id
exceeds Int range at <off>`, `badger: manifest entry size exceeds Int range
at <off+12>`, `badger: manifest entry unknown flags for file <id> at
<off+20>`, `badger: manifest entry min version exceeds Int range at
<off+24>`, `badger: manifest entry max version exceeds Int range at
<off+32>`, `badger: manifest file list truncated at <off>`, `badger:
manifest file count exceeds cap at <off>`, `badger: manifest file list
checksum mismatch at <crc_off>`, `badger: manifest file index out of range at
<i>`.

## 8. Verified subset

Every check below is exercised by `tests/test_conformance.xi` (20 tests,
synthetic buffers exclusively):

* CRC32C known answers, empty input, out-of-range rejection, local cross-check.
* Vlog header: all five fields across three entries (including the raw
  bit-63 expiry pattern and userMeta 200), reserved-byte rejection, both caps,
  truncation, negative offset.
* Vlog walk: three entries with offsets `0/34/59`, `total_bytes` 86, all span
  and meta accessors, empty walk, trailing bytes, entry truncation, entry cap,
  max-entries bound, limit bounds, non-positive max entries.
* Meta: names/membership for all six bits, combined names, unknown bits.
* Keys: version/delete accessors (false and true), empty user key, tagged
  value, short key, span out of bounds, bit-63 rejection.
* SST header: valid parse (checksum type 1 and 0), bad magic, version, block
  size (0 and cap+1), checksum type, reserved bytes, truncation.
* SST data block: four prefix-compressed entries (`shared` 0/2/0/0), the empty
  entry `[0,0,0]`, entry spans/counts, key/value copies, both varint error
  modes, shared-beyond-prev, key/value overruns, key cap, limit bounds.
* Block trailer: parse, match/mismatch, invalid crc, truncation.
* Bloom: hash known answers, parse fields, `ceil` bit size for nbits 9, zero
  nbits, bit-count cap, hash-count bounds, bit-array overrun, length mismatch,
  checksum mismatch; membership for three inserted keys, an absent key, and an
  all-zero filter; hash span bounds.
* Index: two-entry parse, accessors, first-key lookup (exact, between, below
  first, above last, out-of-span), empty index, truncation, count cap, entry
  overrun, bit-63 offset, key cap, checksum mismatch, length mismatch.
* Footer: valid handle + checksum, `footer_ok` boundaries, truncation, bad
  checksum, handle below header, size beyond base, bit-63 offset.
* Manifest header: valid/unused creation, bad magic, version, bit-63 creation,
  reserved, truncation.
* Manifest file list: three entries with flags 2/1/3, all selectors, offsets
  and consumed counts, flag names, single-entry parses, list truncation, count
  cap, checksum mismatch, unknown flags with file id, id/size/min/max bit-63
  rejections, entry truncation.
* Composite SST file (131 bytes): header + block + trailer + index + bloom +
  footer read back end to end with consistent offsets, lookup and membership.

Documented but not separately exercised (behaviour still implemented):
`badger_sst_magic_ok` with a valid magic at a non-zero offset, the
`BADGER_SST_CHECKSUM_NONE` trailer path, `badger_sst_footer_ok` with
`file_size` below the footer size, `badger_meta_known` for every meta value.

## 9. Bounds and caps

| constant                        | value    | applies to                     |
|---------------------------------|----------|--------------------------------|
| `BADGER_VLOG_ENTRY_CAP`         | 1048576  | vlog key, value, whole entry   |
| `BADGER_SST_MAX_KEY_LEN`        | 1048576  | block-entry and index keys     |
| `BADGER_SST_MAX_VALUE_LEN`      | 1048576  | block-entry values             |
| `BADGER_SST_MAX_BLOCK_SIZE`     | 8388608  | header block size              |
| `BADGER_SST_MAX_INDEX_ENTRIES`  | 100000   | index entry count              |
| `BADGER_BLOOM_MAX_BITS`         | 8388608  | bloom bit count                |
| `BADGER_BLOOM_MAX_HASHES`       | 64       | bloom hash count               |
| `BADGER_MANIFEST_MAX_FILES`     | 100000   | manifest file count            |

## 10. Upstream deviations

Verified against the dgraph-io/badger sources (`v1.6.2/structs.go`,
`v2.2007.4/structs.go`, `v2.2007.4/table/table.go`):

* Value log header. v1.6.2 writes 18 fixed bytes with big-endian `klen`,
  `vlen`, `expiresAt`; v2 writes `meta, userMeta` first and the three lengths
  as uvarints (maximum 21 bytes). This module implements the port brief's
  20-byte fixed little-endian layout (18 meaningful bytes + 2 reserved) and
  never claims byte-compatibility with upstream files.
* Key encoding. Upstream appends `MaxUint64 - version` big-endian and keeps
  the delete marker in the vlog meta byte; this module implements the brief's
  little-endian version suffix with the delete tag in bit 0.
* SST table. Upstream v2 stores the table as protobuf `TableIndex`/
  `BlockOffset` plus a protobuf `Checksum` (CRC32C over the block with the
  length-prefixed checksum record); its footer area is
  `checksumLen u32 | checksum | indexLen u32 | index`. The brief (and this
  module) use a LevelDB-style fixed layout with a per-block 4-byte CRC32C
  trailer, a fixed-width index block and a 16-byte footer. Bloom filters
  upstream are JSON `z.Bloom` values inside the index protobuf, not a
  standalone block.
* Manifest. Upstream's MANIFEST is a replayable log of transactions whose
  entries are protobuf-encoded (`pb.ManifestChangeSet`); this module
  implements the brief's fixed header + 40-byte file-list records.
* CRC32C is shared: upstream checksums data blocks with CRC32C Castagnoli
  without the LevelDB rotation mask, which is what `badger_crc32c` computes.

## 11. v0.61.3 notes

Free functions only; parallel Vec fields instead of Vec[StructType]; Ok/Err
construction confined to leaf helpers; typed locals for every Vec read;
`&mut` written explicitly at every call site; no shifts, bit tests by
division/modulo; truncating division; ceil as `q = a/b; r = a%b; if r > 0
{ q + 1 } else { q }`; CRC and 64-bit composition use explicit arithmetic.
`src/badger.xi` and `tests/test_conformance.xi` compile with zero warnings.
