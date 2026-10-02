// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.elastic: a pure Elasticsearch client MODEL (no HTTP).
//
// Scope (SPEC.md has the exact subset):
//   * Query DSL model: match / term / terms / range / bool / exists / nested,
//     built into a flat arena (parallel Vec fields -- Vec[StructType] is
//     unsupported by this compiler), with a deterministic JSON serializer.
//   * Request builders: search body, search request, index request, scroll
//     request and bulk NDJSON line framing.
//   * Response envelope parser: took / timed_out / hits.total / hits.hits
//     (_source raw spans) / an aggregations subset, over a hand-rolled flat
//     JSON scanner. No full JSON DOM; only the envelope fields are read.
//   * Mapping model (field -> type), index settings model, and a bounded
//     scroll/pagination state model.
//
// Purity: every function is deterministic and IO-free. Non-goals: transport,
// HTTP, retries, authentication, TLS, connection pools, full JSON parsing,
// query validation against a live cluster (see SPEC.md).
//
// v0.62.2 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType];
//   * byte-wise scanning with xiom.string.byte_at; every byte is widened to
//     the Int domain with `(byte_at(..) as Int) & 0xFF` before comparison;
//   * Str equality never uses `==` on a value read from a Vec[Str] (BUG 17);
//     every table lookup goes through xiom.string.compare.str_compare and
//     every Vec element read is bound with a typed `let`;
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     `_resp_ok` / `_resp_err` below;
//   * no `continue`/`break`; every scan loop is bounded by the input length;
//   * serializer output is assembled by Str concatenation (no builder), so
//     the recursion never crosses a `&mut Vec[UInt8]` boundary.

module xiom.elastic

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
//  Query kinds and bool categories
// ---------------------------------------------------------------------------

/// No query (zero value; never built).
pub const QE_KIND_NONE: Int = 0;
/// `match` query: field + analyzed text.
pub const QE_KIND_MATCH: Int = 1;
/// `term` query: field + exact term.
pub const QE_KIND_TERM: Int = 2;
/// `terms` query: field + a set of exact terms.
pub const QE_KIND_TERMS: Int = 3;
/// `range` query: field + optional from/to + inclusivity flags.
pub const QE_KIND_RANGE: Int = 4;
/// `bool` query: must / must_not / should / filter child lists.
pub const QE_KIND_BOOL: Int = 5;
/// `exists` query: field presence.
pub const QE_KIND_EXISTS: Int = 6;
/// `nested` query: nested path + one child query.
pub const QE_KIND_NESTED: Int = 7;

/// `must` bool category (AND, scored).
pub const QE_BOOL_MUST: Int = 0;
/// `filter` bool category (AND, unscored).
pub const QE_BOOL_FILTER: Int = 1;
/// `must_not` bool category (NOT).
pub const QE_BOOL_MUST_NOT: Int = 2;
/// `should` bool category (OR, scored).
pub const QE_BOOL_SHOULD: Int = 3;

// ---------------------------------------------------------------------------
//  Mapping field types
// ---------------------------------------------------------------------------

pub const QE_MT_TEXT: Int = 1;
pub const QE_MT_KEYWORD: Int = 2;
pub const QE_MT_LONG: Int = 3;
pub const QE_MT_INTEGER: Int = 4;
pub const QE_MT_DOUBLE: Int = 5;
pub const QE_MT_BOOLEAN: Int = 6;
pub const QE_MT_DATE: Int = 7;
pub const QE_MT_OBJECT: Int = 8;
pub const QE_MT_NESTED: Int = 9;

// ---------------------------------------------------------------------------
//  ASCII byte constants (compared in the Int domain)
// ---------------------------------------------------------------------------

const _QE_QUOTE: Int = 34;
const _QE_COMMA: Int = 44;
const _QE_COLON: Int = 58;
const _QE_LBRACK: Int = 91;
const _QE_BSLASH: Int = 92;
const _QE_RBRACK: Int = 93;
const _QE_LBRACE: Int = 123;
const _QE_RBRACE: Int = 125;
const _QE_MINUS: Int = 45;
const _QE_PLUS: Int = 43;
const _QE_DOT: Int = 46;
const _QE_E_LOWER: Int = 101;
const _QE_E_UPPER: Int = 69;
const _QE_ZERO: Int = 48;
const _QE_NINE: Int = 57;

// ---------------------------------------------------------------------------
//  Low-level flat JSON scanning (Str + Int cursor -> Int cursor)
// ---------------------------------------------------------------------------

// Widened byte read: always 0..255 (trap 3 / trap 13 domain discipline).
fn _by(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Skip ASCII whitespace from i; returns the first non-space index (or len).
fn _skip_ws(s: Str, i: Int) -> Int {
  let n = s.len();
  var p: Int = i;
  var going: Bool = true;
  while p < n && going {
    let b: Int = _by(s, p);
    if b == 32 || b == 9 || b == 10 || b == 13 {
      p = p + 1;
    } else {
      going = false;
    }
  }
  return p;
}

// i points at '"'; returns the index just past the closing quote.
fn _scan_string(s: Str, i: Int) -> Int {
  let n = s.len();
  var p: Int = i + 1;
  var done: Bool = false;
  while p < n && done == false {
    let b: Int = _by(s, p);
    if b == _QE_BSLASH {
      p = p + 2;
    } else {
      if b == _QE_QUOTE {
        p = p + 1;
        done = true;
      } else {
        p = p + 1;
      }
    }
  }
  return p;
}

// i points at a number start; returns the index just past the number.
fn _scan_number(s: Str, i: Int) -> Int {
  let n = s.len();
  var p: Int = i;
  var going: Bool = true;
  while p < n && going {
    let b: Int = _by(s, p);
    if (b >= _QE_ZERO && b <= _QE_NINE) || b == _QE_MINUS || b == _QE_PLUS
        || b == _QE_DOT || b == _QE_E_LOWER || b == _QE_E_UPPER {
      p = p + 1;
    } else {
      going = false;
    }
  }
  return p;
}

// i points at '{' or '['; returns the index just past the matching close.
fn _scan_container(s: Str, i: Int) -> Int {
  let n = s.len();
  var depth: Int = 0;
  var p: Int = i;
  var done: Bool = false;
  while p < n && done == false {
    let b: Int = _by(s, p);
    if b == _QE_QUOTE {
      p = _scan_string(s, p);
    } else {
      if b == _QE_LBRACE || b == _QE_LBRACK {
        depth = depth + 1;
        p = p + 1;
      } else {
        if b == _QE_RBRACE || b == _QE_RBRACK {
          depth = depth - 1;
          p = p + 1;
          if depth <= 0 {
            done = true;
          }
        } else {
          p = p + 1;
        }
      }
    }
  }
  return p;
}

// Skip ws from i; returns the index just past a value that starts there.
fn _scan_value(s: Str, i: Int) -> Int {
  let p: Int = _skip_ws(s, i);
  let b: Int = _by(s, p);
  if b == _QE_QUOTE {
    return _scan_string(s, p);
  }
  if b == _QE_LBRACE || b == _QE_LBRACK {
    return _scan_container(s, p);
  }
  return _scan_number(s, p);
}

// Skip ws then an optional single comma, then ws (object/array iteration).
fn _arr_step(s: Str, i: Int) -> Int {
  var p: Int = _skip_ws(s, i);
  if _by(s, p) == _QE_COMMA {
    p = _skip_ws(s, p + 1);
  }
  return p;
}

// Find `key` among the members of the object whose '{' is at obj_open; the
// search is depth-1 only. Returns the value's start index, or -1.
fn _obj_find(s: Str, obj_open: Int, key: Str) -> Int {
  let n = s.len();
  var p: Int = _skip_ws(s, obj_open + 1);
  var found: Int = -1;
  var going: Bool = true;
  while p < n && going {
    let b: Int = _by(s, p);
    if b == _QE_RBRACE {
      going = false;
    } else {
      if b == _QE_COMMA {
        p = _skip_ws(s, p + 1);
      } else {
        if b == _QE_QUOTE {
          let kstart: Int = p + 1;
          let after: Int = _scan_string(s, p);
          let ktext: Str = string.str_slice(s, kstart, after - 1);
          var q: Int = _skip_ws(s, after);
          if _by(s, q) == _QE_COLON {
            q = _skip_ws(s, q + 1);
          }
          if compare.str_compare(ktext, key) == 0 {
            found = q;
            going = false;
          } else {
            p = _scan_value(s, q);
          }
        } else {
          p = p + 1;
        }
      }
    }
  }
  return found;
}

// Parse an Int at i (optional leading '-'); returns 0 when no digits parse.
fn _read_int(s: Str, i: Int) -> Int {
  let n = s.len();
  var p: Int = _skip_ws(s, i);
  var neg: Bool = false;
  if p < n {
    if _by(s, p) == _QE_MINUS {
      neg = true;
      p = p + 1;
    }
  }
  var v: Int = 0;
  var got: Bool = false;
  var going: Bool = true;
  while p < n && going {
    let b: Int = _by(s, p);
    if b >= _QE_ZERO && b <= _QE_NINE {
      v = v * 10 + (b - _QE_ZERO);
      got = true;
      p = p + 1;
    } else {
      going = false;
    }
  }
  if got == false {
    return 0;
  }
  if neg {
    return 0 - v;
  }
  return v;
}

// True when the literal `lit` starts at i.
fn _read_lit(s: Str, i: Int, lit: Str) -> Bool {
  let p: Int = _skip_ws(s, i);
  let ln: Int = lit.len();
  if p + ln > s.len() {
    return false;
  }
  let piece: Str = string.str_slice(s, p, p + ln);
  return compare.str_compare(piece, lit) == 0;
}

// Raw string value at i (escapes retained), or "" when i is not a string.
fn _read_str_raw(s: Str, i: Int) -> Str {
  let p: Int = _skip_ws(s, i);
  if _by(s, p) == _QE_QUOTE {
    let after: Int = _scan_string(s, p);
    return string.str_slice(s, p + 1, after - 1);
  }
  return "";
}

// ---------------------------------------------------------------------------
//  Response envelope model + parser
// ---------------------------------------------------------------------------

/// Parsed response envelope subset. `src_starts[i]`/`src_lens[i]` are the
/// byte span of the i-th hit's raw `_source` value inside the parsed text
/// (`elastic_response_source` slices it); `agg_names`/`agg_values` hold the
/// aggregations subset in first-seen order. `total_relation` is "eq"/"gte"
/// when the object form was used, "eq" for the legacy numeric form, "" when
/// absent.
pub type EResponse = {
  took: Int;
  timed_out: Bool;
  total: Int;
  total_relation: Str;
  hit_count: Int;
  src_starts: Vec[Int];
  src_lens: Vec[Int];
  agg_names: Vec[Str];
  agg_values: Vec[Int];
}

fn _resp_ok(r: EResponse) -> Result[EResponse, Str] {
  return Ok(r);
}

fn _resp_err(m: Str) -> Result[EResponse, Str] {
  return Err(m);
}

fn _er_empty() -> EResponse {
  return EResponse{
    took: 0;
    timed_out: false;
    total: 0;
    total_relation: "";
    hit_count: 0;
    src_starts: Vec[Int].new();
    src_lens: Vec[Int].new();
    agg_names: Vec[Str].new();
    agg_values: Vec[Int].new();
  };
}

/// Parse the response envelope subset from `text`. Err when `text` is not a
/// JSON object. The scan is linear and bounded by the input length.
/// Complexity: O(len(text)).
pub fn elastic_parse_response(text: Str) -> Result[EResponse, Str] {
  let n = text.len();
  let start: Int = _skip_ws(text, 0);
  if n == 0 || _by(text, start) != _QE_LBRACE {
    return _resp_err("elastic: response must be a JSON object");
  }
  var r: EResponse = _er_empty();
  let took_v: Int = _obj_find(text, start, "took");
  if took_v >= 0 {
    r.took = _read_int(text, took_v);
  }
  let to_v: Int = _obj_find(text, start, "timed_out");
  if to_v >= 0 {
    r.timed_out = _read_lit(text, to_v, "true");
  }
  let hits_obj: Int = _obj_find(text, start, "hits");
  if hits_obj >= 0 && _by(text, hits_obj) == _QE_LBRACE {
    let total_v: Int = _obj_find(text, hits_obj, "total");
    if total_v >= 0 {
      if _by(text, total_v) == _QE_LBRACE {
        let tv: Int = _obj_find(text, total_v, "value");
        if tv >= 0 {
          r.total = _read_int(text, tv);
        }
        let tr: Int = _obj_find(text, total_v, "relation");
        if tr >= 0 {
          r.total_relation = _read_str_raw(text, tr);
        }
      } else {
        r.total = _read_int(text, total_v);
        r.total_relation = "eq";
      }
    }
    let hit_arr: Int = _obj_find(text, hits_obj, "hits");
    if hit_arr >= 0 && _by(text, hit_arr) == _QE_LBRACK {
      var i: Int = _arr_step(text, hit_arr + 1);
      var count: Int = 0;
      var going: Bool = true;
      while i < n && going {
        let b: Int = _by(text, i);
        if b == _QE_RBRACK || b == 0 {
          going = false;
        } else {
          let src: Int = _obj_find(text, i, "_source");
          if src >= 0 {
            let send: Int = _scan_value(text, src);
            r.src_starts.push(src);
            r.src_lens.push(send - src);
          }
          count = count + 1;
          i = _arr_step(text, _scan_value(text, i));
        }
      }
      r.hit_count = count;
    }
  }
  let agg_obj: Int = _obj_find(text, start, "aggregations");
  if agg_obj >= 0 && _by(text, agg_obj) == _QE_LBRACE {
    var a: Int = _arr_step(text, agg_obj + 1);
    var going2: Bool = true;
    while a < n && going2 {
      let b: Int = _by(text, a);
      if b == _QE_RBRACE || b == 0 {
        going2 = false;
      } else {
        if b == _QE_QUOTE {
          let nstart: Int = a + 1;
          let after: Int = _scan_string(text, a);
          let name: Str = string.str_slice(text, nstart, after - 1);
          var c: Int = _skip_ws(text, after);
          if _by(text, c) == _QE_COLON {
            c = _skip_ws(text, c + 1);
          }
          var v: Int = 0;
          if _by(text, c) == _QE_LBRACE {
            let vv: Int = _obj_find(text, c, "value");
            if vv >= 0 {
              v = _read_int(text, vv);
            }
          }
          r.agg_names.push(name);
          r.agg_values.push(v);
          a = _arr_step(text, _scan_value(text, c));
        } else {
          a = a + 1;
        }
      }
    }
  }
  return _resp_ok(r);
}

pub fn elastic_response_took(r: &EResponse) -> Int {
  return r.took;
}

pub fn elastic_response_timed_out(r: &EResponse) -> Bool {
  return r.timed_out;
}

pub fn elastic_response_total(r: &EResponse) -> Int {
  return r.total;
}

pub fn elastic_response_total_relation(r: &EResponse) -> Str {
  return r.total_relation;
}

pub fn elastic_response_hit_count(r: &EResponse) -> Int {
  return r.hit_count;
}

pub fn elastic_response_source_count(r: &EResponse) -> Int {
  return r.src_starts.len();
}

/// Raw `_source` text of hit `i`, sliced from the parsed text.
pub fn elastic_response_source(text: Str, r: &EResponse, i: Int) -> Str {
  if i < 0 || i >= r.src_starts.len() {
    return "";
  }
  let st: Int = r.src_starts[i];
  let ln: Int = r.src_lens[i];
  return string.str_slice(text, st, st + ln);
}

pub fn elastic_response_agg_count(r: &EResponse) -> Int {
  return r.agg_names.len();
}

pub fn elastic_response_agg_name(r: &EResponse, i: Int) -> Str {
  if i < 0 || i >= r.agg_names.len() {
    return "";
  }
  let e: Str = r.agg_names[i];
  return e;
}

pub fn elastic_response_agg_value(r: &EResponse, i: Int) -> Int {
  if i < 0 || i >= r.agg_values.len() {
    return 0;
  }
  let v: Int = r.agg_values[i];
  return v;
}

// ---------------------------------------------------------------------------
//  Query DSL arena
// ---------------------------------------------------------------------------

/// Flat query arena. Every base Vec is pushed together by `_q_push`, so the
/// `kinds`/`fields`/`values`/`froms`/`tos`/`inc_lo`/`inc_hi`/`children` rows
/// stay aligned; the bool and terms child lists are (owner, child/value)
/// pairs in their own parallel Vecs (trap 16).
pub type QEQuery = {
  kinds: Vec[Int];
  fields: Vec[Str];
  values: Vec[Str];
  froms: Vec[Str];
  tos: Vec[Str];
  inc_lo: Vec[Int];
  inc_hi: Vec[Int];
  children: Vec[Int];
  must_owner: Vec[Int];
  must_child: Vec[Int];
  mustnot_owner: Vec[Int];
  mustnot_child: Vec[Int];
  should_owner: Vec[Int];
  should_child: Vec[Int];
  filter_owner: Vec[Int];
  filter_child: Vec[Int];
  terms_owner: Vec[Int];
  terms_value: Vec[Str];
}

/// A new empty query arena. Complexity: O(1).
pub fn elastic_query_new() -> QEQuery {
  return QEQuery{
    kinds: Vec[Int].new();
    fields: Vec[Str].new();
    values: Vec[Str].new();
    froms: Vec[Str].new();
    tos: Vec[Str].new();
    inc_lo: Vec[Int].new();
    inc_hi: Vec[Int].new();
    children: Vec[Int].new();
    must_owner: Vec[Int].new();
    must_child: Vec[Int].new();
    mustnot_owner: Vec[Int].new();
    mustnot_child: Vec[Int].new();
    should_owner: Vec[Int].new();
    should_child: Vec[Int].new();
    filter_owner: Vec[Int].new();
    filter_child: Vec[Int].new();
    terms_owner: Vec[Int].new();
    terms_value: Vec[Str].new();
  };
}

// The single push site for the eight base parallel Vecs.
fn _q_push(q: &mut QEQuery, kind: Int, field: Str, value: Str, fromv: Str,
           tov: Str, ilo: Int, ihi: Int, child: Int) -> Int {
  let id = q.kinds.len();
  q.kinds.push(kind);
  q.fields.push(field);
  q.values.push(value);
  q.froms.push(fromv);
  q.tos.push(tov);
  q.inc_lo.push(ilo);
  q.inc_hi.push(ihi);
  q.children.push(child);
  return id;
}

/// True when every parallel Vec pair is aligned (drift guard).
pub fn elastic_query_consistent(q: &QEQuery) -> Bool {
  let n = q.kinds.len();
  if q.fields.len() != n || q.values.len() != n || q.froms.len() != n {
    return false;
  }
  if q.tos.len() != n || q.inc_lo.len() != n || q.inc_hi.len() != n {
    return false;
  }
  if q.children.len() != n {
    return false;
  }
  if q.must_owner.len() != q.must_child.len() {
    return false;
  }
  if q.mustnot_owner.len() != q.mustnot_child.len() {
    return false;
  }
  if q.should_owner.len() != q.should_child.len() {
    return false;
  }
  if q.filter_owner.len() != q.filter_child.len() {
    return false;
  }
  if q.terms_owner.len() != q.terms_value.len() {
    return false;
  }
  return true;
}

/// Number of nodes in the arena. Complexity: O(1).
pub fn elastic_query_count(q: &QEQuery) -> Int {
  return q.kinds.len();
}

pub fn elastic_query_kind(q: &QEQuery, i: Int) -> Int {
  if i < 0 || i >= q.kinds.len() {
    return QE_KIND_NONE;
  }
  let k: Int = q.kinds[i];
  return k;
}

pub fn elastic_query_field(q: &QEQuery, i: Int) -> Str {
  if i < 0 || i >= q.fields.len() {
    return "";
  }
  let f: Str = q.fields[i];
  return f;
}

pub fn elastic_query_value(q: &QEQuery, i: Int) -> Str {
  if i < 0 || i >= q.values.len() {
    return "";
  }
  let v: Str = q.values[i];
  return v;
}

pub fn elastic_query_kind_name(k: Int) -> Str {
  if k == QE_KIND_MATCH {
    return "match";
  }
  if k == QE_KIND_TERM {
    return "term";
  }
  if k == QE_KIND_TERMS {
    return "terms";
  }
  if k == QE_KIND_RANGE {
    return "range";
  }
  if k == QE_KIND_BOOL {
    return "bool";
  }
  if k == QE_KIND_EXISTS {
    return "exists";
  }
  if k == QE_KIND_NESTED {
    return "nested";
  }
  return "none";
}

// ---------------------------------------------------------------------------
//  Query builders
// ---------------------------------------------------------------------------

/// `match` query on `field` against analyzed text `value`.
pub fn elastic_match(q: &mut QEQuery, field: Str, value: Str) -> Int {
  return _q_push(q, QE_KIND_MATCH, field, value, "", "", 0, 0, -1);
}

/// `term` query on `field` for the exact `value`.
pub fn elastic_term(q: &mut QEQuery, field: Str, value: Str) -> Int {
  return _q_push(q, QE_KIND_TERM, field, value, "", "", 0, 0, -1);
}

/// Empty `terms` query on `field`; add values with `elastic_terms_add`.
pub fn elastic_terms(q: &mut QEQuery, field: Str) -> Int {
  return _q_push(q, QE_KIND_TERMS, field, "", "", "", 0, 0, -1);
}

/// Append one exact term to a `terms` query.
pub fn elastic_terms_add(q: &mut QEQuery, node: Int, value: Str) {
  q.terms_owner.push(node);
  q.terms_value.push(value);
}

/// `range` query; empty `from`/`to` are omitted; `inc_lo`/`inc_hi` select
/// gte/lte (1) versus gt/lt (0).
pub fn elastic_range(q: &mut QEQuery, field: Str, fromv: Str, tov: Str,
                     inc_lo: Int, inc_hi: Int) -> Int {
  return _q_push(q, QE_KIND_RANGE, field, "", fromv, tov, inc_lo, inc_hi, -1);
}

/// Empty `bool` query; add clauses with elastic_bool_*.
pub fn elastic_bool(q: &mut QEQuery) -> Int {
  return _q_push(q, QE_KIND_BOOL, "", "", "", "", 0, 0, -1);
}

fn _bool_add(q: &mut QEQuery, owner: Int, child: Int, which: Int) {
  if which == QE_BOOL_MUST {
    q.must_owner.push(owner);
    q.must_child.push(child);
  } else {
    if which == QE_BOOL_FILTER {
      q.filter_owner.push(owner);
      q.filter_child.push(child);
    } else {
      if which == QE_BOOL_MUST_NOT {
        q.mustnot_owner.push(owner);
        q.mustnot_child.push(child);
      } else {
        if which == QE_BOOL_SHOULD {
          q.should_owner.push(owner);
          q.should_child.push(child);
        }
      }
    }
  }
}

pub fn elastic_bool_must(q: &mut QEQuery, owner: Int, child: Int) {
  _bool_add(q, owner, child, QE_BOOL_MUST);
}

pub fn elastic_bool_filter(q: &mut QEQuery, owner: Int, child: Int) {
  _bool_add(q, owner, child, QE_BOOL_FILTER);
}

pub fn elastic_bool_must_not(q: &mut QEQuery, owner: Int, child: Int) {
  _bool_add(q, owner, child, QE_BOOL_MUST_NOT);
}

pub fn elastic_bool_should(q: &mut QEQuery, owner: Int, child: Int) {
  _bool_add(q, owner, child, QE_BOOL_SHOULD);
}

/// `exists` query on `field`.
pub fn elastic_exists(q: &mut QEQuery, field: Str) -> Int {
  return _q_push(q, QE_KIND_EXISTS, field, "", "", "", 0, 0, -1);
}

/// `nested` query on nested `path` with one `child` query.
pub fn elastic_nested(q: &mut QEQuery, path: Str, child: Int) -> Int {
  return _q_push(q, QE_KIND_NESTED, path, "", "", "", 0, 0, child);
}

// ---------------------------------------------------------------------------
//  Query serializer
// ---------------------------------------------------------------------------

fn _hex_digit(v: Int) -> Str {
  if v < 10 {
    return string.str_slice("0123456789abcdef", v, v + 1);
  }
  return string.str_slice("0123456789abcdef", v, v + 1);
}

// Deterministic JSON string escaping for query values/fields.
fn _json_escape(s: Str) -> Str {
  let n = s.len();
  var out = "";
  var i: Int = 0;
  while i < n {
    let b: Int = _by(s, i);
    if b == 34 {
      out = out + "\\\"";
    } else {
      if b == 92 {
        out = out + "\\\\";
      } else {
        if b == 10 {
          out = out + "\\n";
        } else {
          if b == 13 {
            out = out + "\\r";
          } else {
            if b == 9 {
              out = out + "\\t";
            } else {
              if b < 32 {
                out = out + "\\u00" + _hex_digit(b / 16) + _hex_digit(b % 16);
              } else {
                out = out + string.str_slice(s, i, i + 1);
              }
            }
          }
        }
      }
    }
    i = i + 1;
  }
  return out;
}

fn _terms_join(q: &QEQuery, owner: Int) -> Str {
  var out = "";
  var first: Bool = true;
  var i: Int = 0;
  while i < q.terms_owner.len() {
    let o: Int = q.terms_owner[i];
    if o == owner {
      let v: Str = q.terms_value[i];
      if first {
        first = false;
      } else {
        out = out + ",";
      }
      out = out + "\"" + _json_escape(v) + "\"";
    }
    i = i + 1;
  }
  return out;
}

fn _bool_count(q: &QEQuery, owner: Int, which: Int) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  if which == QE_BOOL_MUST {
    while i < q.must_owner.len() {
      let o: Int = q.must_owner[i];
      if o == owner {
        n = n + 1;
      }
      i = i + 1;
    }
  } else {
    if which == QE_BOOL_FILTER {
      while i < q.filter_owner.len() {
        let o: Int = q.filter_owner[i];
        if o == owner {
          n = n + 1;
        }
        i = i + 1;
      }
    } else {
      if which == QE_BOOL_MUST_NOT {
        while i < q.mustnot_owner.len() {
          let o: Int = q.mustnot_owner[i];
          if o == owner {
            n = n + 1;
          }
          i = i + 1;
        }
      } else {
        if which == QE_BOOL_SHOULD {
          while i < q.should_owner.len() {
            let o: Int = q.should_owner[i];
            if o == owner {
              n = n + 1;
            }
            i = i + 1;
          }
        }
      }
    }
  }
  return n;
}

fn _bool_join(q: &QEQuery, owner: Int, which: Int) -> Str {
  var out = "";
  var first: Bool = true;
  var i: Int = 0;
  if which == QE_BOOL_MUST {
    while i < q.must_owner.len() {
      let o: Int = q.must_owner[i];
      let c: Int = q.must_child[i];
      if o == owner {
        if first {
          first = false;
        } else {
          out = out + ",";
        }
        out = out + elastic_query_to_json(q, c);
      }
      i = i + 1;
    }
  } else {
    if which == QE_BOOL_FILTER {
      while i < q.filter_owner.len() {
        let o: Int = q.filter_owner[i];
        let c: Int = q.filter_child[i];
        if o == owner {
          if first {
            first = false;
          } else {
            out = out + ",";
          }
          out = out + elastic_query_to_json(q, c);
        }
        i = i + 1;
      }
    } else {
      if which == QE_BOOL_MUST_NOT {
        while i < q.mustnot_owner.len() {
          let o: Int = q.mustnot_owner[i];
          let c: Int = q.mustnot_child[i];
          if o == owner {
            if first {
              first = false;
            } else {
              out = out + ",";
            }
            out = out + elastic_query_to_json(q, c);
          }
          i = i + 1;
        }
      } else {
        if which == QE_BOOL_SHOULD {
          while i < q.should_owner.len() {
            let o: Int = q.should_owner[i];
            let c: Int = q.should_child[i];
            if o == owner {
              if first {
                first = false;
              } else {
                out = out + ",";
              }
              out = out + elastic_query_to_json(q, c);
            }
            i = i + 1;
          }
        }
      }
    }
  }
  return out;
}

/// Serialize node `node` of `q` to a deterministic JSON query clause.
/// Unknown/out-of-range nodes serialize as `{}`.
pub fn elastic_query_to_json(q: &QEQuery, node: Int) -> Str {
  let k: Int = elastic_query_kind(q, node);
  let f: Str = elastic_query_field(q, node);
  if k == QE_KIND_MATCH {
    return "{\"match\":{\"" + _json_escape(f) + "\":{\"query\":\""
      + _json_escape(elastic_query_value(q, node)) + "\"}}}";
  }
  if k == QE_KIND_TERM {
    return "{\"term\":{\"" + _json_escape(f) + "\":{\"value\":\""
      + _json_escape(elastic_query_value(q, node)) + "\"}}}";
  }
  if k == QE_KIND_TERMS {
    return "{\"terms\":{\"" + _json_escape(f) + "\":["
      + _terms_join(q, node) + "]}}";
  }
  if k == QE_KIND_RANGE {
    var inner = "";
    var need: Bool = false;
    let fr: Str = q.froms[node];
    let tv: Str = q.tos[node];
    if fr.len() > 0 {
      var lok: Str = "gt";
      if q.inc_lo[node] == 1 {
        lok = "gte";
      }
      inner = inner + "\"" + lok + "\":\"" + _json_escape(fr) + "\"";
      need = true;
    }
    if tv.len() > 0 {
      var hik: Str = "lt";
      if q.inc_hi[node] == 1 {
        hik = "lte";
      }
      if need {
        inner = inner + ",";
      }
      inner = inner + "\"" + hik + "\":\"" + _json_escape(tv) + "\"";
    }
    return "{\"range\":{\"" + _json_escape(f) + "\":{" + inner + "}}}";
  }
  if k == QE_KIND_BOOL {
    var out = "";
    var need2: Bool = false;
    if _bool_count(q, node, QE_BOOL_MUST) > 0 {
      out = out + "\"must\":[" + _bool_join(q, node, QE_BOOL_MUST) + "]";
      need2 = true;
    }
    if _bool_count(q, node, QE_BOOL_FILTER) > 0 {
      if need2 {
        out = out + ",";
      }
      out = out + "\"filter\":[" + _bool_join(q, node, QE_BOOL_FILTER) + "]";
      need2 = true;
    }
    if _bool_count(q, node, QE_BOOL_MUST_NOT) > 0 {
      if need2 {
        out = out + ",";
      }
      out = out + "\"must_not\":[" + _bool_join(q, node, QE_BOOL_MUST_NOT) + "]";
      need2 = true;
    }
    if _bool_count(q, node, QE_BOOL_SHOULD) > 0 {
      if need2 {
        out = out + ",";
      }
      out = out + "\"should\":[" + _bool_join(q, node, QE_BOOL_SHOULD) + "]";
      need2 = true;
    }
    return "{\"bool\":{" + out + "}}";
  }
  if k == QE_KIND_EXISTS {
    return "{\"exists\":{\"field\":\"" + _json_escape(f) + "\"}}";
  }
  if k == QE_KIND_NESTED {
    let ch: Int = q.children[node];
    return "{\"nested\":{\"path\":\"" + _json_escape(f) + "\",\"query\":"
      + elastic_query_to_json(q, ch) + "}}";
  }
  return "{}";
}

// ---------------------------------------------------------------------------
//  Request builders
// ---------------------------------------------------------------------------

/// `{"query": <node>}` search body.
pub fn elastic_search_body(q: &QEQuery, node: Int) -> Str {
  return "{\"query\":" + elastic_query_to_json(q, node) + "}";
}

/// POST /<index>/_search request envelope.
pub fn elastic_search_request(index: Str, q: &QEQuery, node: Int) -> Str {
  return "{\"method\":\"POST\",\"path\":\"/" + index + "/_search\",\"body\":"
    + elastic_search_body(q, node) + "}";
}

/// Index request envelope. With an empty `id` it is POST /<index>/_doc;
/// otherwise PUT /<index>/_doc/<id>. `doc_json` is embedded verbatim.
pub fn elastic_index_request(index: Str, id: Str, doc_json: Str) -> Str {
  var method = "POST";
  var path = "/" + index + "/_doc";
  if id.len() > 0 {
    method = "PUT";
    path = path + "/" + id;
  }
  return "{\"method\":\"" + method + "\",\"path\":\"" + path
    + "\",\"body\":" + doc_json + "}";
}

/// POST /_search/scroll request envelope with an explicit page size.
pub fn elastic_scroll_request(scroll_id: Str, size: Int) -> Str {
  return "{\"method\":\"POST\",\"path\":\"/_search/scroll\",\"body\":{\"scroll\":\"30s\",\"scroll_id\":\""
    + scroll_id + "\",\"size\":" + int_to_string(size) + "}}";
}

/// One bulk action line targeting `index`, optionally with `_id`.
pub fn elastic_bulk_index_action(index: Str, id: Str) -> Str {
  if id.len() > 0 {
    return "{\"index\":{\"_index\":\"" + index + "\",\"_id\":\"" + id + "\"}}";
  }
  return "{\"index\":{\"_index\":\"" + index + "\"}}";
}

/// Frame one bulk action + source pair as two NDJSON lines (each terminated
/// by '\n'). Complexity: O(action + source).
pub fn elastic_bulk_frame(action: Str, source: Str) -> Str {
  return action + "\n" + source + "\n";
}

/// Number of '\n'-terminated records in an NDJSON blob.
pub fn elastic_ndjson_line_count(s: Str) -> Int {
  let n = s.len();
  var i: Int = 0;
  var c: Int = 0;
  while i < n {
    if _by(s, i) == 10 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// True when the NDJSON blob ends with '\n' (non-empty framing).
pub fn elastic_ndjson_wellformed(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  return _by(s, n - 1) == 10;
}

// ---------------------------------------------------------------------------
//  Mapping model
// ---------------------------------------------------------------------------

/// Field-name -> type mapping. `types[i]` belongs to `names[i]`.
pub type EMapping = {
  names: Vec[Str];
  types: Vec[Int];
}

/// A new empty mapping. Complexity: O(1).
pub fn elastic_mapping_new() -> EMapping {
  return EMapping{
    names: Vec[Str].new();
    types: Vec[Int].new();
  };
}

/// Add/overwrite a field's type. Complexity: O(fields).
pub fn elastic_mapping_add(m: &mut EMapping, name: Str, type_code: Int) {
  var i: Int = 0;
  var found: Bool = false;
  while i < m.names.len() {
    let e: Str = m.names[i];
    if compare.str_compare(e, name) == 0 {
      m.types[i] = type_code;
      found = true;
    }
    i = i + 1;
  }
  if found == false {
    m.names.push(name);
    m.types.push(type_code);
  }
}

/// Number of mapped fields. Complexity: O(1).
pub fn elastic_mapping_count(m: &EMapping) -> Int {
  return m.names.len();
}

pub fn elastic_mapping_name(m: &EMapping, i: Int) -> Str {
  if i < 0 || i >= m.names.len() {
    return "";
  }
  let e: Str = m.names[i];
  return e;
}

pub fn elastic_mapping_type(m: &EMapping, i: Int) -> Int {
  if i < 0 || i >= m.types.len() {
    return 0;
  }
  let t: Int = m.types[i];
  return t;
}

/// Type code of a named field, or 0 when absent. Complexity: O(fields).
pub fn elastic_mapping_field_type(m: &EMapping, name: Str) -> Int {
  var i: Int = 0;
  var out: Int = 0;
  while i < m.names.len() {
    let e: Str = m.names[i];
    if compare.str_compare(e, name) == 0 {
      out = m.types[i];
    }
    i = i + 1;
  }
  return out;
}

pub fn elastic_mapping_type_name(t: Int) -> Str {
  if t == QE_MT_TEXT {
    return "text";
  }
  if t == QE_MT_KEYWORD {
    return "keyword";
  }
  if t == QE_MT_LONG {
    return "long";
  }
  if t == QE_MT_INTEGER {
    return "integer";
  }
  if t == QE_MT_DOUBLE {
    return "double";
  }
  if t == QE_MT_BOOLEAN {
    return "boolean";
  }
  if t == QE_MT_DATE {
    return "date";
  }
  if t == QE_MT_OBJECT {
    return "object";
  }
  if t == QE_MT_NESTED {
    return "nested";
  }
  return "";
}

/// `{"properties":{ "<name>":{"type":"<type>"}, ... }}`.
pub fn elastic_mapping_to_json(m: &EMapping) -> Str {
  var out = "";
  var i: Int = 0;
  while i < m.names.len() {
    let e: Str = m.names[i];
    if i > 0 {
      out = out + ",";
    }
    out = out + "\"" + e + "\":{\"type\":\""
      + elastic_mapping_type_name(m.types[i]) + "\"}";
    i = i + 1;
  }
  return "{\"properties\":{" + out + "}}";
}

// ---------------------------------------------------------------------------
//  Index settings model
// ---------------------------------------------------------------------------

pub type EIndexSettings = {
  shards: Int;
  replicas: Int;
  refresh: Str;
}

/// Default settings: 1 shard, 1 replica, 1s refresh interval.
pub fn elastic_settings_new() -> EIndexSettings {
  return EIndexSettings{
    shards: 1;
    replicas: 1;
    refresh: "1s";
  };
}

pub fn elastic_settings_set_shards(s: &mut EIndexSettings, v: Int) {
  s.shards = v;
}

pub fn elastic_settings_set_replicas(s: &mut EIndexSettings, v: Int) {
  s.replicas = v;
}

pub fn elastic_settings_set_refresh(s: &mut EIndexSettings, v: Str) {
  s.refresh = v;
}

pub fn elastic_settings_shards(s: &EIndexSettings) -> Int {
  return s.shards;
}

pub fn elastic_settings_replicas(s: &EIndexSettings) -> Int {
  return s.replicas;
}

pub fn elastic_settings_refresh(s: &EIndexSettings) -> Str {
  return s.refresh;
}

/// `{"index":{"number_of_shards":N,"number_of_replicas":N,"refresh_interval":"..."}}`.
pub fn elastic_settings_to_json(s: &EIndexSettings) -> Str {
  return "{\"index\":{\"number_of_shards\":" + int_to_string(s.shards)
    + ",\"number_of_replicas\":" + int_to_string(s.replicas)
    + ",\"refresh_interval\":\"" + s.refresh + "\"}}";
}

// ---------------------------------------------------------------------------
//  Scroll / bounded pagination state
// ---------------------------------------------------------------------------

/// Bounded scroll state. `max_pages` caps the number of pages; `done` latches
/// once the cap is reached or a page reports no hits. `ids` accumulates one
/// id per observed hit (test/diagnostic aid).
pub type EScroll = {
  scroll_id: Str;
  size: Int;
  page: Int;
  seen: Int;
  max_pages: Int;
  done: Bool;
  ids: Vec[Str];
}

/// New scroll state. `max_pages` <= 0 is treated as 1 (at least one page).
pub fn elastic_scroll_new(scroll_id: Str, size: Int, max_pages: Int) -> EScroll {
  var mp: Int = max_pages;
  if mp < 1 {
    mp = 1;
  }
  return EScroll{
    scroll_id: scroll_id;
    size: size;
    page: 0;
    seen: 0;
    max_pages: mp;
    done: false;
    ids: Vec[Str].new();
  };
}

/// Advance the scroll by one page observing `hits` hits. Returns true when a
/// further page remains (and the scroll is not done). Latches `done` on the
/// page cap or on an empty page.
pub fn elastic_scroll_advance(s: &mut EScroll, hits: Int) -> Bool {
  if s.done {
    return false;
  }
  s.page = s.page + 1;
  s.seen = s.seen + hits;
  if s.page >= s.max_pages {
    s.done = true;
    return false;
  }
  if hits <= 0 {
    s.done = true;
    return false;
  }
  return true;
}

pub fn elastic_scroll_done(s: &EScroll) -> Bool {
  return s.done;
}

pub fn elastic_scroll_page(s: &EScroll) -> Int {
  return s.page;
}

pub fn elastic_scroll_seen(s: &EScroll) -> Int {
  return s.seen;
}

pub fn elastic_scroll_add_id(s: &mut EScroll, id: Str) {
  s.ids.push(id);
}

pub fn elastic_scroll_id_count(s: &EScroll) -> Int {
  return s.ids.len();
}

pub fn elastic_scroll_id_at(s: &EScroll, i: Int) -> Str {
  if i < 0 || i >= s.ids.len() {
    return "";
  }
  let e: Str = s.ids[i];
  return e;
}

/// Next page request envelope for this scroll's id/size.
pub fn elastic_scroll_next_request(s: &EScroll) -> Str {
  return elastic_scroll_request(s.scroll_id, s.size);
}

// ---------------------------------------------------------------------------
//  Pagination arithmetic
// ---------------------------------------------------------------------------

/// Number of pages needed for `total` items at `size` per page. Uses the
/// truncation-safe ceil form (trap 18); non-positive inputs yield 0.
pub fn elastic_page_count(total: Int, size: Int) -> Int {
  if total <= 0 || size <= 0 {
    return 0;
  }
  let q = total / size;
  let r = total % size;
  if r > 0 {
    return q + 1;
  }
  return q;
}
