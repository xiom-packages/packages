// XIOM -- xiom.cloudlog: cloud log pipeline model (pure, deterministic)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement xiom.cloudlog as a real, tested, pure-XIOM model of a
// cloud log pipeline. Scope, five cooperating models:
//
//   1. INGEST   -- a bounded ingest buffer with parallel-vector content
//                  (lines/seqs/times/sizes), a producer sequence counter, a
//                  consumer watermark (highest contiguous sequence accepted),
//                  gap/duplicate accounting, and size/time flush policies
//                  (max_events / max_bytes / max_age_ms) that produce a
//                  deterministic CloudFlush plan.
//   2. FORMAT   -- structured event encoding/decoding for a key=value line
//                  format and a flat JSON-ish object subset, both carrying
//                  time (epoch ms), level (name + 0..5 code) and severity
//                  (0..5) fields, with byte-exact escaping round-trips and
//                  deterministic "cloudlog: <reason> at <offset>" errors.
//   3. STREAM   -- an append-only record stream stored as a single Str blob
//                  plus parallel offset/length/time vectors (no Vec[Str]
//                  blob), and a tail consumer with a delivery cursor, a
//                  monotonic checkpoint, a retained-from floor and an
//                  at-least-once replay window (replay from the checkpoint,
//                  truncated reads reported when retention has advanced past
//                  the cursor).
//   4. STORE    -- a retention store of append/roll segments with per-segment
//                  offsets, byte/event stats, sealed/open/dropped states,
//                  retention policies (bytes/age/segments/events) and a
//                  compaction pass that merges oldest live segments without
//                  changing total statistics.
//   5. SEARCH   -- a flat-table predicate tree (AND/OR/NOT plus level,
//                  severity, message-substring, key/value and time-range
//                  leaves), inclusive time filtering, and deterministic
//                  pagination (index order, matched_total, next_start).
//
// Purity: no network, no disk, no clock, no randomness, no global state. All
// functions are free functions on caller-owned values; every model is a flat
// struct with parallel vectors (Vec[StructType], Vec[Bool] and Vec[Float64]
// are avoided). Inline fixtures in tests/test_conformance.xi lock every rule.
//
// v0.62.2 compiler notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType];
//   * Str equality never uses `==` on a value read from a Vec[Str] element
//     (BUG-17 lowers that to a pointer comparison): every comparison goes
//     through xiom.string.compare.str_compare after binding a typed local;
//   * Vec element reads are always bound to typed locals (`let x: Int = ...`)
//     because untyped generic reads can mis-lower;
//   * widened bytes are masked with `& 0xFF`; no byte is compared against a
//     UInt8 constant >= 128;
//   * Str blobs are built with `Str + Str` and sliced with str_slice, never
//     with sb_to_str over bytes that may contain 0x00 (trap 15);
//   * Ok/Err for struct payloads are constructed only in the tiny leaf
//     helpers `_cl_ok_event` / `_cl_err_event`; scalar Results use
//     `_cl_ok_int` / `_cl_err_int`;
//   * parallel vectors are pushed in lockstep and every accessor guards
//     length mismatches (trap 16).

module xiom.cloudlog

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (UInt8, all < 128; high bytes are widened/masked)
// --------------------------------------------------

const _CL_TAB: UInt8 = 9u8;
const _CL_LF: UInt8 = 10u8;
const _CL_CR: UInt8 = 13u8;
const _CL_SP: UInt8 = 32u8;
const _CL_DQUOTE: UInt8 = 34u8;
const _CL_HASH: UInt8 = 35u8;
const _CL_COMMA: UInt8 = 44u8;
const _CL_DASH: UInt8 = 45u8;
const _CL_DOT: UInt8 = 46u8;
const _CL_SLASH: UInt8 = 47u8;
const _CL_ZERO: UInt8 = 48u8;
const _CL_NINE: UInt8 = 57u8;
const _CL_COLON: UInt8 = 58u8;
const _CL_EQ: UInt8 = 61u8;
const _CL_UPPER_A: UInt8 = 65u8;
const _CL_UPPER_F: UInt8 = 70u8;
const _CL_UPPER_Z: UInt8 = 90u8;
const _CL_BACKSLASH: UInt8 = 92u8;
const _CL_UNDERSCORE: UInt8 = 95u8;
const _CL_LOWER_A: UInt8 = 97u8;
const _CL_LOWER_B: UInt8 = 98u8;
const _CL_LOWER_F: UInt8 = 102u8;
const _CL_LOWER_N: UInt8 = 110u8;
const _CL_LOWER_R: UInt8 = 114u8;
const _CL_LOWER_T: UInt8 = 116u8;
const _CL_LOWER_U: UInt8 = 117u8;
const _CL_LOWER_X: UInt8 = 120u8;
const _CL_LOWER_Z: UInt8 = 122u8;
const _CL_LBRACE: UInt8 = 123u8;
const _CL_RBRACE: UInt8 = 125u8;
const _CL_DEL: UInt8 = 127u8;

// Level codes: 0 trace, 1 debug, 2 info, 3 warn, 4 error, 5 fatal.
const _CL_LEVEL_MAX: Int = 5;
const _CL_KEY_MAX: Int = 64;

// Predicate opcodes (flat node table).
const _CL_PRED_FALSE: Int = 0;
const _CL_PRED_TRUE: Int = 1;
const _CL_PRED_AND: Int = 2;
const _CL_PRED_OR: Int = 3;
const _CL_PRED_NOT: Int = 4;
const _CL_PRED_LEVEL: Int = 5;
const _CL_PRED_SEV_GE: Int = 6;
const _CL_PRED_MSG: Int = 7;
const _CL_PRED_KEY: Int = 8;
const _CL_PRED_TIME: Int = 9;

// Segment states.
const _CL_SEG_DEAD: Int = 0;
const _CL_SEG_OPEN: Int = 1;
const _CL_SEG_SEALED: Int = 2;

// Ingest accept codes.
const _CL_ACCEPT_IN_ORDER: Int = 0;
const _CL_ACCEPT_GAP: Int = 1;
const _CL_ACCEPT_DUPLICATE: Int = 2;
const _CL_ACCEPT_EMPTY: Int = 3;

// Flush reasons.
const _CL_FLUSH_NONE: Int = 0;
const _CL_FLUSH_COUNT: Int = 1;
const _CL_FLUSH_BYTES: Int = 2;
const _CL_FLUSH_AGE: Int = 3;
const _CL_FLUSH_EXPLICIT: Int = 4;

// Retention reasons.
const _CL_RETAIN_NONE: Int = 0;
const _CL_RETAIN_BYTES: Int = 1;
const _CL_RETAIN_AGE: Int = 2;
const _CL_RETAIN_SEGMENTS: Int = 3;
const _CL_RETAIN_EVENTS: Int = 4;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One structured log event. `time_ms` is an epoch-millisecond integer,
/// `level` a 0..5 code (see cl_level_name), `severity` a 0..5 code (usually
/// equal to level; carried independently on the wire). `keys`/`vals` are
/// parallel vectors of extra attributes in insertion order.
pub type CloudEvent = {
  time_ms: Int;
  level: Int;
  severity: Int;
  msg: Str;
  keys: Vec[Str];
  vals: Vec[Str];
}

/// Ingest flush policy. A value <= 0 disables that trigger.
pub type CloudFlushPolicy = {
  max_events: Int;
  max_bytes: Int;
  max_age_ms: Int;
}

/// The ingest buffer: content parallel vectors plus sequence and flush state.
/// `watermark` is the highest contiguous sequence accepted (-1 relative to
/// `base_seq` before any event); `seen_max` is the highest sequence ever
/// seen; `next_seq` is the producer counter used by cl_ingest_assign.
pub type CloudIngest = {
  lines: Vec[Str];
  seqs: Vec[Int];
  times: Vec[Int];
  sizes: Vec[Int];
  base_seq: Int;
  next_seq: Int;
  watermark: Int;
  seen_max: Int;
  accepted: Int;
  duplicates: Int;
  gap_events: Int;
  total_bytes: Int;
}

/// A deterministic flush decision (also returned by cl_ingest_flush, which
/// additionally clears the buffer). `reason` is one of the _CL_FLUSH_*
/// codes; `seq_first`/`seq_last` are -1 for an empty buffer.
pub type CloudFlush = {
  should: Bool;
  reason: Int;
  count: Int;
  bytes: Int;
  age_ms: Int;
  seq_first: Int;
  seq_last: Int;
}

/// Append-only record stream: one Str `blob` with records separated by LF,
/// plus parallel start-offset / byte-length / timestamp vectors. Records are
/// addressed by index.
pub type CloudStream = {
  blob: Str;
  off: Vec[Int];
  len: Vec[Int];
  ts: Vec[Int];
}

/// Tail consumer state. `cursor` is the next record index to deliver,
/// `acked` the committed checkpoint (all records before it are processed),
/// `retained_from` the earliest index still retained by the stream. The
/// replay window is `cursor - acked`.
pub type CloudTail = {
  cursor: Int;
  acked: Int;
  retained_from: Int;
}

/// One pull from a stream: the record texts, their stream indices, the first
/// index read, the next cursor, and flags for replay and retention
/// truncation.
pub type CloudRead = {
  lines: Vec[Str];
  idx: Vec[Int];
  count: Int;
  from: Int;
  next_cursor: Int;
  replayed: Bool;
  truncated: Bool;
}

/// Retention store policy. A value <= 0 disables that policy; policies are
/// applied in the fixed order bytes, age, segments, events and the newest
/// live segment is never dropped.
pub type CloudStorePolicy = {
  max_bytes: Int;
  max_age_ms: Int;
  max_segments: Int;
  max_events: Int;
  compact_at: Int;
  compact_to: Int;
}

/// Retention store: parallel per-segment vectors (state `seg_state` is
/// _CL_SEG_*), segment roll threshold `seg_max_events`, monotonic next byte
/// offset and lifetime/server counters.
pub type CloudStore = {
  seg_from_off: Vec[Int];
  seg_to_off: Vec[Int];
  seg_from_time: Vec[Int];
  seg_to_time: Vec[Int];
  seg_bytes: Vec[Int];
  seg_events: Vec[Int];
  seg_state: Vec[Int];
  seg_max_events: Int;
  next_off: Int;
  live_count: Int;
  total_bytes: Int;
  total_events: Int;
  dropped_segments: Int;
  dropped_bytes: Int;
  dropped_events: Int;
  compacted_segments: Int;
}

/// Outcome of one cl_store_apply_retention call: how much was dropped, the
/// policy reason (_CL_RETAIN_*) and the oldest surviving offset/time (0 when
/// nothing survives, which cannot happen while one segment is kept).
pub type CloudRetention = {
  dropped: Int;
  dropped_bytes: Int;
  dropped_events: Int;
  reason: Int;
  keep_from_off: Int;
  keep_from_time: Int;
}

/// Searchable in-memory log: parallel per-record time/level/severity/message
/// vectors plus a flattened key/value table where entry `i` belongs to record
/// `krec[i]`.
pub type CloudLog = {
  time: Vec[Int];
  level: Vec[Int];
  sev: Vec[Int];
  msg: Vec[Str];
  kname: Vec[Str];
  kval: Vec[Str];
  krec: Vec[Int];
}

/// Flat predicate tree: every node is a slot in parallel vectors. `op` holds
/// a _CL_PRED_* opcode; AND/OR use left/right children, NOT uses left, leaf
/// nodes use num/num2 (integers) and text/text2 (strings).
pub type CloudPred = {
  op: Vec[Int];
  left: Vec[Int];
  right: Vec[Int];
  num: Vec[Int];
  num2: Vec[Int];
  text: Vec[Str];
  text2: Vec[Str];
}

/// One deterministic search page: matching record indices in scan order
/// (`hits`), the number of matches collected, the next `start` (-1 when
/// exhausted), the total match count in the time range, and the number of
/// records scanned.
pub type CloudPage = {
  hits: Vec[Int];
  count: Int;
  next_start: Int;
  matched_total: Int;
  scanned: Int;
}

// Private scan results (plain values; no Result is built in scanners).

type _ClInt = {
  value: Int;
  next: Int;
  ok: Bool;
  err: Str;
  pos: Int;
}

type _ClScan = {
  text: Str;
  next: Int;
  ok: Bool;
  err: Str;
  pos: Int;
}

// --------------------------------------------------
//  Leaf Result helpers and text helpers
// --------------------------------------------------

fn _cl_ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _cl_err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _cl_ok_event(v: CloudEvent) -> Result[CloudEvent, Str] {
  return Ok(v);
}

fn _cl_err_event(m: Str) -> Result[CloudEvent, Str] {
  return Err(m);
}

fn _cl_int_to_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

fn _cl_err_at(reason: Str, pos: Int) -> Str {
  return "cloudlog: " + reason + " at " + _cl_int_to_str(pos);
}

fn _cl_is_digit(b: UInt8) -> Bool {
  return b >= _CL_ZERO && b <= _CL_NINE;
}

fn _cl_key_char(b: UInt8) -> Bool {
  if b >= _CL_LOWER_A && b <= _CL_LOWER_Z {
    return true;
  }
  if b >= _CL_UPPER_A && b <= _CL_UPPER_Z {
    return true;
  }
  if _cl_is_digit(b) {
    return true;
  }
  if b == _CL_UNDERSCORE || b == _CL_DOT || b == _CL_DASH {
    return true;
  }
  return false;
}

/// True for a valid attribute key: 1..64 bytes of [A-Za-z0-9_.-].
pub fn cl_key_ok(key: Str) -> Bool {
  let n = key.len();
  if n < 1 || n > _CL_KEY_MAX {
    return false;
  }
  var i = 0;
  while i < n {
    if !_cl_key_char(string.byte_at(key, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _cl_hex_val(b: UInt8) -> Int {
  if b >= _CL_ZERO && b <= _CL_NINE {
    return (b as Int) - 48;
  }
  if b >= _CL_UPPER_A && b <= _CL_UPPER_F {
    return (b as Int) - 55;
  }
  if b >= _CL_LOWER_A && b <= _CL_LOWER_F {
    return (b as Int) - 87;
  }
  return -1;
}

fn _cl_hex_digit(v: Int) -> UInt8 {
  if v < 10 {
    return (48 + v) as UInt8;
  }
  return (87 + v) as UInt8;
}

fn _cl_push_hex2(out: &mut Vec[UInt8], v: Int) {
  out.push(_cl_hex_digit((v / 16) % 16));
  out.push(_cl_hex_digit(v % 16));
}

fn _cl_skip_ws(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _CL_SP || b == _CL_TAB || b == _CL_LF || b == _CL_CR {
      i = i + 1;
    } else {
      break;
    }
  }
  return i;
}

/// Decimal integer at `from`: optional '-', then 1..18 digits. Errors are
/// "missing integer" / "integer overflow" with the offending position.
fn _cl_scan_int(s: Str, from: Int) -> _ClInt {
  let n = s.len();
  var r = _ClInt{ value: 0; next: from; ok: false; err: ""; pos: from };
  var i = from;
  var neg = false;
  if i < n && string.byte_at(s, i) == _CL_DASH {
    neg = true;
    i = i + 1;
  }
  let digits_at = i;
  var acc = 0;
  var digits = 0;
  while i < n && _cl_is_digit(string.byte_at(s, i)) {
    if digits >= 18 {
      r.err = "integer overflow";
      r.pos = i;
      return r;
    }
    acc = acc * 10 + ((string.byte_at(s, i) as Int) - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    r.err = "missing integer";
    r.pos = digits_at;
    return r;
  }
  r.value = acc;
  if neg {
    r.value = 0 - acc;
  }
  r.next = i;
  r.ok = true;
  return r;
}

/// True when `word` occurs at byte `at` in `s` (exact bytes, no delimiter
/// requirement).
fn _cl_word_at(s: Str, at: Int, word: Str) -> Bool {
  if at < 0 || at + word.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < word.len() {
    if string.byte_at(s, at + i) != string.byte_at(word, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Naive substring test; the empty needle is contained in every haystack.
pub fn cl_text_contains(hay: Str, needle: Str) -> Bool {
  let hn = hay.len();
  let nn = needle.len();
  if nn == 0 {
    return true;
  }
  if nn > hn {
    return false;
  }
  var i = 0;
  while i + nn <= hn {
    var j = 0;
    var hit = true;
    while j < nn {
      if string.byte_at(hay, i + j) != string.byte_at(needle, j) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Levels
// --------------------------------------------------

/// Level name for a 0..5 code: trace, debug, info, warn, error, fatal;
/// "" outside the range.
pub fn cl_level_name(level: Int) -> Str {
  if level == 0 {
    return "trace";
  }
  if level == 1 {
    return "debug";
  }
  if level == 2 {
    return "info";
  }
  if level == 3 {
    return "warn";
  }
  if level == 4 {
    return "error";
  }
  if level == 5 {
    return "fatal";
  }
  return "";
}

/// Level code for a name from cl_level_name (case-sensitive, byte-exact).
/// Returns Ok(0..5) or Err("cloudlog: unknown level: <name>").
pub fn cl_level_code(name: Str) -> Result[Int, Str] {
  if compare.str_compare(name, "trace") == 0 {
    return _cl_ok_int(0);
  }
  if compare.str_compare(name, "debug") == 0 {
    return _cl_ok_int(1);
  }
  if compare.str_compare(name, "info") == 0 {
    return _cl_ok_int(2);
  }
  if compare.str_compare(name, "warn") == 0 {
    return _cl_ok_int(3);
  }
  if compare.str_compare(name, "error") == 0 {
    return _cl_ok_int(4);
  }
  if compare.str_compare(name, "fatal") == 0 {
    return _cl_ok_int(5);
  }
  return _cl_err_int("cloudlog: unknown level: " + name);
}

/// True for a valid level code (0..5).
pub fn cl_level_valid(level: Int) -> Bool {
  return level >= 0 && level <= _CL_LEVEL_MAX;
}

// --------------------------------------------------
//  Events and accessors
// --------------------------------------------------

/// New event with severity defaulted to the level code.
pub fn cl_event_new(time_ms: Int, level: Int, msg: Str) -> CloudEvent {
  return CloudEvent{
    time_ms: time_ms;
    level: level;
    severity: level;
    msg: msg;
    keys: Vec[Str].new();
    vals: Vec[Str].new();
  };
}

/// New event with an explicit severity code.
pub fn cl_event_new_full(time_ms: Int, level: Int, severity: Int, msg: Str) -> CloudEvent {
  return CloudEvent{
    time_ms: time_ms;
    level: level;
    severity: severity;
    msg: msg;
    keys: Vec[Str].new();
    vals: Vec[Str].new();
  };
}

/// Append one attribute; false when the key is not a valid attribute key.
pub fn cl_event_set(ev: &mut CloudEvent, key: Str, val: Str) -> Bool {
  if !cl_key_ok(key) {
    return false;
  }
  ev.keys.push(key);
  ev.vals.push(val);
  return true;
}

/// True when an attribute with this exact key exists.
pub fn cl_event_has_key(ev: &CloudEvent, key: Str) -> Bool {
  let n = ev.keys.len();
  var i = 0;
  while i < n {
    let k: Str = ev.keys[i];
    if compare.str_compare(k, key) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// First attribute value with this key; None when absent.
pub fn cl_event_get(ev: &CloudEvent, key: Str) -> Option[Str] {
  let n = ev.keys.len();
  let vn = ev.vals.len();
  var i = 0;
  while i < n && i < vn {
    let k: Str = ev.keys[i];
    if compare.str_compare(k, key) == 0 {
      let v: Str = ev.vals[i];
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

pub fn cl_event_key_count(ev: &CloudEvent) -> Int {
  let n = ev.keys.len();
  if ev.vals.len() < n {
    return ev.vals.len();
  }
  return n;
}

/// Attribute key `i`; "" out of range.
pub fn cl_event_key(ev: &CloudEvent, i: Int) -> Str {
  if i < 0 || i >= ev.keys.len() {
    return "";
  }
  let k: Str = ev.keys[i];
  return k;
}

/// Attribute value `i`; "" out of range.
pub fn cl_event_val(ev: &CloudEvent, i: Int) -> Str {
  if i < 0 || i >= ev.vals.len() {
    return "";
  }
  let v: Str = ev.vals[i];
  return v;
}

// --------------------------------------------------
//  key=value format
// --------------------------------------------------

// Escape for quoted key=value values: \\ \" \n \r \t and \xNN for other
// control bytes (including DEL).
fn _cl_kv_escape(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _CL_BACKSLASH {
      out.push(_CL_BACKSLASH);
      out.push(_CL_BACKSLASH);
    } elif b == _CL_DQUOTE {
      out.push(_CL_BACKSLASH);
      out.push(_CL_DQUOTE);
    } elif b == _CL_LF {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_N);
    } elif b == _CL_CR {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_R);
    } elif b == _CL_TAB {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_T);
    } elif b < 32u8 || b == _CL_DEL {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_X);
      _cl_push_hex2(out, (b as Int) & 0xFF);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

/// Decode one quoted key=value value starting at the opening quote.
/// Escapes: \\ \" \n \r \t and \xNN (two hex digits, NUL rejected).
fn _cl_kv_string(s: Str, from: Int) -> _ClScan {
  let n = s.len();
  var r = _ClScan{ text: ""; next: from; ok: false; err: ""; pos: from };
  if from >= n || string.byte_at(s, from) != _CL_DQUOTE {
    r.err = "expected string";
    r.pos = from;
    return r;
  }
  var i = from + 1;
  var out = Vec[UInt8].new();
  while i < n {
    let b = string.byte_at(s, i);
    if b == _CL_DQUOTE {
      r.text = builder.sb_to_str(&out);
      r.next = i + 1;
      r.ok = true;
      return r;
    }
    if b == _CL_BACKSLASH {
      if i + 1 >= n {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
      let e = string.byte_at(s, i + 1);
      if e == _CL_DQUOTE {
        out.push(_CL_DQUOTE);
        i = i + 2;
      } elif e == _CL_BACKSLASH {
        out.push(_CL_BACKSLASH);
        i = i + 2;
      } elif e == _CL_LOWER_N {
        out.push(_CL_LF);
        i = i + 2;
      } elif e == _CL_LOWER_R {
        out.push(_CL_CR);
        i = i + 2;
      } elif e == _CL_LOWER_T {
        out.push(_CL_TAB);
        i = i + 2;
      } elif e == _CL_LOWER_X {
        if i + 4 > n {
          r.err = "bad escape";
          r.pos = i;
          return r;
        }
        let h0 = _cl_hex_val(string.byte_at(s, i + 2));
        let h1 = _cl_hex_val(string.byte_at(s, i + 3));
        if h0 < 0 || h1 < 0 {
          r.err = "bad escape";
          r.pos = i;
          return r;
        }
        let v = h0 * 16 + h1;
        if v == 0 {
          r.err = "unsupported escape";
          r.pos = i;
          return r;
        }
        out.push(v as UInt8);
        i = i + 4;
      } else {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
    } elif b < 32u8 || b == _CL_DEL {
      r.err = "bad character";
      r.pos = i;
      return r;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  r.err = "unterminated string";
  r.pos = n;
  return r;
}

/// Encode an event as one key=value line:
/// `time=<ms> level=<name> severity=<n> msg="..." [key="..."]...`
/// (extra attributes in insertion order; canonical quoted-value escaping).
pub fn cl_kv_encode(ev: &CloudEvent) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, "time=");
  builder.sb_push_int(&mut sb, ev.time_ms);
  builder.sb_push_str(&mut sb, " level=");
  builder.sb_push_str(&mut sb, cl_level_name(ev.level));
  builder.sb_push_str(&mut sb, " severity=");
  builder.sb_push_int(&mut sb, ev.severity);
  builder.sb_push_str(&mut sb, " msg=\"");
  _cl_kv_escape(&mut sb, ev.msg);
  builder.sb_push_byte(&mut sb, _CL_DQUOTE);
  let kn = ev.keys.len();
  let vn = ev.vals.len();
  var i = 0;
  while i < kn && i < vn {
    let k: Str = ev.keys[i];
    let v: Str = ev.vals[i];
    builder.sb_push_byte(&mut sb, _CL_SP);
    builder.sb_push_str(&mut sb, k);
    builder.sb_push_str(&mut sb, "=\"");
    _cl_kv_escape(&mut sb, v);
    builder.sb_push_byte(&mut sb, _CL_DQUOTE);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// Parse one key=value line into a CloudEvent. Fields are SP-separated;
/// values are bare (no SP) or double-quoted. Required: `time` (integer) and
/// `level` (name). Optional: `severity` (0..5 integer, defaults to level) and
/// `msg` (string, defaults ""). Any other key becomes an attribute; duplicate
/// keys (header or attribute) are errors. Every error is
/// "cloudlog: <reason> at <byte offset>".
pub fn cl_kv_decode(line: Str) -> Result[CloudEvent, Str] {
  let n = line.len();
  var ev = cl_event_new(0, 2, "");
  var i = 0;
  while i < n && string.byte_at(line, i) == _CL_SP {
    i = i + 1;
  }
  if i >= n {
    return _cl_err_event(_cl_err_at("empty line", 0));
  }
  var seen_time = false;
  var seen_level = false;
  var seen_sev = false;
  var seen_msg = false;
  while i < n {
    while i < n && string.byte_at(line, i) == _CL_SP {
      i = i + 1;
    }
    if i >= n {
      break;
    }
    let key_at = i;
    while i < n && _cl_key_char(string.byte_at(line, i)) {
      i = i + 1;
    }
    if i == key_at {
      return _cl_err_event(_cl_err_at("bad key", i));
    }
    let key = string.str_slice(line, key_at, i);
    if i >= n || string.byte_at(line, i) != _CL_EQ {
      return _cl_err_event(_cl_err_at("expected =", i));
    }
    i = i + 1;
    if i >= n {
      return _cl_err_event(_cl_err_at("missing value", i));
    }
    var val = "";
    var val_at = i;
    var was_quoted = false;
    if string.byte_at(line, i) == _CL_DQUOTE {
      was_quoted = true;
      val_at = i + 1;
      let sc = _cl_kv_string(line, i);
      if !sc.ok {
        return _cl_err_event(_cl_err_at(sc.err, sc.pos));
      }
      val = sc.text;
      i = sc.next;
      if i < n && string.byte_at(line, i) != _CL_SP {
        return _cl_err_event(_cl_err_at("bad value", i));
      }
    } else {
      let bare_at = i;
      while i < n && string.byte_at(line, i) != _CL_SP {
        let vb = string.byte_at(line, i);
        if vb == _CL_BACKSLASH || vb == _CL_DQUOTE {
          return _cl_err_event(_cl_err_at("bad value", i));
        }
        i = i + 1;
      }
      if i == bare_at {
        return _cl_err_event(_cl_err_at("missing value", bare_at));
      }
      val = string.str_slice(line, bare_at, i);
    }
    if compare.str_compare(key, "time") == 0 {
      if seen_time {
        return _cl_err_event(_cl_err_at("duplicate key: time", key_at));
      }
      seen_time = true;
      if was_quoted {
        return _cl_err_event(_cl_err_at("bad integer", val_at));
      }
      let iv = _cl_scan_int(line, val_at);
      if !iv.ok {
        return _cl_err_event(_cl_err_at(iv.err, iv.pos));
      }
      if iv.next != i {
        return _cl_err_event(_cl_err_at("bad integer", iv.next));
      }
      ev.time_ms = iv.value;
    } elif compare.str_compare(key, "level") == 0 {
      if seen_level {
        return _cl_err_event(_cl_err_at("duplicate key: level", key_at));
      }
      seen_level = true;
      let lc = cl_level_code(val);
      if !lc.is_ok {
        return _cl_err_event(_cl_err_at("unknown level: " + val, val_at));
      }
      ev.level = lc.value;
    } elif compare.str_compare(key, "severity") == 0 {
      if seen_sev {
        return _cl_err_event(_cl_err_at("duplicate key: severity", key_at));
      }
      seen_sev = true;
      if was_quoted {
        return _cl_err_event(_cl_err_at("bad integer", val_at));
      }
      let sv = _cl_scan_int(line, val_at);
      if !sv.ok {
        return _cl_err_event(_cl_err_at(sv.err, sv.pos));
      }
      if sv.next != i {
        return _cl_err_event(_cl_err_at("bad integer", sv.next));
      }
      if sv.value < 0 || sv.value > _CL_LEVEL_MAX {
        return _cl_err_event(_cl_err_at("bad severity", val_at));
      }
      ev.severity = sv.value;
    } elif compare.str_compare(key, "msg") == 0 {
      if seen_msg {
        return _cl_err_event(_cl_err_at("duplicate key: msg", key_at));
      }
      seen_msg = true;
      ev.msg = val;
    } else {
      if cl_event_has_key(&ev, key) {
        return _cl_err_event(_cl_err_at("duplicate key: " + key, key_at));
      }
      if !cl_event_set(&mut ev, key, val) {
        return _cl_err_event(_cl_err_at("bad key", key_at));
      }
    }
  }
  if !seen_time {
    return _cl_err_event(_cl_err_at("missing time", n));
  }
  if !seen_level {
    return _cl_err_event(_cl_err_at("missing level", n));
  }
  if !seen_sev {
    ev.severity = ev.level;
  }
  return _cl_ok_event(ev);
}

// --------------------------------------------------
//  JSON-ish format
// --------------------------------------------------

// Escape for JSON strings: \" \\ / escaped forms; control bytes < 0x20 use
// \u00NN. Bytes >= 0x80 pass through byte-exact.
fn _cl_json_escape(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _CL_DQUOTE {
      out.push(_CL_BACKSLASH);
      out.push(_CL_DQUOTE);
    } elif b == _CL_BACKSLASH {
      out.push(_CL_BACKSLASH);
      out.push(_CL_BACKSLASH);
    } elif b == _CL_LF {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_N);
    } elif b == _CL_CR {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_R);
    } elif b == _CL_TAB {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_T);
    } elif b == 8u8 {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_B);
    } elif b == 12u8 {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_F);
    } elif b < 32u8 {
      out.push(_CL_BACKSLASH);
      out.push(_CL_LOWER_U);
      out.push(_CL_ZERO);
      out.push(_CL_ZERO);
      _cl_push_hex2(out, (b as Int) & 0xFF);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

/// Decode one double-quoted JSON string starting at `from`. Escapes: \" \\
/// \/ \b \f \n \r \t and \uXXXX for code points 1..127 (0 or >127 are
/// "unsupported unicode escape"); raw control bytes are "bad character".
fn _cl_json_string(s: Str, from: Int) -> _ClScan {
  let n = s.len();
  var r = _ClScan{ text: ""; next: from; ok: false; err: ""; pos: from };
  if from >= n || string.byte_at(s, from) != _CL_DQUOTE {
    r.err = "expected string";
    r.pos = from;
    return r;
  }
  var i = from + 1;
  var out = Vec[UInt8].new();
  while i < n {
    let b = string.byte_at(s, i);
    if b == _CL_DQUOTE {
      r.text = builder.sb_to_str(&out);
      r.next = i + 1;
      r.ok = true;
      return r;
    }
    if b == _CL_BACKSLASH {
      if i + 1 >= n {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
      let e = string.byte_at(s, i + 1);
      if e == _CL_DQUOTE {
        out.push(_CL_DQUOTE);
        i = i + 2;
      } elif e == _CL_BACKSLASH {
        out.push(_CL_BACKSLASH);
        i = i + 2;
      } elif e == _CL_SLASH {
        out.push(_CL_SLASH);
        i = i + 2;
      } elif e == _CL_LOWER_B {
        out.push(8u8);
        i = i + 2;
      } elif e == _CL_LOWER_F {
        out.push(12u8);
        i = i + 2;
      } elif e == _CL_LOWER_N {
        out.push(_CL_LF);
        i = i + 2;
      } elif e == _CL_LOWER_R {
        out.push(_CL_CR);
        i = i + 2;
      } elif e == _CL_LOWER_T {
        out.push(_CL_TAB);
        i = i + 2;
      } elif e == _CL_LOWER_U {
        if i + 6 > n {
          r.err = "bad unicode escape";
          r.pos = i;
          return r;
        }
        let h0 = _cl_hex_val(string.byte_at(s, i + 2));
        let h1 = _cl_hex_val(string.byte_at(s, i + 3));
        let h2 = _cl_hex_val(string.byte_at(s, i + 4));
        let h3 = _cl_hex_val(string.byte_at(s, i + 5));
        if h0 < 0 || h1 < 0 || h2 < 0 || h3 < 0 {
          r.err = "bad unicode escape";
          r.pos = i;
          return r;
        }
        let cp = h0 * 4096 + h1 * 256 + h2 * 16 + h3;
        if cp < 1 || cp > 127 {
          r.err = "unsupported unicode escape";
          r.pos = i;
          return r;
        }
        out.push(cp as UInt8);
        i = i + 6;
      } else {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
    } elif b < 32u8 {
      r.err = "bad character";
      r.pos = i;
      return r;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  r.err = "unterminated string";
  r.pos = n;
  return r;
}

/// Encode an event as a flat JSON-ish object:
/// `{"time":<ms>,"level":"<name>","severity":<n>,"msg":"..."[,"k":"v"]...}`
/// Extra attribute values are always encoded as strings (integers and bools
/// from cl_json_decode are stored as their text form).
pub fn cl_json_encode(ev: &CloudEvent) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, "{\"time\":");
  builder.sb_push_int(&mut sb, ev.time_ms);
  builder.sb_push_str(&mut sb, ",\"level\":\"");
  builder.sb_push_str(&mut sb, cl_level_name(ev.level));
  builder.sb_push_str(&mut sb, "\",\"severity\":");
  builder.sb_push_int(&mut sb, ev.severity);
  builder.sb_push_str(&mut sb, ",\"msg\":\"");
  _cl_json_escape(&mut sb, ev.msg);
  builder.sb_push_byte(&mut sb, _CL_DQUOTE);
  let kn = ev.keys.len();
  let vn = ev.vals.len();
  var i = 0;
  while i < kn && i < vn {
    let k: Str = ev.keys[i];
    let v: Str = ev.vals[i];
    builder.sb_push_str(&mut sb, ",\"");
    _cl_json_escape(&mut sb, k);
    builder.sb_push_str(&mut sb, "\":\"");
    _cl_json_escape(&mut sb, v);
    builder.sb_push_byte(&mut sb, _CL_DQUOTE);
    i = i + 1;
  }
  builder.sb_push_byte(&mut sb, _CL_RBRACE);
  return builder.sb_to_str(&sb);
}

/// Parse a flat JSON-ish object with string keys. Values may be strings,
/// integers (stored as their decimal text) or true/false (stored as text);
/// nested objects/arrays are "unsupported value". Required fields: `time`
/// (integer) and `level` (string name); optional `severity` (0..5 integer,
/// defaults to level) and `msg` (string). Duplicate keys are errors. Errors
/// are "cloudlog: <reason> at <byte offset>".
pub fn cl_json_decode(text: Str) -> Result[CloudEvent, Str] {
  let n = text.len();
  var ev = cl_event_new(0, 2, "");
  var i = _cl_skip_ws(text, 0);
  if i >= n {
    return _cl_err_event(_cl_err_at("empty document", 0));
  }
  if string.byte_at(text, i) != _CL_LBRACE {
    return _cl_err_event(_cl_err_at("expected object", i));
  }
  i = _cl_skip_ws(text, i + 1);
  var seen_time = false;
  var seen_level = false;
  var seen_sev = false;
  var seen_msg = false;
  if i < n && string.byte_at(text, i) == _CL_RBRACE {
    i = i + 1;
    i = _cl_skip_ws(text, i);
    if i < n {
      return _cl_err_event(_cl_err_at("trailing data", i));
    }
    return _cl_err_event(_cl_err_at("missing time", n));
  }
  var done = false;
  while !done {
    i = _cl_skip_ws(text, i);
    if i >= n {
      return _cl_err_event(_cl_err_at("unterminated object", n));
    }
    if string.byte_at(text, i) != _CL_DQUOTE {
      return _cl_err_event(_cl_err_at("expected key", i));
    }
    let key_at = i;
    let ks = _cl_json_string(text, i);
    if !ks.ok {
      return _cl_err_event(_cl_err_at(ks.err, ks.pos));
    }
    let key = ks.text;
    i = _cl_skip_ws(text, ks.next);
    if i >= n || string.byte_at(text, i) != _CL_COLON {
      return _cl_err_event(_cl_err_at("expected colon", i));
    }
    i = _cl_skip_ws(text, i + 1);
    if i >= n {
      return _cl_err_event(_cl_err_at("expected value", n));
    }
    var val = "";
    var kind = 0;
    var ival = 0;
    let value_at = i;
    if string.byte_at(text, i) == _CL_DQUOTE {
      let vs = _cl_json_string(text, i);
      if !vs.ok {
        return _cl_err_event(_cl_err_at(vs.err, vs.pos));
      }
      val = vs.text;
      kind = 1;
      i = vs.next;
    } elif string.byte_at(text, i) == _CL_DASH || _cl_is_digit(string.byte_at(text, i)) {
      let iv = _cl_scan_int(text, i);
      if !iv.ok {
        return _cl_err_event(_cl_err_at(iv.err, iv.pos));
      }
      ival = iv.value;
      val = _cl_int_to_str(ival);
      kind = 2;
      i = iv.next;
    } elif string.byte_at(text, i) == _CL_LOWER_T {
      if !_cl_word_at(text, i, "true") {
        return _cl_err_event(_cl_err_at("unsupported value", i));
      }
      val = "true";
      kind = 3;
      i = i + 4;
    } elif string.byte_at(text, i) == _CL_LOWER_F {
      if !_cl_word_at(text, i, "false") {
        return _cl_err_event(_cl_err_at("unsupported value", i));
      }
      val = "false";
      kind = 3;
      i = i + 5;
    } else {
      return _cl_err_event(_cl_err_at("unsupported value", i));
    }
    if compare.str_compare(key, "time") == 0 {
      if seen_time {
        return _cl_err_event(_cl_err_at("duplicate key: time", key_at));
      }
      seen_time = true;
      if kind != 2 {
        return _cl_err_event(_cl_err_at("bad integer", value_at));
      }
      ev.time_ms = ival;
    } elif compare.str_compare(key, "level") == 0 {
      if seen_level {
        return _cl_err_event(_cl_err_at("duplicate key: level", key_at));
      }
      seen_level = true;
      if kind != 1 {
        return _cl_err_event(_cl_err_at("bad level", value_at));
      }
      let lc = cl_level_code(val);
      if !lc.is_ok {
        return _cl_err_event(_cl_err_at("unknown level: " + val, value_at));
      }
      ev.level = lc.value;
    } elif compare.str_compare(key, "severity") == 0 {
      if seen_sev {
        return _cl_err_event(_cl_err_at("duplicate key: severity", key_at));
      }
      seen_sev = true;
      if kind != 2 || ival < 0 || ival > _CL_LEVEL_MAX {
        return _cl_err_event(_cl_err_at("bad severity", value_at));
      }
      ev.severity = ival;
    } elif compare.str_compare(key, "msg") == 0 {
      if seen_msg {
        return _cl_err_event(_cl_err_at("duplicate key: msg", key_at));
      }
      seen_msg = true;
      if kind != 1 {
        return _cl_err_event(_cl_err_at("bad string", value_at));
      }
      ev.msg = val;
    } else {
      if cl_event_has_key(&ev, key) {
        return _cl_err_event(_cl_err_at("duplicate key: " + key, key_at));
      }
      if !cl_event_set(&mut ev, key, val) {
        return _cl_err_event(_cl_err_at("bad key", key_at));
      }
    }
    i = _cl_skip_ws(text, i);
    if i >= n {
      return _cl_err_event(_cl_err_at("unterminated object", n));
    }
    let t = string.byte_at(text, i);
    if t == _CL_COMMA {
      i = i + 1;
    } elif t == _CL_RBRACE {
      i = i + 1;
      done = true;
    } else {
      return _cl_err_event(_cl_err_at("unterminated object", i));
    }
  }
  i = _cl_skip_ws(text, i);
  if i < n {
    return _cl_err_event(_cl_err_at("trailing data", i));
  }
  if !seen_time {
    return _cl_err_event(_cl_err_at("missing time", n));
  }
  if !seen_level {
    return _cl_err_event(_cl_err_at("missing level", n));
  }
  if !seen_sev {
    ev.severity = ev.level;
  }
  return _cl_ok_event(ev);
}

// --------------------------------------------------
//  Ingest batching and sequence watermarks
// --------------------------------------------------

/// New ingest buffer whose first expected sequence is `base_seq`.
pub fn cl_ingest_new(base_seq: Int) -> CloudIngest {
  return CloudIngest{
    lines: Vec[Str].new();
    seqs: Vec[Int].new();
    times: Vec[Int].new();
    sizes: Vec[Int].new();
    base_seq: base_seq;
    next_seq: base_seq;
    watermark: base_seq - 1;
    seen_max: base_seq - 1;
    accepted: 0;
    duplicates: 0;
    gap_events: 0;
    total_bytes: 0;
  };
}

fn _cl_ingest_has_seq(ing: &CloudIngest, seq: Int) -> Bool {
  let n = ing.seqs.len();
  var i = 0;
  while i < n {
    let s: Int = ing.seqs[i];
    if s == seq {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Accept one externally sequenced event. Returns _CL_ACCEPT_IN_ORDER (0)
/// when the sequence is now contiguous, _CL_ACCEPT_GAP (1) when it was
/// accepted but a gap remains, _CL_ACCEPT_DUPLICATE (2) for a sequence at or
/// below the watermark, and _CL_ACCEPT_EMPTY (3) for an empty line (which is
/// never stored). The watermark advances through any filled gap.
pub fn cl_ingest_accept(ing: &mut CloudIngest, seq: Int, time_ms: Int, line: Str) -> Int {
  if line.len() == 0 {
    return _CL_ACCEPT_EMPTY;
  }
  if seq < ing.watermark + 1 {
    ing.duplicates = ing.duplicates + 1;
    return _CL_ACCEPT_DUPLICATE;
  }
  ing.lines.push(line);
  ing.seqs.push(seq);
  ing.times.push(time_ms);
  ing.sizes.push(line.len());
  ing.accepted = ing.accepted + 1;
  ing.total_bytes = ing.total_bytes + line.len();
  if seq > ing.seen_max {
    ing.seen_max = seq;
  }
  if seq == ing.watermark + 1 {
    ing.watermark = seq;
    var more = true;
    while more {
      more = false;
      if _cl_ingest_has_seq(ing, ing.watermark + 1) {
        ing.watermark = ing.watermark + 1;
        more = true;
      }
    }
  }
  if seq > ing.watermark {
    ing.gap_events = ing.gap_events + 1;
    return _CL_ACCEPT_GAP;
  }
  return _CL_ACCEPT_IN_ORDER;
}

/// Producer path: assign the next sequence and accept the event in one step
/// (returns the accept code).
pub fn cl_ingest_assign(ing: &mut CloudIngest, time_ms: Int, line: Str) -> Int {
  let s = ing.next_seq;
  ing.next_seq = ing.next_seq + 1;
  return cl_ingest_accept(ing, s, time_ms, line);
}

/// Highest contiguous sequence accepted; `base_seq - 1` when none.
pub fn cl_ingest_watermark(ing: &CloudIngest) -> Int {
  return ing.watermark;
}

/// Highest sequence ever seen; `base_seq - 1` when none.
pub fn cl_ingest_seen_max(ing: &CloudIngest) -> Int {
  return ing.seen_max;
}

/// Sequences seen above the watermark (`seen_max - watermark`, >= 0).
pub fn cl_ingest_pending(ing: &CloudIngest) -> Int {
  let d = ing.seen_max - ing.watermark;
  if d < 0 {
    return 0;
  }
  return d;
}

/// Buffered event count.
pub fn cl_ingest_count(ing: &CloudIngest) -> Int {
  return ing.lines.len();
}

pub fn cl_ingest_accepted(ing: &CloudIngest) -> Int {
  return ing.accepted;
}

pub fn cl_ingest_duplicates(ing: &CloudIngest) -> Int {
  return ing.duplicates;
}

pub fn cl_ingest_gap_events(ing: &CloudIngest) -> Int {
  return ing.gap_events;
}

pub fn cl_ingest_total_bytes(ing: &CloudIngest) -> Int {
  return ing.total_bytes;
}

/// Timestamp of the oldest buffered event; 0 when empty.
pub fn cl_ingest_first_time(ing: &CloudIngest) -> Int {
  if ing.times.len() == 0 {
    return 0;
  }
  let t: Int = ing.times[0];
  return t;
}

/// Timestamp of the newest buffered event; 0 when empty.
pub fn cl_ingest_last_time(ing: &CloudIngest) -> Int {
  let n = ing.times.len();
  if n == 0 {
    return 0;
  }
  let t: Int = ing.times[n - 1];
  return t;
}

/// Age of the oldest buffered event at `now_ms`; 0 when empty.
pub fn cl_ingest_age_ms(ing: &CloudIngest, now_ms: Int) -> Int {
  if ing.times.len() == 0 {
    return 0;
  }
  let t: Int = ing.times[0];
  return now_ms - t;
}

fn _cl_policy_triggers(pol: &CloudFlushPolicy, count: Int, bytes: Int, age_ms: Int) -> Int {
  if pol.max_events > 0 && count >= pol.max_events {
    return _CL_FLUSH_COUNT;
  }
  if pol.max_bytes > 0 && bytes >= pol.max_bytes {
    return _CL_FLUSH_BYTES;
  }
  if pol.max_age_ms > 0 && age_ms >= pol.max_age_ms {
    return _CL_FLUSH_AGE;
  }
  return _CL_FLUSH_NONE;
}

/// Current flush decision without mutating the buffer. Triggers are checked
/// in the fixed order count, bytes, age; an empty buffer never flushes.
pub fn cl_ingest_plan_flush(ing: &CloudIngest, pol: &CloudFlushPolicy, now_ms: Int) -> CloudFlush {
  let count = ing.lines.len();
  var f = CloudFlush{
    should: false;
    reason: _CL_FLUSH_NONE;
    count: count;
    bytes: ing.total_bytes;
    age_ms: 0;
    seq_first: -1;
    seq_last: -1;
  };
  if count == 0 {
    return f;
  }
  f.age_ms = now_ms - cl_ingest_first_time(ing);
  if ing.seqs.len() == count {
    f.seq_first = ing.seqs[0];
    f.seq_last = ing.seqs[count - 1];
  }
  let reason = _cl_policy_triggers(pol, count, ing.total_bytes, f.age_ms);
  if reason != _CL_FLUSH_NONE {
    f.should = true;
    f.reason = reason;
  }
  return f;
}

/// Flush the buffer: returns the pre-flush plan (reason _CL_FLUSH_EXPLICIT
/// when no policy triggered) and clears content and the byte total; sequence
/// assignments and lifetime counters (accepted, duplicates, gap_events,
/// watermark, next_seq) are preserved.
pub fn cl_ingest_flush(ing: &mut CloudIngest, pol: &CloudFlushPolicy, now_ms: Int) -> CloudFlush {
  var f = cl_ingest_plan_flush(ing, pol, now_ms);
  if f.count == 0 {
    return f;
  }
  if f.reason == _CL_FLUSH_NONE {
    f.reason = _CL_FLUSH_EXPLICIT;
  }
  f.should = true;
  ing.lines = Vec[Str].new();
  ing.seqs = Vec[Int].new();
  ing.times = Vec[Int].new();
  ing.sizes = Vec[Int].new();
  ing.total_bytes = 0;
  return f;
}

// --------------------------------------------------
//  Stream and tail consumer
// --------------------------------------------------

pub fn cl_stream_new() -> CloudStream {
  return CloudStream{
    blob: "";
    off: Vec[Int].new();
    len: Vec[Int].new();
    ts: Vec[Int].new();
  };
}

fn _cl_has_break(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _CL_LF || b == _CL_CR {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Append one record to the stream and return its index, or -1 when the
/// record is empty or contains CR/LF (which would break record framing).
pub fn cl_stream_append(st: &mut CloudStream, ts: Int, line: Str) -> Int {
  if line.len() == 0 {
    return -1;
  }
  if _cl_has_break(line) {
    return -1;
  }
  let idx = st.off.len();
  st.off.push(st.blob.len());
  st.len.push(line.len());
  st.ts.push(ts);
  st.blob = st.blob + line + "\n";
  return idx;
}

pub fn cl_stream_count(st: &CloudStream) -> Int {
  return st.off.len();
}

/// Record `i` text; "" out of range.
pub fn cl_stream_line(st: &CloudStream, i: Int) -> Str {
  if i < 0 || i >= st.off.len() || i >= st.len.len() {
    return "";
  }
  let at: Int = st.off[i];
  let ln: Int = st.len[i];
  return string.str_slice(st.blob, at, at + ln);
}

/// Record `i` timestamp; 0 out of range.
pub fn cl_stream_ts(st: &CloudStream, i: Int) -> Int {
  if i < 0 || i >= st.ts.len() {
    return 0;
  }
  let t: Int = st.ts[i];
  return t;
}

/// Total blob byte length including record separators.
pub fn cl_stream_byte_len(st: &CloudStream) -> Int {
  return st.blob.len();
}

/// Newest minus oldest record timestamp; 0 for fewer than two records.
pub fn cl_stream_span_ms(st: &CloudStream) -> Int {
  let n = st.ts.len();
  if n < 2 {
    return 0;
  }
  let first: Int = st.ts[0];
  let last: Int = st.ts[n - 1];
  return last - first;
}

/// New tail consumer whose cursor and checkpoint both start at
/// max(retained_from, 0).
pub fn cl_tail_new(retained_from: Int) -> CloudTail {
  var r = retained_from;
  if r < 0 {
    r = 0;
  }
  return CloudTail{ cursor: r; acked: r; retained_from: r; };
}

pub fn cl_tail_cursor(t: &CloudTail) -> Int {
  return t.cursor;
}

pub fn cl_tail_acked(t: &CloudTail) -> Int {
  return t.acked;
}

pub fn cl_tail_retained_from(t: &CloudTail) -> Int {
  return t.retained_from;
}

/// Delivered-but-uncommitted window (`cursor - acked`, clamped at 0).
pub fn cl_tail_lag(t: &CloudTail) -> Int {
  let d = t.cursor - t.acked;
  if d < 0 {
    return 0;
  }
  return d;
}

/// Move the cursor to `idx`, clamped up to the retention floor. Returns the
/// resulting cursor.
pub fn cl_tail_seek(t: &mut CloudTail, idx: Int) -> Int {
  if idx < t.retained_from {
    t.cursor = t.retained_from;
  } else {
    t.cursor = idx;
  }
  return t.cursor;
}

/// Commit through `through` (monotonic: refused when below the current
/// checkpoint). Advances the checkpoint to `through` and the cursor to at
/// least the checkpoint. This is the at-least-once commit: call it only
/// after the delivered records were processed.
pub fn cl_tail_commit(t: &mut CloudTail, through: Int) -> Bool {
  if through < t.acked {
    return false;
  }
  t.acked = through;
  if t.cursor < t.acked {
    t.cursor = t.acked;
  }
  return true;
}

/// Advance the retention floor (never backwards). Returns the new floor.
pub fn cl_tail_set_retained(t: &mut CloudTail, idx: Int) -> Int {
  if idx > t.retained_from {
    t.retained_from = idx;
  }
  return t.retained_from;
}

fn _cl_tail_read_from(st: &CloudStream, from_in: Int, max: Int, replayed: Bool, truncated: Bool) -> CloudRead {
  var total = st.off.len();
  if st.len.len() < total {
    total = st.len.len();
  }
  var from = from_in;
  if from < 0 {
    from = 0;
  }
  if from > total {
    from = total;
  }
  var r = CloudRead{
    lines: Vec[Str].new();
    idx: Vec[Int].new();
    count: 0;
    from: from;
    next_cursor: from;
    replayed: replayed;
    truncated: truncated;
  };
  if max <= 0 || from >= total {
    return r;
  }
  var take = max;
  if take > total - from {
    take = total - from;
  }
  var i = from;
  while i < from + take {
    let at: Int = st.off[i];
    let ln: Int = st.len[i];
    r.lines.push(string.str_slice(st.blob, at, at + ln));
    r.idx.push(i);
    i = i + 1;
  }
  r.count = take;
  r.next_cursor = from + take;
  return r;
}

/// Pull up to `max` records at the tail cursor without committing. When the
/// cursor is below the retention floor the read starts at the floor and
/// `truncated` is true (data was lost); the caller advances/commits with the
/// returned next_cursor after processing.
pub fn cl_tail_read(st: &CloudStream, t: &CloudTail, max: Int) -> CloudRead {
  var from = t.cursor;
  var truncated = false;
  if from < t.retained_from {
    from = t.retained_from;
    truncated = true;
  }
  return _cl_tail_read_from(st, from, max, false, truncated);
}

/// Replay up to `max` records from the committed checkpoint (at-least-once
/// redelivery after a crash). `truncated` is true when the checkpoint is
/// below the retention floor; commit only after the replayed records were
/// processed.
pub fn cl_tail_replay(st: &CloudStream, t: &CloudTail, max: Int) -> CloudRead {
  var from = t.acked;
  var truncated = false;
  if from < t.retained_from {
    from = t.retained_from;
    truncated = true;
  }
  return _cl_tail_read_from(st, from, max, true, truncated);
}

/// Invariant check: floor <= checkpoint <= cursor <= stream count.
pub fn cl_tail_ok(st: &CloudStream, t: &CloudTail) -> Bool {
  let total = st.off.len();
  if t.retained_from < 0 || t.retained_from > total {
    return false;
  }
  if t.acked < t.retained_from || t.cursor < t.acked {
    return false;
  }
  return t.cursor <= total;
}

// --------------------------------------------------
//  Retention store
// --------------------------------------------------

/// New empty store; `seg_max_events` (clamped to >= 1) is the per-segment
/// event roll threshold.
pub fn cl_store_new(seg_max_events: Int) -> CloudStore {
  var m = seg_max_events;
  if m < 1 {
    m = 1;
  }
  return CloudStore{
    seg_from_off: Vec[Int].new();
    seg_to_off: Vec[Int].new();
    seg_from_time: Vec[Int].new();
    seg_to_time: Vec[Int].new();
    seg_bytes: Vec[Int].new();
    seg_events: Vec[Int].new();
    seg_state: Vec[Int].new();
    seg_max_events: m;
    next_off: 0;
    live_count: 0;
    total_bytes: 0;
    total_events: 0;
    dropped_segments: 0;
    dropped_bytes: 0;
    dropped_events: 0;
    compacted_segments: 0;
  };
}

fn _cl_store_open_index(st: &CloudStore) -> Int {
  var i = st.seg_state.len();
  while i > 0 {
    i = i - 1;
    let s: Int = st.seg_state[i];
    if s == _CL_SEG_OPEN {
      return i;
    }
  }
  return -1;
}

/// Append one event (`nbytes` > 0) to the newest live segment, rolling a new
/// segment when the previous one is sealed or full. Returns the segment
/// index, or -1 when `nbytes` <= 0.
pub fn cl_store_append(st: &mut CloudStore, time_ms: Int, nbytes: Int) -> Int {
  if nbytes <= 0 {
    return -1;
  }
  var idx = _cl_store_open_index(st);
  var need_new = false;
  if idx < 0 {
    need_new = true;
  } else {
    let ev: Int = st.seg_events[idx];
    if ev >= st.seg_max_events {
      st.seg_state[idx] = _CL_SEG_SEALED;
      need_new = true;
    }
  }
  if need_new {
    st.seg_from_off.push(st.next_off);
    st.seg_to_off.push(st.next_off);
    st.seg_from_time.push(time_ms);
    st.seg_to_time.push(time_ms);
    st.seg_bytes.push(0);
    st.seg_events.push(0);
    st.seg_state.push(_CL_SEG_OPEN);
    idx = st.seg_state.len() - 1;
    st.live_count = st.live_count + 1;
  }
  st.seg_to_off[idx] = st.next_off + nbytes;
  st.seg_to_time[idx] = time_ms;
  st.seg_bytes[idx] = st.seg_bytes[idx] + nbytes;
  st.seg_events[idx] = st.seg_events[idx] + 1;
  st.next_off = st.next_off + nbytes;
  st.total_bytes = st.total_bytes + nbytes;
  st.total_events = st.total_events + 1;
  let after: Int = st.seg_events[idx];
  if after >= st.seg_max_events {
    st.seg_state[idx] = _CL_SEG_SEALED;
  }
  return idx;
}

/// Seal the newest open segment; returns its index or -1 when none is open.
pub fn cl_store_seal(st: &mut CloudStore) -> Int {
  let idx = _cl_store_open_index(st);
  if idx < 0 {
    return -1;
  }
  st.seg_state[idx] = _CL_SEG_SEALED;
  return idx;
}

pub fn cl_store_live_count(st: &CloudStore) -> Int {
  return st.live_count;
}

pub fn cl_store_segment_count(st: &CloudStore) -> Int {
  return st.seg_state.len();
}

pub fn cl_store_total_bytes(st: &CloudStore) -> Int {
  return st.total_bytes;
}

pub fn cl_store_total_events(st: &CloudStore) -> Int {
  return st.total_events;
}

pub fn cl_store_next_off(st: &CloudStore) -> Int {
  return st.next_off;
}

pub fn cl_store_dropped_segments(st: &CloudStore) -> Int {
  return st.dropped_segments;
}

pub fn cl_store_dropped_bytes(st: &CloudStore) -> Int {
  return st.dropped_bytes;
}

pub fn cl_store_dropped_events(st: &CloudStore) -> Int {
  return st.dropped_events;
}

pub fn cl_store_compacted_segments(st: &CloudStore) -> Int {
  return st.compacted_segments;
}

/// Segment `i` state (_CL_SEG_*); -1 out of range.
pub fn cl_store_segment_state(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_state.len() {
    return -1;
  }
  let s: Int = st.seg_state[i];
  return s;
}

pub fn cl_store_segment_bytes(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_bytes.len() {
    return 0;
  }
  let b: Int = st.seg_bytes[i];
  return b;
}

pub fn cl_store_segment_events(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_events.len() {
    return 0;
  }
  let e: Int = st.seg_events[i];
  return e;
}

pub fn cl_store_segment_from_off(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_from_off.len() {
    return 0;
  }
  let v: Int = st.seg_from_off[i];
  return v;
}

pub fn cl_store_segment_to_off(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_to_off.len() {
    return 0;
  }
  let v: Int = st.seg_to_off[i];
  return v;
}

pub fn cl_store_segment_from_time(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_from_time.len() {
    return 0;
  }
  let v: Int = st.seg_from_time[i];
  return v;
}

pub fn cl_store_segment_to_time(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_to_time.len() {
    return 0;
  }
  let v: Int = st.seg_to_time[i];
  return v;
}

/// Segment `i` time span (to_time - from_time); 0 out of range.
pub fn cl_store_segment_span_ms(st: &CloudStore, i: Int) -> Int {
  if i < 0 || i >= st.seg_from_time.len() || i >= st.seg_to_time.len() {
    return 0;
  }
  let a: Int = st.seg_from_time[i];
  let b: Int = st.seg_to_time[i];
  return b - a;
}

fn _cl_store_oldest_live(st: &CloudStore) -> Int {
  var i = 0;
  while i < st.seg_state.len() {
    let s: Int = st.seg_state[i];
    if s >= _CL_SEG_OPEN {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn _cl_store_next_live(st: &CloudStore, from: Int) -> Int {
  var i = from + 1;
  while i < st.seg_state.len() {
    let s: Int = st.seg_state[i];
    if s >= _CL_SEG_OPEN {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Oldest live segment start time; 0 when the store is empty.
pub fn cl_store_oldest_time(st: &CloudStore) -> Int {
  let i = _cl_store_oldest_live(st);
  if i < 0 || i >= st.seg_from_time.len() {
    return 0;
  }
  let v: Int = st.seg_from_time[i];
  return v;
}

/// Newest live segment end time; 0 when the store is empty.
pub fn cl_store_newest_time(st: &CloudStore) -> Int {
  var i = st.seg_state.len();
  while i > 0 {
    i = i - 1;
    let s: Int = st.seg_state[i];
    if s >= _CL_SEG_OPEN {
      if i >= st.seg_to_time.len() {
        return 0;
      }
      let v: Int = st.seg_to_time[i];
      return v;
    }
  }
  return 0;
}

// Drop the oldest live segment (refused when only one remains). Returns the
// dropped index or -1.
fn _cl_store_drop_oldest(st: &mut CloudStore) -> Int {
  if st.live_count <= 1 {
    return -1;
  }
  let idx = _cl_store_oldest_live(st);
  if idx < 0 {
    return -1;
  }
  st.seg_state[idx] = _CL_SEG_DEAD;
  st.live_count = st.live_count - 1;
  let b: Int = st.seg_bytes[idx];
  let e: Int = st.seg_events[idx];
  st.total_bytes = st.total_bytes - b;
  st.total_events = st.total_events - e;
  st.dropped_segments = st.dropped_segments + 1;
  st.dropped_bytes = st.dropped_bytes + b;
  st.dropped_events = st.dropped_events + e;
  return idx;
}

/// Apply the retention policy: bytes, then age, then segment count, then
/// event count (each stage disabled when its policy value is <= 0). The
/// newest live segment is never dropped. Returns what was dropped, the first
/// policy reason that caused a drop (_CL_RETAIN_*) and the oldest surviving
/// offset/time.
pub fn cl_store_apply_retention(st: &mut CloudStore, pol: &CloudStorePolicy, now_ms: Int) -> CloudRetention {
  var r = CloudRetention{
    dropped: 0;
    dropped_bytes: 0;
    dropped_events: 0;
    reason: _CL_RETAIN_NONE;
    keep_from_off: cl_store_segment_from_off(st, _cl_store_oldest_live(st));
    keep_from_time: cl_store_oldest_time(st);
  };
  let d0 = st.dropped_segments;
  let db0 = st.dropped_bytes;
  let de0 = st.dropped_events;
  // 1. bytes
  if pol.max_bytes > 0 {
    var go = true;
    while go {
      go = false;
      if st.live_count > 1 && st.total_bytes > pol.max_bytes {
        if _cl_store_drop_oldest(st) >= 0 {
          go = true;
        }
      }
    }
  }
  if st.dropped_segments > d0 && r.reason == _CL_RETAIN_NONE {
    r.reason = _CL_RETAIN_BYTES;
  }
  // 2. age (whole segment older than the window)
  let d1 = st.dropped_segments;
  if pol.max_age_ms > 0 {
    var go = true;
    while go {
      go = false;
      if st.live_count > 1 {
        let old_t = _cl_store_oldest_live_end(st);
        if now_ms - old_t > pol.max_age_ms {
          if _cl_store_drop_oldest(st) >= 0 {
            go = true;
          }
        }
      }
    }
  }
  if st.dropped_segments > d1 && r.reason == _CL_RETAIN_NONE {
    r.reason = _CL_RETAIN_AGE;
  }
  // 3. segment count
  let d2 = st.dropped_segments;
  if pol.max_segments > 0 {
    var go = true;
    while go {
      go = false;
      if st.live_count > 1 && st.live_count > pol.max_segments {
        if _cl_store_drop_oldest(st) >= 0 {
          go = true;
        }
      }
    }
  }
  if st.dropped_segments > d2 && r.reason == _CL_RETAIN_NONE {
    r.reason = _CL_RETAIN_SEGMENTS;
  }
  // 4. event count
  let d3 = st.dropped_segments;
  if pol.max_events > 0 {
    var go = true;
    while go {
      go = false;
      if st.live_count > 1 && st.total_events > pol.max_events {
        if _cl_store_drop_oldest(st) >= 0 {
          go = true;
        }
      }
    }
  }
  if st.dropped_segments > d3 && r.reason == _CL_RETAIN_NONE {
    r.reason = _CL_RETAIN_EVENTS;
  }
  r.dropped = st.dropped_segments - d0;
  r.dropped_bytes = st.dropped_bytes - db0;
  r.dropped_events = st.dropped_events - de0;
  r.keep_from_off = cl_store_segment_from_off(st, _cl_store_oldest_live(st));
  r.keep_from_time = cl_store_oldest_time(st);
  return r;
}

// Oldest live segment end time; 0 when empty. Used by the age policy.
fn _cl_store_oldest_live_end(st: &CloudStore) -> Int {
  let i = _cl_store_oldest_live(st);
  if i < 0 || i >= st.seg_to_time.len() {
    return 0;
  }
  let v: Int = st.seg_to_time[i];
  return v;
}

/// Merge the oldest live segments until at most `target` (clamped to >= 1)
/// remain. Statistics are preserved (bytes/events move into the surviving
/// older segment); each merge increments compacted_segments. Returns the
/// number of merges performed.
pub fn cl_store_compact(st: &mut CloudStore, target: Int) -> Int {
  var t = target;
  if t < 1 {
    t = 1;
  }
  var merges = 0;
  while st.live_count > t {
    let a = _cl_store_oldest_live(st);
    let b = _cl_store_next_live(st, a);
    if a < 0 || b < 0 {
      break;
    }
    st.seg_to_off[a] = st.seg_to_off[b];
    st.seg_to_time[a] = st.seg_to_time[b];
    st.seg_bytes[a] = st.seg_bytes[a] + st.seg_bytes[b];
    st.seg_events[a] = st.seg_events[a] + st.seg_events[b];
    let bs: Int = st.seg_state[b];
    if bs == _CL_SEG_OPEN {
      st.seg_state[a] = _CL_SEG_OPEN;
    }
    st.seg_state[b] = _CL_SEG_DEAD;
    st.live_count = st.live_count - 1;
    st.compacted_segments = st.compacted_segments + 1;
    merges = merges + 1;
  }
  return merges;
}

/// True when the policy wants compaction now (compact_at > 0 and the live
/// segment count exceeds it).
pub fn cl_store_compact_due(st: &CloudStore, pol: &CloudStorePolicy) -> Bool {
  if pol.compact_at <= 0 {
    return false;
  }
  return st.live_count > pol.compact_at;
}

// --------------------------------------------------
//  Search: log table, predicate tree, pagination
// --------------------------------------------------

pub fn cl_log_new() -> CloudLog {
  return CloudLog{
    time: Vec[Int].new();
    level: Vec[Int].new();
    sev: Vec[Int].new();
    msg: Vec[Str].new();
    kname: Vec[Str].new();
    kval: Vec[Str].new();
    krec: Vec[Int].new();
  };
}

/// Append one record and return its index.
pub fn cl_log_add(l: &mut CloudLog, time_ms: Int, level: Int, severity: Int, msg: Str) -> Int {
  l.time.push(time_ms);
  l.level.push(level);
  l.sev.push(severity);
  l.msg.push(msg);
  return l.time.len() - 1;
}

/// Attach one attribute to record `rec`; false for an invalid record index
/// or key.
pub fn cl_log_add_kv(l: &mut CloudLog, rec: Int, key: Str, val: Str) -> Bool {
  if rec < 0 || rec >= l.time.len() {
    return false;
  }
  if !cl_key_ok(key) {
    return false;
  }
  l.kname.push(key);
  l.kval.push(val);
  l.krec.push(rec);
  return true;
}

pub fn cl_log_count(l: &CloudLog) -> Int {
  return l.time.len();
}

pub fn cl_log_time(l: &CloudLog, i: Int) -> Int {
  if i < 0 || i >= l.time.len() {
    return 0;
  }
  let v: Int = l.time[i];
  return v;
}

pub fn cl_log_level(l: &CloudLog, i: Int) -> Int {
  if i < 0 || i >= l.level.len() {
    return -1;
  }
  let v: Int = l.level[i];
  return v;
}

pub fn cl_log_severity(l: &CloudLog, i: Int) -> Int {
  if i < 0 || i >= l.sev.len() {
    return -1;
  }
  let v: Int = l.sev[i];
  return v;
}

pub fn cl_log_msg(l: &CloudLog, i: Int) -> Str {
  if i < 0 || i >= l.msg.len() {
    return "";
  }
  let v: Str = l.msg[i];
  return v;
}

/// First attribute value with this key on `rec`; None when absent.
pub fn cl_log_key_get(l: &CloudLog, rec: Int, key: Str) -> Option[Str] {
  let n = l.krec.len();
  let nn = l.kname.len();
  let vn = l.kval.len();
  var i = 0;
  while i < n && i < nn && i < vn {
    let r: Int = l.krec[i];
    if r == rec {
      let k: Str = l.kname[i];
      if compare.str_compare(k, key) == 0 {
        let v: Str = l.kval[i];
        return Some(v);
      }
    }
    i = i + 1;
  }
  return None;
}

pub fn cl_pred_new() -> CloudPred {
  return CloudPred{
    op: Vec[Int].new();
    left: Vec[Int].new();
    right: Vec[Int].new();
    num: Vec[Int].new();
    num2: Vec[Int].new();
    text: Vec[Str].new();
    text2: Vec[Str].new();
  };
}

fn _cl_pred_push(p: &mut CloudPred, op: Int, left: Int, right: Int, num: Int, num2: Int, text: Str, text2: Str) -> Int {
  p.op.push(op);
  p.left.push(left);
  p.right.push(right);
  p.num.push(num);
  p.num2.push(num2);
  p.text.push(text);
  p.text2.push(text2);
  return p.op.len() - 1;
}

/// Constant node (op TRUE/FALSE).
pub fn cl_pred_const(p: &mut CloudPred, value: Bool) -> Int {
  if value {
    return _cl_pred_push(p, _CL_PRED_TRUE, -1, -1, 0, 0, "", "");
  }
  return _cl_pred_push(p, _CL_PRED_FALSE, -1, -1, 0, 0, "", "");
}

/// Logical AND of nodes `a` and `b`; -1 when a child index is invalid.
pub fn cl_pred_and(p: &mut CloudPred, a: Int, b: Int) -> Int {
  if a < 0 || b < 0 || a >= p.op.len() || b >= p.op.len() {
    return -1;
  }
  return _cl_pred_push(p, _CL_PRED_AND, a, b, 0, 0, "", "");
}

/// Logical OR of nodes `a` and `b`; -1 when a child index is invalid.
pub fn cl_pred_or(p: &mut CloudPred, a: Int, b: Int) -> Int {
  if a < 0 || b < 0 || a >= p.op.len() || b >= p.op.len() {
    return -1;
  }
  return _cl_pred_push(p, _CL_PRED_OR, a, b, 0, 0, "", "");
}

/// Logical NOT of node `a`; -1 when the child index is invalid.
pub fn cl_pred_not(p: &mut CloudPred, a: Int) -> Int {
  if a < 0 || a >= p.op.len() {
    return -1;
  }
  return _cl_pred_push(p, _CL_PRED_NOT, a, -1, 0, 0, "", "");
}

/// Leaf: record level equals `level`.
pub fn cl_pred_level(p: &mut CloudPred, level: Int) -> Int {
  return _cl_pred_push(p, _CL_PRED_LEVEL, -1, -1, level, 0, "", "");
}

/// Leaf: record severity >= `severity`.
pub fn cl_pred_sev_ge(p: &mut CloudPred, severity: Int) -> Int {
  return _cl_pred_push(p, _CL_PRED_SEV_GE, -1, -1, severity, 0, "", "");
}

/// Leaf: message contains `needle` (empty needle matches every record).
pub fn cl_pred_msg_contains(p: &mut CloudPred, needle: Str) -> Int {
  return _cl_pred_push(p, _CL_PRED_MSG, -1, -1, 0, 0, needle, "");
}

/// Leaf: record has attribute `key` with exactly `val`.
pub fn cl_pred_key_eq(p: &mut CloudPred, key: Str, val: Str) -> Int {
  return _cl_pred_push(p, _CL_PRED_KEY, -1, -1, 0, 0, key, val);
}

/// Leaf: record time in the inclusive range [from_time, to_time].
pub fn cl_pred_time_range(p: &mut CloudPred, from_time: Int, to_time: Int) -> Int {
  return _cl_pred_push(p, _CL_PRED_TIME, -1, -1, from_time, to_time, "", "");
}

pub fn cl_pred_node_count(p: &CloudPred) -> Int {
  return p.op.len();
}

/// Opcode of node `i`; -1 out of range.
pub fn cl_pred_op(p: &CloudPred, i: Int) -> Int {
  if i < 0 || i >= p.op.len() {
    return -1;
  }
  let v: Int = p.op[i];
  return v;
}

fn _cl_log_key_match(l: &CloudLog, rec: Int, key: Str, val: Str) -> Bool {
  let n = l.krec.len();
  let nn = l.kname.len();
  let vn = l.kval.len();
  var i = 0;
  while i < n && i < nn && i < vn {
    let r: Int = l.krec[i];
    if r == rec {
      let k: Str = l.kname[i];
      if compare.str_compare(k, key) == 0 {
        let v: Str = l.kval[i];
        if compare.str_compare(v, val) == 0 {
          return true;
        }
      }
    }
    i = i + 1;
  }
  return false;
}

/// Evaluate predicate node `node` against record `rec` (explicit opcode
/// dispatch; out-of-range nodes and records evaluate false).
pub fn cl_pred_eval(p: &CloudPred, l: &CloudLog, rec: Int, node: Int) -> Bool {
  if node < 0 || node >= p.op.len() {
    return false;
  }
  if rec < 0 || rec >= l.time.len() {
    return false;
  }
  let op: Int = p.op[node];
  if op == _CL_PRED_TRUE {
    return true;
  }
  if op == _CL_PRED_FALSE {
    return false;
  }
  if op == _CL_PRED_AND {
    let a: Int = p.left[node];
    let b: Int = p.right[node];
    return cl_pred_eval(p, l, rec, a) && cl_pred_eval(p, l, rec, b);
  }
  if op == _CL_PRED_OR {
    let a: Int = p.left[node];
    let b: Int = p.right[node];
    return cl_pred_eval(p, l, rec, a) || cl_pred_eval(p, l, rec, b);
  }
  if op == _CL_PRED_NOT {
    let a: Int = p.left[node];
    return !cl_pred_eval(p, l, rec, a);
  }
  if op == _CL_PRED_LEVEL {
    if rec >= l.level.len() {
      return false;
    }
    let have: Int = l.level[rec];
    let want: Int = p.num[node];
    return have == want;
  }
  if op == _CL_PRED_SEV_GE {
    if rec >= l.sev.len() {
      return false;
    }
    let have: Int = l.sev[rec];
    let want: Int = p.num[node];
    return have >= want;
  }
  if op == _CL_PRED_MSG {
    if rec >= l.msg.len() {
      return false;
    }
    let have: Str = l.msg[rec];
    let needle: Str = p.text[node];
    return cl_text_contains(have, needle);
  }
  if op == _CL_PRED_KEY {
    let key: Str = p.text[node];
    let val: Str = p.text2[node];
    return _cl_log_key_match(l, rec, key, val);
  }
  if op == _CL_PRED_TIME {
    let lo: Int = p.num[node];
    let hi: Int = p.num2[node];
    let t: Int = l.time[rec];
    return t >= lo && t <= hi;
  }
  return false;
}

/// Count records in the inclusive time range that satisfy the predicate root
/// (the last node pushed into `p`).
pub fn cl_search_count(l: &CloudLog, p: &CloudPred, from_time: Int, to_time: Int) -> Int {
  if from_time > to_time {
    return 0;
  }
  let root = p.op.len() - 1;
  let n = l.time.len();
  var hits = 0;
  var i = 0;
  while i < n {
    let t: Int = l.time[i];
    if t >= from_time && t <= to_time {
      if cl_pred_eval(p, l, i, root) {
        hits = hits + 1;
      }
    }
    i = i + 1;
  }
  return hits;
}

/// Deterministic paginated search. Records are scanned in index order;
/// `start` is the 0-based ordinal of the first wanted match (clamped at 0)
/// and `limit` the page size. Returns the matching record indices, the page
/// count, `matched_total` over the whole range, the number of records
/// scanned, and `next_start` (-1 when no further match exists; when limit
/// <= 0 the page is empty and `next_start` is `start` while matches remain).
pub fn cl_search(l: &CloudLog, p: &CloudPred, from_time: Int, to_time: Int, start: Int, limit: Int) -> CloudPage {
  var page = CloudPage{
    hits: Vec[Int].new();
    count: 0;
    next_start: -1;
    matched_total: 0;
    scanned: l.time.len();
  };
  if from_time > to_time {
    return page;
  }
  var s = start;
  if s < 0 {
    s = 0;
  }
  let root = p.op.len() - 1;
  let n = l.time.len();
  var ordinal = 0;
  var i = 0;
  while i < n {
    let t: Int = l.time[i];
    var hit = false;
    if t >= from_time && t <= to_time {
      hit = cl_pred_eval(p, l, i, root);
    }
    if hit {
      page.matched_total = page.matched_total + 1;
      if limit > 0 && ordinal >= s && page.count < limit {
        page.hits.push(i);
        page.count = page.count + 1;
      }
      ordinal = ordinal + 1;
    }
    i = i + 1;
  }
  if limit > 0 && s + page.count < page.matched_total {
    page.next_start = s + page.count;
  } elif limit <= 0 && page.matched_total > s {
    page.next_start = s;
  } else {
    page.next_start = -1;
  }
  return page;
}
