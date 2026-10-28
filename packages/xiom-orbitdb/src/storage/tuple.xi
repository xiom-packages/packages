// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.storage.tuple

use xiom.convert;
use xiom.string;

// Local error type for tuple encoding -- mirrors xiom.db.error.DbError.
enum DbError {
  NotFound,
  DuplicateKey,
  ConstraintViolation,
  SchemaMismatch,
  StorageError,
  Corruption,
}

pub type DbResult[T] = Result[T, DbError];

// Row / tuple representation and the columnar `ResultSet` container. A `Row` is
// an integer-valued record addressed by a monotonic id. The codec is
// byte-packed v1 (all buffer elements are byte values 0..255):
//
//   0: magic 0xDB    1: version 0x01    2: field_count (1..255)
//   then field_count fields, each: type 0x01 (i64) + 8 bytes little-endian
//   (field 0 is the row id, fields 1.. are the columns)
//
// Minimum encoded size is 12 bytes. The buffer stays `Vec[Int]` until the
// stdlib byte-IO / Vec[UInt8] conversion gap closes (STDLIB-WISHLIST row 5);
// it is byte-true today so CRC32C and on-disk page budgets apply directly.

pub type Row = {
  id: Int;
  data: Vec[Int];
}

pub fn Row.new(id: Int, data: Vec[Int]) -> Row {
  return Row{ id: id, data: data };
}

pub fn Row.get_column(row: &Row, index: Int) -> Option[Int] {
  if index < 0 { return None; }
  if index >= row.data.len() { return None; }
  return Some(row.data[index]);
}

pub fn Row.set_column(row: &mut Row, index: Int, value: Int) -> Bool {
  if index < 0 { return false; }
  if index >= row.data.len() { return false; }
  row.data[index] = value;
  return true;
}

pub fn Row.column_count(row: &Row) -> Int {
  return row.data.len();
}

// --- Tuple codec v1 (byte-packed) ---

pub const TUPLE_MAGIC: Int = 0xDB;
pub const TUPLE_VERSION: Int = 1;
pub const TUPLE_MAX_FIELDS: Int = 255;

// Exported for the snapshot node-page codec in the engine (one LE layout for
// every on-disk codec); keep the byte order in lockstep with TUPLE_VERSION.
pub fn tuple_push_int_le(out: &mut Vec[Int], v: Int) {
  var k = 0;
  while k < 8 {
    out.push((v >> (8 * k)) & 0xFF);
    k = k + 1;
  }
}

// Reconstruct an i64 from 8 little-endian bytes without ever leaving the
// signed 64-bit range (top byte first, seven magnitude bits before the low
// seven bytes; sign applied last). Exported with `tuple_push_int_le`.
pub fn tuple_read_int_le(buf: &Vec[Int], at: Int) -> Int {
  let top = buf[at + 7] & 0xFF;
  let sign = (top & 0x80) == 0x80;
  var v = top & 0x7F;
  var k = 6;
  while k >= 0 {
    v = (v << 8) | (buf[at + k] & 0xFF);
    k = k - 1;
  }
  if sign {
    return -(9223372036854775807 - v) - 1;
  }
  return v;
}

pub fn tuple_encoded_len(row: &Row) -> Int {
  return 3 + 9 * (row.data.len() + 1);
}

// True when the row's v1 encoding fits the given page payload budget.
pub fn tuple_fits_page(row: &Row, page_size: Int) -> Bool {
  if page_size < 0 { return false; }
  return tuple_encoded_len(row) <= page_size;
}

// Direct byte builder: caller must have validated the field count. Each
// field emits a type byte (0x01 = i64) followed by 8 little-endian bytes.
fn tuple_encode_bytes(row: &Row) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(TUPLE_MAGIC);
  out.push(TUPLE_VERSION);
  out.push(row.data.len() + 1);
  out.push(0x01);
  tuple_push_int_le(&mut out, row.id);
  var i = 0;
  while i < row.data.len() {
    out.push(0x01);
    tuple_push_int_le(&mut out, row.data[i]);
    i = i + 1;
  }
  return out;
}

// Checked encode: Err(ConstraintViolation) when the row exceeds 255 fields
// (a v1 field_count byte cannot represent it).
pub fn tuple_encode_checked(row: &Row) -> DbResult[Vec[Int]] {
  if row.data.len() + 1 > TUPLE_MAX_FIELDS {
    return Err(DbError.ConstraintViolation);
  }
  return Ok(tuple_encode_bytes(row));
}

// Convenience encode for callers that cannot fail. Returns an EMPTY buffer
// when the row is not encodable (empty is never a valid v1 record: minimum
// size 12); use `tuple_encode_checked` to distinguish the reason. Kept for
// signature compatibility with the C-ORBIT-01 repro bundles.
pub fn tuple_encode(row: &Row) -> Vec[Int] {
  if row.data.len() + 1 > TUPLE_MAX_FIELDS {
    var empty = Vec[Int].new();
    return empty;
  }
  return tuple_encode_bytes(row);
}

// Decode a v1 buffer produced by `tuple_encode_checked`. Validates magic,
// version, field count, exact length and every field type; any violation is
// Err(Corruption) -- no partial rows.
pub fn tuple_decode(buf: &Vec[Int]) -> DbResult[Row] {
  if buf.len() < 12 {
    return Err(DbError.Corruption);
  }
  if buf[0] != TUPLE_MAGIC {
    return Err(DbError.Corruption);
  }
  if buf[1] != TUPLE_VERSION {
    return Err(DbError.Corruption);
  }
  let count = buf[2];
  if count < 1 {
    return Err(DbError.Corruption);
  }
  if buf.len() != 3 + 9 * count {
    return Err(DbError.Corruption);
  }

  var at = 3;
  var i = 0;
  while i < count {
    if buf[at] != 0x01 {
      return Err(DbError.Corruption);
    }
    at = at + 9;
    i = i + 1;
  }

  let id = tuple_read_int_le(buf, 4);
  var data = Vec[Int].new();
  var j = 1;
  while j < count {
    data.push(tuple_read_int_le(buf, 4 + 9 * j));
    j = j + 1;
  }
  return Ok(Row{ id: id, data: data });
}

// --- Tuple codec v2 (typed values, M5.1) ----------------------------------
//
// Same container magic; version 2 makes every field a TYPE-TAGGED value:
//
//   0: magic 0xDB    1: version 0x02    2: field_count (1..255)
//   then field_count tagged values; field 0 MUST be VInt (the row id).
//
//   tag 0x00 VNull   -- no payload
//   tag 0x01 VInt    -- 8 bytes little-endian
//   tag 0x02 VFloat  -- 8 bytes IEEE-754 double, little-endian
//   tag 0x03 VText   -- u32 LE byte length + UTF-8 bytes (byte-exact)
//   tag 0x04 VBlob   -- u32 LE byte length + raw bytes (0..255)
//
// Strict decode: every buffer element must be a byte (0..255) for the whole
// row, exact length (no trailing bytes), field 0 must decode as VInt, each
// tagged payload must lie inside the buffer and respect the u32 length
// fields. v1 buffers do not decode here and v2 buffers do not decode in
// `tuple_decode` -- the version byte is the discriminator (migration notes
// in docs/FORMATS.md). The v1 codec stays frozen; new on-disk rows use v2
// (the engine integration is the following M5 slice).

pub const TUPLE_VERSION_V2: Int = 2;
pub const TUPLE2_TAG_NULL: Int = 0x00;
pub const TUPLE2_TAG_INT: Int = 0x01;
pub const TUPLE2_TAG_FLOAT: Int = 0x02;
pub const TUPLE2_TAG_TEXT: Int = 0x03;
pub const TUPLE2_TAG_BLOB: Int = 0x04;
// One text/blob length field is u32; longer values are not representable.
pub const TUPLE2_MAX_VALUE_BYTES: Int = 4294967295;

// The M5 value model: null, int64, f64, UTF-8 text, raw bytes. Variant names
// are V-prefixed so composed programs stay unambiguous (C-ORBIT-07 hygiene);
// consumer modules still module-qualify their patterns (m225 caveat).
pub type TValue = enum {
  VNull,
  VInt(v: Int),
  VFloat(f: Float64),
  VText(s: Str),
  VBlob(b: Vec[Int]),
}

// A v2 row: id plus typed column values (on disk field 0 is the id's VInt).
pub type TypedRow = {
  id: Int;
  values: Vec[TValue];
}

fn tuple2_push_u32_le(out: &mut Vec[Int], v: Int) {
  out.push(v & 0xFF);
  out.push((v >> 8) & 0xFF);
  out.push((v >> 16) & 0xFF);
  out.push((v >> 24) & 0xFF);
}

// Composed multiplicatively so no bitwise/additive precedence is involved.
fn tuple2_read_u32_le(buf: &Vec[Int], at: Int) -> Int {
  var v = 0;
  var k = 3;
  while k >= 0 {
    v = v * 256 + (buf[at + k] & 0xFF);
    k = k - 1;
  }
  return v;
}

// Whole-body unsafe (pointer bit-cast, mirroring xiom.serialize.endian):
// T007 requires a pre-entry contract on the confinement unit.
fn tuple2_push_f64_le(out: &mut Vec[Int], f: Float64)
  requires: true
{
  unsafe {
    var b: [8]UInt8;
    let fp: *mut Float64 = &b[0] as *mut Float64;
    *fp = f;
    var i = 0;
    while i < 8 {
      // Direct fixed-array UInt8->Int cast: zero-extension verified on
      // v0.64.5 (m260; repro docs/repro/enum-tuple-codegen PART B, 248 x2
      // platforms). The old `& 0xFF` workaround is retired.
      out.push(b[i] as Int);
      i = i + 1;
    }
  }
}

fn tuple2_read_f64_le(buf: &Vec[Int], at: Int) -> Float64
  requires: true
{
  unsafe {
    var b: [8]UInt8;
    var i = 0;
    while i < 8 {
      b[i] = (buf[at + i] & 0xFF) as UInt8;
      i = i + 1;
    }
    let fp: *const Float64 = &b[0] as *const Float64;
    return *fp;
  }
}

// Strict byte convention: every element of [from, to) is 0..255.
fn tuple2_bytes_valid(buf: &Vec[Int], from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if buf[i] < 0 { return false; }
    if buf[i] > 255 { return false; }
    i = i + 1;
  }
  return true;
}

// UTF-8 bytes [at, at+n) -> Str (byte-exact; the stdlib builds the Str).
fn tuple2_text_from_bytes(buf: &Vec[Int], at: Int, n: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < n {
    bytes.push((buf[at + i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// Encoded byte length of one value (tag + payload).
pub fn tuple2_value_len(v: TValue) -> Int {
  match v {
    VNull => { return 1; }
    VInt(_) => { return 9; }
    VFloat(_) => { return 9; }
    VText(s) => { return 5 + s.len(); }
    VBlob(b) => { return 5 + b.len(); }
  }
}

// Append one tagged value. Callers must have validated it (see
// `tuple2_encode_row_checked`); blob elements are masked to bytes here.
fn tuple2_push_value(out: &mut Vec[Int], v: TValue) {
  match v {
    VNull => { out.push(TUPLE2_TAG_NULL); }
    VInt(x) => {
      out.push(TUPLE2_TAG_INT);
      tuple_push_int_le(out, x);
    }
    VFloat(f) => {
      out.push(TUPLE2_TAG_FLOAT);
      tuple2_push_f64_le(out, f);
    }
    VText(s) => {
      out.push(TUPLE2_TAG_TEXT);
      tuple2_push_u32_le(out, s.len());
      var i = 0;
      while i < s.len() {
        out.push(string.byte_at(s, i) as Int);
        i = i + 1;
      }
    }
    VBlob(b) => {
      out.push(TUPLE2_TAG_BLOB);
      tuple2_push_u32_le(out, b.len());
      var i = 0;
      while i < b.len() {
        out.push(b[i] & 0xFF);
        i = i + 1;
      }
    }
  }
}

// Decode one tagged value at `at`. Returns the value AND the next offset
// (the natural `(TValue, Int)` position tuple), so callers advance by the
// returned position instead of re-deriving the length.
//
// C-ORBIT-12 WORKAROUND RETIRED (v0.64.8, 2026-10-19): `c6b3362ef`
// registers unresolved tuple names on demand; the natural position tuple
// now compiles in this module-qualified context. Acceptance: the split
// suite (163/163) x2 both platforms on the v0.64.8 archive; item
// REL-20261017-1154-orbitdb verified + closed at this adoption.
pub fn tuple2_read_value(buf: &Vec[Int], at: Int) -> DbResult[(TValue, Int)] {
  if at < 0 { return Err(DbError.Corruption); }
  if at >= buf.len() { return Err(DbError.Corruption); }
  let tag = buf[at] & 0xFF;
  if tag == TUPLE2_TAG_NULL {
    return Ok((TValue.VNull, at + 1));
  }
  if tag == TUPLE2_TAG_INT {
    if at + 9 > buf.len() { return Err(DbError.Corruption); }
    let x = tuple_read_int_le(buf, at + 1);
    return Ok((TValue.VInt(x), at + 9));
  }
  if tag == TUPLE2_TAG_FLOAT {
    if at + 9 > buf.len() { return Err(DbError.Corruption); }
    let f = tuple2_read_f64_le(buf, at + 1);
    return Ok((TValue.VFloat(f), at + 9));
  }
  if tag == TUPLE2_TAG_TEXT {
    if at + 5 > buf.len() { return Err(DbError.Corruption); }
    let n = tuple2_read_u32_le(buf, at + 1);
    if at + 5 + n > buf.len() { return Err(DbError.Corruption); }
    let s = tuple2_text_from_bytes(buf, at + 5, n);
    return Ok((TValue.VText(s), at + 5 + n));
  }
  if tag == TUPLE2_TAG_BLOB {
    if at + 5 > buf.len() { return Err(DbError.Corruption); }
    let n = tuple2_read_u32_le(buf, at + 1);
    if at + 5 + n > buf.len() { return Err(DbError.Corruption); }
    var b = Vec[Int].new();
    var i = 0;
    while i < n {
      b.push(buf[at + 5 + i] & 0xFF);
      i = i + 1;
    }
    return Ok((TValue.VBlob(b), at + 5 + n));
  }
  return Err(DbError.Corruption);
}

// Encoded length of a v2 row: 3 container bytes + the id's VInt + values.
pub fn tuple2_encoded_len(values: &Vec[TValue]) -> Int {
  var n = 3 + 9;
  var i = 0;
  while i < values.len() {
    n = n + tuple2_value_len(values[i]);
    i = i + 1;
  }
  return n;
}

// True when the row's v2 encoding fits the given page payload budget.
pub fn tuple2_fits_page(values: &Vec[TValue], page_size: Int) -> Bool {
  if page_size < 0 { return false; }
  return tuple2_encoded_len(values) <= page_size;
}

pub fn tuple2_kind(v: TValue) -> Int {
  match v {
    VNull => { return TUPLE2_TAG_NULL; }
    VInt(_) => { return TUPLE2_TAG_INT; }
    VFloat(_) => { return TUPLE2_TAG_FLOAT; }
    VText(_) => { return TUPLE2_TAG_TEXT; }
    VBlob(_) => { return TUPLE2_TAG_BLOB; }
  }
}

pub fn tuple2_is_null(v: TValue) -> Bool {
  match v {
    VNull => { return true; }
    _ => { return false; }
  }
}

pub fn tuple2_int_value(v: TValue) -> Option[Int] {
  match v {
    VInt(x) => { return Some(x); }
    _ => { return None; }
  }
}

pub fn tuple2_float_value(v: TValue) -> Option[Float64] {
  match v {
    VFloat(f) => { return Some(f); }
    _ => { return None; }
  }
}

pub fn tuple2_text_value(v: TValue) -> Option[Str] {
  match v {
    VText(s) => { return Some(s); }
    _ => { return None; }
  }
}

pub fn tuple2_blob_value(v: TValue) -> Option[Vec[Int]] {
  match v {
    VBlob(b) => { return Some(b); }
    _ => { return None; }
  }
}

// --- Typed comparisons (M5-S4) --------------------------------------------
//
// Total order over TValue, used by typed query predicates:
//   Null < numeric (Int/Float, compared numerically) < Text < Blob.
// Int vs float compares numerically via Float64 (lossy beyond 2^53 -- the
// documented approximation); int vs int is exact; floats are natural with
// NaN first (NaN == NaN); text is bytewise lexicographic (UTF-8 bytes);
// blob is element-wise 0..255. `tuple2_compare` == 0 IS equality (so
// VInt(1) equals VFloat(1.0)). No SQL three-valued logic: every condition
// evaluates to true/false against this order.

// 0 null, 1 numeric, 2 text, 3 blob.
fn tuple2_kind_rank(v: TValue) -> Int {
  match v {
    VNull => { return 0; }
    VInt(_) => { return 1; }
    VFloat(_) => { return 1; }
    VText(_) => { return 2; }
    VBlob(_) => { return 3; }
  }
}

fn tuple2_f64_cmp(a: Float64, b: Float64) -> Int {
  if a != a {
    if b != b { return 0; }
    return -1;
  }
  if b != b { return 1; }
  if a < b { return -1; }
  if a > b { return 1; }
  return 0;
}

fn tuple2_text_cmp(a: Str, b: Str) -> Int {
  let la = a.len();
  let lb = b.len();
  var i = 0;
  while i < la && i < lb {
    let ba = string.byte_at(a, i);
    let bb = string.byte_at(b, i);
    if ba < bb { return -1; }
    if ba > bb { return 1; }
    i = i + 1;
  }
  if la < lb { return -1; }
  if la > lb { return 1; }
  return 0;
}

fn tuple2_blob_cmp(a: &Vec[Int], b: &Vec[Int]) -> Int {
  var i = 0;
  while i < a.len() && i < b.len() {
    if a[i] < b[i] { return -1; }
    if a[i] > b[i] { return 1; }
    i = i + 1;
  }
  if a.len() < b.len() { return -1; }
  if a.len() > b.len() { return 1; }
  return 0;
}

pub fn tuple2_compare(a: TValue, b: TValue) -> Int {
  let ra = tuple2_kind_rank(a);
  let rb = tuple2_kind_rank(b);
  if ra != rb {
    if ra < rb { return -1; }
    return 1;
  }
  if ra == 0 { return 0; }
  if ra == 1 {
    let ka = tuple2_kind(a);
    let kb = tuple2_kind(b);
    if ka == 0x01 && kb == 0x01 {
      match tuple2_int_value(a) {
        None => { return 0; }
        Some(ia) => {
          match tuple2_int_value(b) {
            None => { return 0; }
            Some(ib) => {
              if ia < ib { return -1; }
              if ia > ib { return 1; }
              return 0;
            }
          }
        }
      }
    }
    // At least one float: numeric compare through Float64.
    var fa = 0.0;
    var fb = 0.0;
    match tuple2_float_value(a) {
      Some(x) => { fa = x; }
      None => {
        match tuple2_int_value(a) {
          Some(n) => { fa = convert.int_to_float(n); }
          None => {}
        }
      }
    }
    match tuple2_float_value(b) {
      Some(x) => { fb = x; }
      None => {
        match tuple2_int_value(b) {
          Some(n) => { fb = convert.int_to_float(n); }
          None => {}
        }
      }
    }
    return tuple2_f64_cmp(fa, fb);
  }
  if ra == 2 {
    match tuple2_text_value(a) {
      None => { return 0; }
      Some(sa) => {
        match tuple2_text_value(b) {
          None => { return 0; }
          Some(sb) => { return tuple2_text_cmp(sa, sb); }
        }
      }
    }
  }
  match tuple2_blob_value(a) {
    None => { return 0; }
    Some(ba) => {
      match tuple2_blob_value(b) {
        None => { return 0; }
        Some(bb) => { return tuple2_blob_cmp(&ba, &bb); }
      }
    }
  }
}

// Checked encode: the row must be representable -- field count <= 255, text
// and blob lengths within u32, blob elements 0..255. The id is field 0 and
// is always VInt on disk.
pub fn tuple2_encode_row_checked(id: Int, values: &Vec[TValue]) -> DbResult[Vec[Int]] {
  if values.len() + 1 > TUPLE_MAX_FIELDS {
    return Err(DbError.ConstraintViolation);
  }
  var i = 0;
  while i < values.len() {
    let v = values[i];
    match v {
      VNull => {}
      VInt(_) => {}
      VFloat(_) => {}
      VText(s) => {
        if s.len() > TUPLE2_MAX_VALUE_BYTES { return Err(DbError.ConstraintViolation); }
      }
      VBlob(b) => {
        if b.len() > TUPLE2_MAX_VALUE_BYTES { return Err(DbError.ConstraintViolation); }
        var k = 0;
        while k < b.len() {
          if b[k] < 0 { return Err(DbError.ConstraintViolation); }
          if b[k] > 255 { return Err(DbError.ConstraintViolation); }
          k = k + 1;
        }
      }
    }
    i = i + 1;
  }
  var out = Vec[Int].new();
  out.push(TUPLE_MAGIC);
  out.push(TUPLE_VERSION_V2);
  out.push(values.len() + 1);
  tuple2_push_value(&mut out, TValue.VInt(id));
  i = 0;
  while i < values.len() {
    tuple2_push_value(&mut out, values[i]);
    i = i + 1;
  }
  return Ok(out);
}

// Strict decode of a v2 buffer produced by `tuple2_encode_row_checked`.
pub fn tuple2_decode_row(buf: &Vec[Int]) -> DbResult[TypedRow] {
  if buf.len() < 12 { return Err(DbError.Corruption); }
  if buf[0] != TUPLE_MAGIC { return Err(DbError.Corruption); }
  if buf[1] != TUPLE_VERSION_V2 { return Err(DbError.Corruption); }
  let count = buf[2];
  if count < 1 { return Err(DbError.Corruption); }
  if !tuple2_bytes_valid(buf, 0, buf.len()) { return Err(DbError.Corruption); }

  match tuple2_read_value(buf, 3) {
    Err(e) => { return Err(e); }
    Ok(idv) => {
      match tuple2_int_value(idv.0) {
        None => { return Err(DbError.Corruption); }
        Some(id) => {
          var values = Vec[TValue].new();
          var at = idv.1;
          var j = 1;
          while j < count {
            match tuple2_read_value(buf, at) {
              Err(e2) => { return Err(e2); }
              Ok(v) => {
                values.push(v.0);
                at = v.1;
              }
            }
            j = j + 1;
          }
          if at != buf.len() { return Err(DbError.Corruption); }
          return Ok(TypedRow{ id: id, values: values });
        }
      }
    }
  }
}

pub type ResultSet = {
  columns: Vec[Str];
  rows: Vec[Row];
}

pub fn ResultSet.new(columns: Vec[Str]) -> ResultSet {
  var rows = Vec[Row].new();
  return ResultSet{ columns: columns, rows: rows };
}

pub fn ResultSet.add_row(rs: &mut ResultSet, row: Row) {
  rs.rows.push(row);
}

pub fn ResultSet.row_count(rs: &ResultSet) -> Int {
  return rs.rows.len();
}

pub fn ResultSet.column_count(rs: &ResultSet) -> Int {
  return rs.columns.len();
}

pub fn ResultSet.get_row(rs: &ResultSet, index: Int) -> Option[Row] {
  if index < 0 { return None; }
  if index >= rs.rows.len() { return None; }
  var r = rs.rows[index];
  return Some(r);
}
