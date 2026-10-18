// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.payload.payload

// Payload metadata for a point: a schemaless list of typed fields, its WAL
// codec (durable metadata), and the id -> Payload store. Extracted from the
// consolidated engine (first layer of the post-AUDIT module tree).

use xiom.num.float;
use xiom.string.slice;

// Tagged scalar carried by a payload field.
pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = {
  key: Str;
  value: FieldValue;
}

pub type Payload = {
  fields: Vec[PayloadField];
}

pub fn payload_new() -> Payload {
  var fields = Vec[PayloadField].new();
  return Payload{ fields: fields };
}

// Set or OVERWRITE a field (linear scan; a sorted key index is a later
// Phase 3 deliverable).
pub fn payload_set(p: &mut Payload, key: Str, value: FieldValue) {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      p.fields[i].value = value;
      return;
    }
    i = i + 1;
  }
  p.fields.push(PayloadField{ key: key, value: value });
}

pub fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return true; }
    i = i + 1;
  }
  return false;
}

pub fn payload_get(p: &Payload, key: Str) -> Option[FieldValue] {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return Some(p.fields[i].value); }
    i = i + 1;
  }
  return None;
}

pub fn payload_len(p: &Payload) -> Int {
  return p.fields.len();
}

pub fn field_value_kind(v: &FieldValue) -> Str {
  match v {
    IntVal(_) => "int",
    FloatVal(_) => "float",
    TextVal(_) => "text",
    BoolVal(_) => "bool",
  }
}

// Exact equality within one type; cross-type comparisons are false.
pub fn field_value_eq(a: &FieldValue, b: &FieldValue) -> Bool {
  match a {
    IntVal(av) => {
      match b { IntVal(bv) => { return av == bv; } _ => { return false; } }
    }
    FloatVal(av) => {
      match b { FloatVal(bv) => { return av == bv; } _ => { return false; } }
    }
    TextVal(av) => {
      match b { TextVal(bv) => { return av == bv; } _ => { return false; } }
    }
    BoolVal(av) => {
      match b { BoolVal(bv) => { return av == bv; } _ => { return false; } }
    }
  }
}

// Numeric view for Range: Int promotes to Float32, non-numeric -> None.
pub fn field_value_as_float(v: &FieldValue) -> Option[Float32] {
  match v {
    FloatVal(f) => { return Some(f); }
    IntVal(i) => { return Some(i as Float32); }
    _ => { return None; }
  }
}

// ---- Payload WAL codec (durable metadata) ----
// Word layout: [version=1, field_count,
//   (key_len, key_bytes...), kind, value_words...
// kind 1=int (v), 2=float (f64 bit pattern of the f32), 3=text (len, bytes),
// 4=bool (0|1)]. Decode is strict; malformed -> None (torn-record tolerance).
fn push_str_words(out: &mut Vec[Int], s: Str) {
  var bytes = slice.str_bytes(s);
  out.push(bytes.len());
  var i: Int = 0;
  while i < bytes.len() {
    out.push(bytes[i] as Int);
    i = i + 1;
  }
}

pub fn payload_encode(p: &Payload) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(1);
  out.push(p.fields.len());
  var i: Int = 0;
  while i < p.fields.len() {
    push_str_words(&mut out, p.fields[i].key);
    var fv = p.fields[i].value;
    match fv {
      IntVal(v) => { out.push(1); out.push(v); }
      FloatVal(f) => { out.push(2); out.push(float.float_bits(f as Float64)); }
      TextVal(t) => { out.push(3); push_str_words(&mut out, t); }
      BoolVal(b) => {
        out.push(4);
        if b { out.push(1); } else { out.push(0); }
      }
    }
    i = i + 1;
  }
  return out;
}

pub fn payload_decode(words: &Vec[Int]) -> Option[Payload] {
  if words.len() < 2 { return None; }
  if words[0] != 1 { return None; }
  var count = words[1];
  if count < 0 { return None; }
  var out = payload_new();
  var pos: Int = 2;
  var i: Int = 0;
  while i < count {
    if pos >= words.len() { return None; }
    var klen = words[pos];
    pos = pos + 1;
    if klen < 0 || pos + klen > words.len() { return None; }
    var kb = Vec[UInt8].new();
    var j: Int = 0;
    while j < klen {
      kb.push(words[pos + j] as UInt8);
      j = j + 1;
    }
    pos = pos + klen;
    var key = Str::from_utf8(&kb);
    if pos >= words.len() { return None; }
    var kind = words[pos];
    pos = pos + 1;
    if kind == 1 {
      if pos >= words.len() { return None; }
      var iv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.IntVal(iv));
    } elif kind == 2 {
      if pos >= words.len() { return None; }
      var bits = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.FloatVal(float.bits_to_float(bits) as Float32));
    } elif kind == 3 {
      if pos >= words.len() { return None; }
      var tlen = words[pos];
      pos = pos + 1;
      if tlen < 0 || pos + tlen > words.len() { return None; }
      var tb = Vec[UInt8].new();
      var k: Int = 0;
      while k < tlen {
        tb.push(words[pos + k] as UInt8);
        k = k + 1;
      }
      pos = pos + tlen;
      payload_set(&mut out, key, FieldValue.TextVal(Str::from_utf8(&tb)));
    } elif kind == 4 {
      if pos >= words.len() { return None; }
      var bv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.BoolVal(bv != 0));
    } else {
      return None;
    }
    i = i + 1;
  }
  return Some(out);
}

// ---- Payload store: point id -> Payload (linear scan, swap-remove) ----
// Plus a sorted key index over the stored fields (Phase 3 refinement): rows
// are kept sorted by (field, kind, num, text, id) in PARALLEL vectors --
// deliberately not a Vec[Struct] (the nested-Vec heap shape dodges the
// AUDIT T001 family; the XVC-C-08 trailing-field misread is fixed in
// compiler v0.64.2).
// Lookups: exists/count/Eq use binary search (Eq scans the field window for
// float values, where IEEE +-0.0 / NaN need semantic comparison); Range
// scans the field's numeric rows.
pub type PayloadEntry = {
  id: Int;
  payload: Payload;
}

pub type PayloadStore = {
  entries: Vec[PayloadEntry];
  index_field: Vec[Str];
  index_kind: Vec[Int];
  index_num: Vec[Int];
  index_text: Vec[Str];
  index_id: Vec[Int];
}

pub fn payload_store_new() -> PayloadStore {
  var entries = Vec[PayloadEntry].new();
  var index_field = Vec[Str].new();
  var index_kind = Vec[Int].new();
  var index_num = Vec[Int].new();
  var index_text = Vec[Str].new();
  var index_id = Vec[Int].new();
  return PayloadStore{
    entries: entries,
    index_field: index_field,
    index_kind: index_kind,
    index_num: index_num,
    index_text: index_text,
    index_id: index_id,
  };
}

// Insert or replace the payload for `id` (index rows follow the payload).
pub fn payload_store_put(s: &mut PayloadStore, id: Int, payload: Payload) {
  payload_index_remove_ids(s, id);
  var f: Int = 0;
  while f < payload.fields.len() {
    var fv = payload.fields[f].value;
    var fk = payload.fields[f].key;
    payload_index_insert(s, fk, field_index_kind(&fv), field_index_num(&fv), field_index_text(&fv), id);
    f = f + 1;
  }
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      s.entries[i].payload = payload;
      return;
    }
    i = i + 1;
  }
  s.entries.push(PayloadEntry{ id: id, payload: payload });
}

pub fn payload_store_get(s: &PayloadStore, id: Int) -> Option[Payload] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

pub fn payload_store_remove(s: &mut PayloadStore, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { pos = i; }
    i = i + 1;
  }
  if pos == -1 { return false; }
  payload_index_remove_ids(s, id);
  var last: Int = s.entries.len() - 1;
  s.entries[pos] = s.entries[last];
  s.entries.pop();
  return true;
}

pub fn payload_store_len(s: &PayloadStore) -> Int {
  return s.entries.len();
}

// Memory accounting estimate (model constants: see the
// `hnsw_memory_estimate` header). Per entry: PayloadEntry = id (8 B) +
// Payload header (24 B) + fields heap; PayloadField = Str header (24 B) +
// enum slot (32 B) + key bytes + value heap (TextVal: + len B; the
// numeric/bool variants are inline). Index arrays count one slot per row
// (Str rows = 24 B header; their bytes are either aliased with the
// payload text or bounded by it, so they are not double-counted).
pub fn payload_store_memory_estimate(s: &PayloadStore) -> Int
  ensures: result >= 0
{
  var bytes: Int = 24; // entries Vec header
  var i: Int = 0;
  while i < s.entries.len() {
    var p = s.entries[i].payload;
    bytes = bytes + 8 + 24 + 24; // entry + Payload header + fields vec header
    var f: Int = 0;
    while f < p.fields.len() {
      var k = p.fields[f].key;
      bytes = bytes + 56 + k.len();
      var fv = p.fields[f].value;
      match fv {
        TextVal(t) => { bytes = bytes + t.len(); }
        _ => {}
      }
      f = f + 1;
    }
    i = i + 1;
  }
  bytes = bytes + (24 + s.index_field.len() * 24); // field names (Str slots)
  bytes = bytes + (24 + s.index_kind.len() * 8);
  bytes = bytes + (24 + s.index_num.len() * 8);
  bytes = bytes + (24 + s.index_text.len() * 24);
  bytes = bytes + (24 + s.index_id.len() * 8);
  return bytes;
}

// ============================================================================
// Sorted key index (Phase 3 refinement)
// ============================================================================
// Row semantics: kind 1 = int, 2 = float (num = Float64 bits of the Float32),
// 3 = text (text = value bytes), 4 = bool (num = 0|1). Rows are unique per
// (id, field); a payload overwrite or a remove deletes that id's rows first.

fn field_index_kind(v: &FieldValue) -> Int {
  match v {
    IntVal(_) => { return 1; }
    FloatVal(_) => { return 2; }
    TextVal(_) => { return 3; }
    BoolVal(_) => { return 4; }
  }
}

fn field_index_num(v: &FieldValue) -> Int {
  match v {
    IntVal(x) => { return x; }
    FloatVal(f) => { return float.float_bits(f as Float64); }
    BoolVal(b) => { if b { return 1; } else { return 0; } }
    TextVal(_) => { return 0; }
  }
}

fn field_index_text(v: &FieldValue) -> Str {
  match v {
    TextVal(t) => { return t; }
    _ => { return ""; }
  }
}

// Lexicographic byte order for field names / text values (no Str `<` in the
// language; bytes come from slice.str_bytes).
fn str_less(a: Str, b: Str) -> Bool {
  var ab = slice.str_bytes(a);
  var bb = slice.str_bytes(b);
  var n: Int = ab.len();
  if bb.len() < n { n = bb.len(); }
  var i: Int = 0;
  while i < n {
    if ab[i] != bb[i] { return (ab[i] as Int) < (bb[i] as Int); }
    i = i + 1;
  }
  return ab.len() < bb.len();
}

// First row with index_field >= field.
fn payload_index_field_start(s: &PayloadStore, field: Str) -> Int {
  var lo: Int = 0;
  var hi: Int = s.index_id.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if str_less(s.index_field[mid], field) { lo = mid + 1; } else { hi = mid; }
  }
  return lo;
}

// row(mid) tuple (field, kind, num, text) < query tuple?
fn payload_index_tuple_before(s: &PayloadStore, mid: Int, field: Str, kind: Int, num: Int, text: Str) -> Bool {
  var rf = s.index_field[mid];
  if rf == field {
    var rk = s.index_kind[mid];
    if rk == kind {
      var rn = s.index_num[mid];
      if rn == num {
        var rt = s.index_text[mid];
        if rt == text { return false; }
        return str_less(rt, text);
      }
      return rn < num;
    }
    return rk < kind;
  }
  return str_less(rf, field);
}

// First row at or after the exact (field, kind, num, text) tuple.
fn payload_index_tuple_start(s: &PayloadStore, field: Str, kind: Int, num: Int, text: Str) -> Int {
  var lo: Int = 0;
  var hi: Int = s.index_id.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if payload_index_tuple_before(s, mid, field, kind, num, text) { lo = mid + 1; } else { hi = mid; }
  }
  return lo;
}

// row(mid) < (field, kind, num, text, id)?
fn payload_index_row_before(s: &PayloadStore, mid: Int, field: Str, kind: Int, num: Int, text: Str, id: Int) -> Bool {
  var rf = s.index_field[mid];
  if rf == field {
    var rk = s.index_kind[mid];
    if rk == kind {
      var rn = s.index_num[mid];
      if rn == num {
        var rt = s.index_text[mid];
        if rt == text { return s.index_id[mid] < id; }
        return str_less(rt, text);
      }
      return rn < num;
    }
    return rk < kind;
  }
  return str_less(rf, field);
}

// Sorted insert position for the row.
fn payload_index_find_pos(s: &PayloadStore, field: Str, kind: Int, num: Int, text: Str, id: Int) -> Int {
  var lo: Int = 0;
  var hi: Int = s.index_id.len();
  while lo < hi {
    var mid: Int = (lo + hi) / 2;
    if payload_index_row_before(s, mid, field, kind, num, text, id) { lo = mid + 1; } else { hi = mid; }
  }
  return lo;
}

fn payload_index_insert(s: &mut PayloadStore, field: Str, kind: Int, num: Int, text: Str, id: Int) {
  var pos: Int = payload_index_find_pos(s, field, kind, num, text, id);
  s.index_field.push("");
  s.index_kind.push(0);
  s.index_num.push(0);
  s.index_text.push("");
  s.index_id.push(id);
  var j: Int = s.index_id.len() - 1;
  while j > pos {
    s.index_field[j] = s.index_field[j - 1];
    s.index_kind[j] = s.index_kind[j - 1];
    s.index_num[j] = s.index_num[j - 1];
    s.index_text[j] = s.index_text[j - 1];
    s.index_id[j] = s.index_id[j - 1];
    j = j - 1;
  }
  s.index_field[pos] = field;
  s.index_kind[pos] = kind;
  s.index_num[pos] = num;
  s.index_text[pos] = text;
  s.index_id[pos] = id;
}

fn payload_index_remove_ids(s: &mut PayloadStore, id: Int) {
  var i: Int = 0;
  while i < s.index_id.len() {
    if s.index_id[i] == id {
      var last: Int = s.index_id.len() - 1;
      var j: Int = i;
      while j < last {
        s.index_field[j] = s.index_field[j + 1];
        s.index_kind[j] = s.index_kind[j + 1];
        s.index_num[j] = s.index_num[j + 1];
        s.index_text[j] = s.index_text[j + 1];
        s.index_id[j] = s.index_id[j + 1];
        j = j + 1;
      }
      s.index_field.pop();
      s.index_kind.pop();
      s.index_num.pop();
      s.index_text.pop();
      s.index_id.pop();
    } else {
      i = i + 1;
    }
  }
}

// Total indexed rows (sum of fields over all stored payloads).
pub fn payload_store_index_len(s: &PayloadStore) -> Int {
  return s.index_id.len();
}

pub fn payload_store_index_exists(s: &PayloadStore, field: Str) -> Bool {
  var pos: Int = payload_index_field_start(s, field);
  if pos < s.index_id.len() && s.index_field[pos] == field { return true; }
  return false;
}

// Rows for one field = payloads carrying it (Existence/selectivity stat).
pub fn payload_store_index_field_count(s: &PayloadStore, field: Str) -> Int {
  var pos: Int = payload_index_field_start(s, field);
  var n: Int = 0;
  while pos < s.index_id.len() && s.index_field[pos] == field {
    n = n + 1;
    pos = pos + 1;
  }
  return n;
}

// Ids carrying `field` (any value), in index row order.
pub fn payload_store_index_field_ids(s: &PayloadStore, field: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var pos: Int = payload_index_field_start(s, field);
  while pos < s.index_id.len() && s.index_field[pos] == field {
    out.push(s.index_id[pos]);
    pos = pos + 1;
  }
  return out;
}

// Ids whose field equals `value` (semantic equality, like field_value_eq).
// Int/bool/text use an exact tuple search; floats scan the field window and
// compare numerically (IEEE +-0.0 / NaN stay consistent with field_value_eq).
pub fn payload_store_index_eq(s: &PayloadStore, field: Str, value: FieldValue) -> Vec[Int] {
  var out = Vec[Int].new();
  var kind: Int = field_index_kind(&value);
  if kind == 2 {
    var pos: Int = payload_index_field_start(s, field);
    while pos < s.index_id.len() && s.index_field[pos] == field {
      if s.index_kind[pos] == 2 {
        var fv = float.bits_to_float(s.index_num[pos]) as Float32;
        var cand = FieldValue.FloatVal(fv);
        if field_value_eq(&cand, &value) { out.push(s.index_id[pos]); }
      }
      pos = pos + 1;
    }
    return out;
  }
  var num: Int = field_index_num(&value);
  var text: Str = field_index_text(&value);
  var p: Int = payload_index_tuple_start(s, field, kind, num, text);
  while p < s.index_id.len()
    && s.index_field[p] == field
    && s.index_kind[p] == kind
    && s.index_num[p] == num
    && s.index_text[p] == text {
    out.push(s.index_id[p]);
    p = p + 1;
  }
  return out;
}

// Ids whose field is numeric and within [lo, hi] (Int promotes to Float32,
// matching filter_range semantics).
pub fn payload_store_index_range(s: &PayloadStore, field: Str, lo: Float32, hi: Float32) -> Vec[Int] {
  var out = Vec[Int].new();
  var pos: Int = payload_index_field_start(s, field);
  while pos < s.index_id.len() && s.index_field[pos] == field {
    var k = s.index_kind[pos];
    if k == 1 {
      var v = s.index_num[pos] as Float32;
      if v >= lo && v <= hi { out.push(s.index_id[pos]); }
    } elif k == 2 {
      var v2 = float.bits_to_float(s.index_num[pos]) as Float32;
      if v2 >= lo && v2 <= hi { out.push(s.index_id[pos]); }
    }
    pos = pos + 1;
  }
  return out;
}

// Match counts without materializing id lists (planner estimates). Same
// semantics as the _eq/_range walks above; duplicated deliberately so the
// estimate path stays allocation-free.
pub fn payload_store_index_count_eq(s: &PayloadStore, field: Str, value: FieldValue) -> Int {
  var kind: Int = field_index_kind(&value);
  var n: Int = 0;
  if kind == 2 {
    var pos: Int = payload_index_field_start(s, field);
    while pos < s.index_id.len() && s.index_field[pos] == field {
      if s.index_kind[pos] == 2 {
        var fv = float.bits_to_float(s.index_num[pos]) as Float32;
        var cand = FieldValue.FloatVal(fv);
        if field_value_eq(&cand, &value) { n = n + 1; }
      }
      pos = pos + 1;
    }
    return n;
  }
  var num: Int = field_index_num(&value);
  var text: Str = field_index_text(&value);
  var p: Int = payload_index_tuple_start(s, field, kind, num, text);
  while p < s.index_id.len()
    && s.index_field[p] == field
    && s.index_kind[p] == kind
    && s.index_num[p] == num
    && s.index_text[p] == text {
    n = n + 1;
    p = p + 1;
  }
  return n;
}

pub fn payload_store_index_count_range(s: &PayloadStore, field: Str, lo: Float32, hi: Float32) -> Int {
  var n: Int = 0;
  var pos: Int = payload_index_field_start(s, field);
  while pos < s.index_id.len() && s.index_field[pos] == field {
    var k = s.index_kind[pos];
    if k == 1 {
      var v = s.index_num[pos] as Float32;
      if v >= lo && v <= hi { n = n + 1; }
    } elif k == 2 {
      var v2 = float.bits_to_float(s.index_num[pos]) as Float32;
      if v2 >= lo && v2 <= hi { n = n + 1; }
    }
    pos = pos + 1;
  }
  return n;
}
