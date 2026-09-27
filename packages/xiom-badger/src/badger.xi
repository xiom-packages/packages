// XIOM -- xiom.badger: BadgerDB v1.6.2 file-format structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a read-only STRUCTURE parser for BadgerDB v1.6.2 (dgraph-io/badger
// @ v1.6.2) on-disk formats. Callers pass the whole file (or a block) as a
// byte vector; every parsed value is a scalar field or an offset/size pair (a
// span) into that buffer. Nothing is written, no storage-engine behaviour
// (transactions, memtable, compaction, GC) is implemented, and no value
// indirection is followed.
//
// This module is BYTE-COMPATIBLE with the v1.6.2 formats. It is NOT the
// Badger v2/v3/v4 format (module github.com/dgraph-io/badger/v2 and later),
// which is explicitly out of scope. Every layout below was verified against
// the upstream v1.6.2 sources fetched during this rewrite and cited per
// section in SPEC.md; the conformance suite parses vectors produced by
// building the actual upstream packages (see tests).
//
// Implemented layers, all exactly as upstream v1.6.2 writes them:
//   * value log entry (structs.go: header 18 fixed bytes, big-endian:
//     klen u32 BE, vlen u32 BE, expiresAt u64 BE, meta byte, userMeta byte;
//     then key, value, and a u32 BE CRC32C of header+key+value). Multi-entry
//     walking verifies each entry CRC and enforces a local 1 MiB guard; the
//     upstream transaction grouping (value.go iterate: bitTxn entries share
//     one timestamp, bitFinTxn closes the group) is exposed by
//     badger_vlog_txn_prefix.
//   * key structure (y/y.go KeyWithTs): user key followed by the 8-byte
//     big-endian pattern MaxUint64 - ts. There is NO delete bit in the key
//     in v1.6.2: the delete marker is Entry.meta bitDelete (structs.go Entry,
//     txn.go Delete), serialized as the vlog header meta byte and as the
//     ValueStruct meta byte in SST blocks.
//   * SST table (table/ package): a sequence of data blocks from offset 0,
//     each entry a 10-byte big-endian header (plen u16, klen u16, vlen u16,
//     prev u32) plus the key diff plus a ValueStruct (meta byte, userMeta
//     byte, uvarint expiresAt, value bytes); blocks end with a dummy
//     plen=0/klen=0 entry. Then the block index (u32 BE block-end offsets,
//     then u32 BE count) and the bloom filter (bbloom JSON bytes, then its
//     u32 BE length) as the last bytes of the file. v1.6.2 has NO table
//     header, NO per-block CRC trailer and NO table footer; table integrity
//     is a SHA-256 over the whole file recorded in the MANIFEST
//     (table.go loadToRAM), implemented here as badger_sst_checksum*.
//   * bloom filter (bbloom v0.0.0-20190825152654): JSON envelope
//     {"FilterSet":"<base64>","SetLocs":N}; membership is SipHash-2-4 with
//     the fixed bbloom key 0xDEADBEAF/0xFAEBDAED and the double-hash probe
//     (h + i*l) & (size-1), using the stdlib xiom.hash.siphash.
//   * manifest (manifest.go): 8-byte header "Bdgr" + magicVersion 4 (u32 BE),
//     then records of u32 BE protobuf length, u32 BE CRC32C, and the
//     pb.ManifestChangeSet protobuf bytes (pb/pb.proto). Unknown protobuf
//     fields are skipped per wire type; every parsed field is documented.
//   * CRC32C (Castagnoli, reflected polynomial 0x82F63B78, init/final
//     0xFFFFFFFF) implemented locally with known-answer tests; upstream
//     uses hash/crc32 with y.CastagnoliCrcTable for vlog entries and
//     manifest records.
//
// Upstream deviations that are deliberate and documented:
//   * a local 1 MiB sanity cap per value-log key/value/whole entry, and a
//     65536-byte key bound taken from value.go safeRead.Entry. Upstream has
//     no value-length cap of its own (the value-log file size bounds it).
//   * malformed input is reported as Err with a byte offset; upstream
//     value-log iteration silently truncates at the first bad entry. The
//     parse-only contract prefers errors; walk callers can stop early with
//     the max_entries bound.
//   * the v2 brief layouts once implemented by this package (BDGR 16-byte
//     SST header, block CRC trailer, 16-byte footer, 20-byte LE vlog header,
//     LE key tag with a delete bit, 40-byte manifest entries) do not exist
//     in v1.6.2 and were removed. See SPEC.md section "removed brief layout".
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType]; parsed
//     tables are flat parallel Vec fields and every push is mirrored.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * big-endian 64-bit fields use the overflow-safe shape: the low seven
//     bytes accumulate with a `place` factor and the top byte is applied
//     separately, so the raw 64-bit pattern is exact.
//   * bit tests use division and modulo; shifts (`<<`, `>>`) appear only in
//     the big-endian readers, the SHA-256 core and the UInt64 bloom probes,
//     all validated by the conformance suite on this compiler.
//   * error messages carry byte offsets as decimal text.

module xiom.badger

use xiom.convert.int;
use xiom.string;
use xiom.hash.siphash;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Value log entry header size in bytes (v1.6.2 structs.go headerBufSize).
pub const BADGER_VLOG_HEADER_SIZE: Int = 18;

// Value log entry CRC size in bytes (v1.6.2 crc32.Size).
pub const BADGER_VLOG_CRC_SIZE: Int = 4;

// Local sanity cap, in bytes, for one key length, one value length and one
// whole value log entry (18 + key + value + 4). Not an upstream constant.
pub const BADGER_VLOG_ENTRY_CAP: Int = 1048576;

// Upstream key-length bound: value.go safeRead.Entry rejects klen > 1<<16.
pub const BADGER_VLOG_KEY_LEN_MAX: Int = 65536;

// valuePointer encoding size (structs.go vptrSize).
pub const BADGER_VALUE_POINTER_SIZE: Int = 12;

// Value log meta bits (value.go v1.6.2, lines 46-54).
pub const BADGER_META_DELETE: Int = 1;
pub const BADGER_META_VALUE_POINTER: Int = 2;
pub const BADGER_META_DISCARD_EARLIER_VERSIONS: Int = 4;
pub const BADGER_META_MERGE_ENTRY: Int = 8;
pub const BADGER_META_TXN: Int = 64;
pub const BADGER_META_FIN_TXN: Int = 128;

// Union of the six defined meta bits (1|2|4|8|64|128).
pub const BADGER_META_DEFINED: Int = 207;

// Key version tag size: 8-byte big-endian MaxUint64 - ts (y/y.go KeyWithTs).
pub const BADGER_KEY_TAG_SIZE: Int = 8;

// SST block entry header size (table/builder.go header: plen, klen, vlen,
// prev).
pub const BADGER_SST_ENTRY_HEADER_SIZE: Int = 10;

// header.prev sentinel for the first key-value pair of a block (math.MaxUint32).
pub const BADGER_SST_ENTRY_PREV_NONE: Int = 4294967295;

// Upstream restart interval (table/builder.go restartInterval).
pub const BADGER_SST_RESTART_INTERVAL: Int = 100;

// Field bounds: plen/klen/vlen are u16 on disk (table/builder.go header).
pub const BADGER_SST_MAX_KEY_LEN: Int = 65535;
pub const BADGER_SST_MAX_VALUE_LEN: Int = 65535;

// Local sanity caps for parsed structures.
pub const BADGER_SST_MAX_BLOCK_ENTRIES: Int = 100000;
pub const BADGER_SST_MAX_INDEX_BLOCKS: Int = 100000;
pub const BADGER_BLOOM_MAX_BYTES: Int = 8388608;

// SST file naming (table/table.go: suffix ".sst", IDToFilename "%06d").
pub const BADGER_SST_FILENAME_SUFFIX: Str = ".sst";

// Manifest constants (manifest.go: magicText "Bdgr", magicVersion 4).
pub const BADGER_MANIFEST_MAGIC: Int = 1113876338;
pub const BADGER_MANIFEST_VERSION: Int = 4;
pub const BADGER_MANIFEST_HEADER_SIZE: Int = 8;
pub const BADGER_MANIFEST_MAX_RECORDS: Int = 100000;
pub const BADGER_MANIFEST_MAX_TABLES: Int = 100000;

// Manifest change operations (pb/pb.proto Operation).
pub const BADGER_MANIFEST_OP_CREATE: Int = 0;
pub const BADGER_MANIFEST_OP_DELETE: Int = 1;

// Protobuf wire types (pb/pb.proto encoding).
pub const BADGER_PROTO_WIRE_VARINT: Int = 0;
pub const BADGER_PROTO_WIRE_64BIT: Int = 1;
pub const BADGER_PROTO_WIRE_BYTES: Int = 2;
pub const BADGER_PROTO_WIRE_32BIT: Int = 5;

// badger_vlog_field selectors.
pub const BADGER_VLOG_FIELD_OFFSET: Int = 0;
pub const BADGER_VLOG_FIELD_KEY_OFFSET: Int = 1;
pub const BADGER_VLOG_FIELD_KEY_SIZE: Int = 2;
pub const BADGER_VLOG_FIELD_VALUE_OFFSET: Int = 3;
pub const BADGER_VLOG_FIELD_VALUE_SIZE: Int = 4;
pub const BADGER_VLOG_FIELD_META: Int = 5;
pub const BADGER_VLOG_FIELD_USER_META: Int = 6;
pub const BADGER_VLOG_FIELD_EXPIRES_AT: Int = 7;
pub const BADGER_VLOG_FIELD_CRC: Int = 8;
pub const BADGER_VLOG_FIELD_COUNT: Int = 9;

// badger_sst_block_field selectors.
pub const BADGER_SST_FIELD_ENTRY_OFFSET: Int = 0;
pub const BADGER_SST_FIELD_KEY_OFFSET: Int = 1;
pub const BADGER_SST_FIELD_KEY_SIZE: Int = 2;
pub const BADGER_SST_FIELD_VALUE_OFFSET: Int = 3;
pub const BADGER_SST_FIELD_VALUE_SIZE: Int = 4;
pub const BADGER_SST_FIELD_PLEN: Int = 5;
pub const BADGER_SST_FIELD_VLEN: Int = 6;
pub const BADGER_SST_FIELD_PREV: Int = 7;
pub const BADGER_SST_FIELD_COUNT: Int = 8;

// badger_manifest_record_field selectors.
pub const BADGER_MANIFEST_RECORD_FIELD_LENGTH: Int = 0;
pub const BADGER_MANIFEST_RECORD_FIELD_CRC: Int = 1;
pub const BADGER_MANIFEST_RECORD_FIELD_OFFSET: Int = 2;
pub const BADGER_MANIFEST_RECORD_FIELD_BODY_OFFSET: Int = 3;
pub const BADGER_MANIFEST_RECORD_FIELD_COUNT: Int = 4;

// badger_manifest_change_field selectors.
pub const BADGER_MANIFEST_CHANGE_FIELD_ID: Int = 0;
pub const BADGER_MANIFEST_CHANGE_FIELD_OP: Int = 1;
pub const BADGER_MANIFEST_CHANGE_FIELD_LEVEL: Int = 2;
pub const BADGER_MANIFEST_CHANGE_FIELD_CHECKSUM_OFFSET: Int = 3;
pub const BADGER_MANIFEST_CHANGE_FIELD_CHECKSUM_SIZE: Int = 4;
pub const BADGER_MANIFEST_CHANGE_FIELD_OFFSET: Int = 5;
pub const BADGER_MANIFEST_CHANGE_FIELD_SIZE: Int = 6;
pub const BADGER_MANIFEST_CHANGE_FIELD_COUNT: Int = 7;

// badger_manifest_table_field selectors.
pub const BADGER_MANIFEST_TABLE_FIELD_ID: Int = 0;
pub const BADGER_MANIFEST_TABLE_FIELD_LEVEL: Int = 1;
pub const BADGER_MANIFEST_TABLE_FIELD_CHECKSUM_OFFSET: Int = 2;
pub const BADGER_MANIFEST_TABLE_FIELD_CHECKSUM_SIZE: Int = 3;
pub const BADGER_MANIFEST_TABLE_FIELD_COUNT: Int = 4;

// The module version.
pub const BADGER_MODULE_VERSION: Str = "0.1.0";

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A decoded unsigned varint plus the number of bytes it consumed.
///
/// `value` is in [0, 2^63) for every reader in this module; anything above
/// the Int range is reported as an overflow error.
pub type BadgerVarint = {
  value: Int;
  size: Int;
}

/// A decoded v1.6.2 value pointer (structs.go valuePointer).
///
/// All three fields are u32 big-endian on disk: fid, len, offset (in that
/// order).
pub type BadgerValuePointer = {
  fid: Int;
  len: Int;
  offset: Int;
}

/// A decoded versioned key: user key span plus the 8-byte version suffix.
///
/// Layout per y/y.go: user key bytes followed by the big-endian 64-bit
/// pattern `MaxUint64 - ts`. `tagged` is that raw pattern interpreted as a
/// two's-complement Int (it is negative whenever ts < 2^63-1, which is the
/// normal case); `version` is `MaxUint64 - tagged` computed modulo 2^64, so
/// it equals `ts` for every timestamp a real Badger writes. v1.6.2 has no
/// delete bit in the key: the delete marker is a meta bit (see
/// BADGER_META_DELETE).
pub type BadgerKey = {
  user_offset: Int;
  user_size: Int;
  tagged: Int;
  version: Int;
}

/// One parsed value log entry header (18 bytes at `off`).
///
/// `expires_at` is the raw two's-complement u64 pattern of the big-endian
/// field (0 = no expiry); `meta` is the meta bit byte and `user_meta` the
/// caller's user byte. The key starts right after the header.
pub type BadgerVlogHeader = {
  key_len: Int;
  val_len: Int;
  expires_at: Int;
  meta: Int;
  user_meta: Int;
}

/// A whole value log walk, in parallel vectors.
///
/// Entry i occupies [offsets[i], offsets[i] + entry_bytes) in the source
/// buffer; `key_offsets[i]`/`key_sizes[i]` locate the key,
/// `value_offsets[i]`/`value_sizes[i]` the value, `crcs[i]` the stored u32
/// CRC32C trailer and `metas[i]`/`user_metas[i]` the header bytes.
/// `total_bytes` is the number of bytes consumed from the walk start to the
/// end of the last entry.
pub type BadgerVlogWalk = {
  count: Int;
  offsets: Vec[Int];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  metas: Vec[Int];
  user_metas: Vec[Int];
  expires: Vec[Int];
  crcs: Vec[Int];
  total_bytes: Int;
}

/// Result of replaying the upstream v1.6.2 transaction grouping over a walk.
///
/// `valid_entries` is the number of leading entries that form complete,
/// committed transaction groups (or plain non-transaction entries);
/// `groups` is the number of closed bitFinTxn groups; `closed` is true when
/// the walk ends exactly on a group boundary; `reason` is "" on success or a
/// short description of where upstream iteration would stop.
pub type BadgerVlogTxn = {
  valid_entries: Int;
  groups: Int;
  closed: Bool;
  reason: Str;
}

/// A decoded SST ValueStruct (y/iterator.go).
///
/// On disk: meta byte, userMeta byte, uvarint expiresAt, then the value
/// bytes to the end of the entry. `value_offset`/`value_size` locate the
/// value inside the source buffer; `size` is the encoded length.
pub type BadgerSstValStruct = {
  meta: Int;
  user_meta: Int;
  expires_at: Int;
  value_offset: Int;
  value_size: Int;
  size: Int;
}

/// One decoded SST data-block entry.
///
/// Layout: 10-byte big-endian header (plen, klen, vlen, prev), the key diff
/// bytes, then the ValueStruct bytes. `key` is the fully reconstructed key
/// (block base key prefix + diff, per table/iterator.go parseKV);
/// `value_offset` is the offset of the ValueStruct inside the block body;
/// `entry_bytes` is the total consumed byte count.
pub type BadgerSstEntry = {
  plen: Int;
  klen: Int;
  vlen: Int;
  prev: Int;
  key_offset: Int;
  value_offset: Int;
  entry_bytes: Int;
  key: Vec[UInt8];
}

/// A whole SST data block walked entry by entry, in parallel vectors.
///
/// Keys are reconstructed in `key_data`/`key_offsets`/`key_sizes`;
/// `plens[i]`/`vlens[i]`/`prevs[i]` are the raw header fields;
/// `value_offsets[i]`/`value_sizes[i]` locate the ValueStruct bytes;
/// `entry_offsets[i]` is where entry i starts. `end_offset` is where the
/// dummy plen=0/klen=0 terminator (table/builder.go finishBlock) starts.
pub type BadgerSstEntries = {
  count: Int;
  key_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  plens: Vec[Int];
  vlens: Vec[Int];
  prevs: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  entry_offsets: Vec[Int];
  end_offset: Int;
}

/// A parsed v1.6.2 SST block index.
///
/// In file order: `count` u32 BE block-end offsets, then a u32 BE count
/// (table/builder.go blockIndex). Block i spans
/// [start(i), block_ends[i]) with start(0)=0 and start(i)=block_ends[i-1].
/// `offset`/`size` locate the index region in the source buffer.
pub type BadgerSstIndex = {
  count: Int;
  block_ends: Vec[Int];
  offset: Int;
  size: Int;
}

/// The tail of a v1.6.2 SST file: index handle plus bloom block handle.
///
/// v1.6.2 has no footer: the last 4 bytes are the bloom JSON length, and the
/// index sits immediately before the bloom JSON (table/table.go readIndex).
pub type BadgerSstTail = {
  file_size: Int;
  index_offset: Int;
  index_size: Int;
  index_count: Int;
  bloom_offset: Int;
  bloom_size: Int;
}

/// A parsed bbloom JSON envelope (bbloom JSONMarshal fields).
///
/// `filter_set_offset`/`filter_set_size` locate the base64 FilterSet text
/// inside the source buffer, `bits` is its decoded byte array (little-endian
/// 64-bit words on the machine that wrote it), `byte_count` is `bits.len()`,
/// `exponent` is log2(bit_count) with bit_count = 8*byte_count, and
/// `set_locs` the probe count.
pub type BadgerBloom = {
  set_locs: Int;
  byte_count: Int;
  exponent: Int;
  filter_set_offset: Int;
  filter_set_size: Int;
  text_offset: Int;
  text_size: Int;
  bits: Vec[UInt8];
}

/// A parsed 8-byte manifest header.
///
/// `magic` is the u32 BE value of "Bdgr" (BADGER_MANIFEST_MAGIC), `version`
/// must be 4 (manifest.go magicVersion).
pub type BadgerManifestHeader = {
  magic: Int;
  version: Int;
}

/// One parsed manifest record framing (manifest.go addChanges).
///
/// `length` and `crc` are the u32 BE fields; `body_offset` is where the
/// protobuf ManifestChangeSet starts and `consumed` is 8 + length.
pub type BadgerManifestRecord = {
  length: Int;
  crc: Int;
  offset: Int;
  body_offset: Int;
  consumed: Int;
}

/// A whole manifest record walk, in parallel vectors.
///
/// `truncated` is true when the file ends in a partial record; the file must
/// be truncated at `trunc_offset` before appending (ReplayManifestFile
/// semantics). CRC mismatches and over-long lengths are errors.
pub type BadgerManifestRecords = {
  count: Int;
  lengths: Vec[Int];
  crcs: Vec[Int];
  offsets: Vec[Int];
  body_offsets: Vec[Int];
  total_bytes: Int;
  truncated: Bool;
  trunc_offset: Int;
}

/// One parsed protobuf ManifestChange (pb/pb.proto).
///
/// Proto3 defaults are reported explicitly: `op` is CREATE (0) when the
/// field is absent, `level` is 0 when absent, `has_checksum` tells whether
/// the bytes field was present, and `checksum_offset`/`checksum_size` span
/// it when it is. `offset`/`size` describe the change message bytes.
pub type BadgerManifestChange = {
  id: Int;
  op: Int;
  level: Int;
  has_checksum: Bool;
  checksum_offset: Int;
  checksum_size: Int;
  offset: Int;
  size: Int;
}

/// A whole ManifestChangeSet parsed from one record body.
pub type BadgerManifestChanges = {
  count: Int;
  ids: Vec[Int];
  ops: Vec[Int];
  levels: Vec[Int];
  checksum_offsets: Vec[Int];
  checksum_sizes: Vec[Int];
  has_checksums: Vec[Bool];
  offsets: Vec[Int];
  sizes: Vec[Int];
}

/// The replayed final table set of a manifest (applyChangeSet semantics).
///
/// `record_count` is the number of well-formed records replayed,
/// `change_count` the total changes applied; the remaining parallel vectors
/// describe the live tables (id, level, checksum span) after all records.
pub type BadgerManifestTables = {
  record_count: Int;
  change_count: Int;
  count: Int;
  ids: Vec[Int];
  levels: Vec[Int];
  checksum_offsets: Vec[Int];
  checksum_sizes: Vec[Int];
  truncated: Bool;
  trunc_offset: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] { return Ok(v); }
// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] { return Err(m); }
// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
// Ok(v) for Result[BadgerVarint, Int] (the Int is a reader status code).
fn _ok_vv(v: BadgerVarint) -> Result[BadgerVarint, Int] { return Ok(v); }
// Err(c) for Result[BadgerVarint, Int].
fn _err_vc(c: Int) -> Result[BadgerVarint, Int] { return Err(c); }
// Ok(v) for Result[BadgerValuePointer, Str].
fn _ok_vp(v: BadgerValuePointer) -> Result[BadgerValuePointer, Str] { return Ok(v); }
// Err(m) for Result[BadgerValuePointer, Str].
fn _err_vp(m: Str) -> Result[BadgerValuePointer, Str] { return Err(m); }
// Ok(v) for Result[BadgerKey, Str].
fn _ok_key(v: BadgerKey) -> Result[BadgerKey, Str] { return Ok(v); }
// Err(m) for Result[BadgerKey, Str].
fn _err_key(m: Str) -> Result[BadgerKey, Str] { return Err(m); }
// Ok(v) for Result[BadgerVlogHeader, Str].
fn _ok_vh(v: BadgerVlogHeader) -> Result[BadgerVlogHeader, Str] { return Ok(v); }
// Err(m) for Result[BadgerVlogHeader, Str].
fn _err_vh(m: Str) -> Result[BadgerVlogHeader, Str] { return Err(m); }
// Ok(v) for Result[BadgerVlogWalk, Str].
fn _ok_vwalk(v: BadgerVlogWalk) -> Result[BadgerVlogWalk, Str] { return Ok(v); }
// Err(m) for Result[BadgerVlogWalk, Str].
fn _err_vwalk(m: Str) -> Result[BadgerVlogWalk, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstValStruct, Str].
fn _ok_vs(v: BadgerSstValStruct) -> Result[BadgerSstValStruct, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstValStruct, Str].
fn _err_vs(m: Str) -> Result[BadgerSstValStruct, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstEntry, Str].
fn _ok_sse(v: BadgerSstEntry) -> Result[BadgerSstEntry, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstEntry, Str].
fn _err_sse(m: Str) -> Result[BadgerSstEntry, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstEntries, Str].
fn _ok_sse_list(v: BadgerSstEntries) -> Result[BadgerSstEntries, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstEntries, Str].
fn _err_sse_list(m: Str) -> Result[BadgerSstEntries, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstIndex, Str].
fn _ok_idx(v: BadgerSstIndex) -> Result[BadgerSstIndex, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstIndex, Str].
fn _err_idx(m: Str) -> Result[BadgerSstIndex, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstTail, Str].
fn _ok_tail(v: BadgerSstTail) -> Result[BadgerSstTail, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstTail, Str].
fn _err_tail(m: Str) -> Result[BadgerSstTail, Str] { return Err(m); }
// Ok(v) for Result[BadgerBloom, Str].
fn _ok_bloom(v: BadgerBloom) -> Result[BadgerBloom, Str] { return Ok(v); }
// Err(m) for Result[BadgerBloom, Str].
fn _err_bloom(m: Str) -> Result[BadgerBloom, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestHeader, Str].
fn _ok_mh(v: BadgerManifestHeader) -> Result[BadgerManifestHeader, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestHeader, Str].
fn _err_mh(m: Str) -> Result[BadgerManifestHeader, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestRecord, Str].
fn _ok_mrec(v: BadgerManifestRecord) -> Result[BadgerManifestRecord, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestRecord, Str].
fn _err_mrec(m: Str) -> Result[BadgerManifestRecord, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestRecords, Str].
fn _ok_mrecs(v: BadgerManifestRecords) -> Result[BadgerManifestRecords, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestRecords, Str].
fn _err_mrecs(m: Str) -> Result[BadgerManifestRecords, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestChanges, Str].
fn _ok_mch(v: BadgerManifestChanges) -> Result[BadgerManifestChanges, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestChanges, Str].
fn _err_mch(m: Str) -> Result[BadgerManifestChanges, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestChange, Str].
fn _ok_mchg(v: BadgerManifestChange) -> Result[BadgerManifestChange, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestChange, Str].
fn _err_mchg(m: Str) -> Result[BadgerManifestChange, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestTables, Str].
fn _ok_mt(v: BadgerManifestTables) -> Result[BadgerManifestTables, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestTables, Str].
fn _err_mt(m: Str) -> Result[BadgerManifestTables, Str] { return Err(m); }

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// "badger: <msg> at <off>" -- structural errors carry their byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return "badger: " + msg + " at " + int_to_base(off, 10);
}

// Byte at `pos`, widened to 0..255; the caller guarantees the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Raw big-endian field of `size` (1, 2, 4 or 8) bytes at `off`.
//
// For size 8 the raw two's-complement 64-bit pattern is returned: the low
// seven bytes (least significant first) accumulate with a `place` factor and
// the top byte is applied separately, so no intermediate overflows. The
// caller guarantees off + size <= data.len().
fn _rbe(data: &Vec[UInt8], off: Int, size: Int) -> Int {
  var nlow = size;
  if size == 8 {
    nlow = 7;
  }
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < nlow {
    let b = _byte(data, off + size - 1 - i);
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  if size == 8 {
    let top = _byte(data, off);
    if top < 128 {
      return top * place + low;
    }
    let t = top - 128;
    let hi = low + t * place;
    return hi + (0 - 9223372036854775807 - 1);
  }
  return low;
}

// Copy [start, start + size) of `data` into a fresh Vec; callers guarantee
// the bounds.
fn _copy_range(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    let b: UInt8 = data[start + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Append all bytes of `src` to `dst`.
fn _append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// 2^k for small non-negative k, computed by repeated doubling (no shifts).
fn _pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// True when bit `bit_value` (a power-of-two mask) is set in `v`; implemented
// with division and modulo, never shifts.
fn _bit_set(v: Int, bit_value: Int) -> Bool {
  if bit_value <= 0 {
    return false;
  }
  let q = v / bit_value;
  let r = q % 2;
  if r == 1 {
    return true;
  }
  return false;
}

// Logical right shift of a UInt64 by k bits (k in [1, 63]). Two-var body:
// a single-var mask statement is mis-inlined by the compiler (BUG 15).
fn _u64shr(x: UInt64, k: Int) -> UInt64 {
  var shift = 64 - k;
  var mask: UInt64 = ((1 as UInt64) << shift) - 1;
  return (x >> k) & mask;
}

// (1 << k) - 1 as UInt64, for k in [0, 62].
fn _u64mask(k: Int) -> UInt64 {
  return ((1 as UInt64) << k) - 1;
}

// True when `data[pos..) ` starts with the bytes of `lit`.
fn _starts_with(data: &Vec[UInt8], pos: Int, limit: Int, lit: Str) -> Bool {
  if pos + lit.len() > limit {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    let b = _byte(data, pos + i);
    if b != (string.byte_at(lit, i) as Int) & 0xFF {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// First occurrence of `lit` in [from, limit), or -1.
fn _find_literal(data: &Vec[UInt8], from: Int, limit: Int, lit: Str) -> Int {
  var pos = from;
  while pos < limit {
    if _starts_with(data, pos, limit, lit) {
      return pos;
    }
    pos = pos + 1;
  }
  return -1;
}

// --------------------------------------------------
//  CRC32C (Castagnoli), local implementation
// --------------------------------------------------

// One reflected CRC32C step for byte `b`: xor into the register, then eight
// right shifts with the reversed polynomial 0x82F63B78 (2197175160) fed back
// on every set low bit. The register stays in [0, 2^32).
fn _crc32c_step(crc_in: Int, b: Int) -> Int {
  var crc = crc_in ^ b;
  var k = 0;
  while k < 8 {
    let lsb = crc % 2;
    crc = crc / 2;
    if lsb == 1 {
      crc = crc ^ 2197175160;
    }
    k = k + 1;
  }
  return crc;
}

/// Raw CRC32C (Castagnoli, reflected polynomial 0x82F63B78, init 0xFFFFFFFF,
/// final xor 0xFFFFFFFF) over [start, start + size) of `data`.
///
/// Matches Go's hash/crc32 with y.CastagnoliCrcTable (crc32.MakeTable(
/// crc32.Castagnoli)), which upstream v1.6.2 uses for value-log entries and
/// manifest records. Returns a u32 as an Int, or -1 when `start`/`size` are
/// negative or the range falls outside `data`. No LevelDB rotation mask is
/// applied. Complexity: O(size).
pub fn badger_crc32c(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  if start < 0 { return -1; }
  if size < 0 { return -1; }
  if start + size > data.len() { return -1; }
  var crc = 4294967295;
  var i = 0;
  while i < size {
    crc = _crc32c_step(crc, _byte(data, start + i));
    i = i + 1;
  }
  return (crc ^ 4294967295) & 4294967295;
}

// --------------------------------------------------
//  Varint readers (protobuf uvarint)
// --------------------------------------------------

// Shared base-128 uvarint reader, at most 10 bytes. `limit` is an exclusive
// byte bound (<= data.len()); callers guarantee pos >= 0. Err codes:
// 1 truncated, 2 overflow (value above the Int range).
fn _uvarint_core(data: &Vec[UInt8], pos: Int, limit: Int) -> Result[BadgerVarint, Int] {
  var value: Int = 0;
  var mult: Int = 1;
  var i = 0;
  while i < 10 {
    if pos + i >= limit { return _err_vc(1); }
    let b = _byte(data, pos + i);
    let cont = b / 128;
    let payload = b % 128;
    if i == 9 {
      if cont == 1 { return _err_vc(2); }
      if payload > 127 { return _err_vc(2); }
      // The 10th byte may only contribute the low bit for a u64; anything
      // that would push the value past 2^63-1 is an overflow for Int.
      if payload > 0 { return _err_vc(2); }
      return _ok_vv(BadgerVarint{ value: value + payload * mult; size: 10; });
    }
    if mult > 0 && payload > (9223372036854775807 - value) / mult {
      return _err_vc(2);
    }
    value = value + payload * mult;
    if cont == 0 {
      return _ok_vv(BadgerVarint{ value: value; size: i + 1; });
    }
    mult = mult * 128;
    i = i + 1;
  }
  return _err_vc(1);
}

// Turn a _uvarint_core status code into "<label>: truncated at <pos>" or
// "<label>: overflow at <pos>".
fn _vmsg(label: Str, code: Int, pos: Int) -> Str {
  if code == 1 { return _at(label + ": truncated", pos); }
  if code == 2 { return _at(label + ": overflow", pos); }
  return _at(label + ": bad input", pos);
}

// --------------------------------------------------
//  Base64 (std encoding, padded) over a byte span
// --------------------------------------------------

// Base64 alphabet value of byte `b`, or -1.
fn _b64_val(b: Int) -> Int {
  if b >= 65 && b <= 90 { return b - 65; }
  if b >= 97 && b <= 122 { return b - 97 + 26; }
  if b >= 48 && b <= 57 { return b - 48 + 52; }
  if b == 43 { return 62; }
  if b == 47 { return 63; }
  return -1;
}

// Decode standard padded base64 over [off, off + size); size must be a
// multiple of 4 (Go's encoding/json emits exactly that for []byte fields).
fn _b64_span(data: &Vec[UInt8], off: Int, size: Int) -> Result[Vec[UInt8], Str] {
  if size % 4 != 0 {
    return _err_bytes(_at("bloom filter set: bad base64 length", off));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    let c0 = _b64_val(_byte(data, off + i));
    let c1 = _b64_val(_byte(data, off + i + 1));
    if c0 < 0 { return _err_bytes(_at("bloom filter set: bad base64 char", off + i)); }
    if c1 < 0 { return _err_bytes(_at("bloom filter set: bad base64 char", off + i + 1)); }
    out.push(((c0 * 4 + c1 / 16) & 255) as UInt8);
    let b2 = _byte(data, off + i + 2);
    if b2 == 61 {
      if i + 4 != size { return _err_bytes(_at("bloom filter set: bad base64 padding", off + i + 2)); }
      return _ok_bytes(out);
    }
    let c2 = _b64_val(b2);
    if c2 < 0 { return _err_bytes(_at("bloom filter set: bad base64 char", off + i + 2)); }
    out.push((((c1 % 16) * 16 + c2 / 4) & 255) as UInt8);
    let b3 = _byte(data, off + i + 3);
    if b3 == 61 {
      if i + 4 != size { return _err_bytes(_at("bloom filter set: bad base64 padding", off + i + 3)); }
      return _ok_bytes(out);
    }
    let c3 = _b64_val(b3);
    if c3 < 0 { return _err_bytes(_at("bloom filter set: bad base64 char", off + i + 3)); }
    out.push((((c2 % 4) * 64 + c3) & 255) as UInt8);
    i = i + 4;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  SHA-256 (whole-table checksum, table/table.go loadToRAM)
// --------------------------------------------------

// Rotate right a 32-bit word held in an Int.
fn _sha_rotr(x: Int, n: Int) -> Int {
  let a = x >> n;
  let b = x << (32 - n);
  return (a | b) & 4294967295;
}

// SHA-256 Ch(e, f, g).
fn _sha_ch(e: Int, f: Int, g: Int) -> Int {
  let a = e & f;
  let b = (4294967295 - e) & g;
  return a ^ b;
}

// SHA-256 Maj(a, b, c).
fn _sha_maj(a: Int, b: Int, c: Int) -> Int {
  let x = a & b;
  let y = a & c;
  let z = b & c;
  return x ^ y ^ z;
}

// SHA-256 big sigma 0.
fn _sha_bs0(x: Int) -> Int {
  return _sha_rotr(x, 2) ^ _sha_rotr(x, 13) ^ _sha_rotr(x, 22);
}

// SHA-256 big sigma 1.
fn _sha_bs1(x: Int) -> Int {
  return _sha_rotr(x, 6) ^ _sha_rotr(x, 11) ^ _sha_rotr(x, 25);
}

// SHA-256 small sigma 0.
fn _sha_ss0(x: Int) -> Int {
  let a = _sha_rotr(x, 7);
  let b = _sha_rotr(x, 18);
  let c = x >> 3;
  return a ^ b ^ c;
}

// SHA-256 small sigma 1.
fn _sha_ss1(x: Int) -> Int {
  let a = _sha_rotr(x, 17);
  let b = _sha_rotr(x, 19);
  let c = x >> 10;
  return a ^ b ^ c;
}

// The 64 SHA-256 round constants (FIPS 180-4 section 4.2.2), generated from
// the fractional parts of the cube roots of the first 64 primes.
fn _sha256_k() -> Vec[Int] {
  var k = Vec[Int].new();
  k.push(1116352408); k.push(1899447441); k.push(3049323471); k.push(3921009573);
  k.push(961987163); k.push(1508970993); k.push(2453635748); k.push(2870763221);
  k.push(3624381080); k.push(310598401); k.push(607225278); k.push(1426881987);
  k.push(1925078388); k.push(2162078206); k.push(2614888103); k.push(3248222580);
  k.push(3835390401); k.push(4022224774); k.push(264347078); k.push(604807628);
  k.push(770255983); k.push(1249150122); k.push(1555081692); k.push(1996064986);
  k.push(2554220882); k.push(2821834349); k.push(2952996808); k.push(3210313671);
  k.push(3336571891); k.push(3584528711); k.push(113926993); k.push(338241895);
  k.push(666307205); k.push(773529912); k.push(1294757372); k.push(1396182291);
  k.push(1695183700); k.push(1986661051); k.push(2177026350); k.push(2456956037);
  k.push(2730485921); k.push(2820302411); k.push(3259730800); k.push(3345764771);
  k.push(3516065817); k.push(3600352804); k.push(4094571909); k.push(275423344);
  k.push(430227734); k.push(506948616); k.push(659060556); k.push(883997877);
  k.push(958139571); k.push(1322822218); k.push(1537002063); k.push(1747873779);
  k.push(1955562222); k.push(2024104815); k.push(2227730452); k.push(2361852424);
  k.push(2428436474); k.push(2756734187); k.push(3204031479); k.push(3329325298);
  return k;
}

// SHA-256 of a byte buffer, returned as 32 bytes. Local pure-XIOM
// implementation: the stdlib sha256 in this toolchain links against a native
// symbol (xiom_sha256_hash) that is not provided by the pinned v0.61.3
// compiler, so the module carries its own verified implementation instead.
fn _sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  var padded = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    let b: UInt8 = data[i];
    padded.push(b);
    i = i + 1;
  }
  padded.push(128);
  while (padded.len() % 64) != 56 {
    padded.push(0);
  }
  let bitlen = data.len() * 8;
  var sh = 56;
  while sh >= 0 {
    let v = (bitlen >> sh) & 255;
    padded.push(v as UInt8);
    sh = sh - 8;
  }
  var h0 = 1779033703; var h1 = 3144134277; var h2 = 1013904242; var h3 = 2773480762;
  var h4 = 1359893119; var h5 = 2600822924; var h6 = 528734635; var h7 = 1541459225;
  let k = _sha256_k();
  var chunk = 0;
  while chunk < padded.len() {
    var w = Vec[Int].new();
    var j = 0;
    while j < 16 {
      let o = chunk + j * 4;
      let b0: Int = (padded[o] as Int) & 255;
      let b1: Int = (padded[o + 1] as Int) & 255;
      let b2: Int = (padded[o + 2] as Int) & 255;
      let b3: Int = (padded[o + 3] as Int) & 255;
      w.push(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3);
      j = j + 1;
    }
    var j2 = 16;
    while j2 < 64 {
      let w15: Int = w[j2 - 15];
      let w7: Int = w[j2 - 7];
      let w16: Int = w[j2 - 16];
      let w2: Int = w[j2 - 2];
      let s0 = _sha_ss0(w15);
      let s1 = _sha_ss1(w2);
      let v = w16 + s0 + w7 + s1;
      w.push(v & 4294967295);
      j2 = j2 + 1;
    }
    var a = h0; var b = h1; var c = h2; var d = h3;
    var e = h4; var f = h5; var g = h6; var h = h7;
    var r = 0;
    while r < 64 {
      let s1 = _sha_bs1(e);
      let ch_efg = _sha_ch(e, f, g);
      let kv: Int = k[r];
      let wv: Int = w[r];
      let t1 = (h + s1 + ch_efg + kv + wv) & 4294967295;
      let s0 = _sha_bs0(a);
      let mj = _sha_maj(a, b, c);
      let t2 = (s0 + mj) & 4294967295;
      let new_e = (d + t1) & 4294967295;
      let new_a = (t1 + t2) & 4294967295;
      h = g;
      g = f;
      f = e;
      e = new_e;
      d = c;
      c = b;
      b = a;
      a = new_a;
      r = r + 1;
    }
    h0 = (h0 + a) & 4294967295;
    h1 = (h1 + b) & 4294967295;
    h2 = (h2 + c) & 4294967295;
    h3 = (h3 + d) & 4294967295;
    h4 = (h4 + e) & 4294967295;
    h5 = (h5 + f) & 4294967295;
    h6 = (h6 + g) & 4294967295;
    h7 = (h7 + h) & 4294967295;
    chunk = chunk + 64;
  }
  var out = Vec[UInt8].new();
  out.push(((h0 >> 24) & 255) as UInt8); out.push(((h0 >> 16) & 255) as UInt8);
  out.push(((h0 >> 8) & 255) as UInt8); out.push((h0 & 255) as UInt8);
  out.push(((h1 >> 24) & 255) as UInt8); out.push(((h1 >> 16) & 255) as UInt8);
  out.push(((h1 >> 8) & 255) as UInt8); out.push((h1 & 255) as UInt8);
  out.push(((h2 >> 24) & 255) as UInt8); out.push(((h2 >> 16) & 255) as UInt8);
  out.push(((h2 >> 8) & 255) as UInt8); out.push((h2 & 255) as UInt8);
  out.push(((h3 >> 24) & 255) as UInt8); out.push(((h3 >> 16) & 255) as UInt8);
  out.push(((h3 >> 8) & 255) as UInt8); out.push((h3 & 255) as UInt8);
  out.push(((h4 >> 24) & 255) as UInt8); out.push(((h4 >> 16) & 255) as UInt8);
  out.push(((h4 >> 8) & 255) as UInt8); out.push((h4 & 255) as UInt8);
  out.push(((h5 >> 24) & 255) as UInt8); out.push(((h5 >> 16) & 255) as UInt8);
  out.push(((h5 >> 8) & 255) as UInt8); out.push((h5 & 255) as UInt8);
  out.push(((h6 >> 24) & 255) as UInt8); out.push(((h6 >> 16) & 255) as UInt8);
  out.push(((h6 >> 8) & 255) as UInt8); out.push((h6 & 255) as UInt8);
  out.push(((h7 >> 24) & 255) as UInt8); out.push(((h7 >> 16) & 255) as UInt8);
  out.push(((h7 >> 8) & 255) as UInt8); out.push((h7 & 255) as UInt8);
  return out;
}

// --------------------------------------------------
//  Value log meta bits
// --------------------------------------------------

/// Name of a single meta bit value: "DELETE" (1), "VALUE_POINTER" (2),
/// "DISCARD_EARLIER_VERSIONS" (4), "MERGE_ENTRY" (8), "TXN" (64), "FIN_TXN"
/// (128), or "" for anything else. Mirrors value.go v1.6.2 lines 46-54.
/// Complexity: O(1).
pub fn badger_meta_bit_name(bit_value: Int) -> Str {
  if bit_value == BADGER_META_DELETE { return "DELETE"; }
  if bit_value == BADGER_META_VALUE_POINTER { return "VALUE_POINTER"; }
  if bit_value == BADGER_META_DISCARD_EARLIER_VERSIONS { return "DISCARD_EARLIER_VERSIONS"; }
  if bit_value == BADGER_META_MERGE_ENTRY { return "MERGE_ENTRY"; }
  if bit_value == BADGER_META_TXN { return "TXN"; }
  if bit_value == BADGER_META_FIN_TXN { return "FIN_TXN"; }
  return "";
}

/// True when the meta byte has `bit_value` set; false for non-positive bit
/// values. Complexity: O(1).
pub fn badger_meta_has(meta: Int, bit_value: Int) -> Bool {
  return _bit_set(meta, bit_value);
}

/// True when every set bit of `meta` is one of the six defined bits (i.e.
/// meta is a subset of BADGER_META_DEFINED); false for negative bytes.
/// Complexity: O(1).
pub fn badger_meta_known(meta: Int) -> Bool {
  if meta < 0 { return false; }
  return (meta & BADGER_META_DEFINED) == meta;
}

/// A "|"-joined list of the defined meta bit names set in `meta`, in bit
/// order; "" when no defined bit is set. Complexity: O(1).
pub fn badger_meta_names(meta: Int) -> Str {
  var out = "";
  var first = true;
  if _bit_set(meta, BADGER_META_DELETE) {
    out = "DELETE";
    first = false;
  }
  if _bit_set(meta, BADGER_META_VALUE_POINTER) {
    if first {
      out = "VALUE_POINTER";
      first = false;
    } else {
      out = out + "|VALUE_POINTER";
    }
  }
  if _bit_set(meta, BADGER_META_DISCARD_EARLIER_VERSIONS) {
    if first {
      out = "DISCARD_EARLIER_VERSIONS";
      first = false;
    } else {
      out = out + "|DISCARD_EARLIER_VERSIONS";
    }
  }
  if _bit_set(meta, BADGER_META_MERGE_ENTRY) {
    if first {
      out = "MERGE_ENTRY";
      first = false;
    } else {
      out = out + "|MERGE_ENTRY";
    }
  }
  if _bit_set(meta, BADGER_META_TXN) {
    if first {
      out = "TXN";
      first = false;
    } else {
      out = out + "|TXN";
    }
  }
  if _bit_set(meta, BADGER_META_FIN_TXN) {
    if first {
      out = "FIN_TXN";
      first = false;
    } else {
      out = out + "|FIN_TXN";
    }
  }
  return out;
}

/// Decimal parse of an unsigned 64-bit value over [off, off + size).
///
/// Mirrors strconv.ParseUint(v, 10, 64) for the value-log transaction
/// terminator: at least one digit, every byte in '0'..'9', and a value that
/// fits the Int range. Errors carry the offending offset.
fn _u64_from_digits(data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if size <= 0 {
    return _err_int(_at("txn terminator: empty value", off));
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b = _byte(data, off + i);
    if b < 48 || b > 57 {
      return _err_int(_at("txn terminator: not decimal", off + i));
    }
    let d = b - 48;
    if v > (9223372036854775807 - d) / 10 {
      return _err_int(_at("txn terminator: overflow", off));
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  Value log entries
// --------------------------------------------------

/// Parse the 18-byte value log entry header at `off` (v1.6.2 structs.go:
/// klen u32 BE, vlen u32 BE, expiresAt u64 BE, meta byte, userMeta byte).
///
/// A key length above BADGER_VLOG_KEY_LEN_MAX (65536, the upstream bound at
/// value.go safeRead.Entry) or a value length above BADGER_VLOG_ENTRY_CAP
/// (local 1 MiB guard) is rejected before any span arithmetic.
///
/// Errors: "badger: vlog header out of bounds at <off>", "badger: vlog
/// header truncated at <off>", "badger: vlog key length exceeds upstream
/// bound at <off>", "badger: vlog value length exceeds cap at <off + 4>".
/// Complexity: O(1).
pub fn badger_parse_vlog_header(data: &Vec[UInt8], off: Int) -> Result[BadgerVlogHeader, Str] {
  if off < 0 {
    return _err_vh(_at("vlog header out of bounds", 0));
  }
  if off > data.len() || BADGER_VLOG_HEADER_SIZE > data.len() - off {
    return _err_vh(_at("vlog header truncated", off));
  }
  let key_len = _rbe(data, off, 4);
  let val_len = _rbe(data, off + 4, 4);
  if key_len > BADGER_VLOG_KEY_LEN_MAX {
    return _err_vh(_at("vlog key length exceeds upstream bound", off));
  }
  if val_len > BADGER_VLOG_ENTRY_CAP {
    return _err_vh(_at("vlog value length exceeds cap", off + 4));
  }
  return _ok_vh(BadgerVlogHeader{
    key_len: key_len;
    val_len: val_len;
    expires_at: _rbe(data, off + 8, 8);
    meta: _byte(data, off + 16);
    user_meta: _byte(data, off + 17);
  });
}

/// Total byte size of the entry described by `h`:
/// 18 (header) + keyLen + valLen + 4 (CRC32C), per value.go safeRead.Entry
/// (vp.Len = headerBufSize + len(key) + len(value) + crc32.Size).
/// Complexity: O(1).
pub fn badger_vlog_entry_total(h: &BadgerVlogHeader) -> Int {
  let k: Int = h.key_len;
  let v: Int = h.val_len;
  return BADGER_VLOG_HEADER_SIZE + k + v + BADGER_VLOG_CRC_SIZE;
}

/// CRC32C stored at the end of the entry at `off`, and a check against the
/// freshly computed CRC32C of header+key+value (structs.go encodeEntry:
/// the hash covers the header, key and value, and is written big-endian).
///
/// Errors mirror badger_parse_vlog_header plus "badger: vlog entry truncated
/// at <off>". Complexity: O(entry size).
pub fn badger_vlog_entry_crc(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 {
    return _err_int(_at("vlog entry out of bounds", 0));
  }
  let hr = badger_parse_vlog_header(data, off);
  if !hr.is_ok {
    return _err_int(hr.error);
  }
  let h = hr.value;
  let total: Int = badger_vlog_entry_total(&h);
  if off > data.len() || total > data.len() - off {
    return _err_int(_at("vlog entry truncated", off));
  }
  let crc_off = off + total - BADGER_VLOG_CRC_SIZE;
  return _ok_int(_rbe(data, crc_off, 4));
}

/// True when the stored CRC32C trailer of the entry at `off` matches the
/// CRC32C of header+key+value. Errors mirror badger_vlog_entry_crc.
/// Complexity: O(entry size).
pub fn badger_vlog_entry_crc_ok(data: &Vec[UInt8], off: Int) -> Result[Bool, Str] {
  if off < 0 {
    return _err_bool(_at("vlog entry out of bounds", 0));
  }
  let hr = badger_parse_vlog_header(data, off);
  if !hr.is_ok {
    return _err_bool(hr.error);
  }
  let h = hr.value;
  let body: Int = BADGER_VLOG_HEADER_SIZE + h.key_len + h.val_len;
  let total: Int = body + BADGER_VLOG_CRC_SIZE;
  if off > data.len() || total > data.len() - off {
    return _err_bool(_at("vlog entry truncated", off));
  }
  let computed = badger_crc32c(data, off, body);
  let stored = _rbe(data, off + body, 4);
  return _ok_bool(computed == stored);
}

/// Walk consecutive value log entries over [off, limit).
///
/// Every entry is structurally validated and its CRC32C must match. Stops
/// exactly at `limit`; a partial header (fewer than 18 bytes left) is an
/// error, so a walk never silently drops trailing bytes. Every entry must
/// fit inside `limit`, its total size must stay within
/// BADGER_VLOG_ENTRY_CAP (local guard), and at most `max_entries` entries
/// are accepted (pass a positive bound).
///
/// Upstream value.go iterate() silently truncates at the first bad entry;
/// this parser reports it instead (documented deviation).
///
/// Errors: "badger: vlog walk start out of bounds at 0", "badger: vlog walk
/// limit out of bounds at <limit>", "badger: vlog walk limit before start at
/// <limit>", "badger: vlog walk max entries must be positive at <off>",
/// "badger: vlog walk trailing bytes at <pos>", "badger: vlog entry exceeds
/// cap at <pos>", "badger: vlog entry crc mismatch at <pos>", "badger: vlog
/// walk exceeds max entries at <pos>", plus any header-parse error.
/// Complexity: O(bytes walked).
pub fn badger_vlog_walk(data: &Vec[UInt8], off: Int, limit: Int, max_entries: Int) -> Result[BadgerVlogWalk, Str] {
  if off < 0 {
    return _err_vwalk(_at("vlog walk start out of bounds", 0));
  }
  if limit > data.len() {
    return _err_vwalk(_at("vlog walk limit out of bounds", limit));
  }
  if limit < off {
    return _err_vwalk(_at("vlog walk limit before start", limit));
  }
  if max_entries <= 0 {
    return _err_vwalk(_at("vlog walk max entries must be positive", off));
  }
  var offsets = Vec[Int].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var metas = Vec[Int].new();
  var user_metas = Vec[Int].new();
  var expires = Vec[Int].new();
  var crcs = Vec[Int].new();
  var pos = off;
  var total: Int = 0;
  while pos < limit {
    if limit - pos < BADGER_VLOG_HEADER_SIZE {
      return _err_vwalk(_at("vlog walk trailing bytes", pos));
    }
    let hr = badger_parse_vlog_header(data, pos);
    if !hr.is_ok {
      return _err_vwalk(hr.error);
    }
    let h = hr.value;
    let klen: Int = h.key_len;
    let vlen: Int = h.val_len;
    let body: Int = BADGER_VLOG_HEADER_SIZE + klen + vlen;
    let eb: Int = body + BADGER_VLOG_CRC_SIZE;
    if eb > BADGER_VLOG_ENTRY_CAP {
      return _err_vwalk(_at("vlog entry exceeds cap", pos));
    }
    if eb > limit - pos {
      return _err_vwalk(_at("vlog entry truncated", pos));
    }
    let computed = badger_crc32c(data, pos, body);
    let stored = _rbe(data, pos + body, 4);
    if computed != stored {
      return _err_vwalk(_at("vlog entry crc mismatch", pos));
    }
    if offsets.len() >= max_entries {
      return _err_vwalk(_at("vlog walk exceeds max entries", pos));
    }
    offsets.push(pos);
    key_offsets.push(pos + BADGER_VLOG_HEADER_SIZE);
    key_sizes.push(klen);
    value_offsets.push(pos + BADGER_VLOG_HEADER_SIZE + klen);
    value_sizes.push(vlen);
    metas.push(h.meta);
    user_metas.push(h.user_meta);
    expires.push(h.expires_at);
    crcs.push(stored);
    total = total + eb;
    pos = pos + eb;
  }
  return _ok_vwalk(BadgerVlogWalk{
    count: offsets.len();
    offsets: offsets;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    metas: metas;
    user_metas: user_metas;
    expires: expires;
    crcs: crcs;
    total_bytes: total;
  });
}

/// Number of entries in a value log walk. Complexity: O(1).
pub fn badger_vlog_count(w: &BadgerVlogWalk) -> Int {
  return w.count;
}

/// Field `field` (one of the BADGER_VLOG_FIELD_* selectors) of entry `i`, or
/// Err("badger: vlog field index out of range at <i>") when `i` is outside
/// [0, count) or the selector is unknown.
/// Complexity: O(1).
pub fn badger_vlog_field(w: &BadgerVlogWalk, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= w.count {
    return _err_int(_at("vlog field index out of range", i));
  }
  if field == BADGER_VLOG_FIELD_OFFSET {
    let v: Int = w.offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_KEY_OFFSET {
    let v: Int = w.key_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_KEY_SIZE {
    let v: Int = w.key_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_VALUE_OFFSET {
    let v: Int = w.value_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_VALUE_SIZE {
    let v: Int = w.value_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_META {
    let v: Int = w.metas[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_USER_META {
    let v: Int = w.user_metas[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_EXPIRES_AT {
    let v: Int = w.expires[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_CRC {
    let v: Int = w.crcs[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_COUNT {
    return _ok_int(w.count);
  }
  return _err_int(_at("vlog field index out of range", i));
}

/// Key bytes of walk entry `i` copied out of `data`, or an empty Vec when `i`
/// is out of range. Complexity: O(key length).
pub fn badger_vlog_key_bytes(data: &Vec[UInt8], w: &BadgerVlogWalk, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let ko: Int = w.key_offsets[i];
  let ks: Int = w.key_sizes[i];
  return _copy_range(data, ko, ks);
}

/// Value bytes of walk entry `i` copied out of `data`, or an empty Vec when
/// `i` is out of range. Complexity: O(value length).
pub fn badger_vlog_value_bytes(data: &Vec[UInt8], w: &BadgerVlogWalk, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let vo: Int = w.value_offsets[i];
  let vs: Int = w.value_sizes[i];
  return _copy_range(data, vo, vs);
}

/// Replay the upstream v1.6.2 transaction grouping over a walk
/// (value.go iterate lines 290-345).
///
/// Rules: entries with bitTxn must all carry the same key timestamp; the
/// group is committed by a bitFinTxn entry whose value is that timestamp in
/// decimal; a plain entry encountered while a group is open stops the
/// replay; an open group at the end leaves the last group(s) uncommitted.
/// `valid_entries` is the committed prefix, `groups` the number of closed
/// groups, `closed` whether the walk ends on a boundary, and `reason` is ""
/// or a short description of where upstream would stop.
/// Complexity: O(entries + key/value bytes scanned).
pub fn badger_vlog_txn_prefix(data: &Vec[UInt8], w: &BadgerVlogWalk) -> BadgerVlogTxn {
  var last_commit: Int = 0;
  var valid: Int = 0;
  var groups: Int = 0;
  var closed = false;
  var reason = "";
  var stop = false;
  var i = 0;
  while i < w.count && !stop {
    let meta: Int = w.metas[i];
    if _bit_set(meta, BADGER_META_TXN) {
      let ko: Int = w.key_offsets[i];
      let ks: Int = w.key_sizes[i];
      var ts: Int = 0;
      if ks > BADGER_KEY_TAG_SIZE {
        let tagged = _rbe(data, ko + ks - BADGER_KEY_TAG_SIZE, 8);
        ts = (0 - 1) - tagged;
      }
      if last_commit == 0 {
        last_commit = ts;
      }
      if last_commit != ts {
        reason = "txn timestamp mismatch";
        stop = true;
      }
    } elif _bit_set(meta, BADGER_META_FIN_TXN) {
      let vo: Int = w.value_offsets[i];
      let vs: Int = w.value_sizes[i];
      let pr = _u64_from_digits(data, vo, vs);
      if !pr.is_ok {
        reason = pr.error;
        stop = true;
      } else {
        let txn_ts: Int = pr.value;
        if last_commit == 0 || last_commit != txn_ts {
          reason = "txn terminator without matching group";
          stop = true;
        } else {
          last_commit = 0;
          groups = groups + 1;
          valid = i + 1;
        }
      }
    } else {
      if last_commit != 0 {
        reason = "plain entry inside txn group";
        stop = true;
      } else {
        valid = i + 1;
      }
    }
    i = i + 1;
  }
  if !stop {
    if last_commit == 0 {
      closed = true;
    } else {
      reason = "unclosed txn group";
    }
  }
  return BadgerVlogTxn{
    valid_entries: valid;
    groups: groups;
    closed: closed;
    reason: reason;
  };
}

/// Decode a 12-byte value pointer (structs.go valuePointer: fid, len, offset
/// as u32 big-endian, in that order).
///
/// Errors: "badger: value pointer out of bounds at 0", "badger: value
/// pointer truncated at <off>". Complexity: O(1).
pub fn badger_value_pointer_decode(data: &Vec[UInt8], off: Int) -> Result[BadgerValuePointer, Str] {
  if off < 0 {
    return _err_vp(_at("value pointer out of bounds", 0));
  }
  if off > data.len() || BADGER_VALUE_POINTER_SIZE > data.len() - off {
    return _err_vp(_at("value pointer truncated", off));
  }
  return _ok_vp(BadgerValuePointer{
    fid: _rbe(data, off, 4);
    len: _rbe(data, off + 4, 4);
    offset: _rbe(data, off + 8, 4);
  });
}

// --------------------------------------------------
//  Versioned keys
// --------------------------------------------------

/// Decode a versioned key spanning `size` (> 8) bytes at `off`.
///
/// Layout per y/y.go KeyWithTs: user key bytes followed by the 8-byte
/// big-endian pattern `MaxUint64 - ts`. `version` is that pattern subtracted
/// from MaxUint64 modulo 2^64 (i.e. the timestamp). There is no delete bit
/// in the key: the delete marker is meta bit BADGER_META_DELETE
/// (structs.go Entry.meta, txn.go Delete).
///
/// Errors: "badger: key shorter than version tag at <off>", "badger: key
/// span out of bounds at <off>". Complexity: O(1).
pub fn badger_key_decode(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerKey, Str] {
  if off < 0 {
    return _err_key(_at("key span out of bounds", 0));
  }
  if size <= BADGER_KEY_TAG_SIZE {
    return _err_key(_at("key shorter than version tag", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_key(_at("key span out of bounds", off));
  }
  let tag_off = off + size - BADGER_KEY_TAG_SIZE;
  let tagged = _rbe(data, tag_off, 8);
  let version = (0 - 1) - tagged;
  return _ok_key(BadgerKey{
    user_offset: off;
    user_size: size - BADGER_KEY_TAG_SIZE;
    tagged: tagged;
    version: version;
  });
}

/// Parse the timestamp of a versioned key spanning `size` bytes at `off`,
/// mirroring y.ParseTs exactly: 0 when size <= 8, else
/// `MaxUint64 - BE64(key[size-8..])` modulo 2^64.
/// Complexity: O(1).
pub fn badger_key_parse_ts(data: &Vec[UInt8], off: Int, size: Int) -> Int {
  if size <= BADGER_KEY_TAG_SIZE {
    return 0;
  }
  if off < 0 {
    return 0;
  }
  if off > data.len() || size > data.len() - off {
    return 0;
  }
  let tagged = _rbe(data, off + size - BADGER_KEY_TAG_SIZE, 8);
  return (0 - 1) - tagged;
}

/// Timestamp of a decoded key (MaxUint64 - suffix, modulo 2^64).
/// Complexity: O(1).
pub fn badger_key_version(k: &BadgerKey) -> Int {
  return k.version;
}

/// Raw 8-byte suffix pattern of a decoded key, as a two's-complement Int.
/// Complexity: O(1).
pub fn badger_key_tagged(k: &BadgerKey) -> Int {
  return k.tagged;
}

/// User-key byte length of a decoded key. Complexity: O(1).
pub fn badger_key_user_size(k: &BadgerKey) -> Int {
  return k.user_size;
}

/// User-key bytes of a decoded key copied out of `data`; empty when the span
/// is invalid. Complexity: O(user key length).
pub fn badger_key_user_bytes(data: &Vec[UInt8], k: &BadgerKey) -> Vec[UInt8] {
  if k.user_offset < 0 || k.user_size < 0 {
    return Vec[UInt8].new();
  }
  if k.user_offset > data.len() || k.user_size > data.len() - k.user_offset {
    return Vec[UInt8].new();
  }
  return _copy_range(data, k.user_offset, k.user_size);
}

// --------------------------------------------------
//  SST ValueStruct and data-block entries
// --------------------------------------------------

/// Decode an SST ValueStruct spanning `size` bytes at `off` (y/iterator.go:
/// meta byte, userMeta byte, uvarint expiresAt, value bytes to the end).
///
/// Errors: "badger: value struct out of bounds at 0", "badger: value struct
/// too short at <off>", "badger: value struct out of bounds at <off>" and
/// "badger: value struct expires: truncated|overflow at <off + 2>".
/// Complexity: O(1).
pub fn badger_sst_value_struct_decode(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerSstValStruct, Str] {
  if off < 0 {
    return _err_vs(_at("value struct out of bounds", 0));
  }
  if size < 3 {
    return _err_vs(_at("value struct too short", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_vs(_at("value struct out of bounds", off));
  }
  let vr = _uvarint_core(data, off + 2, off + size);
  if !vr.is_ok {
    return _err_vs(_vmsg("value struct expires", vr.error, off + 2));
  }
  let vv = vr.value;
  let varint_size: Int = vv.size;
  let value_off = off + 2 + varint_size;
  return _ok_vs(BadgerSstValStruct{
    meta: _byte(data, off);
    user_meta: _byte(data, off + 1);
    expires_at: vv.value;
    value_offset: value_off;
    value_size: size - 2 - varint_size;
    size: size;
  });
}

/// Decode one SST data-block entry at `pos` inside the block body.
///
/// Layout (table/builder.go header): plen u16 BE, klen u16 BE, vlen u16 BE,
/// prev u32 BE, then `klen` key-diff bytes, then `vlen` ValueStruct bytes.
/// `base_key` is the block base key (the first key of the block, empty for
/// the first entry); the reconstructed key is `base_key[:plen]` + diff
/// (table/iterator.go parseKV). `limit` is an exclusive byte bound inside
/// `body`.
///
/// Errors: "badger: sst entry out of bounds at 0", "badger: sst entry limit
/// out of bounds at <limit>", "badger: sst entry header truncated at <pos>",
/// "badger: sst entry prefix exceeds base key at <pos>", "badger: sst entry
/// key truncated at <pos>", "badger: sst entry value truncated at <pos>".
/// Complexity: O(key length).
pub fn badger_parse_sst_block_entry(body: &Vec[UInt8], pos: Int, limit: Int, base_key: &Vec[UInt8]) -> Result[BadgerSstEntry, Str] {
  if pos < 0 {
    return _err_sse(_at("sst entry out of bounds", 0));
  }
  if limit > body.len() {
    return _err_sse(_at("sst entry limit out of bounds", limit));
  }
  if pos > limit || BADGER_SST_ENTRY_HEADER_SIZE > limit - pos {
    return _err_sse(_at("sst entry header truncated", pos));
  }
  let plen = _rbe(body, pos, 2);
  let klen = _rbe(body, pos + 2, 2);
  let vlen = _rbe(body, pos + 4, 2);
  let prev = _rbe(body, pos + 6, 4);
  if plen > base_key.len() {
    return _err_sse(_at("sst entry prefix exceeds base key", pos));
  }
  let key_start = pos + BADGER_SST_ENTRY_HEADER_SIZE;
  if klen > limit - key_start {
    return _err_sse(_at("sst entry key truncated", pos));
  }
  let value_start = key_start + klen;
  if vlen > limit - value_start {
    return _err_sse(_at("sst entry value truncated", pos));
  }
  var key = Vec[UInt8].new();
  var i = 0;
  while i < plen {
    let b: UInt8 = base_key[i];
    key.push(b);
    i = i + 1;
  }
  i = 0;
  while i < klen {
    let b: UInt8 = body[key_start + i];
    key.push(b);
    i = i + 1;
  }
  return _ok_sse(BadgerSstEntry{
    plen: plen;
    klen: klen;
    vlen: vlen;
    prev: prev;
    key_offset: key_start;
    value_offset: value_start;
    entry_bytes: BADGER_SST_ENTRY_HEADER_SIZE + klen + vlen;
    key: key;
  });
}

/// Walk every real entry of one SST data block over [0, limit).
///
/// Entries are read until the dummy terminator written by
/// table/builder.go finishBlock (plen=0 and klen=0) or until `limit`. The
/// terminator is not counted; `end_offset` is its offset (or `limit` when
/// absent, which upstream iteration tolerates as a clean end of data). The
/// first entry must have plen=0; keys are reconstructed against the block
/// base key (the first reconstructed key). Blocks longer than
/// BADGER_SST_MAX_BLOCK_ENTRIES entries are rejected (local guard).
///
/// Errors: "badger: sst block limit out of bounds at <limit>", "badger: sst
/// block first entry prefix nonzero at <pos>", "badger: sst block exceeds
/// max entries at <pos>", plus any entry error.
/// Complexity: O(block size).
pub fn badger_sst_block_walk(body: &Vec[UInt8], limit: Int) -> Result[BadgerSstEntries, Str] {
  if limit < 0 {
    return _err_sse_list(_at("sst block limit out of bounds", 0));
  }
  if limit > body.len() {
    return _err_sse_list(_at("sst block limit out of bounds", limit));
  }
  var key_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var plens = Vec[Int].new();
  var vlens = Vec[Int].new();
  var prevs = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var entry_offsets = Vec[Int].new();
  var base = Vec[UInt8].new();
  var pos = 0;
  var count = 0;
  var end_off = limit;
  var ended = false;
  while pos < limit && !ended {
    if limit - pos < BADGER_SST_ENTRY_HEADER_SIZE {
      return _err_sse_list(_at("sst entry header truncated", pos));
    }
    let plen = _rbe(body, pos, 2);
    let klen = _rbe(body, pos + 2, 2);
    if plen == 0 && klen == 0 {
      end_off = pos;
      ended = true;
    } else {
      if count == 0 && plen != 0 {
        return _err_sse_list(_at("sst block first entry prefix nonzero", pos));
      }
      let er = badger_parse_sst_block_entry(body, pos, limit, &base);
      if !er.is_ok {
        return _err_sse_list(er.error);
      }
      let e = er.value;
      let e_plen: Int = e.plen;
      let e_vlen: Int = e.vlen;
      let e_prev: Int = e.prev;
      let e_ko: Int = e.key_offset;
      let e_ks: Int = e.klen;
      let e_vo: Int = e.value_offset;
      if count == 0 {
        var bi = 0;
        while bi < e.key.len() {
          let b: UInt8 = e.key[bi];
          base.push(b);
          bi = bi + 1;
        }
      }
      var ki = 0;
      key_offsets.push(key_data.len());
      key_sizes.push(e.key.len());
      while ki < e.key.len() {
        let b: UInt8 = e.key[ki];
        key_data.push(b);
        ki = ki + 1;
      }
      plens.push(e_plen);
      vlens.push(e_vlen);
      prevs.push(e_prev);
      value_offsets.push(e_vo);
      value_sizes.push(e_vlen);
      entry_offsets.push(pos);
      count = count + 1;
      if count > BADGER_SST_MAX_BLOCK_ENTRIES {
        return _err_sse_list(_at("sst block exceeds max entries", pos));
      }
      pos = pos + e.entry_bytes;
    }
  }
  return _ok_sse_list(BadgerSstEntries{
    count: count;
    key_data: key_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    plens: plens;
    vlens: vlens;
    prevs: prevs;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    entry_offsets: entry_offsets;
    end_offset: end_off;
  });
}

/// Number of entries in an SST block walk. Complexity: O(1).
pub fn badger_sst_block_count(e: &BadgerSstEntries) -> Int {
  return e.count;
}

/// Field `field` (one of the BADGER_SST_FIELD_* selectors) of block entry
/// `i`, or Err("badger: sst field index out of range at <i>").
/// Complexity: O(1).
pub fn badger_sst_block_field(e: &BadgerSstEntries, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= e.count {
    return _err_int(_at("sst field index out of range", i));
  }
  if field == BADGER_SST_FIELD_ENTRY_OFFSET {
    let v: Int = e.entry_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_KEY_OFFSET {
    let v: Int = e.key_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_KEY_SIZE {
    let v: Int = e.key_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_VALUE_OFFSET {
    let v: Int = e.value_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_VALUE_SIZE {
    let v: Int = e.value_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_PLEN {
    let v: Int = e.plens[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_VLEN {
    let v: Int = e.vlens[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_PREV {
    let v: Int = e.prevs[i];
    return _ok_int(v);
  }
  if field == BADGER_SST_FIELD_COUNT {
    return _ok_int(e.count);
  }
  return _err_int(_at("sst field index out of range", i));
}

/// Reconstructed key of block entry `i`, copied from the walk's key buffer;
/// empty when `i` is out of range. Complexity: O(key length).
pub fn badger_sst_block_key(e: &BadgerSstEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let ko: Int = e.key_offsets[i];
  let ks: Int = e.key_sizes[i];
  return _copy_range(&e.key_data, ko, ks);
}

/// ValueStruct bytes of block entry `i`, copied out of the block body;
/// empty when `i` is out of range. Complexity: O(value size).
pub fn badger_sst_block_value(body: &Vec[UInt8], e: &BadgerSstEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let vo: Int = e.value_offsets[i];
  let vs: Int = e.value_sizes[i];
  return _copy_range(body, vo, vs);
}

/// Offset where the block terminator starts (or the walk limit when the
/// block has no terminator). Complexity: O(1).
pub fn badger_sst_block_entries_end(e: &BadgerSstEntries) -> Int {
  return e.end_offset;
}

// --------------------------------------------------
//  SST block index and file tail
// --------------------------------------------------

/// Parse the v1.6.2 block index over [off, off + size).
///
/// On disk: `count` u32 BE block-end offsets, then one u32 BE count
/// (table/builder.go blockIndex). `size` must be exactly 4*count + 4. Block
/// i spans [start(i), block_ends[i]) with start(0)=0 and
/// start(i)=block_ends[i-1]. Offsets must be monotonic.
///
/// Errors: "badger: sst index out of bounds at 0", "badger: sst index too
/// short at <off>", "badger: sst index out of bounds at <off>", "badger: sst
/// index count exceeds cap at <off + size - 4>", "badger: sst index size
/// mismatch at <off>", "badger: sst index block offsets not monotonic at
/// <off + 4*i>".
/// Complexity: O(count).
pub fn badger_sst_index_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerSstIndex, Str] {
  if off < 0 {
    return _err_idx(_at("sst index out of bounds", 0));
  }
  if size < 4 {
    return _err_idx(_at("sst index too short", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_idx(_at("sst index out of bounds", off));
  }
  let count = _rbe(data, off + size - 4, 4);
  if count > BADGER_SST_MAX_INDEX_BLOCKS {
    return _err_idx(_at("sst index count exceeds cap", off + size - 4));
  }
  if size != 4 * count + 4 {
    return _err_idx(_at("sst index size mismatch", off));
  }
  var block_ends = Vec[Int].new();
  var prev: Int = 0;
  var i = 0;
  while i < count {
    let v = _rbe(data, off + 4 * i, 4);
    if i > 0 && v < prev {
      return _err_idx(_at("sst index block offsets not monotonic", off + 4 * i));
    }
    block_ends.push(v);
    prev = v;
    i = i + 1;
  }
  return _ok_idx(BadgerSstIndex{
    count: count;
    block_ends: block_ends;
    offset: off;
    size: size;
  });
}

/// Number of blocks in a parsed index. Complexity: O(1).
pub fn badger_sst_index_count(ix: &BadgerSstIndex) -> Int {
  return ix.count;
}

/// End offset (exclusive) of block `i`, or Err("badger: sst index block out
/// of range at <i>"). Complexity: O(1).
pub fn badger_sst_index_block_end(ix: &BadgerSstIndex, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= ix.count {
    return _err_int(_at("sst index block out of range", i));
  }
  let v: Int = ix.block_ends[i];
  return _ok_int(v);
}

/// Start offset of block `i` (0 for block 0, else the previous end), or
/// Err("badger: sst index block out of range at <i>").
/// Complexity: O(1).
pub fn badger_sst_index_block_start(ix: &BadgerSstIndex, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= ix.count {
    return _err_int(_at("sst index block out of range", i));
  }
  if i == 0 {
    return _ok_int(0);
  }
  let v: Int = ix.block_ends[i - 1];
  return _ok_int(v);
}

/// Byte length of block `i`, or Err("badger: sst index block out of range at
/// <i>"). Complexity: O(1).
pub fn badger_sst_index_block_size(ix: &BadgerSstIndex, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= ix.count {
    return _err_int(_at("sst index block out of range", i));
  }
  let end: Int = ix.block_ends[i];
  if i == 0 {
    return _ok_int(end);
  }
  let start: Int = ix.block_ends[i - 1];
  return _ok_int(end - start);
}

/// Parse the tail of a complete v1.6.2 SST file (table/table.go readIndex).
///
/// v1.6.2 has NO table header and NO footer. The file is: data blocks, the
/// block index (4*count + 4 bytes), the bbloom JSON bytes, then a u32 BE
/// bloom length as the very last field. This function reads backwards from
/// the end and returns both handles plus the index block count. The bloom
/// JSON and the index are validated structurally by their own parsers.
///
/// Errors: "badger: sst file too short for tail at 0", "badger: sst bloom
/// length out of bounds at <len - 4>", "badger: sst index count exceeds cap
/// at <off>", "badger: sst index out of bounds at <off>".
/// Complexity: O(1).
pub fn badger_sst_tail_parse(data: &Vec[UInt8]) -> Result[BadgerSstTail, Str] {
  let n = data.len();
  if n < 8 {
    return _err_tail(_at("sst file too short for tail", 0));
  }
  let bloom_len = _rbe(data, n - 4, 4);
  if bloom_len > n - 8 {
    return _err_tail(_at("sst bloom length out of bounds", n - 4));
  }
  let bloom_off = n - 4 - bloom_len;
  if bloom_off < 4 {
    return _err_tail(_at("sst bloom length out of bounds", n - 4));
  }
  let count = _rbe(data, bloom_off - 4, 4);
  if count > BADGER_SST_MAX_INDEX_BLOCKS {
    return _err_tail(_at("sst index count exceeds cap", bloom_off - 4));
  }
  let index_size = 4 * count + 4;
  if index_size > bloom_off {
    return _err_tail(_at("sst index out of bounds", bloom_off - 4));
  }
  return _ok_tail(BadgerSstTail{
    file_size: n;
    index_offset: bloom_off - index_size;
    index_size: index_size;
    index_count: count;
    bloom_offset: bloom_off;
    bloom_size: bloom_len;
  });
}

// --------------------------------------------------
//  Bloom filter (bbloom JSON envelope)
// --------------------------------------------------

/// Parse the bbloom JSON envelope over [off, off + size).
///
/// The envelope is Go's encoding/json output for
/// `bloomJSONImExport{FilterSet []byte, SetLocs uint64}`, i.e.
/// `{"FilterSet":"<base64>","SetLocs":N}`; the FilterSet base64 decodes to
/// `size/8` bytes of little-endian 64-bit words. `exponent` is log2 of the
/// bit count (8*byte_count), so the probe mask is 2^exponent - 1 and a bit
/// index maps to byte idx/8, bit idx%8.
///
/// Errors: "badger: bloom filter out of bounds at 0", "badger: bloom filter
/// set missing at <off>", "badger: bloom filter set unterminated at <pos>",
/// "badger: bloom set locs missing at <pos>", "badger: bloom set locs out of
/// range at <pos>", "badger: bloom filter set too small at <pos>", "badger:
/// bloom filter set size not a power of two at <pos>", plus base64 errors.
/// Complexity: O(filter set size).
pub fn badger_bloom_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerBloom, Str] {
  if off < 0 {
    return _err_bloom(_at("bloom filter out of bounds", 0));
  }
  if off > data.len() || size > data.len() - off {
    return _err_bloom(_at("bloom filter out of bounds", off));
  }
  let limit = off + size;
  let fs = _find_literal(data, off, limit, "\"FilterSet\":\"");
  if fs < 0 {
    return _err_bloom(_at("bloom filter set missing", off));
  }
  let b64_off = fs + 13;
  let close = _find_literal(data, b64_off, limit, "\"");
  if close < 0 {
    return _err_bloom(_at("bloom filter set unterminated", b64_off));
  }
  let b64_size = close - b64_off;
  let br = _b64_span(data, b64_off, b64_size);
  if !br.is_ok {
    return _err_bloom(br.error);
  }
  let bits = br.value;
  if bits.len() < 64 {
    return _err_bloom(_at("bloom filter set too small", b64_off));
  }
  if bits.len() > BADGER_BLOOM_MAX_BYTES {
    return _err_bloom(_at("bloom filter set exceeds cap", b64_off));
  }
  var p: Int = 512;
  var exp: Int = 9;
  let bit_count = bits.len() * 8;
  while p < bit_count {
    p = p * 2;
    exp = exp + 1;
  }
  if p != bit_count {
    return _err_bloom(_at("bloom filter set size not a power of two", b64_off));
  }
  let sl = _find_literal(data, close, limit, "\"SetLocs\":");
  if sl < 0 {
    return _err_bloom(_at("bloom set locs missing", off));
  }
  var locs: Int = 0;
  var digits: Int = 0;
  var i = sl + 10;
  while i < limit {
    let b = _byte(data, i);
    if b < 48 || b > 57 {
      break;
    }
    if locs > 1000 {
      return _err_bloom(_at("bloom set locs out of range", sl + 10));
    }
    locs = locs * 10 + (b - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 || locs <= 0 || locs > 64 {
    return _err_bloom(_at("bloom set locs out of range", sl + 10));
  }
  return _ok_bloom(BadgerBloom{
    set_locs: locs;
    byte_count: bits.len();
    exponent: exp;
    filter_set_offset: b64_off;
    filter_set_size: b64_size;
    text_offset: off;
    text_size: size;
    bits: bits;
  });
}

/// Raw bit test on a parsed bloom filter, mirroring bbloom isSet:
/// `bitset[idx>>6] & (1 << (idx%64)) != 0`, which on the little-endian byte
/// layout written by bbloom JSONMarshal is byte `idx/8`, bit `idx%8`.
///
/// Err("badger: bloom bit index out of range at <idx>") when idx is outside
/// [0, 8*byte_count). Complexity: O(1).
pub fn badger_bloom_bit(b: &BadgerBloom, idx: Int) -> Result[Bool, Str] {
  if idx < 0 || idx >= b.byte_count * 8 {
    return _err_bool(_at("bloom bit index out of range", idx));
  }
  let byte_idx = idx / 8;
  let bit_idx = idx % 8;
  let bv: Int = (b.bits[byte_idx] as Int) & 255;
  return _ok_bool(_bit_set(bv, _pow2(bit_idx)));
}

/// bbloom membership test for the key bytes at [key_off, key_off + key_size)
/// in `data` (bbloom Has: SipHash-2-4 with the fixed key 0xDEADBEAF /
/// 0xFAEBDAED over the key, then probes (h + i*l) & (size-1)).
///
/// This mirrors table.Builder.Finish, which feeds `y.ParseKey(key)` (the
/// user key without the version suffix) into the filter. `key_off`/`key_size`
/// must therefore span the user key, not a versioned full key.
///
/// Errors: "badger: bloom key out of bounds at 0" and "badger: bloom key out
/// of bounds at <key_off>". Complexity: O(key length + set_locs).
pub fn badger_bloom_has(data: &Vec[UInt8], b: &BadgerBloom, key_off: Int, key_size: Int) -> Result[Bool, Str] {
  if key_off < 0 || key_size < 0 {
    return _err_bool(_at("bloom key out of bounds", 0));
  }
  if key_off > data.len() || key_size > data.len() - key_off {
    return _err_bool(_at("bloom key out of bounds", key_off));
  }
  let key = _copy_range(data, key_off, key_size);
  let k0: UInt64 = 3735928495;
  let k1: UInt64 = 4209761005;
  let hash = siphash24(&key, k0, k1);
  let shift: Int = 64 - b.exponent;
  let hi = _u64shr(hash, shift);
  let lo = _u64shr(hash << shift, shift);
  let mask = _u64mask(b.exponent);
  var probe: Int = 0;
  while probe < b.set_locs {
    let idx64: UInt64 = (hi + (probe as UInt64) * lo) & mask;
    let idx: Int = idx64 as Int;
    let byte_idx = idx / 8;
    let bit_idx = idx % 8;
    let bv: Int = (b.bits[byte_idx] as Int) & 255;
    if !_bit_set(bv, _pow2(bit_idx)) {
      return _ok_bool(false);
    }
    probe = probe + 1;
  }
  return _ok_bool(true);
}

// --------------------------------------------------
//  Whole-table SHA-256 checksum (table/table.go loadToRAM)
// --------------------------------------------------

/// SHA-256 of a whole SST file, as v1.6.2 computes it when loading a table
/// (table/table.go loadToRAM: `sha256.Sum256` over the file) and stores it
/// in the MANIFEST for that table id. Pure-XIOM implementation (see
/// _sha256); 32 bytes, same order as the upstream digest.
/// Complexity: O(file size).
pub fn badger_sst_checksum(data: &Vec[UInt8]) -> Vec[UInt8] {
  return _sha256(data);
}

/// Lowercase hex of badger_sst_checksum(data) (64 chars), matching the
/// digest text used in upstream MANIFEST checksum-mismatch messages.
/// Complexity: O(file size).
pub fn badger_sst_checksum_hex(data: &Vec[UInt8]) -> Str {
  let digest = _sha256(data);
  let alpha = "0123456789abcdef";
  var out = "";
  var i = 0;
  while i < digest.len() {
    let b: Int = (digest[i] as Int) & 255;
    let hi = b / 16;
    let lo = b % 16;
    out = out + string.str_slice(alpha, hi, hi + 1);
    out = out + string.str_slice(alpha, lo, lo + 1);
    i = i + 1;
  }
  return out;
}

/// True when badger_sst_checksum(data) equals the 32-byte `expected` digest
/// (e.g. the bytes of a ManifestChange checksum field).
/// Complexity: O(file size).
pub fn badger_sst_checksum_ok(data: &Vec[UInt8], expected: &Vec[UInt8]) -> Bool {
  let digest = _sha256(data);
  if digest.len() != expected.len() {
    return false;
  }
  var i = 0;
  while i < digest.len() {
    let a: UInt8 = digest[i];
    let b: UInt8 = expected[i];
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// The v1.6.2 SST filename for a table id: six zero-padded decimal digits
/// plus ".sst" (table/table.go IDToFilename). Ids are u64 upstream; a
/// negative id has no upstream representation and returns "".
/// Complexity: O(id digits).
pub fn badger_sst_filename(id: Int) -> Str {
  if id < 0 {
    return "";
  }
  var digits = int_to_base(id, 10);
  while digits.len() < 6 {
    digits = "0" + digits;
  }
  return digits + BADGER_SST_FILENAME_SUFFIX;
}

// --------------------------------------------------
//  Manifest
// --------------------------------------------------

/// Parse the v1.6.2 manifest header (8 bytes at offset 0):
/// "Bdgr" (4 bytes, u32 BE 1113876338) then magicVersion u32 BE 4
/// (manifest.go magicText/magicVersion).
///
/// Errors: "badger: manifest header truncated at 0", "badger: manifest bad
/// magic at 0", "badger: manifest unsupported version at 4" (upstream
/// errBadMagic / unsupported-version error).
/// Complexity: O(1).
pub fn badger_manifest_header_parse(data: &Vec[UInt8]) -> Result[BadgerManifestHeader, Str] {
  if data.len() < BADGER_MANIFEST_HEADER_SIZE {
    return _err_mh(_at("manifest header truncated", 0));
  }
  let magic = _rbe(data, 0, 4);
  if magic != BADGER_MANIFEST_MAGIC {
    return _err_mh(_at("manifest bad magic", 0));
  }
  let version = _rbe(data, 4, 4);
  if version != BADGER_MANIFEST_VERSION {
    return _err_mh(_at("manifest unsupported version", 4));
  }
  return _ok_mh(BadgerManifestHeader{ magic: magic; version: version; });
}

/// Parse one manifest record framing at `off`: u32 BE protobuf length, u32
/// BE CRC32C, then the ManifestChangeSet bytes (manifest.go addChanges).
///
/// Errors: "badger: manifest record out of bounds at 0", "badger: manifest
/// record truncated at <off>" when the 8-byte framing or the body is
/// incomplete, and "badger: manifest length exceeds file size at <off>" for
/// the upstream over-allocation guard.
/// Complexity: O(length).
pub fn badger_manifest_record_parse(data: &Vec[UInt8], off: Int) -> Result[BadgerManifestRecord, Str] {
  if off < 0 {
    return _err_mrec(_at("manifest record out of bounds", 0));
  }
  if off > data.len() || 8 > data.len() - off {
    return _err_mrec(_at("manifest record truncated", off));
  }
  let length = _rbe(data, off, 4);
  let crc = _rbe(data, off + 4, 4);
  if length > data.len() {
    return _err_mrec(_at("manifest length exceeds file size", off));
  }
  if length > data.len() - off - 8 {
    return _err_mrec(_at("manifest record truncated", off));
  }
  return _ok_mrec(BadgerManifestRecord{
    length: length;
    crc: crc;
    offset: off;
    body_offset: off + 8;
    consumed: 8 + length;
  });
}

/// Walk every complete manifest record starting at `off`, mirroring
/// ReplayManifestFile: a partial trailing record stops the walk (`truncated`
/// true, `trunc_offset` = offset before it) and a CRC32C mismatch is a hard
/// error. `total_bytes` counts the bytes of the complete records.
///
/// Errors: standard record errors plus "badger: manifest checksum mismatch at
/// <off>", "badger: manifest walk start out of bounds at 0", "badger:
/// manifest walk offset out of bounds at <off>", "badger: manifest walk
/// exceeds max records at <off>".
/// Complexity: O(records).
pub fn badger_manifest_records_parse(data: &Vec[UInt8], off: Int) -> Result[BadgerManifestRecords, Str] {
  if off < 0 {
    return _err_mrecs(_at("manifest walk start out of bounds", 0));
  }
  if off > data.len() {
    return _err_mrecs(_at("manifest walk offset out of bounds", off));
  }
  var lengths = Vec[Int].new();
  var crcs = Vec[Int].new();
  var offsets = Vec[Int].new();
  var body_offsets = Vec[Int].new();
  var pos = off;
  var truncated = false;
  var trunc_off = off;
  var total: Int = 0;
  var stop = false;
  while pos < data.len() && !stop {
    if data.len() - pos < 8 {
      truncated = true;
      trunc_off = pos;
      stop = true;
    } else {
      let length = _rbe(data, pos, 4);
      if length > data.len() {
        return _err_mrecs(_at("manifest length exceeds file size", pos));
      }
      if length > data.len() - pos - 8 {
        truncated = true;
        trunc_off = pos;
        stop = true;
      } else {
        if lengths.len() >= BADGER_MANIFEST_MAX_RECORDS {
          return _err_mrecs(_at("manifest walk exceeds max records", pos));
        }
        let stored = _rbe(data, pos + 4, 4);
        let computed = badger_crc32c(data, pos + 8, length);
        if computed != stored {
          return _err_mrecs(_at("manifest checksum mismatch", pos));
        }
        lengths.push(length);
        crcs.push(stored);
        offsets.push(pos);
        body_offsets.push(pos + 8);
        total = total + 8 + length;
        pos = pos + 8 + length;
      }
    }
  }
  if !truncated {
    trunc_off = pos;
  }
  return _ok_mrecs(BadgerManifestRecords{
    count: lengths.len();
    lengths: lengths;
    crcs: crcs;
    offsets: offsets;
    body_offsets: body_offsets;
    total_bytes: total;
    truncated: truncated;
    trunc_offset: trunc_off;
  });
}

/// Number of records in a manifest walk. Complexity: O(1).
pub fn badger_manifest_record_count(r: &BadgerManifestRecords) -> Int {
  return r.count;
}

/// Field `field` (one of the BADGER_MANIFEST_RECORD_FIELD_* selectors) of
/// record `i`, or Err("badger: manifest record index out of range at <i>").
/// Complexity: O(1).
pub fn badger_manifest_record_field(r: &BadgerManifestRecords, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= r.count {
    return _err_int(_at("manifest record index out of range", i));
  }
  if field == BADGER_MANIFEST_RECORD_FIELD_LENGTH {
    let v: Int = r.lengths[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_RECORD_FIELD_CRC {
    let v: Int = r.crcs[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_RECORD_FIELD_OFFSET {
    let v: Int = r.offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_RECORD_FIELD_BODY_OFFSET {
    let v: Int = r.body_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_RECORD_FIELD_COUNT {
    return _ok_int(r.count);
  }
  return _err_int(_at("manifest record index out of range", i));
}

// Skip one protobuf field at `pos` and return the next position.
fn _proto_skip(data: &Vec[UInt8], pos: Int, limit: Int, wire: Int) -> Result[Int, Str] {
  if wire == BADGER_PROTO_WIRE_VARINT {
    let vr = _uvarint_core(data, pos, limit);
    if !vr.is_ok {
      return _err_int(_vmsg("manifest varint", vr.error, pos));
    }
    let vv = vr.value;
    return _ok_int(pos + vv.size);
  }
  if wire == BADGER_PROTO_WIRE_64BIT {
    if pos > limit || 8 > limit - pos {
      return _err_int(_at("manifest fixed64 truncated", pos));
    }
    return _ok_int(pos + 8);
  }
  if wire == BADGER_PROTO_WIRE_BYTES {
    let vr = _uvarint_core(data, pos, limit);
    if !vr.is_ok {
      return _err_int(_vmsg("manifest length", vr.error, pos));
    }
    let vv = vr.value;
    let next = pos + vv.size;
    if next > limit || vv.value > limit - next {
      return _err_int(_at("manifest length-delimited field truncated", pos));
    }
    return _ok_int(next + vv.value);
  }
  if wire == BADGER_PROTO_WIRE_32BIT {
    if pos > limit || 4 > limit - pos {
      return _err_int(_at("manifest fixed32 truncated", pos));
    }
    return _ok_int(pos + 4);
  }
  return _err_int(_at("manifest unknown wire type", pos));
}

// Parse one ManifestChange message over [off, off + size).
fn _manifest_change_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerManifestChange, Str] {
  var id: Int = 0;
  var op: Int = BADGER_MANIFEST_OP_CREATE;
  var level: Int = 0;
  var has_checksum = false;
  var checksum_off: Int = 0;
  var checksum_size: Int = 0;
  let limit = off + size;
  var pos = off;
  while pos < limit {
    let keyr = _uvarint_core(data, pos, limit);
    if !keyr.is_ok {
      return _err_mchg(_vmsg("manifest change field", keyr.error, pos));
    }
    let kv = keyr.value;
    pos = pos + kv.size;
    let field_no = kv.value / 8;
    let wire = kv.value % 8;
    if field_no == 1 {
      if wire != BADGER_PROTO_WIRE_VARINT {
        return _err_mchg(_at("manifest change id wire type", pos));
      }
      let vr = _uvarint_core(data, pos, limit);
      if !vr.is_ok {
        return _err_mchg(_vmsg("manifest change id", vr.error, pos));
      }
      let vv = vr.value;
      id = vv.value;
      pos = pos + vv.size;
    } elif field_no == 2 {
      if wire != BADGER_PROTO_WIRE_VARINT {
        return _err_mchg(_at("manifest change op wire type", pos));
      }
      let vr = _uvarint_core(data, pos, limit);
      if !vr.is_ok {
        return _err_mchg(_vmsg("manifest change op", vr.error, pos));
      }
      let vv = vr.value;
      op = vv.value;
      pos = pos + vv.size;
    } elif field_no == 3 {
      if wire != BADGER_PROTO_WIRE_VARINT {
        return _err_mchg(_at("manifest change level wire type", pos));
      }
      let vr = _uvarint_core(data, pos, limit);
      if !vr.is_ok {
        return _err_mchg(_vmsg("manifest change level", vr.error, pos));
      }
      let vv = vr.value;
      level = vv.value;
      pos = pos + vv.size;
    } elif field_no == 4 {
      if wire != BADGER_PROTO_WIRE_BYTES {
        return _err_mchg(_at("manifest change checksum wire type", pos));
      }
      let vr = _uvarint_core(data, pos, limit);
      if !vr.is_ok {
        return _err_mchg(_vmsg("manifest change checksum", vr.error, pos));
      }
      let vv = vr.value;
      let body = pos + vv.size;
      if vv.value > limit - body {
        return _err_mchg(_at("manifest change checksum truncated", pos));
      }
      has_checksum = true;
      checksum_off = body;
      checksum_size = vv.value;
      pos = body + vv.value;
    } else {
      let sk = _proto_skip(data, pos, limit, wire);
      if !sk.is_ok {
        return _err_mchg(sk.error);
      }
      let next: Int = sk.value;
      pos = next;
    }
  }
  let change = BadgerManifestChange{
    id: id;
    op: op;
    level: level;
    has_checksum: has_checksum;
    checksum_offset: checksum_off;
    checksum_size: checksum_size;
    offset: off;
    size: size;
  };
  return _ok_mchg(change);
}

/// Parse one ManifestChangeSet protobuf body over [off, off + size).
///
/// Schema (pb/pb.proto): `repeated ManifestChange changes = 1`; each change
/// is `uint64 Id = 1; Operation Op = 2; uint32 Level = 3; bytes Checksum =
/// 4`. Proto3 default-valued scalars may be absent (Op CREATE = 0, Level 0,
/// empty Checksum); absent fields are reported with their defaults and
/// `has_checksums`/`has_checksum` flags. Unknown fields are skipped by wire
/// type.
///
/// Errors: "badger: manifest changeset out of bounds at 0", "badger:
/// manifest changeset out of bounds at <off>", "badger: manifest changeset
/// wire type at <pos>", plus field/varint errors.
/// Complexity: O(body size).
pub fn badger_manifest_changeset_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerManifestChanges, Str] {
  if off < 0 {
    return _err_mch(_at("manifest changeset out of bounds", 0));
  }
  if off > data.len() || size > data.len() - off {
    return _err_mch(_at("manifest changeset out of bounds", off));
  }
  var ids = Vec[Int].new();
  var ops = Vec[Int].new();
  var levels = Vec[Int].new();
  var checksum_offsets = Vec[Int].new();
  var checksum_sizes = Vec[Int].new();
  var has_checksums = Vec[Bool].new();
  var offsets = Vec[Int].new();
  var sizes = Vec[Int].new();
  let limit = off + size;
  var pos = off;
  while pos < limit {
    let keyr = _uvarint_core(data, pos, limit);
    if !keyr.is_ok {
      return _err_mch(_vmsg("manifest changeset field", keyr.error, pos));
    }
    let kv = keyr.value;
    pos = pos + kv.size;
    let field_no = kv.value / 8;
    let wire = kv.value % 8;
    if field_no == 1 {
      if wire != BADGER_PROTO_WIRE_BYTES {
        return _err_mch(_at("manifest changeset wire type", pos));
      }
      let vr = _uvarint_core(data, pos, limit);
      if !vr.is_ok {
        return _err_mch(_vmsg("manifest change length", vr.error, pos));
      }
      let vv = vr.value;
      let body = pos + vv.size;
      if vv.value > limit - body {
        return _err_mch(_at("manifest change truncated", pos));
      }
      let cr = _manifest_change_parse(data, body, vv.value);
      if !cr.is_ok {
        return _err_mch(cr.error);
      }
      let ch = cr.value;
      let c_id: Int = ch.id;
      let c_op: Int = ch.op;
      let c_level: Int = ch.level;
      let c_has: Bool = ch.has_checksum;
      let c_coff: Int = ch.checksum_offset;
      let c_csz: Int = ch.checksum_size;
      ids.push(c_id);
      ops.push(c_op);
      levels.push(c_level);
      has_checksums.push(c_has);
      checksum_offsets.push(c_coff);
      checksum_sizes.push(c_csz);
      offsets.push(ch.offset);
      sizes.push(ch.size);
      pos = body + vv.value;
    } else {
      let sk = _proto_skip(data, pos, limit, wire);
      if !sk.is_ok {
        return _err_mch(sk.error);
      }
      let next: Int = sk.value;
      pos = next;
    }
  }
  return _ok_mch(BadgerManifestChanges{
    count: ids.len();
    ids: ids;
    ops: ops;
    levels: levels;
    checksum_offsets: checksum_offsets;
    checksum_sizes: checksum_sizes;
    has_checksums: has_checksums;
    offsets: offsets;
    sizes: sizes;
  });
}

/// Number of changes in a parsed changeset. Complexity: O(1).
pub fn badger_manifest_change_count(c: &BadgerManifestChanges) -> Int {
  return c.count;
}

/// Field `field` (one of the BADGER_MANIFEST_CHANGE_FIELD_* selectors) of
/// change `i`, or Err("badger: manifest change index out of range at <i>").
/// For CHECKSUM_SIZE of an absent checksum the value 0 is returned.
/// Complexity: O(1).
pub fn badger_manifest_change_field(c: &BadgerManifestChanges, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.count {
    return _err_int(_at("manifest change index out of range", i));
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_ID {
    let v: Int = c.ids[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_OP {
    let v: Int = c.ops[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_LEVEL {
    let v: Int = c.levels[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_CHECKSUM_OFFSET {
    let v: Int = c.checksum_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_CHECKSUM_SIZE {
    let v: Int = c.checksum_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_OFFSET {
    let v: Int = c.offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_SIZE {
    let v: Int = c.sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_CHANGE_FIELD_COUNT {
    return _ok_int(c.count);
  }
  return _err_int(_at("manifest change index out of range", i));
}

/// True when change `i` carries an explicit Checksum bytes field.
/// Complexity: O(1).
pub fn badger_manifest_change_has_checksum(c: &BadgerManifestChanges, i: Int) -> Bool {
  if i < 0 || i >= c.count {
    return false;
  }
  let v: Bool = c.has_checksums[i];
  return v;
}

/// Replay the whole manifest from the 8-byte header at offset 0 and return
/// the final live table set, with upstream applyChangeSet semantics
/// (manifest.go applyManifestChange): CREATE adds a table (duplicate id is
/// an error), DELETE removes it (unknown id is an error), any other Op is
/// invalid. A partial trailing record is tolerated exactly like
/// ReplayManifestFile (record ignored, `truncated`/`trunc_offset` reported).
///
/// Errors: any header/record/changeset error, "badger: manifest table
/// exists at <pos>", "badger: manifest removes non-existing table at <pos>",
/// "badger: manifest invalid op at <pos>", "badger: manifest exceeds max
/// tables at <pos>".
/// Complexity: O(manifest size * tables).
pub fn badger_manifest_replay(data: &Vec[UInt8], off: Int) -> Result[BadgerManifestTables, Str] {
  let hr = badger_manifest_header_parse(data);
  if !hr.is_ok {
    return _err_mt(hr.error);
  }
  var ids = Vec[Int].new();
  var levels = Vec[Int].new();
  var ck_offs = Vec[Int].new();
  var ck_sizes = Vec[Int].new();
  var record_count: Int = 0;
  var change_count: Int = 0;
  var start = off;
  if start < BADGER_MANIFEST_HEADER_SIZE {
    start = BADGER_MANIFEST_HEADER_SIZE;
  }
  let rr = badger_manifest_records_parse(data, start);
  if !rr.is_ok {
    return _err_mt(rr.error);
  }
  let recs = rr.value;
  let rc: Int = recs.count;
  var ri = 0;
  while ri < rc {
    let bo: Int = recs.body_offsets[ri];
    let ln: Int = recs.lengths[ri];
    let cr = badger_manifest_changeset_parse(data, bo, ln);
    if !cr.is_ok {
      return _err_mt(cr.error);
    }
    let cs = cr.value;
    let cc: Int = cs.count;
    record_count = record_count + 1;
    var ci = 0;
    while ci < cc {
      let ch_id: Int = cs.ids[ci];
      let ch_op: Int = cs.ops[ci];
      let ch_level: Int = cs.levels[ci];
      let ch_has: Bool = cs.has_checksums[ci];
      let ch_coff: Int = cs.checksum_offsets[ci];
      let ch_csz: Int = cs.checksum_sizes[ci];
      let ch_off: Int = cs.offsets[ci];
      if ch_op == BADGER_MANIFEST_OP_CREATE {
        var found: Int = -1;
        var k = 0;
        while k < ids.len() {
          let vid: Int = ids[k];
          if vid == ch_id {
            found = k;
          }
          k = k + 1;
        }
        if found >= 0 {
          return _err_mt(_at("manifest table exists", ch_off));
        }
        if ids.len() >= BADGER_MANIFEST_MAX_TABLES {
          return _err_mt(_at("manifest exceeds max tables", ch_off));
        }
        ids.push(ch_id);
        levels.push(ch_level);
        if ch_has {
          ck_offs.push(ch_coff);
          ck_sizes.push(ch_csz);
        } else {
          ck_offs.push(0);
          ck_sizes.push(0);
        }
      } elif ch_op == BADGER_MANIFEST_OP_DELETE {
        var found: Int = -1;
        var k = 0;
        while k < ids.len() {
          let vid: Int = ids[k];
          if vid == ch_id {
            found = k;
          }
          k = k + 1;
        }
        if found < 0 {
          return _err_mt(_at("manifest removes non-existing table", ch_off));
        }
        var vi = found;
        while vi + 1 < ids.len() {
          let nid: Int = ids[vi + 1];
          let nlv: Int = levels[vi + 1];
          let nco: Int = ck_offs[vi + 1];
          let ncs: Int = ck_sizes[vi + 1];
          ids[vi] = nid;
          levels[vi] = nlv;
          ck_offs[vi] = nco;
          ck_sizes[vi] = ncs;
          vi = vi + 1;
        }
        ids.pop();
        levels.pop();
        ck_offs.pop();
        ck_sizes.pop();
      } else {
        return _err_mt(_at("manifest invalid op", ch_off));
      }
      change_count = change_count + 1;
      ci = ci + 1;
    }
    ri = ri + 1;
  }
  return _ok_mt(BadgerManifestTables{
    record_count: record_count;
    change_count: change_count;
    count: ids.len();
    ids: ids;
    levels: levels;
    checksum_offsets: ck_offs;
    checksum_sizes: ck_sizes;
    truncated: recs.truncated;
    trunc_offset: recs.trunc_offset;
  });
}

/// Number of live tables in a replayed manifest. Complexity: O(1).
pub fn badger_manifest_file_count(t: &BadgerManifestTables) -> Int {
  return t.count;
}

/// Field `field` (one of the BADGER_MANIFEST_TABLE_FIELD_* selectors) of
/// live table `i`, or Err("badger: manifest table index out of range at
/// <i>"). Complexity: O(1).
pub fn badger_manifest_file_field(t: &BadgerManifestTables, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= t.count {
    return _err_int(_at("manifest table index out of range", i));
  }
  if field == BADGER_MANIFEST_TABLE_FIELD_ID {
    let v: Int = t.ids[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_TABLE_FIELD_LEVEL {
    let v: Int = t.levels[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_TABLE_FIELD_CHECKSUM_OFFSET {
    let v: Int = t.checksum_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_TABLE_FIELD_CHECKSUM_SIZE {
    let v: Int = t.checksum_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_MANIFEST_TABLE_FIELD_COUNT {
    return _ok_int(t.count);
  }
  return _err_int(_at("manifest table index out of range", i));
}

/// The module version. Complexity: O(1).
pub fn badger_version() -> Str {
  return BADGER_MODULE_VERSION;
}



