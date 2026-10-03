// XIOM -- xiom.rocksdb: pure-XIOM LSM storage-engine model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (full rules, invariants and error catalogue in SPEC.md):
//   * memtable: a sorted, skiplist-shaped write buffer for (column family,
//     key, sequence) entries with deterministic node heights and per-entry
//     byte accounting;
//   * WAL model: append-only records, sync policy (none / flush / full),
//     a durability watermark, explicit sync and replay into a memtable;
//   * SST model: a table built from a memtable as sorted data blocks plus
//     an index array and a Bloom-filter shape (bit array + probe);
//   * version/level structure: files placed on L0..Ln with size targets,
//     per-level scores and a deterministic compaction picker;
//   * compaction: deterministic input selection, bounded rounds, newest-
//     version dedup with snapshot-safe retention and bottom-level
//     tombstone dropping;
//   * key-value API model over the engine: put / delete / get at sequence
//     numbers and snapshots, range scan and a snapshot iterator; column
//     families share one sequence and are namespaced by id; statistics.
//
// Non-goals: no FFI, no filesystem, no threads, no wall clock and no
// byte-level RocksDB file formats. Everything is deterministic: no result
// depends on anything but the arguments and the prior call sequence.
//
// v0.62.2 notes that shaped this module:
//   * free functions only; parallel vectors instead of Vec[StructType];
//   * every Vec element read goes through a typed local; every byte read
//     is widened with `(b as Int) & 0xFF`;
//   * Ok/Err construction is confined to the _rocksdb_ok_* / _rocksdb_err_*
//     leaf helpers;
//   * &mut Vec mutation goes through struct fields or explicit &mut locals;
//     aggregate state is updated through struct fields, and every helper
//     still returns its result (no scalar out-parameters);
//   * no `match`, no `loop`, no lambdas, no `self`; bounded `while` loops.

module xiom.rocksdb

use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Reported module version.
const _ROCKSDB_VERSION: Str = "0.1.0";

// Canonical "absent / tombstone" error text returned by get.
const _ROCKSDB_NOT_FOUND: Str = "rocksdb: not found";

// Per-entry byte overhead charged by the memtable and the WAL model.
const _ROCKSDB_ENTRY_OVERHEAD: Int = 16;

// Value type of a tombstone in a memtable/WAL/SST entry.
const _ROCKSDB_TYPE_DELETE: Int = 0;

// Value type of a live value in a memtable/WAL/SST entry.
const _ROCKSDB_TYPE_VALUE: Int = 1;

// WAL sync policy: never synced until an explicit call.
const _ROCKSDB_SYNC_NONE: Int = 0;

// WAL sync policy: every append reaches the OS (flush).
const _ROCKSDB_SYNC_FLUSH: Int = 1;

// WAL sync policy: every append is durable (sync).
const _ROCKSDB_SYNC_FULL: Int = 2;

// Hard cap on skiplist node height.
const _ROCKSDB_MAX_HEIGHT: Int = 12;

// Hard cap on the number of levels a version can hold.
const _ROCKSDB_MAX_LEVELS: Int = 7;

// Defaults used by rocksdb_db_new_default.
const _ROCKSDB_DEFAULT_CAPACITY: Int = 4096;
const _ROCKSDB_DEFAULT_L0_TRIGGER: Int = 4;
const _ROCKSDB_DEFAULT_LEVEL_BASE: Int = 262144;
const _ROCKSDB_DEFAULT_LEVEL_MULT: Int = 10;
const _ROCKSDB_DEFAULT_MAX_LEVELS: Int = 7;
const _ROCKSDB_DEFAULT_BLOCK_ENTRIES: Int = 4;
const _ROCKSDB_DEFAULT_BLOOM_BITS: Int = 10;
const _ROCKSDB_DEFAULT_BLOOM_HASHES: Int = 3;
const _ROCKSDB_DEFAULT_WAL_POLICY: Int = 1;

// Smallest Bloom filter (bits) any table gets, regardless of key count.
const _ROCKSDB_MIN_BLOOM_BITS: Int = 64;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// The in-memory write buffer: entries sorted by
/// (column family ascending, key bytewise ascending, sequence descending).
///
/// `keys_data`/`values_data` are byte blobs sliced by the parallel
/// offsets/sizes arrays; `heights[i]` is the deterministic skiplist node
/// height of entry `i`; `bytes` charges key + value + entry overhead per
/// entry and never decreases on put (only on clear or a fresh memtable).
pub type RocksDbMemtable = {
  count: Int;
  bytes: Int;
  capacity: Int;
  keys_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  values_data: Vec[UInt8];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  seqs: Vec[Int];
  types: Vec[Int];
  cfs: Vec[Int];
  heights: Vec[Int];
}

/// The write-ahead log model: append-only records plus a durability
/// watermark `synced` (records below it survive a crash). `syncs` counts
/// full syncs, `flushes` counts OS flushes; policy NONE (0) does neither on
/// append, FLUSH (1) flushes on every append, FULL (2) syncs on every
/// append. Explicit rocksdb_wal_sync always syncs.
pub type RocksDbWal = {
  count: Int;
  bytes: Int;
  synced: Int;
  syncs: Int;
  flushes: Int;
  policy: Int;
  keys_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  values_data: Vec[UInt8];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  seqs: Vec[Int];
  types: Vec[Int];
  cfs: Vec[Int];
}

/// One immutably built SST model: sorted entries partitioned into data
/// blocks (every `block_first[b]`-th entry starts block `b`), an index
/// whose key `b` is the full first key of block `b`, and a Bloom-filter
/// shape over every (cf, key) in the table.
pub type RocksDbTable = {
  file_number: Int;
  count: Int;
  bytes: Int;
  block_count: Int;
  keys_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  values_data: Vec[UInt8];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  seqs: Vec[Int];
  types: Vec[Int];
  cfs: Vec[Int];
  block_first: Vec[Int];
  index_data: Vec[UInt8];
  index_offsets: Vec[Int];
  index_sizes: Vec[Int];
  bloom_data: Vec[UInt8];
  bloom_bitlen: Int;
  bloom_hashes: Int;
  bloom_keys: Int;
}

/// The level structure: files flattened in (level, file number) order with
/// per-file entry ranges, index ranges, Bloom ranges and (cf, key) min/max
/// bounds. Files are appended by flush at L0 and by compaction at L+1.
pub type RocksDbVersion = {
  l0_trigger: Int;
  level_base_bytes: Int;
  level_multiplier: Int;
  max_levels: Int;
  block_entries: Int;
  bloom_bits_per_key: Int;
  bloom_hashes: Int;
  level_count: Int;
  file_count: Int;
  next_file_number: Int;
  total_bytes: Int;
  file_level: Vec[Int];
  file_number: Vec[Int];
  file_bytes: Vec[Int];
  file_entry_start: Vec[Int];
  file_entry_count: Vec[Int];
  file_block_count: Vec[Int];
  file_index_start: Vec[Int];
  file_index_count: Vec[Int];
  file_bloom_offset: Vec[Int];
  file_bloom_size: Vec[Int];
  file_bloom_bitlen: Vec[Int];
  file_minkey_cf: Vec[Int];
  file_minkey_data: Vec[UInt8];
  file_minkey_offsets: Vec[Int];
  file_minkey_sizes: Vec[Int];
  file_maxkey_cf: Vec[Int];
  file_maxkey_data: Vec[UInt8];
  file_maxkey_offsets: Vec[Int];
  file_maxkey_sizes: Vec[Int];
  ent_keys_data: Vec[UInt8];
  ent_key_offsets: Vec[Int];
  ent_key_sizes: Vec[Int];
  ent_values_data: Vec[UInt8];
  ent_value_offsets: Vec[Int];
  ent_value_sizes: Vec[Int];
  ent_seqs: Vec[Int];
  ent_types: Vec[Int];
  ent_cfs: Vec[Int];
  idx_data: Vec[UInt8];
  idx_offsets: Vec[Int];
  idx_sizes: Vec[Int];
  bloom_data: Vec[UInt8];
}

/// A materialized snapshot iterator: one visible value per key of one
/// column family at `snapshot`, in bytewise key order. Tombstones and
/// superseded versions are filtered out at creation time.
pub type RocksDbIter = {
  count: Int;
  pos: Int;
  cf: Int;
  snapshot: Int;
  keys_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  values_data: Vec[UInt8];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  seqs: Vec[Int];
}

/// The result of a bounded range scan: visible entries with
/// min_key <= key <= max_key of one column family, in key order, at most
/// `limit` of them (limit <= 0 means unlimited). `truncated` is true when
/// the limit stopped the scan while more matching entries existed.
pub type RocksDbScan = {
  count: Int;
  truncated: Bool;
  cf: Int;
  keys_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  values_data: Vec[UInt8];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  seqs: Vec[Int];
}

/// Engine statistics. `gets` counts rocksdb_lookup/rocksdb_get_at calls,
/// `hits`/`misses` split them; flush/compaction counters are byte and
/// operation totals; `snapshots` counts creations; `iterator_creates` and
/// `scans` count iterator and scan constructions.
pub type RocksDbStats = {
  puts: Int;
  deletes: Int;
  gets: Int;
  hits: Int;
  misses: Int;
  flushes: Int;
  compactions: Int;
  flush_bytes: Int;
  compact_bytes: Int;
  wal_syncs: Int;
  snapshots: Int;
  iterator_creates: Int;
  scans: Int;
}

/// One rocksdb_version_compact call: `rounds` compactions ran, each moving
/// `input_files` files (with `input_entries` entries and `bytes_in` bytes)
/// at `last_level` to level+1, producing at most one output file with
/// `output_entries` entries and `bytes_out` bytes; `dropped_entries` counts
/// superseded versions removed. `levels_picked` counts picked levels.
pub type RocksDbCompactionReport = {
  rounds: Int;
  levels_picked: Int;
  input_files: Int;
  output_files: Int;
  input_entries: Int;
  output_entries: Int;
  dropped_entries: Int;
  bytes_in: Int;
  bytes_out: Int;
  last_level: Int;
}

/// The engine handle: sequence counter, column-family registry, snapshots,
/// statistics and the nested write state (active memtable, WAL, version).
/// The default column family id 0 named "default" always exists.
pub type RocksDbDb = {
  sequence: Int;
  next_cf: Int;
  mt: RocksDbMemtable;
  wal: RocksDbWal;
  ver: RocksDbVersion;
  st: RocksDbStats;
  cf_ids: Vec[Int];
  cf_names: Vec[Str];
  snapshots: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _rocksdb_ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _rocksdb_err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int in 0..255; callers guarantee the bounds.
fn _rocksdb_byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Copy [start, start + size) of `data` into a fresh Vec.
fn _rocksdb_copy_range(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
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
fn _rocksdb_append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// Bytewise (lexicographic, shorter-first) comparison: -1, 0 or 1.
fn _rocksdb_cmp_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Int {
  var n = a.len();
  if b.len() < n { n = b.len(); }
  var i = 0;
  while i < n {
    let av = _rocksdb_byte(a, i);
    let bv = _rocksdb_byte(b, i);
    if av < bv { return -1; }
    if av > bv { return 1; }
    i = i + 1;
  }
  if a.len() < b.len() { return -1; }
  if a.len() > b.len() { return 1; }
  return 0;
}

// Compare two blobs inside (possibly different) byte blobs.
fn _rocksdb_blob_cmp(d1: &Vec[UInt8], o1: Int, n1: Int, d2: &Vec[UInt8], o2: Int, n2: Int) -> Int {
  var n = n1;
  if n2 < n { n = n2; }
  var i = 0;
  while i < n {
    let av = _rocksdb_byte(d1, o1 + i);
    let bv = _rocksdb_byte(d2, o2 + i);
    if av < bv { return -1; }
    if av > bv { return 1; }
    i = i + 1;
  }
  if n1 < n2 { return -1; }
  if n1 > n2 { return 1; }
  return 0;
}

// Compare one blob with a whole key.
fn _rocksdb_blob_key_cmp(data: &Vec[UInt8], off: Int, size: Int, key: &Vec[UInt8]) -> Int {
  var n = size;
  if key.len() < n { n = key.len(); }
  var i = 0;
  while i < n {
    let av = _rocksdb_byte(data, off + i);
    let bv = _rocksdb_byte(key, i);
    if av < bv { return -1; }
    if av > bv { return 1; }
    i = i + 1;
  }
  if size < key.len() { return -1; }
  if size > key.len() { return 1; }
  return 0;
}

// True when the blob equals the whole key.
fn _rocksdb_blob_key_eq(data: &Vec[UInt8], off: Int, size: Int, key: &Vec[UInt8]) -> Bool {
  return _rocksdb_blob_key_cmp(data, off, size, key) == 0;
}

// Compare (cf, key) compounds: cf first, then key bytes.
fn _rocksdb_cf_key_cmp(cf1: Int, k1: &Vec[UInt8], cf2: Int, k2: &Vec[UInt8]) -> Int {
  if cf1 < cf2 { return -1; }
  if cf1 > cf2 { return 1; }
  return _rocksdb_cmp_bytes(k1, k2);
}

// Int elements of `a` ascending insertion sort. Bounded by len^2.
fn _rocksdb_sort_ints(a: &mut Vec[Int]) {
  var i = 1;
  while i < a.len() {
    let cur: Int = a[i];
    var j = i - 1;
    var moving = true;
    while j >= 0 && moving {
      let prev: Int = a[j];
      if prev > cur {
        a[j + 1] = prev;
        j = j - 1;
      } else {
        moving = false;
      }
    }
    a[j + 1] = cur;
    i = i + 1;
  }
}

// --------------------------------------------------
//  Hashing and Bloom shape
// --------------------------------------------------

// FNV-1a-style 32-bit hash of (cf, key bytes), salted by `seed`. The
// multiply stays below 2^56, so no 64-bit overflow is possible.
fn _rocksdb_hash32(cf: Int, key: &Vec[UInt8], seed: Int) -> Int {
  var h = 2166136261;
  var i = 0;
  while i < key.len() {
    let b: UInt8 = key[i];
    let bi = (b as Int) & 0xFF;
    h = ((h ^ bi) * 16777619) % 4294967296;
    i = i + 1;
  }
  var c = cf;
  if c < 0 { c = 0; }
  h = (h + c * 40503) % 4294967296;
  h = (h + seed * 2654435761) % 4294967296;
  h = (h + h / 65536) % 4294967296;
  return h;
}

// Skiplist node height for a hash: 1 plus the number of trailing zero bits,
// capped at _ROCKSDB_MAX_HEIGHT. A zero hash yields height 1.
fn _rocksdb_height_of_hash(h: Int) -> Int {
  var x = h;
  var height = 1;
  while height < _ROCKSDB_MAX_HEIGHT && x > 0 && x % 2 == 0 {
    height = height + 1;
    x = x / 2;
  }
  return height;
}

// 2^k for 0 <= k <= 7 (a single byte bit mask).
fn _rocksdb_bit_mask(k: Int) -> Int {
  var m = 1;
  var i = 0;
  while i < k {
    m = m * 2;
    i = i + 1;
  }
  return m;
}

// Set bit `bit` (mod bitlen) in the byte array, at byte offset `off`.
fn _rocksdb_bloom_set(data: &mut Vec[UInt8], off: Int, bitlen: Int, bit: Int) {
  if bitlen <= 0 { return; }
  let b = bit % bitlen;
  let byte_index = off + b / 8;
  let mask = _rocksdb_bit_mask(b % 8);
  while data.len() <= byte_index {
    data.push(0 as UInt8);
  }
  let cur = _rocksdb_byte(data, byte_index);
  data[byte_index] = (cur | mask) as UInt8;
}

// True when bit `bit` (mod bitlen) is set, at byte offset `off`.
fn _rocksdb_bloom_test(data: &Vec[UInt8], off: Int, bitlen: Int, bit: Int) -> Bool {
  if bitlen <= 0 { return false; }
  let b = bit % bitlen;
  let byte_index = off + b / 8;
  if byte_index >= data.len() { return false; }
  let mask = _rocksdb_bit_mask(b % 8);
  let cur = _rocksdb_byte(data, byte_index);
  return (cur / mask) % 2 == 1;
}

// True when all `hashes` bits for (cf, key) are set: the key may be in the
// filter. False is definitive (no false negatives).
fn _rocksdb_bloom_probe(data: &Vec[UInt8], off: Int, bitlen: Int, hashes: Int, cf: Int, key: &Vec[UInt8]) -> Bool {
  if bitlen <= 0 { return false; }
  if hashes <= 0 { return false; }
  let h1 = _rocksdb_hash32(cf, key, 1);
  let h2 = _rocksdb_hash32(cf, key, 2);
  var i = 0;
  while i < hashes {
    let bit = (h1 + i * h2) % bitlen;
    if !_rocksdb_bloom_test(data, off, bitlen, bit) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Memtable
// --------------------------------------------------

/// A fresh empty memtable with the given byte capacity (values below 64 are
/// raised to 64 so accounting tests stay meaningful). Complexity: O(1).
pub fn rocksdb_memtable_new(capacity: Int) -> RocksDbMemtable {
  var cap = capacity;
  if cap < 64 { cap = 64; }
  return RocksDbMemtable{
    count: 0;
    bytes: 0;
    capacity: cap;
    keys_data: Vec[UInt8].new();
    key_offsets: Vec[Int].new();
    key_sizes: Vec[Int].new();
    values_data: Vec[UInt8].new();
    value_offsets: Vec[Int].new();
    value_sizes: Vec[Int].new();
    seqs: Vec[Int].new();
    types: Vec[Int].new();
    cfs: Vec[Int].new();
    heights: Vec[Int].new();
  };
}

// Insertion position for (cf, key, seq) in the sorted memtable: the first
// entry that sorts after the new one. Binary search; entries sort by
// (cf asc, key asc, seq desc).
fn _rocksdb_mt_insert_pos(mt: &RocksDbMemtable, cf: Int, key: &Vec[UInt8], seq: Int) -> Int {
  var lo = 0;
  var hi = mt.count;
  while lo < hi {
    let mid = lo + (hi - lo) / 2;
    let mcf: Int = mt.cfs[mid];
    var before = false;
    if mcf < cf {
      before = true;
    } elif mcf > cf {
      before = false;
    } else {
      let koff: Int = mt.key_offsets[mid];
      let ksz: Int = mt.key_sizes[mid];
      let c = _rocksdb_blob_key_cmp(mt.keys_data, koff, ksz, key);
      if c < 0 {
        before = true;
      } elif c > 0 {
        before = false;
      } else {
        let mseq: Int = mt.seqs[mid];
        if mseq > seq { before = true; }
      }
    }
    if before {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Append one entry to the memtable. `ktype` is 1 (value) or 0 (tombstone).
///
/// Entries may share a key when sequences differ. Returns the insertion
/// index, or -1 for an empty key, a negative sequence or an unknown type.
/// Complexity: O(log count) search plus O(count) shifting.
pub fn rocksdb_memtable_put(mt: &mut RocksDbMemtable, cf: Int, key: &Vec[UInt8], value: &Vec[UInt8], seq: Int, ktype: Int) -> Int {
  if key.len() == 0 { return -1; }
  if seq < 0 { return -1; }
  if ktype != _ROCKSDB_TYPE_VALUE && ktype != _ROCKSDB_TYPE_DELETE { return -1; }
  let pos = _rocksdb_mt_insert_pos(mt, cf, key, seq);
  let ko = mt.keys_data.len();
  _rocksdb_append(&mut mt.keys_data, key);
  let vo = mt.values_data.len();
  _rocksdb_append(&mut mt.values_data, value);
  mt.key_offsets.insert(pos, ko);
  mt.key_sizes.insert(pos, key.len());
  mt.value_offsets.insert(pos, vo);
  mt.value_sizes.insert(pos, value.len());
  mt.seqs.insert(pos, seq);
  mt.types.insert(pos, ktype);
  mt.cfs.insert(pos, cf);
  mt.heights.insert(pos, rocksdb_memtable_height_for_key(cf, key, seq));
  mt.count = mt.count + 1;
  mt.bytes = mt.bytes + key.len() + value.len() + _ROCKSDB_ENTRY_OVERHEAD;
  return pos;
}

/// Deterministic skiplist node height for (cf, key, seq): 1..12.
/// Complexity: O(key length).
pub fn rocksdb_memtable_height_for_key(cf: Int, key: &Vec[UInt8], seq: Int) -> Int {
  let h = _rocksdb_hash32(cf, key, seq + 7);
  return _rocksdb_height_of_hash(h);
}

/// Empty the memtable, keeping its capacity, and reset count/bytes.
/// Complexity: O(1).
pub fn rocksdb_memtable_clear(mt: &mut RocksDbMemtable) {
  mt.keys_data = Vec[UInt8].new();
  mt.key_offsets = Vec[Int].new();
  mt.key_sizes = Vec[Int].new();
  mt.values_data = Vec[UInt8].new();
  mt.value_offsets = Vec[Int].new();
  mt.value_sizes = Vec[Int].new();
  mt.seqs = Vec[Int].new();
  mt.types = Vec[Int].new();
  mt.cfs = Vec[Int].new();
  mt.heights = Vec[Int].new();
  mt.count = 0;
  mt.bytes = 0;
}

/// Number of entries. Complexity: O(1).
pub fn rocksdb_memtable_count(mt: &RocksDbMemtable) -> Int {
  return mt.count;
}

/// Charged bytes: key + value + overhead per entry. Complexity: O(1).
pub fn rocksdb_memtable_bytes(mt: &RocksDbMemtable) -> Int {
  return mt.bytes;
}

/// Configured byte capacity (>= 64). Complexity: O(1).
pub fn rocksdb_memtable_capacity(mt: &RocksDbMemtable) -> Int {
  return mt.capacity;
}

/// True when charged bytes reached the capacity. Complexity: O(1).
pub fn rocksdb_memtable_is_full(mt: &RocksDbMemtable) -> Bool {
  if mt.bytes >= mt.capacity { return true; }
  return false;
}

/// True when the memtable should be flushed: same rule as is_full.
/// Complexity: O(1).
pub fn rocksdb_memtable_should_flush(mt: &RocksDbMemtable) -> Bool {
  return rocksdb_memtable_is_full(mt);
}

// The lower-bound binary search shared by find and search_steps: the first
// entry that does not sort strictly before (cf, key, snapshot). `counted`
// selects the probe count instead of the position.
fn _rocksdb_mt_lower_bound(mt: &RocksDbMemtable, cf: Int, key: &Vec[UInt8], snapshot: Int, counted: Int) -> Int {
  var lo = 0;
  var hi = mt.count;
  var probes = 0;
  while lo < hi {
    let mid = lo + (hi - lo) / 2;
    probes = probes + 1;
    let mcf: Int = mt.cfs[mid];
    var before = false;
    if mcf < cf {
      before = true;
    } elif mcf > cf {
      before = false;
    } else {
      let koff: Int = mt.key_offsets[mid];
      let ksz: Int = mt.key_sizes[mid];
      let c = _rocksdb_blob_key_cmp(mt.keys_data, koff, ksz, key);
      if c < 0 {
        before = true;
      } elif c > 0 {
        before = false;
      } else {
        let mseq: Int = mt.seqs[mid];
        if mseq > snapshot { before = true; }
      }
    }
    if before {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if counted == 1 { return probes; }
  return lo;
}

/// Index of the newest entry visible at `snapshot` for (cf, key), or -1.
/// A tombstone is returned like any other entry (type 0); callers decide.
/// Complexity: O(log count).
pub fn rocksdb_memtable_find(mt: &RocksDbMemtable, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  if key.len() == 0 { return -1; }
  let pos = _rocksdb_mt_lower_bound(mt, cf, key, snapshot, 0);
  if pos >= mt.count { return -1; }
  let pcf: Int = mt.cfs[pos];
  if pcf != cf { return -1; }
  let koff: Int = mt.key_offsets[pos];
  let ksz: Int = mt.key_sizes[pos];
  if !_rocksdb_blob_key_eq(mt.keys_data, koff, ksz, key) { return -1; }
  return pos;
}

/// Comparison count of the binary search used by rocksdb_memtable_find:
/// 0 for an empty memtable or an empty key, else the number of probes.
/// Complexity: O(log count).
pub fn rocksdb_memtable_search_steps(mt: &RocksDbMemtable, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  if key.len() == 0 { return 0; }
  return _rocksdb_mt_lower_bound(mt, cf, key, snapshot, 1);
}

/// Column family id of entry `i`, or -1 when out of range. Complexity: O(1).
pub fn rocksdb_memtable_entry_cf(mt: &RocksDbMemtable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= mt.count { return -1; }
  return mt.cfs[i];
}

/// Sequence number of entry `i`, or -1 when out of range. Complexity: O(1).
pub fn rocksdb_memtable_entry_seq(mt: &RocksDbMemtable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= mt.count { return -1; }
  return mt.seqs[i];
}

/// Value type of entry `i` (1 value, 0 tombstone), or -1 out of range.
/// Complexity: O(1).
pub fn rocksdb_memtable_entry_type(mt: &RocksDbMemtable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= mt.count { return -1; }
  return mt.types[i];
}

/// Key bytes of entry `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_memtable_entry_key(mt: &RocksDbMemtable, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= mt.count { return Vec[UInt8].new(); }
  let koff: Int = mt.key_offsets[i];
  let ksz: Int = mt.key_sizes[i];
  return _rocksdb_copy_range(mt.keys_data, koff, ksz);
}

/// Value bytes of entry `i` (empty Vec out of range). Complexity: O(value).
pub fn rocksdb_memtable_entry_value(mt: &RocksDbMemtable, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= mt.count { return Vec[UInt8].new(); }
  let voff: Int = mt.value_offsets[i];
  let vsz: Int = mt.value_sizes[i];
  return _rocksdb_copy_range(mt.values_data, voff, vsz);
}

/// Skiplist height of entry `i`, or 0 when out of range. Complexity: O(1).
pub fn rocksdb_memtable_entry_height(mt: &RocksDbMemtable, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= mt.count { return 0; }
  return mt.heights[i];
}

/// Maximum node height (0 when empty). Complexity: O(count).
pub fn rocksdb_memtable_height(mt: &RocksDbMemtable) -> Int {
  var h = 0;
  var i = 0;
  while i < mt.count {
    let e: Int = mt.heights[i];
    if e > h { h = e; }
    i = i + 1;
  }
  return h;
}

/// Number of entries whose node height is >= `height` (0 when height <= 0).
/// Complexity: O(count).
pub fn rocksdb_memtable_level_count(mt: &RocksDbMemtable, height: Int) -> Int {
  if height <= 0 { return 0; }
  var n = 0;
  var i = 0;
  while i < mt.count {
    let e: Int = mt.heights[i];
    if e >= height { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// True when the memtable order invariant holds: (cf asc, key asc, seq desc).
/// Complexity: O(count * key).
pub fn rocksdb_memtable_is_sorted(mt: &RocksDbMemtable) -> Bool {
  var i = 1;
  while i < mt.count {
    let pcf: Int = mt.cfs[i - 1];
    let ccf: Int = mt.cfs[i];
    var bad = false;
    if ccf < pcf {
      bad = true;
    } elif ccf == pcf {
      let poff: Int = mt.key_offsets[i - 1];
      let psz: Int = mt.key_sizes[i - 1];
      let coff: Int = mt.key_offsets[i];
      let csz: Int = mt.key_sizes[i];
      let c = _rocksdb_blob_cmp(mt.keys_data, poff, psz, mt.keys_data, coff, csz);
      if c > 0 {
        bad = true;
      } elif c == 0 {
        let pseq: Int = mt.seqs[i - 1];
        let cseq: Int = mt.seqs[i];
        if cseq > pseq { bad = true; }
      }
    }
    if bad { return false; }
    i = i + 1;
  }
  return true;
}

/// Newest visible value for (cf, key) at `snapshot`, or
/// Err("rocksdb: not found") for an absent key and for a tombstone.
/// Complexity: O(log count + value).
pub fn rocksdb_memtable_get(mt: &RocksDbMemtable, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Result[Vec[UInt8], Str] {
  let i = rocksdb_memtable_find(mt, cf, key, snapshot);
  if i < 0 { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  let ty: Int = mt.types[i];
  if ty == _ROCKSDB_TYPE_DELETE { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  return _rocksdb_ok_bytes(rocksdb_memtable_entry_value(mt, i));
}

// --------------------------------------------------
//  WAL
// --------------------------------------------------

/// A fresh empty WAL with the given sync policy (values outside 0..2 are
/// clamped). Complexity: O(1).
pub fn rocksdb_wal_new(policy: Int) -> RocksDbWal {
  var p = policy;
  if p < _ROCKSDB_SYNC_NONE { p = _ROCKSDB_SYNC_NONE; }
  if p > _ROCKSDB_SYNC_FULL { p = _ROCKSDB_SYNC_FULL; }
  return RocksDbWal{
    count: 0;
    bytes: 0;
    synced: 0;
    syncs: 0;
    flushes: 0;
    policy: p;
    keys_data: Vec[UInt8].new();
    key_offsets: Vec[Int].new();
    key_sizes: Vec[Int].new();
    values_data: Vec[UInt8].new();
    value_offsets: Vec[Int].new();
    value_sizes: Vec[Int].new();
    seqs: Vec[Int].new();
    types: Vec[Int].new();
    cfs: Vec[Int].new();
  };
}

/// Policy name: "none" (0), "flush" (1), "sync" (2), "" otherwise.
/// Complexity: O(1).
pub fn rocksdb_wal_policy_name(policy: Int) -> Str {
  if policy == _ROCKSDB_SYNC_NONE { return "none"; }
  if policy == _ROCKSDB_SYNC_FLUSH { return "flush"; }
  if policy == _ROCKSDB_SYNC_FULL { return "sync"; }
  return "";
}

/// Append one record. Returns its index, or -1 for an empty key, a negative
/// sequence or an unknown type. Policy FLUSH marks the record durable and
/// counts a flush; policy SYNC marks it durable and counts a sync.
/// Complexity: O(key + value).
pub fn rocksdb_wal_append(w: &mut RocksDbWal, cf: Int, key: &Vec[UInt8], value: &Vec[UInt8], seq: Int, ktype: Int) -> Int {
  if key.len() == 0 { return -1; }
  if seq < 0 { return -1; }
  if ktype != _ROCKSDB_TYPE_VALUE && ktype != _ROCKSDB_TYPE_DELETE { return -1; }
  let pos = w.count;
  let ko = w.keys_data.len();
  _rocksdb_append(&mut w.keys_data, key);
  let vo = w.values_data.len();
  _rocksdb_append(&mut w.values_data, value);
  w.key_offsets.push(ko);
  w.key_sizes.push(key.len());
  w.value_offsets.push(vo);
  w.value_sizes.push(value.len());
  w.seqs.push(seq);
  w.types.push(ktype);
  w.cfs.push(cf);
  w.count = w.count + 1;
  w.bytes = w.bytes + key.len() + value.len() + _ROCKSDB_ENTRY_OVERHEAD;
  if w.policy == _ROCKSDB_SYNC_FLUSH {
    w.synced = w.count;
    w.flushes = w.flushes + 1;
  } elif w.policy == _ROCKSDB_SYNC_FULL {
    w.synced = w.count;
    w.syncs = w.syncs + 1;
  }
  return pos;
}

/// Force a sync: every appended record becomes durable. Returns the new
/// durable watermark (the record count) and increments the sync counter.
/// Complexity: O(1).
pub fn rocksdb_wal_sync(w: &mut RocksDbWal) -> Int {
  w.synced = w.count;
  w.syncs = w.syncs + 1;
  return w.synced;
}

/// Number of records. Complexity: O(1).
pub fn rocksdb_wal_count(w: &RocksDbWal) -> Int {
  return w.count;
}

/// Charged bytes: key + value + overhead per record. Complexity: O(1).
pub fn rocksdb_wal_bytes(w: &RocksDbWal) -> Int {
  return w.bytes;
}

/// Durable record watermark. Complexity: O(1).
pub fn rocksdb_wal_synced(w: &RocksDbWal) -> Int {
  return w.synced;
}

/// Records appended but not durable (count - synced). Complexity: O(1).
pub fn rocksdb_wal_pending(w: &RocksDbWal) -> Int {
  return w.count - w.synced;
}

/// Full syncs issued (automatic under policy SYNC plus explicit calls).
/// Complexity: O(1).
pub fn rocksdb_wal_syncs(w: &RocksDbWal) -> Int {
  return w.syncs;
}

/// OS flushes issued (automatic under policy FLUSH). Complexity: O(1).
pub fn rocksdb_wal_flushes(w: &RocksDbWal) -> Int {
  return w.flushes;
}

/// Configured policy (0 none, 1 flush, 2 sync). Complexity: O(1).
pub fn rocksdb_wal_policy(w: &RocksDbWal) -> Int {
  return w.policy;
}

/// True when the first `upto` records (0..upto) are durable.
/// Complexity: O(1).
pub fn rocksdb_wal_is_durable(w: &RocksDbWal, upto: Int) -> Bool {
  if upto < 0 { return false; }
  if upto > w.count { return false; }
  if upto <= w.synced { return true; }
  return false;
}

/// Column family of record `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_wal_entry_cf(w: &RocksDbWal, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= w.count { return -1; }
  return w.cfs[i];
}

/// Sequence of record `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_wal_entry_seq(w: &RocksDbWal, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= w.count { return -1; }
  return w.seqs[i];
}

/// Type of record `i` (1 value, 0 tombstone), or -1 out of range.
/// Complexity: O(1).
pub fn rocksdb_wal_entry_type(w: &RocksDbWal, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= w.count { return -1; }
  return w.types[i];
}

/// Key of record `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_wal_entry_key(w: &RocksDbWal, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let koff: Int = w.key_offsets[i];
  let ksz: Int = w.key_sizes[i];
  return _rocksdb_copy_range(w.keys_data, koff, ksz);
}

/// Value of record `i` (empty Vec out of range). Complexity: O(value).
pub fn rocksdb_wal_entry_value(w: &RocksDbWal, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let voff: Int = w.value_offsets[i];
  let vsz: Int = w.value_sizes[i];
  return _rocksdb_copy_range(w.values_data, voff, vsz);
}

// Replay records in [start, stop) into `mt`; returns records applied.
fn _rocksdb_wal_replay_range(w: &RocksDbWal, start: Int, stop: Int, mt: &mut RocksDbMemtable) -> Int {
  var applied = 0;
  var i = start;
  while i < stop {
    let cf: Int = w.cfs[i];
    let seq: Int = w.seqs[i];
    let ty: Int = w.types[i];
    let koff: Int = w.key_offsets[i];
    let ksz: Int = w.key_sizes[i];
    let voff: Int = w.value_offsets[i];
    let vsz: Int = w.value_sizes[i];
    let key = _rocksdb_copy_range(w.keys_data, koff, ksz);
    let value = _rocksdb_copy_range(w.values_data, voff, vsz);
    let pos = rocksdb_memtable_put(mt, cf, &key, &value, seq, ty);
    if pos >= 0 { applied = applied + 1; }
    i = i + 1;
  }
  return applied;
}

/// Replay every WAL record into `mt`, in append order, preserving each
/// record's cf, sequence and type. Returns the number of records applied.
/// Complexity: O(total bytes).
pub fn rocksdb_wal_replay(w: &RocksDbWal, mt: &mut RocksDbMemtable) -> Int {
  return _rocksdb_wal_replay_range(w, 0, w.count, mt);
}

/// Replay records from index `start` to the end. Complexity: O(total bytes).
pub fn rocksdb_wal_replay_from(w: &RocksDbWal, start: Int, mt: &mut RocksDbMemtable) -> Int {
  var s = start;
  if s < 0 { s = 0; }
  return _rocksdb_wal_replay_range(w, s, w.count, mt);
}

/// Replay records in [start, stop), clamped to the record range.
/// Complexity: O(total bytes).
pub fn rocksdb_wal_replay_range(w: &RocksDbWal, start: Int, stop: Int, mt: &mut RocksDbMemtable) -> Int {
  var s = start;
  var e = stop;
  if s < 0 { s = 0; }
  if e > w.count { e = w.count; }
  if e < s { e = s; }
  return _rocksdb_wal_replay_range(w, s, e, mt);
}

// --------------------------------------------------
//  SST table model
// --------------------------------------------------

// Build a table from parallel entry arrays (they must already be in
// (cf, key, seq desc) order). Data blocks start every `block_entries`
// entries; the index key of block b is the full first key of that block;
// the Bloom filter covers every (cf, key) with `bloom_bits_per_key` bits
// each, rounded up to whole bytes.
fn _rocksdb_table_from_arrays(file_number: Int, block_entries: Int, bloom_bits_per_key: Int, bloom_hashes: Int, count: Int, cfs: &Vec[Int], seqs: &Vec[Int], types: &Vec[Int], kd: &Vec[UInt8], ko: &Vec[Int], ks: &Vec[Int], vd: &Vec[UInt8], vo: &Vec[Int], vs: &Vec[Int]) -> RocksDbTable {
  var be = block_entries;
  if be < 1 { be = 1; }
  var bh = bloom_hashes;
  if bh < 1 { bh = 1; }
  var bpk = bloom_bits_per_key;
  if bpk < 1 { bpk = 1; }
  var bitlen = bpk * count;
  if bitlen < _ROCKSDB_MIN_BLOOM_BITS { bitlen = _ROCKSDB_MIN_BLOOM_BITS; }
  let nbytes = (bitlen + 7) / 8;
  var bloom = Vec[UInt8].new();
  var z = 0;
  while z < nbytes {
    bloom.push(0 as UInt8);
    z = z + 1;
  }
  var keys_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var values_data = Vec[UInt8].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var out_seqs = Vec[Int].new();
  var out_types = Vec[Int].new();
  var out_cfs = Vec[Int].new();
  var block_first = Vec[Int].new();
  var index_data = Vec[UInt8].new();
  var index_offsets = Vec[Int].new();
  var index_sizes = Vec[Int].new();
  var entry_bytes = 0;
  var i = 0;
  while i < count {
    if i % be == 0 {
      let bl_koff: Int = ko[i];
      let bl_ksz: Int = ks[i];
      let ikey = _rocksdb_copy_range(kd, bl_koff, bl_ksz);
      block_first.push(i);
      index_offsets.push(index_data.len());
      index_sizes.push(ikey.len());
      _rocksdb_append(&mut index_data, &ikey);
    }
    let koff: Int = ko[i];
    let ksz: Int = ks[i];
    let ekey = _rocksdb_copy_range(kd, koff, ksz);
    key_offsets.push(keys_data.len());
    key_sizes.push(ekey.len());
    _rocksdb_append(&mut keys_data, &ekey);
    let vkoff: Int = vo[i];
    let vksz: Int = vs[i];
    let eval = _rocksdb_copy_range(vd, vkoff, vksz);
    value_offsets.push(values_data.len());
    value_sizes.push(eval.len());
    _rocksdb_append(&mut values_data, &eval);
    let e_ty: Int = types[i];
    let e_cf: Int = cfs[i];
    let e_seq: Int = seqs[i];
    out_types.push(e_ty);
    out_cfs.push(e_cf);
    out_seqs.push(e_seq);
    let h1 = _rocksdb_hash32(e_cf, &ekey, 1);
    let h2 = _rocksdb_hash32(e_cf, &ekey, 2);
    var hi = 0;
    while hi < bh {
      let bit = (h1 + hi * h2) % bitlen;
      _rocksdb_bloom_set(&mut bloom, 0, bitlen, bit);
      hi = hi + 1;
    }
    entry_bytes = entry_bytes + ksz + vksz + _ROCKSDB_ENTRY_OVERHEAD;
    i = i + 1;
  }
  let block_count = block_first.len();
  let total = entry_bytes + index_data.len() + bloom.len() + block_count * 4;
  return RocksDbTable{
    file_number: file_number;
    count: count;
    bytes: total;
    block_count: block_count;
    keys_data: keys_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    values_data: values_data;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    seqs: out_seqs;
    types: out_types;
    cfs: out_cfs;
    block_first: block_first;
    index_data: index_data;
    index_offsets: index_offsets;
    index_sizes: index_sizes;
    bloom_data: bloom;
    bloom_bitlen: bitlen;
    bloom_hashes: bh;
    bloom_keys: count;
  };
}

/// Build an SST model from a memtable: entries stay in memtable order,
/// partitioned into data blocks of at most `block_entries` entries, with an
/// index key per block and a Bloom filter over every (cf, key).
/// Complexity: O(entries + index + bloom).
pub fn rocksdb_table_build(mt: &RocksDbMemtable, file_number: Int, block_entries: Int, bloom_bits_per_key: Int, bloom_hashes: Int) -> RocksDbTable {
  let cfs: Vec[Int] = mt.cfs;
  let seqs: Vec[Int] = mt.seqs;
  let ltypes: Vec[Int] = mt.types;
  let kd: Vec[UInt8] = mt.keys_data;
  let ko: Vec[Int] = mt.key_offsets;
  let ks: Vec[Int] = mt.key_sizes;
  let vd: Vec[UInt8] = mt.values_data;
  let vo: Vec[Int] = mt.value_offsets;
  let vs: Vec[Int] = mt.value_sizes;
  return _rocksdb_table_from_arrays(file_number, block_entries, bloom_bits_per_key, bloom_hashes, mt.count, &cfs, &seqs, &ltypes, &kd, &ko, &ks, &vd, &vo, &vs);
}

/// Number of entries in the table. Complexity: O(1).
pub fn rocksdb_table_count(t: &RocksDbTable) -> Int {
  return t.count;
}

/// Charged table bytes: entry bytes + index bytes + Bloom bytes + 4 bytes
/// per data block. Complexity: O(1).
pub fn rocksdb_table_bytes(t: &RocksDbTable) -> Int {
  return t.bytes;
}

/// File number carried by the table. Complexity: O(1).
pub fn rocksdb_table_file_number(t: &RocksDbTable) -> Int {
  return t.file_number;
}

/// Number of data blocks. Complexity: O(1).
pub fn rocksdb_table_block_count(t: &RocksDbTable) -> Int {
  return t.block_count;
}

/// Bloom filter length in bits. Complexity: O(1).
pub fn rocksdb_table_bloom_bitlen(t: &RocksDbTable) -> Int {
  return t.bloom_bitlen;
}

/// Bloom hash count. Complexity: O(1).
pub fn rocksdb_table_bloom_hashes(t: &RocksDbTable) -> Int {
  return t.bloom_hashes;
}

/// Keys the Bloom filter was built over (one per entry, duplicates
/// included). Complexity: O(1).
pub fn rocksdb_table_bloom_keys(t: &RocksDbTable) -> Int {
  return t.bloom_keys;
}

/// Column family of entry `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_table_entry_cf(t: &RocksDbTable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.count { return -1; }
  return t.cfs[i];
}

/// Sequence of entry `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_table_entry_seq(t: &RocksDbTable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.count { return -1; }
  return t.seqs[i];
}

/// Type of entry `i` (1 value, 0 tombstone), or -1 out of range.
/// Complexity: O(1).
pub fn rocksdb_table_entry_type(t: &RocksDbTable, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.count { return -1; }
  return t.types[i];
}

/// Key of entry `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_table_entry_key(t: &RocksDbTable, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= t.count { return Vec[UInt8].new(); }
  let koff: Int = t.key_offsets[i];
  let ksz: Int = t.key_sizes[i];
  return _rocksdb_copy_range(t.keys_data, koff, ksz);
}

/// Value of entry `i` (empty Vec out of range). Complexity: O(value).
pub fn rocksdb_table_entry_value(t: &RocksDbTable, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= t.count { return Vec[UInt8].new(); }
  let voff: Int = t.value_offsets[i];
  let vsz: Int = t.value_sizes[i];
  return _rocksdb_copy_range(t.values_data, voff, vsz);
}

/// First key of the table (empty Vec when the table is empty).
/// Complexity: O(key).
pub fn rocksdb_table_first_key(t: &RocksDbTable) -> Vec[UInt8] {
  return rocksdb_table_entry_key(t, 0);
}

/// Last key of the table (empty Vec when the table is empty).
/// Complexity: O(key).
pub fn rocksdb_table_last_key(t: &RocksDbTable) -> Vec[UInt8] {
  return rocksdb_table_entry_key(t, t.count - 1);
}

/// Entry index of the first entry of data block `b`, or -1 out of range.
/// Complexity: O(1).
pub fn rocksdb_table_block_first(t: &RocksDbTable, b: Int) -> Int {
  if b < 0 { return -1; }
  if b >= t.block_first.len() { return -1; }
  return t.block_first[b];
}

/// Index key of data block `b` (the full first key of the block), or an
/// empty Vec out of range. Complexity: O(key).
pub fn rocksdb_table_index_key(t: &RocksDbTable, b: Int) -> Vec[UInt8] {
  if b < 0 { return Vec[UInt8].new(); }
  if b >= t.index_sizes.len() { return Vec[UInt8].new(); }
  let ioff: Int = t.index_offsets[b];
  let isz: Int = t.index_sizes[b];
  return _rocksdb_copy_range(t.index_data, ioff, isz);
}

/// Bloom probe for (cf, key): false is definitive (the key is absent).
/// Complexity: O(key * hashes).
pub fn rocksdb_table_bloom_may_contain(t: &RocksDbTable, cf: Int, key: &Vec[UInt8]) -> Bool {
  return _rocksdb_bloom_probe(t.bloom_data, 0, t.bloom_bitlen, t.bloom_hashes, cf, key);
}

/// Number of set bits in the Bloom filter. Complexity: O(bytes).
pub fn rocksdb_table_bloom_set_bits(t: &RocksDbTable) -> Int {
  var n = 0;
  var i = 0;
  while i < t.bloom_data.len() {
    let b = _rocksdb_byte(t.bloom_data, i);
    var k = 0;
    while k < 8 {
      if (b / _rocksdb_bit_mask(k)) % 2 == 1 { n = n + 1; }
      k = k + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Fill ratio of the Bloom filter in tenths of a percent (0..1000):
/// set_bits * 1000 / bitlen. Complexity: O(bytes).
pub fn rocksdb_table_bloom_fill_permille(t: &RocksDbTable) -> Int {
  if t.bloom_bitlen <= 0 { return 0; }
  let bits = rocksdb_table_bloom_set_bits(t);
  return bits * 1000 / t.bloom_bitlen;
}

/// Index of the newest entry visible at `snapshot` for (cf, key), or -1.
/// Complexity: O(count).
pub fn rocksdb_table_find(t: &RocksDbTable, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  if key.len() == 0 { return -1; }
  var best = -1;
  var best_seq = -1;
  var i = 0;
  while i < t.count {
    let ecf: Int = t.cfs[i];
    if ecf == cf {
      let koff: Int = t.key_offsets[i];
      let ksz: Int = t.key_sizes[i];
      if _rocksdb_blob_key_eq(t.keys_data, koff, ksz, key) {
        let s: Int = t.seqs[i];
        if s <= snapshot && s > best_seq {
          best_seq = s;
          best = i;
        }
      }
    }
    i = i + 1;
  }
  return best;
}

/// Newest visible value at `snapshot`, or Err("rocksdb: not found") for an
/// absent key and for a tombstone. Complexity: O(count + value).
pub fn rocksdb_table_get(t: &RocksDbTable, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Result[Vec[UInt8], Str] {
  let i = rocksdb_table_find(t, cf, key, snapshot);
  if i < 0 { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  let ty: Int = t.types[i];
  if ty == _ROCKSDB_TYPE_DELETE { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  return _rocksdb_ok_bytes(rocksdb_table_entry_value(t, i));
}

// --------------------------------------------------
//  Version and levels
// --------------------------------------------------

/// A fresh empty version with the given level layout (all values clamped:
/// trigger >= 1, base >= 1024, multiplier >= 2, 2 <= max_levels <= 7,
/// block_entries >= 1, bloom sizes >= 1). Complexity: O(1).
pub fn rocksdb_version_new(l0_trigger: Int, level_base_bytes: Int, level_multiplier: Int, max_levels: Int, block_entries: Int, bloom_bits_per_key: Int, bloom_hashes: Int) -> RocksDbVersion {
  var t = l0_trigger;
  if t < 1 { t = 1; }
  var base = level_base_bytes;
  if base < 1024 { base = 1024; }
  var mult = level_multiplier;
  if mult < 2 { mult = 2; }
  var ml = max_levels;
  if ml < 2 { ml = 2; }
  if ml > _ROCKSDB_MAX_LEVELS { ml = _ROCKSDB_MAX_LEVELS; }
  var be = block_entries;
  if be < 1 { be = 1; }
  var bpk = bloom_bits_per_key;
  if bpk < 1 { bpk = 1; }
  var bh = bloom_hashes;
  if bh < 1 { bh = 1; }
  return RocksDbVersion{
    l0_trigger: t;
    level_base_bytes: base;
    level_multiplier: mult;
    max_levels: ml;
    block_entries: be;
    bloom_bits_per_key: bpk;
    bloom_hashes: bh;
    level_count: 0;
    file_count: 0;
    next_file_number: 1;
    total_bytes: 0;
    file_level: Vec[Int].new();
    file_number: Vec[Int].new();
    file_bytes: Vec[Int].new();
    file_entry_start: Vec[Int].new();
    file_entry_count: Vec[Int].new();
    file_block_count: Vec[Int].new();
    file_index_start: Vec[Int].new();
    file_index_count: Vec[Int].new();
    file_bloom_offset: Vec[Int].new();
    file_bloom_size: Vec[Int].new();
    file_bloom_bitlen: Vec[Int].new();
    file_minkey_cf: Vec[Int].new();
    file_minkey_data: Vec[UInt8].new();
    file_minkey_offsets: Vec[Int].new();
    file_minkey_sizes: Vec[Int].new();
    file_maxkey_cf: Vec[Int].new();
    file_maxkey_data: Vec[UInt8].new();
    file_maxkey_offsets: Vec[Int].new();
    file_maxkey_sizes: Vec[Int].new();
    ent_keys_data: Vec[UInt8].new();
    ent_key_offsets: Vec[Int].new();
    ent_key_sizes: Vec[Int].new();
    ent_values_data: Vec[UInt8].new();
    ent_value_offsets: Vec[Int].new();
    ent_value_sizes: Vec[Int].new();
    ent_seqs: Vec[Int].new();
    ent_types: Vec[Int].new();
    ent_cfs: Vec[Int].new();
    idx_data: Vec[UInt8].new();
    idx_offsets: Vec[Int].new();
    idx_sizes: Vec[Int].new();
    bloom_data: Vec[UInt8].new();
  };
}

// Append every entry of table `t` into the version's flattened arrays and
// insert the file metadata at its (level, file number) position.
fn _rocksdb_version_insert_file(v: &mut RocksDbVersion, t: &RocksDbTable, level: Int) -> Int {
  if t.count <= 0 { return -1; }
  if level < 0 { return -1; }
  if level >= v.max_levels { return -1; }
  var pos = 0;
  var found = false;
  while pos < v.file_count && !found {
    let lv: Int = v.file_level[pos];
    if lv > level { found = true; } else { pos = pos + 1; }
  }
  let fk = rocksdb_table_first_key(t);
  let lk = rocksdb_table_last_key(t);
  let fk_cf: Int = t.cfs[0];
  let lk_cf: Int = t.cfs[t.count - 1];
  v.file_level.insert(pos, level);
  v.file_number.insert(pos, t.file_number);
  v.file_bytes.insert(pos, t.bytes);
  v.file_entry_start.insert(pos, v.ent_seqs.len());
  v.file_entry_count.insert(pos, t.count);
  v.file_block_count.insert(pos, t.block_count);
  v.file_index_start.insert(pos, v.idx_sizes.len());
  v.file_index_count.insert(pos, t.index_sizes.len());
  v.file_bloom_offset.insert(pos, v.bloom_data.len());
  v.file_bloom_size.insert(pos, t.bloom_data.len());
  v.file_bloom_bitlen.insert(pos, t.bloom_bitlen);
  v.file_minkey_cf.insert(pos, fk_cf);
  v.file_minkey_offsets.insert(pos, v.file_minkey_data.len());
  v.file_minkey_sizes.insert(pos, fk.len());
  v.file_maxkey_cf.insert(pos, lk_cf);
  v.file_maxkey_offsets.insert(pos, v.file_maxkey_data.len());
  v.file_maxkey_sizes.insert(pos, lk.len());
  _rocksdb_append(&mut v.file_minkey_data, &fk);
  _rocksdb_append(&mut v.file_maxkey_data, &lk);
  let kd: Vec[UInt8] = t.keys_data;
  let ko: Vec[Int] = t.key_offsets;
  let ks: Vec[Int] = t.key_sizes;
  let vd: Vec[UInt8] = t.values_data;
  let vo: Vec[Int] = t.value_offsets;
  let vs: Vec[Int] = t.value_sizes;
  var i = 0;
  while i < t.count {
    let koff: Int = ko[i];
    let ksz: Int = ks[i];
    let ekey = _rocksdb_copy_range(kd, koff, ksz);
    v.ent_key_offsets.push(v.ent_keys_data.len());
    v.ent_key_sizes.push(ksz);
    _rocksdb_append(&mut v.ent_keys_data, &ekey);
    let voff: Int = vo[i];
    let vsz: Int = vs[i];
    let eval = _rocksdb_copy_range(vd, voff, vsz);
    v.ent_value_offsets.push(v.ent_values_data.len());
    v.ent_value_sizes.push(vsz);
    _rocksdb_append(&mut v.ent_values_data, &eval);
    let e_seq: Int = t.seqs[i];
    let e_ty: Int = t.types[i];
    let e_cf: Int = t.cfs[i];
    v.ent_seqs.push(e_seq);
    v.ent_types.push(e_ty);
    v.ent_cfs.push(e_cf);
    i = i + 1;
  }
  var b = 0;
  while b < t.index_sizes.len() {
    let ioff: Int = t.index_offsets[b];
    let isz: Int = t.index_sizes[b];
    let ikey = _rocksdb_copy_range(t.index_data, ioff, isz);
    v.idx_offsets.push(v.idx_data.len());
    v.idx_sizes.push(isz);
    _rocksdb_append(&mut v.idx_data, &ikey);
    b = b + 1;
  }
  var z = 0;
  while z < t.bloom_data.len() {
    let bb: UInt8 = t.bloom_data[z];
    v.bloom_data.push(bb);
    z = z + 1;
  }
  v.file_count = v.file_count + 1;
  v.total_bytes = v.total_bytes + t.bytes;
  if level + 1 > v.level_count { v.level_count = level + 1; }
  return pos;
}

/// Add a table to `level` (0..max_levels-1) preserving (level, file
/// number) order. Returns the file index, or -1 for an empty table or a
/// level outside the layout. Complexity: O(table bytes + files).
pub fn rocksdb_version_add_table(v: &mut RocksDbVersion, t: &RocksDbTable, level: Int) -> Int {
  return _rocksdb_version_insert_file(v, t, level);
}

// Copy file `fi`'s entries into the output parallel arrays; returns the
// number of entries appended.
fn _rocksdb_version_gather_file(v: &RocksDbVersion, fi: Int, cfs: &mut Vec[Int], seqs: &mut Vec[Int], types: &mut Vec[Int], kd: &mut Vec[UInt8], ko: &mut Vec[Int], ks: &mut Vec[Int], vd: &mut Vec[UInt8], vo: &mut Vec[Int], vs: &mut Vec[Int]) -> Int {
  let start: Int = v.file_entry_start[fi];
  let cnt: Int = v.file_entry_count[fi];
  var i = 0;
  while i < cnt {
    let e = start + i;
    let koff: Int = v.ent_key_offsets[e];
    let ksz: Int = v.ent_key_sizes[e];
    let ekey = _rocksdb_copy_range(v.ent_keys_data, koff, ksz);
    ko.push(kd.len());
    ks.push(ksz);
    _rocksdb_append(kd, &ekey);
    let voff: Int = v.ent_value_offsets[e];
    let vsz: Int = v.ent_value_sizes[e];
    let eval = _rocksdb_copy_range(v.ent_values_data, voff, vsz);
    vo.push(vd.len());
    vs.push(vsz);
    _rocksdb_append(vd, &eval);
    let e_cf: Int = v.ent_cfs[e];
    let e_seq: Int = v.ent_seqs[e];
    let e_ty: Int = v.ent_types[e];
    cfs.push(e_cf);
    seqs.push(e_seq);
    types.push(e_ty);
    i = i + 1;
  }
  return cnt;
}

// True when entry `a` sorts after entry `b` in (cf asc, key asc, seq desc).
fn _rocksdb_order_after(a: Int, b: Int, cfs: &Vec[Int], seqs: &Vec[Int], kd: &Vec[UInt8], ko: &Vec[Int], ks: &Vec[Int]) -> Bool {
  let acf: Int = cfs[a];
  let bcf: Int = cfs[b];
  if acf != bcf { return acf > bcf; }
  let aoff: Int = ko[a];
  let asz: Int = ks[a];
  let boff: Int = ko[b];
  let bsz: Int = ks[b];
  let c = _rocksdb_blob_cmp(kd, aoff, asz, kd, boff, bsz);
  if c != 0 { return c > 0; }
  let aseq: Int = seqs[a];
  let bseq: Int = seqs[b];
  return aseq < bseq;
}

// Sort the entry ids 0..count by (cf asc, key asc, seq desc); insertion
// sort, deterministic and stable. Complexity: O(count^2).
fn _rocksdb_sort_order(count: Int, cfs: &Vec[Int], seqs: &Vec[Int], kd: &Vec[UInt8], ko: &Vec[Int], ks: &Vec[Int]) -> Vec[Int] {
  var order = Vec[Int].new();
  var i = 0;
  while i < count {
    order.push(i);
    i = i + 1;
  }
  i = 1;
  while i < count {
    let cur: Int = order[i];
    var j = i - 1;
    var moving = true;
    while j >= 0 && moving {
      let prev: Int = order[j];
      if _rocksdb_order_after(prev, cur, cfs, seqs, kd, ko, ks) {
        order[j + 1] = prev;
        j = j - 1;
      } else {
        moving = false;
      }
    }
    order[j + 1] = cur;
    i = i + 1;
  }
  return order;
}

// True when (cf, key) lies inside file `fi`'s stored [min, max] bounds.
fn _rocksdb_version_file_in_range(v: &RocksDbVersion, fi: Int, cf: Int, key: &Vec[UInt8]) -> Bool {
  let min_cf: Int = v.file_minkey_cf[fi];
  let min_off: Int = v.file_minkey_offsets[fi];
  let min_sz: Int = v.file_minkey_sizes[fi];
  let max_cf: Int = v.file_maxkey_cf[fi];
  let max_off: Int = v.file_maxkey_offsets[fi];
  let max_sz: Int = v.file_maxkey_sizes[fi];
  let min_key = _rocksdb_copy_range(v.file_minkey_data, min_off, min_sz);
  let c1 = _rocksdb_cf_key_cmp(cf, key, min_cf, &min_key);
  if c1 < 0 { return false; }
  let max_key = _rocksdb_copy_range(v.file_maxkey_data, max_off, max_sz);
  let c2 = _rocksdb_cf_key_cmp(cf, key, max_cf, &max_key);
  if c2 > 0 { return false; }
  return true;
}

// Range plus Bloom probe: false is definitive for a real (cf, key) lookup.
fn _rocksdb_version_file_maybe(v: &RocksDbVersion, fi: Int, cf: Int, key: &Vec[UInt8]) -> Bool {
  if !_rocksdb_version_file_in_range(v, fi, cf, key) { return false; }
  let off: Int = v.file_bloom_offset[fi];
  let bitlen: Int = v.file_bloom_bitlen[fi];
  return _rocksdb_bloom_probe(v.bloom_data, off, bitlen, v.bloom_hashes, cf, key);
}

/// Index of the newest entry visible at `snapshot` for (cf, key) across all
/// levels, or -1. Range and Bloom bounds skip files that cannot contain the
/// key (a Bloom false is definitive). Complexity: O(files + entries).
pub fn rocksdb_version_find(v: &RocksDbVersion, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  if key.len() == 0 { return -1; }
  var best = -1;
  var best_seq = -1;
  var i = 0;
  while i < v.file_count {
    if _rocksdb_version_file_maybe(v, i, cf, key) {
      let start: Int = v.file_entry_start[i];
      let cnt: Int = v.file_entry_count[i];
      var e = start;
      let stop = start + cnt;
      while e < stop {
        let ecf: Int = v.ent_cfs[e];
        if ecf == cf {
          let koff: Int = v.ent_key_offsets[e];
          let ksz: Int = v.ent_key_sizes[e];
          if _rocksdb_blob_key_eq(v.ent_keys_data, koff, ksz, key) {
            let s: Int = v.ent_seqs[e];
            if s <= snapshot && s > best_seq {
              best_seq = s;
              best = e;
            }
          }
        }
        e = e + 1;
      }
    }
    i = i + 1;
  }
  return best;
}

/// Newest visible value at `snapshot`, or Err("rocksdb: not found") for an
/// absent key and for a tombstone. Complexity: O(files + entries + value).
pub fn rocksdb_version_get(v: &RocksDbVersion, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Result[Vec[UInt8], Str] {
  let i = rocksdb_version_find(v, cf, key, snapshot);
  if i < 0 { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  let ty: Int = v.ent_types[i];
  if ty == _ROCKSDB_TYPE_DELETE { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  let voff: Int = v.ent_value_offsets[i];
  let vsz: Int = v.ent_value_sizes[i];
  return _rocksdb_ok_bytes(_rocksdb_copy_range(v.ent_values_data, voff, vsz));
}

/// Column family of version entry `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_entry_cf(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.ent_cfs.len() { return -1; }
  return v.ent_cfs[i];
}

/// Sequence of version entry `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_entry_seq(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.ent_seqs.len() { return -1; }
  return v.ent_seqs[i];
}

/// Type of version entry `i` (1 value, 0 tombstone), or -1 out of range.
/// Complexity: O(1).
pub fn rocksdb_version_entry_type(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.ent_types.len() { return -1; }
  return v.ent_types[i];
}

/// Key of version entry `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_version_entry_key(v: &RocksDbVersion, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= v.ent_key_sizes.len() { return Vec[UInt8].new(); }
  let koff: Int = v.ent_key_offsets[i];
  let ksz: Int = v.ent_key_sizes[i];
  return _rocksdb_copy_range(v.ent_keys_data, koff, ksz);
}

/// Value of version entry `i` (empty Vec out of range). Complexity:
/// O(value).
pub fn rocksdb_version_entry_value(v: &RocksDbVersion, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= v.ent_value_sizes.len() { return Vec[UInt8].new(); }
  let voff: Int = v.ent_value_offsets[i];
  let vsz: Int = v.ent_value_sizes[i];
  return _rocksdb_copy_range(v.ent_values_data, voff, vsz);
}

/// Total charged bytes of all files. Complexity: O(1).
pub fn rocksdb_version_total_bytes(v: &RocksDbVersion) -> Int {
  return v.total_bytes;
}

/// Number of files across all levels. Complexity: O(1).
pub fn rocksdb_version_file_count(v: &RocksDbVersion) -> Int {
  return v.file_count;
}

/// Next file number the version will hand out. Complexity: O(1).
pub fn rocksdb_version_next_file_number(v: &RocksDbVersion) -> Int {
  return v.next_file_number;
}

/// Number of files at `level`. Complexity: O(files).
pub fn rocksdb_version_level_file_count(v: &RocksDbVersion, level: Int) -> Int {
  if level < 0 { return 0; }
  var n = 0;
  var i = 0;
  while i < v.file_count {
    let lv: Int = v.file_level[i];
    if lv == level { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Sum of file bytes at `level`. Complexity: O(files).
pub fn rocksdb_version_level_bytes(v: &RocksDbVersion, level: Int) -> Int {
  if level < 0 { return 0; }
  var n = 0;
  var i = 0;
  while i < v.file_count {
    let lv: Int = v.file_level[i];
    if lv == level {
      let b: Int = v.file_bytes[i];
      n = n + b;
    }
    i = i + 1;
  }
  return n;
}

/// Byte target of level `level` (>= 1): base * multiplier^(level-1).
/// Level 0 has no byte target and returns -1. Complexity: O(level).
pub fn rocksdb_version_level_target_bytes(v: &RocksDbVersion, level: Int) -> Int {
  if level < 1 { return -1; }
  var target = v.level_base_bytes;
  var i = 1;
  while i < level {
    target = target * v.level_multiplier;
    i = i + 1;
  }
  return target;
}

/// Compaction score of `level` in per-mille units: L0 scores
/// file_count * 1000 / l0_trigger; Ln >= 1 scores bytes * 1000 / target.
/// A score of 1000 or more means the level needs compaction. Levels outside
/// the layout and the bottom level return 0. Complexity: O(files + level).
pub fn rocksdb_version_score(v: &RocksDbVersion, level: Int) -> Int {
  if level < 0 { return 0; }
  if level >= v.max_levels { return 0; }
  if level == v.max_levels - 1 { return 0; }
  if level == 0 {
    let files = rocksdb_version_level_file_count(v, 0);
    return files * 1000 / v.l0_trigger;
  }
  let target = rocksdb_version_level_target_bytes(v, level);
  if target <= 0 { return 0; }
  let bytes = rocksdb_version_level_bytes(v, level);
  return bytes * 1000 / target;
}

/// Deterministic compaction picker: the non-bottom level with the highest
/// score >= 1000, ties resolved to the lowest level; -1 when nothing needs
/// compaction. Complexity: O(files + levels).
pub fn rocksdb_version_pick_level(v: &RocksDbVersion) -> Int {
  var best = -1;
  var best_score = 999;
  var level = 0;
  while level < v.max_levels - 1 {
    let s = rocksdb_version_score(v, level);
    if s >= 1000 && s > best_score {
      best_score = s;
      best = level;
    }
    level = level + 1;
  }
  return best;
}

/// True when any non-bottom level scores >= 1000. Complexity: O(files).
pub fn rocksdb_version_needs_compaction(v: &RocksDbVersion) -> Bool {
  return rocksdb_version_pick_level(v) >= 0;
}

/// Highest level that contains at least one file, or -1 when empty.
/// Complexity: O(files).
pub fn rocksdb_version_max_level(v: &RocksDbVersion) -> Int {
  var m = -1;
  var i = 0;
  while i < v.file_count {
    let lv: Int = v.file_level[i];
    if lv > m { m = lv; }
    i = i + 1;
  }
  return m;
}

/// Level of file `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_file_level(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.file_count { return -1; }
  return v.file_level[i];
}

/// File number of file `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_file_number(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.file_count { return -1; }
  return v.file_number[i];
}

/// Charged bytes of file `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_file_bytes(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.file_count { return -1; }
  return v.file_bytes[i];
}

/// Entry count of file `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_version_file_entry_count(v: &RocksDbVersion, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.file_count { return -1; }
  return v.file_entry_count[i];
}

/// First key bound of file `i` (empty Vec out of range). Complexity:
/// O(key).
pub fn rocksdb_version_file_first_key(v: &RocksDbVersion, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= v.file_count { return Vec[UInt8].new(); }
  let off: Int = v.file_minkey_offsets[i];
  let sz: Int = v.file_minkey_sizes[i];
  return _rocksdb_copy_range(v.file_minkey_data, off, sz);
}

/// Last key bound of file `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_version_file_last_key(v: &RocksDbVersion, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= v.file_count { return Vec[UInt8].new(); }
  let off: Int = v.file_maxkey_offsets[i];
  let sz: Int = v.file_maxkey_sizes[i];
  return _rocksdb_copy_range(v.file_maxkey_data, off, sz);
}

/// First file at `level` whose (cf, key) bounds contain the key, or -1.
/// Structural (no Bloom probe). Complexity: O(files).
pub fn rocksdb_version_find_file(v: &RocksDbVersion, level: Int, cf: Int, key: &Vec[UInt8]) -> Int {
  var i = 0;
  while i < v.file_count {
    let lv: Int = v.file_level[i];
    if lv == level && _rocksdb_version_file_in_range(v, i, cf, key) { return i; }
    i = i + 1;
  }
  return -1;
}

// Rebuild the version without files whose entry in `dropped` is 1. All
// flattened sections are re-packed, so entry/index/Bloom offsets stay
// consistent and total_bytes is recomputed.
fn _rocksdb_version_remove_files(v: &mut RocksDbVersion, dropped: &Vec[Int]) {
  let n = v.file_count;
  var keep = Vec[Int].new();
  var i = 0;
  while i < n {
    keep.push(1);
    i = i + 1;
  }
  var d = 0;
  while d < dropped.len() {
    let idx: Int = dropped[d];
    if idx >= 0 && idx < n { keep[idx] = 0; }
    d = d + 1;
  }
  var nl_level = Vec[Int].new();
  var nl_number = Vec[Int].new();
  var nl_bytes = Vec[Int].new();
  var nl_entry_start = Vec[Int].new();
  var nl_entry_count = Vec[Int].new();
  var nl_block_count = Vec[Int].new();
  var nl_index_start = Vec[Int].new();
  var nl_index_count = Vec[Int].new();
  var nl_bloom_offset = Vec[Int].new();
  var nl_bloom_size = Vec[Int].new();
  var nl_bloom_bitlen = Vec[Int].new();
  var nl_min_cf = Vec[Int].new();
  var nl_min_data = Vec[UInt8].new();
  var nl_min_offsets = Vec[Int].new();
  var nl_min_sizes = Vec[Int].new();
  var nl_max_cf = Vec[Int].new();
  var nl_max_data = Vec[UInt8].new();
  var nl_max_offsets = Vec[Int].new();
  var nl_max_sizes = Vec[Int].new();
  var ne_kd = Vec[UInt8].new();
  var ne_ko = Vec[Int].new();
  var ne_ks = Vec[Int].new();
  var ne_vd = Vec[UInt8].new();
  var ne_vo = Vec[Int].new();
  var ne_vs = Vec[Int].new();
  var ne_seqs = Vec[Int].new();
  var ne_types = Vec[Int].new();
  var ne_cfs = Vec[Int].new();
  var ni_data = Vec[UInt8].new();
  var ni_offsets = Vec[Int].new();
  var ni_sizes = Vec[Int].new();
  var nb_data = Vec[UInt8].new();
  var new_count = 0;
  var new_total = 0;
  i = 0;
  while i < n {
    let k: Int = keep[i];
    if k == 1 {
      nl_level.push(v.file_level[i]);
      nl_number.push(v.file_number[i]);
      let fb: Int = v.file_bytes[i];
      nl_bytes.push(fb);
      new_total = new_total + fb;
      nl_entry_start.push(ne_ko.len());
      let ecnt: Int = v.file_entry_count[i];
      nl_entry_count.push(ecnt);
      nl_block_count.push(v.file_block_count[i]);
      nl_index_start.push(ni_offsets.len());
      let icnt: Int = v.file_index_count[i];
      nl_index_count.push(icnt);
      nl_bloom_offset.push(nb_data.len());
      let bsz: Int = v.file_bloom_size[i];
      nl_bloom_size.push(bsz);
      nl_bloom_bitlen.push(v.file_bloom_bitlen[i]);
      nl_min_cf.push(v.file_minkey_cf[i]);
      let moff: Int = v.file_minkey_offsets[i];
      let msz: Int = v.file_minkey_sizes[i];
      nl_min_offsets.push(nl_min_data.len());
      nl_min_sizes.push(msz);
      let mk = _rocksdb_copy_range(v.file_minkey_data, moff, msz);
      _rocksdb_append(&mut nl_min_data, &mk);
      nl_max_cf.push(v.file_maxkey_cf[i]);
      let xoff: Int = v.file_maxkey_offsets[i];
      let xsz: Int = v.file_maxkey_sizes[i];
      nl_max_offsets.push(nl_max_data.len());
      nl_max_sizes.push(xsz);
      let xk = _rocksdb_copy_range(v.file_maxkey_data, xoff, xsz);
      _rocksdb_append(&mut nl_max_data, &xk);
      let estart: Int = v.file_entry_start[i];
      var e = 0;
      while e < ecnt {
        let src = estart + e;
        let koff: Int = v.ent_key_offsets[src];
        let ksz: Int = v.ent_key_sizes[src];
        let ek = _rocksdb_copy_range(v.ent_keys_data, koff, ksz);
        ne_ko.push(ne_kd.len());
        ne_ks.push(ksz);
        _rocksdb_append(&mut ne_kd, &ek);
        let voff: Int = v.ent_value_offsets[src];
        let vsz: Int = v.ent_value_sizes[src];
        let ev = _rocksdb_copy_range(v.ent_values_data, voff, vsz);
        ne_vo.push(ne_vd.len());
        ne_vs.push(vsz);
        _rocksdb_append(&mut ne_vd, &ev);
        ne_seqs.push(v.ent_seqs[src]);
        ne_types.push(v.ent_types[src]);
        ne_cfs.push(v.ent_cfs[src]);
        e = e + 1;
      }
      let istart: Int = v.file_index_start[i];
      var b = 0;
      while b < icnt {
        let src2 = istart + b;
        let ioff: Int = v.idx_offsets[src2];
        let isz: Int = v.idx_sizes[src2];
        let ik = _rocksdb_copy_range(v.idx_data, ioff, isz);
        ni_offsets.push(ni_data.len());
        ni_sizes.push(isz);
        _rocksdb_append(&mut ni_data, &ik);
        b = b + 1;
      }
      let boff: Int = v.file_bloom_offset[i];
      var z = 0;
      while z < bsz {
        let bb: UInt8 = v.bloom_data[boff + z];
        nb_data.push(bb);
        z = z + 1;
      }
      new_count = new_count + 1;
    }
    i = i + 1;
  }
  v.file_level = nl_level;
  v.file_number = nl_number;
  v.file_bytes = nl_bytes;
  v.file_entry_start = nl_entry_start;
  v.file_entry_count = nl_entry_count;
  v.file_block_count = nl_block_count;
  v.file_index_start = nl_index_start;
  v.file_index_count = nl_index_count;
  v.file_bloom_offset = nl_bloom_offset;
  v.file_bloom_size = nl_bloom_size;
  v.file_bloom_bitlen = nl_bloom_bitlen;
  v.file_minkey_cf = nl_min_cf;
  v.file_minkey_data = nl_min_data;
  v.file_minkey_offsets = nl_min_offsets;
  v.file_minkey_sizes = nl_min_sizes;
  v.file_maxkey_cf = nl_max_cf;
  v.file_maxkey_data = nl_max_data;
  v.file_maxkey_offsets = nl_max_offsets;
  v.file_maxkey_sizes = nl_max_sizes;
  v.ent_keys_data = ne_kd;
  v.ent_key_offsets = ne_ko;
  v.ent_key_sizes = ne_ks;
  v.ent_values_data = ne_vd;
  v.ent_value_offsets = ne_vo;
  v.ent_value_sizes = ne_vs;
  v.ent_seqs = ne_seqs;
  v.ent_types = ne_types;
  v.ent_cfs = ne_cfs;
  v.idx_data = ni_data;
  v.idx_offsets = ni_offsets;
  v.idx_sizes = ni_sizes;
  v.bloom_data = nb_data;
  v.file_count = new_count;
  v.total_bytes = new_total;
  var lc = 0;
  var j = 0;
  while j < new_count {
    let l: Int = v.file_level[j];
    if l + 1 > lc { lc = l + 1; }
    j = j + 1;
  }
  v.level_count = lc;
}

// True when file `fi`'s bounds intersect the [min, max] (cf, key) range.
fn _rocksdb_version_file_intersects(v: &RocksDbVersion, fi: Int, min_cf: Int, min_key: &Vec[UInt8], max_cf: Int, max_key: &Vec[UInt8]) -> Bool {
  let fmin_cf: Int = v.file_minkey_cf[fi];
  let fmin_off: Int = v.file_minkey_offsets[fi];
  let fmin_sz: Int = v.file_minkey_sizes[fi];
  let fmin = _rocksdb_copy_range(v.file_minkey_data, fmin_off, fmin_sz);
  let fmax_cf: Int = v.file_maxkey_cf[fi];
  let fmax_off: Int = v.file_maxkey_offsets[fi];
  let fmax_sz: Int = v.file_maxkey_sizes[fi];
  let fmax = _rocksdb_copy_range(v.file_maxkey_data, fmax_off, fmax_sz);
  if _rocksdb_cf_key_cmp(fmax_cf, &fmax, min_cf, min_key) < 0 { return false; }
  if _rocksdb_cf_key_cmp(fmin_cf, &fmin, max_cf, max_key) > 0 { return false; }
  return true;
}

/// Run at most `max_rounds` compactions, deterministic in the version state.
///
/// Each round picks the highest-scoring non-bottom level, selects all L0
/// files (or the oldest file at deeper levels) plus every overlapping file
/// at level+1, merges them into one new table at level+1 and removes the
/// inputs. `oldest_snapshot` is the oldest live snapshot sequence, or -1
/// when none: with -1 only the newest version of each (cf, key) is kept
/// (a tombstone is dropped when the output lands at the bottom level);
/// otherwise every version above the snapshot plus the newest version at
/// or below it is kept. Complexity: O(rounds * entries^2).
pub fn rocksdb_version_compact(v: &mut RocksDbVersion, max_rounds: Int, oldest_snapshot: Int) -> RocksDbCompactionReport {
  var rounds = 0;
  var levels_picked = 0;
  var input_files = 0;
  var output_files = 0;
  var input_entries = 0;
  var output_entries = 0;
  var dropped_entries = 0;
  var bytes_in = 0;
  var bytes_out = 0;
  var last_level = -1;
  var going = true;
  var r = 0;
  while r < max_rounds && going {
    let lvl = rocksdb_version_pick_level(v);
    if lvl < 0 {
      going = false;
    } else {
      let target = lvl + 1;
      if target >= v.max_levels {
        going = false;
      } else {
        levels_picked = levels_picked + 1;
        var chosen = Vec[Int].new();
        var min_cf = 0;
        var min_key = Vec[UInt8].new();
        var max_cf = 0;
        var max_key = Vec[UInt8].new();
        var have_range = false;
        var i = 0;
        while i < v.file_count {
          let lv: Int = v.file_level[i];
          if lv == lvl {
            if lvl == 0 {
              chosen.push(i);
            } elif chosen.len() == 0 {
              chosen.push(i);
            }
            let fmin_cf: Int = v.file_minkey_cf[i];
            let fmin_off: Int = v.file_minkey_offsets[i];
            let fmin_sz: Int = v.file_minkey_sizes[i];
            let fmin = _rocksdb_copy_range(v.file_minkey_data, fmin_off, fmin_sz);
            let fmax_cf: Int = v.file_maxkey_cf[i];
            let fmax_off: Int = v.file_maxkey_offsets[i];
            let fmax_sz: Int = v.file_maxkey_sizes[i];
            let fmax = _rocksdb_copy_range(v.file_maxkey_data, fmax_off, fmax_sz);
            if !have_range {
              min_cf = fmin_cf;
              min_key = fmin;
              max_cf = fmax_cf;
              max_key = fmax;
              have_range = true;
            } else {
              if _rocksdb_cf_key_cmp(fmin_cf, &fmin, min_cf, &min_key) < 0 {
                min_cf = fmin_cf;
                min_key = fmin;
              }
              if _rocksdb_cf_key_cmp(fmax_cf, &fmax, max_cf, &max_key) > 0 {
                max_cf = fmax_cf;
                max_key = fmax;
              }
            }
          }
          i = i + 1;
        }
        if chosen.len() == 0 {
          going = false;
        } else {
          i = 0;
          while i < v.file_count {
            let lv2: Int = v.file_level[i];
            if lv2 == target && _rocksdb_version_file_intersects(v, i, min_cf, &min_key, max_cf, &max_key) {
              chosen.push(i);
            }
            i = i + 1;
          }
          _rocksdb_sort_ints(&mut chosen);
          var cfs = Vec[Int].new();
          var seqs = Vec[Int].new();
          var itypes = Vec[Int].new();
          var kd = Vec[UInt8].new();
          var ko = Vec[Int].new();
          var ks = Vec[Int].new();
          var vd = Vec[UInt8].new();
          var vo = Vec[Int].new();
          var vs = Vec[Int].new();
          var ci = 0;
          while ci < chosen.len() {
            let fi: Int = chosen[ci];
            let fsz: Int = v.file_bytes[fi];
            bytes_in = bytes_in + fsz;
            let fcnt: Int = v.file_entry_count[fi];
            input_entries = input_entries + fcnt;
            input_files = input_files + 1;
            _rocksdb_version_gather_file(v, fi, &mut cfs, &mut seqs, &mut itypes, &mut kd, &mut ko, &mut ks, &mut vd, &mut vo, &mut vs);
            ci = ci + 1;
          }
          let gcount = seqs.len();
          let order = _rocksdb_sort_order(gcount, &cfs, &seqs, &kd, &ko, &ks);
          var keepv = Vec[Int].new();
          i = 0;
          while i < gcount {
            keepv.push(0);
            i = i + 1;
          }
          var oi = 0;
          while oi < order.len() {
            let g0: Int = order[oi];
            var gj = oi + 1;
            var scanning = true;
            while gj < order.len() && scanning {
              let gb: Int = order[gj];
              let g0cf: Int = cfs[g0];
              let gbcf: Int = cfs[gb];
              var same = false;
              if g0cf == gbcf {
                let o1: Int = ko[g0];
                let s1: Int = ks[g0];
                let o2: Int = ko[gb];
                let s2: Int = ks[gb];
                if _rocksdb_blob_cmp(kd, o1, s1, kd, o2, s2) == 0 { same = true; }
              }
              if same {
                gj = gj + 1;
              } else {
                scanning = false;
              }
            }
            if oldest_snapshot < 0 {
              keepv[g0] = 1;
              let g0ty: Int = itypes[g0];
              if target == v.max_levels - 1 && g0ty == _ROCKSDB_TYPE_DELETE {
                keepv[g0] = 0;
              }
            } else {
              var gk = oi;
              while gk < gj {
                let idx: Int = order[gk];
                let s: Int = seqs[idx];
                if s > oldest_snapshot { keepv[idx] = 1; }
                gk = gk + 1;
              }
              var gb2 = oi;
              var found_base = false;
              while gb2 < gj && !found_base {
                let idx2: Int = order[gb2];
                let s2: Int = seqs[idx2];
                if s2 <= oldest_snapshot {
                  keepv[idx2] = 1;
                  found_base = true;
                }
                gb2 = gb2 + 1;
              }
            }
            oi = gj;
          }
          var ocfs = Vec[Int].new();
          var oseqs = Vec[Int].new();
          var otypes = Vec[Int].new();
          var okd = Vec[UInt8].new();
          var oko = Vec[Int].new();
          var oks = Vec[Int].new();
          var ovd = Vec[UInt8].new();
          var ovo = Vec[Int].new();
          var ovs = Vec[Int].new();
          var ei = 0;
          while ei < order.len() {
            let idx3: Int = order[ei];
            let k: Int = keepv[idx3];
            if k == 1 {
              let koff: Int = ko[idx3];
              let ksz: Int = ks[idx3];
              let ekey = _rocksdb_copy_range(kd, koff, ksz);
              oko.push(okd.len());
              oks.push(ksz);
              _rocksdb_append(&mut okd, &ekey);
              let voff: Int = vo[idx3];
              let vsz: Int = vs[idx3];
              let eval = _rocksdb_copy_range(vd, voff, vsz);
              ovo.push(ovd.len());
              ovs.push(vsz);
              _rocksdb_append(&mut ovd, &eval);
              let c3: Int = cfs[idx3];
              let s3: Int = seqs[idx3];
              let t3: Int = itypes[idx3];
              ocfs.push(c3);
              oseqs.push(s3);
              otypes.push(t3);
            }
            ei = ei + 1;
          }
          let ocount = oseqs.len();
          _rocksdb_version_remove_files(v, &chosen);
          if ocount > 0 {
            let new_num: Int = v.next_file_number;
            let nt = _rocksdb_table_from_arrays(new_num, v.block_entries, v.bloom_bits_per_key, v.bloom_hashes, ocount, &ocfs, &oseqs, &otypes, &okd, &oko, &oks, &ovd, &ovo, &ovs);
            let added = _rocksdb_version_insert_file(v, &nt, target);
            if added >= 0 {
              v.next_file_number = new_num + 1;
              output_files = output_files + 1;
              output_entries = output_entries + ocount;
              let nb: Int = nt.bytes;
              bytes_out = bytes_out + nb;
            }
          }
          dropped_entries = dropped_entries + (gcount - ocount);
          last_level = target;
          rounds = rounds + 1;
        }
      }
    }
    r = r + 1;
  }
  return RocksDbCompactionReport{
    rounds: rounds;
    levels_picked: levels_picked;
    input_files: input_files;
    output_files: output_files;
    input_entries: input_entries;
    output_entries: output_entries;
    dropped_entries: dropped_entries;
    bytes_in: bytes_in;
    bytes_out: bytes_out;
    last_level: last_level;
  };
}

// --------------------------------------------------
//  Snapshot iterator and range scan
// --------------------------------------------------

// Append every visible memtable entry for (cf, <= snapshot).
fn _rocksdb_gather_mt(mt: &RocksDbMemtable, cf: Int, snapshot: Int, cfs: &mut Vec[Int], seqs: &mut Vec[Int], types: &mut Vec[Int], kd: &mut Vec[UInt8], ko: &mut Vec[Int], ks: &mut Vec[Int], vd: &mut Vec[UInt8], vo: &mut Vec[Int], vs: &mut Vec[Int]) -> Int {
  var n = 0;
  var i = 0;
  while i < mt.count {
    let ecf: Int = mt.cfs[i];
    let es: Int = mt.seqs[i];
    if ecf == cf && es <= snapshot {
      let koff: Int = mt.key_offsets[i];
      let ksz: Int = mt.key_sizes[i];
      let ek = _rocksdb_copy_range(mt.keys_data, koff, ksz);
      ko.push(kd.len());
      ks.push(ksz);
      _rocksdb_append(kd, &ek);
      let voff: Int = mt.value_offsets[i];
      let vsz: Int = mt.value_sizes[i];
      let ev = _rocksdb_copy_range(mt.values_data, voff, vsz);
      vo.push(vd.len());
      vs.push(vsz);
      _rocksdb_append(vd, &ev);
      let ety: Int = mt.types[i];
      cfs.push(ecf);
      seqs.push(es);
      types.push(ety);
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Append every visible version entry for (cf, <= snapshot).
fn _rocksdb_gather_version(v: &RocksDbVersion, cf: Int, snapshot: Int, cfs: &mut Vec[Int], seqs: &mut Vec[Int], types: &mut Vec[Int], kd: &mut Vec[UInt8], ko: &mut Vec[Int], ks: &mut Vec[Int], vd: &mut Vec[UInt8], vo: &mut Vec[Int], vs: &mut Vec[Int]) -> Int {
  var n = 0;
  var i = 0;
  while i < v.file_count {
    let start: Int = v.file_entry_start[i];
    let cnt: Int = v.file_entry_count[i];
    var e = start;
    let stop = start + cnt;
    while e < stop {
      let ecf: Int = v.ent_cfs[e];
      let es: Int = v.ent_seqs[e];
      if ecf == cf && es <= snapshot {
        let koff: Int = v.ent_key_offsets[e];
        let ksz: Int = v.ent_key_sizes[e];
        let ek = _rocksdb_copy_range(v.ent_keys_data, koff, ksz);
        ko.push(kd.len());
        ks.push(ksz);
        _rocksdb_append(kd, &ek);
        let voff: Int = v.ent_value_offsets[e];
        let vsz: Int = v.ent_value_sizes[e];
        let ev = _rocksdb_copy_range(v.ent_values_data, voff, vsz);
        vo.push(vd.len());
        vs.push(vsz);
        _rocksdb_append(vd, &ev);
        let ety: Int = v.ent_types[e];
        cfs.push(ecf);
        seqs.push(es);
        types.push(ety);
        n = n + 1;
      }
      e = e + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Materialize a new snapshot iterator over column family `cf` at sequence
/// `snapshot`: the newest visible version of every key, tombstones removed.
/// Complexity: O(entries^2) (insertion-sorted merge; a model, not a real
/// merge iterator).
pub fn rocksdb_iter_create(db: &mut RocksDbDb, cf: Int, snapshot: Int) -> RocksDbIter {
  var cfs = Vec[Int].new();
  var seqs = Vec[Int].new();
  var itypes = Vec[Int].new();
  var kd = Vec[UInt8].new();
  var ko = Vec[Int].new();
  var ks = Vec[Int].new();
  var vd = Vec[UInt8].new();
  var vo = Vec[Int].new();
  var vs = Vec[Int].new();
  _rocksdb_gather_mt(&db.mt, cf, snapshot, &mut cfs, &mut seqs, &mut itypes, &mut kd, &mut ko, &mut ks, &mut vd, &mut vo, &mut vs);
  _rocksdb_gather_version(&db.ver, cf, snapshot, &mut cfs, &mut seqs, &mut itypes, &mut kd, &mut ko, &mut ks, &mut vd, &mut vo, &mut vs);
  let order = _rocksdb_sort_order(cfs.len(), &cfs, &seqs, &kd, &ko, &ks);
  var it = RocksDbIter{
    count: 0;
    pos: 0;
    cf: cf;
    snapshot: snapshot;
    keys_data: Vec[UInt8].new();
    key_offsets: Vec[Int].new();
    key_sizes: Vec[Int].new();
    values_data: Vec[UInt8].new();
    value_offsets: Vec[Int].new();
    value_sizes: Vec[Int].new();
    seqs: Vec[Int].new();
  };
  var have_prev = false;
  var prev_off = 0;
  var prev_sz = 0;
  var oi = 0;
  while oi < order.len() {
    let idx: Int = order[oi];
    var dup = false;
    if have_prev {
      let o2: Int = ko[idx];
      let s2: Int = ks[idx];
      if _rocksdb_blob_cmp(kd, prev_off, prev_sz, kd, o2, s2) == 0 { dup = true; }
    }
    if !dup {
      prev_off = ko[idx];
      prev_sz = ks[idx];
      have_prev = true;
      let ety: Int = itypes[idx];
      if ety == _ROCKSDB_TYPE_VALUE {
        let koff: Int = ko[idx];
        let ksz: Int = ks[idx];
        let ek = _rocksdb_copy_range(kd, koff, ksz);
        it.key_offsets.push(it.keys_data.len());
        it.key_sizes.push(ksz);
        _rocksdb_append(&mut it.keys_data, &ek);
        let voff: Int = vo[idx];
        let vsz: Int = vs[idx];
        let ev = _rocksdb_copy_range(vd, voff, vsz);
        it.value_offsets.push(it.values_data.len());
        it.value_sizes.push(vsz);
        _rocksdb_append(&mut it.values_data, &ev);
        let es: Int = seqs[idx];
        it.seqs.push(es);
        it.count = it.count + 1;
      }
    }
    oi = oi + 1;
  }
  db.st.iterator_creates = db.st.iterator_creates + 1;
  return it;
}

/// Number of visible entries in the iterator. Complexity: O(1).
pub fn rocksdb_iter_count(it: &RocksDbIter) -> Int {
  return it.count;
}

/// Current cursor position. Complexity: O(1).
pub fn rocksdb_iter_pos(it: &RocksDbIter) -> Int {
  return it.pos;
}

/// True when the cursor points at an entry. Complexity: O(1).
pub fn rocksdb_iter_valid(it: &RocksDbIter) -> Bool {
  if it.pos < 0 { return false; }
  if it.pos >= it.count { return false; }
  return true;
}

/// Key at the cursor (empty Vec when invalid). Complexity: O(key).
pub fn rocksdb_iter_key(it: &RocksDbIter) -> Vec[UInt8] {
  if !rocksdb_iter_valid(it) { return Vec[UInt8].new(); }
  let koff: Int = it.key_offsets[it.pos];
  let ksz: Int = it.key_sizes[it.pos];
  return _rocksdb_copy_range(it.keys_data, koff, ksz);
}

/// Value at the cursor (empty Vec when invalid). Complexity: O(value).
pub fn rocksdb_iter_value(it: &RocksDbIter) -> Vec[UInt8] {
  if !rocksdb_iter_valid(it) { return Vec[UInt8].new(); }
  let voff: Int = it.value_offsets[it.pos];
  let vsz: Int = it.value_sizes[it.pos];
  return _rocksdb_copy_range(it.values_data, voff, vsz);
}

/// Sequence of the entry at the cursor, or -1 when invalid. Complexity:
/// O(1).
pub fn rocksdb_iter_seq(it: &RocksDbIter) -> Int {
  if !rocksdb_iter_valid(it) { return -1; }
  return it.seqs[it.pos];
}

/// Column family of the iterator. Complexity: O(1).
pub fn rocksdb_iter_cf(it: &RocksDbIter) -> Int {
  return it.cf;
}

/// Snapshot sequence of the iterator. Complexity: O(1).
pub fn rocksdb_iter_snapshot(it: &RocksDbIter) -> Int {
  return it.snapshot;
}

/// Seek to the first entry. Complexity: O(1).
pub fn rocksdb_iter_first(it: &mut RocksDbIter) {
  it.pos = 0;
}

/// Advance the cursor by one (no-op past the end). Complexity: O(1).
pub fn rocksdb_iter_next(it: &mut RocksDbIter) {
  if it.pos < it.count {
    it.pos = it.pos + 1;
  }
}

/// Seek to the first entry with key >= `key`. Complexity: O(count + key).
pub fn rocksdb_iter_seek(it: &mut RocksDbIter, key: &Vec[UInt8]) {
  var i = 0;
  var found = false;
  while i < it.count && !found {
    let koff: Int = it.key_offsets[i];
    let ksz: Int = it.key_sizes[i];
    let c = _rocksdb_blob_key_cmp(it.keys_data, koff, ksz, key);
    if c >= 0 { found = true; } else { i = i + 1; }
  }
  it.pos = i;
}

/// Bounded range scan over one column family at `snapshot`:
/// min_key <= key <= max_key in bytewise order, at most `limit` entries
/// (limit <= 0 is unlimited). Complexity: O(entries^2).
pub fn rocksdb_scan(db: &mut RocksDbDb, cf: Int, min_key: &Vec[UInt8], max_key: &Vec[UInt8], limit: Int, snapshot: Int) -> RocksDbScan {
  var out = RocksDbScan{
    count: 0;
    truncated: false;
    cf: cf;
    keys_data: Vec[UInt8].new();
    key_offsets: Vec[Int].new();
    key_sizes: Vec[Int].new();
    values_data: Vec[UInt8].new();
    value_offsets: Vec[Int].new();
    value_sizes: Vec[Int].new();
    seqs: Vec[Int].new();
  };
  var it = rocksdb_iter_create(db, cf, snapshot);
  rocksdb_iter_seek(&mut it, min_key);
  var going = true;
  while going && rocksdb_iter_valid(&it) {
    let koff: Int = it.key_offsets[it.pos];
    let ksz: Int = it.key_sizes[it.pos];
    if max_key.len() > 0 {
      let c = _rocksdb_blob_key_cmp(it.keys_data, koff, ksz, max_key);
      if c > 0 {
        going = false;
      }
    }
    if going {
      if limit > 0 && out.count >= limit {
        out.truncated = true;
        going = false;
      } else {
        let koff2: Int = it.key_offsets[it.pos];
        let ksz2: Int = it.key_sizes[it.pos];
        let ek = _rocksdb_copy_range(it.keys_data, koff2, ksz2);
        out.key_offsets.push(out.keys_data.len());
        out.key_sizes.push(ksz2);
        _rocksdb_append(&mut out.keys_data, &ek);
        let voff: Int = it.value_offsets[it.pos];
        let vsz: Int = it.value_sizes[it.pos];
        let ev = _rocksdb_copy_range(it.values_data, voff, vsz);
        out.value_offsets.push(out.values_data.len());
        out.value_sizes.push(vsz);
        _rocksdb_append(&mut out.values_data, &ev);
        let es: Int = it.seqs[it.pos];
        out.seqs.push(es);
        out.count = out.count + 1;
        rocksdb_iter_next(&mut it);
      }
    }
  }
  db.st.scans = db.st.scans + 1;
  return out;
}

/// Number of entries in the scan result. Complexity: O(1).
pub fn rocksdb_scan_count(s: &RocksDbScan) -> Int {
  return s.count;
}

/// True when the scan stopped at the limit while more entries existed.
/// Complexity: O(1).
pub fn rocksdb_scan_truncated(s: &RocksDbScan) -> Bool {
  return s.truncated;
}

/// Key of scan entry `i` (empty Vec out of range). Complexity: O(key).
pub fn rocksdb_scan_key(s: &RocksDbScan, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= s.count { return Vec[UInt8].new(); }
  let koff: Int = s.key_offsets[i];
  let ksz: Int = s.key_sizes[i];
  return _rocksdb_copy_range(s.keys_data, koff, ksz);
}

/// Value of scan entry `i` (empty Vec out of range). Complexity: O(value).
pub fn rocksdb_scan_value(s: &RocksDbScan, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= s.count { return Vec[UInt8].new(); }
  let voff: Int = s.value_offsets[i];
  let vsz: Int = s.value_sizes[i];
  return _rocksdb_copy_range(s.values_data, voff, vsz);
}

/// Sequence of scan entry `i`, or -1 out of range. Complexity: O(1).
pub fn rocksdb_scan_seq(s: &RocksDbScan, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.count { return -1; }
  return s.seqs[i];
}

// --------------------------------------------------
//  Engine (DB) API
// --------------------------------------------------

// True when `cf` is a registered column family id.
fn _rocksdb_cf_exists(db: &RocksDbDb, cf: Int) -> Bool {
  var i = 0;
  while i < db.cf_ids.len() {
    let id: Int = db.cf_ids[i];
    if id == cf { return true; }
    i = i + 1;
  }
  return false;
}

/// A fresh engine with explicit layout parameters (each clamped like the
/// component constructors). The default column family 0 "default" exists;
/// sequence starts at 0 and the first file number is 1.
/// Complexity: O(1).
pub fn rocksdb_db_new(memtable_capacity: Int, l0_trigger: Int, level_base_bytes: Int, level_multiplier: Int, max_levels: Int, block_entries: Int, bloom_bits_per_key: Int, bloom_hashes: Int, wal_policy: Int) -> RocksDbDb {
  let mt = rocksdb_memtable_new(memtable_capacity);
  let wal = rocksdb_wal_new(wal_policy);
  let ver = rocksdb_version_new(l0_trigger, level_base_bytes, level_multiplier, max_levels, block_entries, bloom_bits_per_key, bloom_hashes);
  let st = RocksDbStats{
    puts: 0;
    deletes: 0;
    gets: 0;
    hits: 0;
    misses: 0;
    flushes: 0;
    compactions: 0;
    flush_bytes: 0;
    compact_bytes: 0;
    wal_syncs: 0;
    snapshots: 0;
    iterator_creates: 0;
    scans: 0;
  };
  var ids = Vec[Int].new();
  ids.push(0);
  var names = Vec[Str].new();
  names.push("default");
  return RocksDbDb{
    sequence: 0;
    next_cf: 1;
    mt: mt;
    wal: wal;
    ver: ver;
    st: st;
    cf_ids: ids;
    cf_names: names;
    snapshots: Vec[Int].new();
  };
}

/// A fresh engine with the documented defaults: 4096-byte memtable, L0
/// trigger 4, 256 KiB base level target, x10 multiplier, 7 levels, 4-entry
/// data blocks, 10 Bloom bits per key / 3 hashes, WAL flush policy.
/// Complexity: O(1).
pub fn rocksdb_db_new_default() -> RocksDbDb {
  return rocksdb_db_new(_ROCKSDB_DEFAULT_CAPACITY, _ROCKSDB_DEFAULT_L0_TRIGGER, _ROCKSDB_DEFAULT_LEVEL_BASE, _ROCKSDB_DEFAULT_LEVEL_MULT, _ROCKSDB_DEFAULT_MAX_LEVELS, _ROCKSDB_DEFAULT_BLOCK_ENTRIES, _ROCKSDB_DEFAULT_BLOOM_BITS, _ROCKSDB_DEFAULT_BLOOM_HASHES, _ROCKSDB_DEFAULT_WAL_POLICY);
}

/// Current sequence number (last assigned write sequence). Complexity:
/// O(1).
pub fn rocksdb_db_sequence(db: &RocksDbDb) -> Int {
  return db.sequence;
}

/// Number of entries in the active memtable. Complexity: O(1).
pub fn rocksdb_db_memtable_count(db: &RocksDbDb) -> Int {
  return db.mt.count;
}

/// Number of charged memtable bytes. Complexity: O(1).
pub fn rocksdb_db_memtable_bytes(db: &RocksDbDb) -> Int {
  return db.mt.bytes;
}

/// Total charged bytes of all version files. Complexity: O(1).
pub fn rocksdb_db_version_total_bytes(db: &RocksDbDb) -> Int {
  return db.ver.total_bytes;
}

/// Number of files across all levels. Complexity: O(1).
pub fn rocksdb_db_file_count(db: &RocksDbDb) -> Int {
  return db.ver.file_count;
}

/// Number of registered column families (the default always counts).
/// Complexity: O(1).
pub fn rocksdb_column_family_count(db: &RocksDbDb) -> Int {
  return db.cf_ids.len();
}

/// Register a new column family named `name`, returning its id, or -1 for
/// an empty or duplicate name. Complexity: O(families * name).
pub fn rocksdb_create_column_family(db: &mut RocksDbDb, name: Str) -> Int {
  if name.len() == 0 { return -1; }
  if rocksdb_column_family_id(db, name) >= 0 { return -1; }
  let id = db.next_cf;
  db.cf_ids.push(id);
  db.cf_names.push(name);
  db.next_cf = db.next_cf + 1;
  return id;
}

/// Id of the first column family named `name`, or -1. Complexity:
/// O(families * name).
pub fn rocksdb_column_family_id(db: &RocksDbDb, name: Str) -> Int {
  var i = 0;
  while i < db.cf_ids.len() {
    let n: Str = db.cf_names[i];
    if compare.str_compare(n, name) == 0 {
      let id: Int = db.cf_ids[i];
      return id;
    }
    i = i + 1;
  }
  return -1;
}

/// Name of column family `id`, or "" when unknown. Complexity: O(families).
pub fn rocksdb_column_family_name(db: &RocksDbDb, id: Int) -> Str {
  var i = 0;
  while i < db.cf_ids.len() {
    let cid: Int = db.cf_ids[i];
    if cid == id {
      let n: Str = db.cf_names[i];
      return n;
    }
    i = i + 1;
  }
  return "";
}

/// Create a snapshot at the current sequence. Returns the snapshot
/// sequence (which is also its handle) and increments the counter.
/// Complexity: O(1).
pub fn rocksdb_snapshot_create(db: &mut RocksDbDb) -> Int {
  let seq = db.sequence;
  db.snapshots.push(seq);
  db.st.snapshots = db.st.snapshots + 1;
  return seq;
}

/// Release the first snapshot equal to `seq`; false when none exists.
/// Complexity: O(snapshots).
pub fn rocksdb_snapshot_release(db: &mut RocksDbDb, seq: Int) -> Bool {
  var i = 0;
  while i < db.snapshots.len() {
    let s: Int = db.snapshots[i];
    if s == seq {
      db.snapshots.remove(i);
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Number of live snapshots. Complexity: O(1).
pub fn rocksdb_snapshot_count(db: &RocksDbDb) -> Int {
  return db.snapshots.len();
}

/// Oldest live snapshot sequence, or -1 when none is live. Complexity:
/// O(snapshots).
pub fn rocksdb_oldest_snapshot(db: &RocksDbDb) -> Int {
  if db.snapshots.len() == 0 { return -1; }
  var m: Int = db.snapshots[0];
  var i = 1;
  while i < db.snapshots.len() {
    let s: Int = db.snapshots[i];
    if s < m { m = s; }
    i = i + 1;
  }
  return m;
}

// Best visible entry for (cf, key, snapshot): seq*2 + type, or -1 when
// absent. Scans the memtable and every version file.
fn _rocksdb_probe_code(db: &RocksDbDb, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  if key.len() == 0 { return -1; }
  var best_seq = -1;
  var best_type = _ROCKSDB_TYPE_VALUE;
  let mi = rocksdb_memtable_find(&db.mt, cf, key, snapshot);
  if mi >= 0 {
    let ms: Int = db.mt.seqs[mi];
    let mtp: Int = db.mt.types[mi];
    best_seq = ms;
    best_type = mtp;
  }
  let vi = rocksdb_version_find(&db.ver, cf, key, snapshot);
  if vi >= 0 {
    let vs: Int = db.ver.ent_seqs[vi];
    if vs > best_seq {
      let vtp: Int = db.ver.ent_types[vi];
      best_seq = vs;
      best_type = vtp;
    }
  }
  if best_seq < 0 { return -1; }
  return best_seq * 2 + best_type;
}

// Value of the best visible entry for (cf, key, snapshot), or Err for an
// absent key / tombstone.
fn _rocksdb_probe_value(db: &RocksDbDb, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Result[Vec[UInt8], Str] {
  if key.len() == 0 { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  var best_seq = -1;
  var best_type = _ROCKSDB_TYPE_VALUE;
  var best_mt = -1;
  var best_v = -1;
  let mi = rocksdb_memtable_find(&db.mt, cf, key, snapshot);
  if mi >= 0 {
    let ms: Int = db.mt.seqs[mi];
    let mtp: Int = db.mt.types[mi];
    best_seq = ms;
    best_type = mtp;
    best_mt = mi;
  }
  let vi = rocksdb_version_find(&db.ver, cf, key, snapshot);
  if vi >= 0 {
    let vs: Int = db.ver.ent_seqs[vi];
    if vs > best_seq {
      let vtp: Int = db.ver.ent_types[vi];
      best_seq = vs;
      best_type = vtp;
      best_mt = -1;
      best_v = vi;
    }
  }
  if best_seq < 0 { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  if best_type == _ROCKSDB_TYPE_DELETE { return _rocksdb_err_bytes(_ROCKSDB_NOT_FOUND); }
  if best_mt >= 0 {
    return _rocksdb_ok_bytes(rocksdb_memtable_entry_value(&db.mt, best_mt));
  }
  return _rocksdb_ok_bytes(rocksdb_version_entry_value(&db.ver, best_v));
}

/// Write `key` = `value` in the default column family: assigns the next
/// sequence, appends a WAL record (subject to the sync policy) and inserts
/// into the memtable. Returns the write sequence, or -1 for an empty key.
/// Complexity: O(key + value).
pub fn rocksdb_put(db: &mut RocksDbDb, key: &Vec[UInt8], value: &Vec[UInt8]) -> Int {
  return rocksdb_put_cf(db, 0, key, value);
}

/// Like rocksdb_put for an explicit registered column family; -1 for an
/// unknown cf or an empty key. Complexity: O(key + value).
pub fn rocksdb_put_cf(db: &mut RocksDbDb, cf: Int, key: &Vec[UInt8], value: &Vec[UInt8]) -> Int {
  if !_rocksdb_cf_exists(db, cf) { return -1; }
  if key.len() == 0 { return -1; }
  let seq = db.sequence + 1;
  let wi = rocksdb_wal_append(&mut db.wal, cf, key, value, seq, _ROCKSDB_TYPE_VALUE);
  if wi < 0 { return -1; }
  let mi = rocksdb_memtable_put(&mut db.mt, cf, key, value, seq, _ROCKSDB_TYPE_VALUE);
  if mi < 0 { return -1; }
  db.sequence = seq;
  db.st.puts = db.st.puts + 1;
  return seq;
}

/// Delete `key` (append a tombstone) in the default column family.
/// Returns the write sequence, or -1 for an empty key. Complexity:
/// O(key).
pub fn rocksdb_delete(db: &mut RocksDbDb, key: &Vec[UInt8]) -> Int {
  return rocksdb_delete_cf(db, 0, key);
}

/// Like rocksdb_delete for an explicit registered column family; -1 for an
/// unknown cf or an empty key. Complexity: O(key).
pub fn rocksdb_delete_cf(db: &mut RocksDbDb, cf: Int, key: &Vec[UInt8]) -> Int {
  if !_rocksdb_cf_exists(db, cf) { return -1; }
  if key.len() == 0 { return -1; }
  let seq = db.sequence + 1;
  let empty = Vec[UInt8].new();
  let wi = rocksdb_wal_append(&mut db.wal, cf, key, &empty, seq, _ROCKSDB_TYPE_DELETE);
  if wi < 0 { return -1; }
  let mi = rocksdb_memtable_put(&mut db.mt, cf, key, &empty, seq, _ROCKSDB_TYPE_DELETE);
  if mi < 0 { return -1; }
  db.sequence = seq;
  db.st.deletes = db.st.deletes + 1;
  return seq;
}

/// Lookup status at `snapshot`: 1 a live value is visible, 0 the newest
/// visible entry is a tombstone, -1 nothing is visible. Counts toward
/// gets/hits/misses. Complexity: O(memtable + version).
pub fn rocksdb_lookup(db: &mut RocksDbDb, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Int {
  let code = _rocksdb_probe_code(db, cf, key, snapshot);
  db.st.gets = db.st.gets + 1;
  if code < 0 {
    db.st.misses = db.st.misses + 1;
    return -1;
  }
  let ty = code % 2;
  db.st.hits = db.st.hits + 1;
  if ty == _ROCKSDB_TYPE_DELETE { return 0; }
  return 1;
}

/// Read the newest value visible at `snapshot`, or Err("rocksdb: not
/// found") for an absent key and for a tombstone. Counts toward
/// gets/hits/misses. Complexity: O(memtable + version + value).
pub fn rocksdb_get_at(db: &mut RocksDbDb, cf: Int, key: &Vec[UInt8], snapshot: Int) -> Result[Vec[UInt8], Str] {
  let r = _rocksdb_probe_value(db, cf, key, snapshot);
  db.st.gets = db.st.gets + 1;
  if r.is_ok {
    db.st.hits = db.st.hits + 1;
  } else {
    db.st.misses = db.st.misses + 1;
  }
  return r;
}

/// Read the newest value for `key` in the default column family at the
/// current sequence. Complexity: O(memtable + version + value).
pub fn rocksdb_get(db: &mut RocksDbDb, key: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let snap = db.sequence;
  return rocksdb_get_at(db, 0, key, snap);
}

/// Like rocksdb_get for an explicit registered column family.
/// Complexity: O(memtable + version + value).
pub fn rocksdb_get_cf(db: &mut RocksDbDb, cf: Int, key: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let snap = db.sequence;
  return rocksdb_get_at(db, cf, key, snap);
}

/// Flush the active memtable into a new L0 file. Returns the new file
/// number, or -1 when the memtable is empty or the version rejects the
/// file. Clears the memtable and updates flush statistics. Complexity:
/// O(memtable bytes + files).
pub fn rocksdb_flush(db: &mut RocksDbDb) -> Int {
  let n: Int = db.mt.count;
  if n <= 0 { return -1; }
  let fnum: Int = db.ver.next_file_number;
  let bt = rocksdb_table_build(&db.mt, fnum, db.ver.block_entries, db.ver.bloom_bits_per_key, db.ver.bloom_hashes);
  let added = rocksdb_version_add_table(&mut db.ver, &bt, 0);
  if added < 0 { return -1; }
  db.ver.next_file_number = fnum + 1;
  let tb: Int = bt.bytes;
  db.st.flushes = db.st.flushes + 1;
  db.st.flush_bytes = db.st.flush_bytes + tb;
  rocksdb_memtable_clear(&mut db.mt);
  return fnum;
}

/// True when the active memtable should be flushed. Complexity: O(1).
pub fn rocksdb_should_flush(db: &RocksDbDb) -> Bool {
  return rocksdb_memtable_should_flush(&db.mt);
}

/// One bounded maintenance pass: flush the memtable when it should be
/// flushed, then run at most `max_rounds` compactions (snapshot-safe: the
/// oldest live snapshot is honoured, or -1 when none is live). Returns the
/// number of actions taken (flush counts as one, each compaction counts as
/// one). Complexity: bounded by arguments and version size.
pub fn rocksdb_maintenance(db: &mut RocksDbDb, max_rounds: Int) -> Int {
  var actions = 0;
  if rocksdb_memtable_should_flush(&db.mt) {
    let f = rocksdb_flush(db);
    if f >= 0 { actions = actions + 1; }
  }
  let oldest = rocksdb_oldest_snapshot(db);
  let rep = rocksdb_version_compact(&mut db.ver, max_rounds, oldest);
  db.st.compactions = db.st.compactions + rep.rounds;
  db.st.compact_bytes = db.st.compact_bytes + rep.bytes_out;
  actions = actions + rep.rounds;
  return actions;
}

/// Snapshot of the engine statistics. Complexity: O(1).
pub fn rocksdb_stats(db: &RocksDbDb) -> RocksDbStats {
  let s: RocksDbStats = db.st;
  return s;
}

/// Module version string ("0.1.0"). Complexity: O(1).
pub fn rocksdb_version() -> Str {
  return _ROCKSDB_VERSION;
}

