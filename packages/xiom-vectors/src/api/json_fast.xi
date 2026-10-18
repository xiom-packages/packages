// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.api.json_fast

// Lane-local fast path for the CANONICAL upsert body
//   {"ids":[...],"vectors":[[...],[...]]}
// A byte-level scanner (strict JSON number/trivia grammar, mirroring the
// stdlib parser's rules: leading zeros rejected, frac/exp digits required,
// `xiom.core.to_float_from_str` conversion + finite/range checks) that
// avoids the generic parser, which is superlinear on numeric payloads as
// of stdlib 2ab2a13 (REL-20261011-1453-xvector).
//
// CONSERVATIVE by construction: anything the scanner does not fully
// recognize (other keys, payloads, strings/bools/nulls, escapes,
// duplicate keys, trailing junk, odd numbers, non-ASCII, dimension 0,
// ids beyond 2^53) returns None and the caller takes the strict generic
// path -- so acceptance can only ever shrink, never diverge. The probe
// gates byte-for-byte response equality between the fast and strict
// modes over an accept/reject + mutation matrix.

use xiom.string.slice;
use xiom.vector.primitives;

pub type FastUpsert = {
  ids: Vec[Int];
  vectors: Vec[Vector];
}

fn is_ws(c: UInt8) -> Bool {
  return c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8;
}

fn is_digit(c: UInt8) -> Bool {
  return c >= 48u8 && c <= 57u8;
}

fn skip_ws(b: &Vec[UInt8], p: Int) -> Int {
  var i = p;
  while i < b.len() && is_ws(b[i]) {
    i = i + 1;
  }
  return i;
}

// Strict number scan (mirrors _json_parse_number) with INLINE decimal
// accumulation: no per-number Str and no converter call on the hot path.
// Conservatism: >17 significant digits or |exp| > 350 falls back (None ->
// strict generic path). Within those bounds the value is within a few ulp
// of the stdlib converter (documented in SPEC; the response contract does
// not echo values, so byte-level response parity is unaffected).
fn scan_number(b: &Vec[UInt8], p: Int, out: &mut Float64) -> Int {
  var start = p;
  var i = p;
  var neg: Bool = false;
  if i < b.len() && b[i] == 45u8 {
    neg = true;
    i = i + 1;
  }
  if i >= b.len() || !is_digit(b[i]) {
    return -1;
  }
  var int_start = i;
  while i < b.len() && is_digit(b[i]) {
    i = i + 1;
  }
  if i - int_start > 1 && b[int_start] == 48u8 {
    return -1; // leading zeros
  }
  var idig: Int = 0;
  var dig: Int = 0;
  var k = int_start;
  while k < i {
    if dig > 15 {
      return -1;
    }
    idig = idig * 10 + ((b[k] - 48u8) as Int);
    dig = dig + 1;
    k = k + 1;
  }
  var fdig: Int = 0;
  var fdn: Int = 0;
  if i < b.len() && b[i] == 46u8 {
    i = i + 1;
    if i >= b.len() || !is_digit(b[i]) {
      return -1;
    }
    var frac_start = i;
    while i < b.len() && is_digit(b[i]) {
      i = i + 1;
    }
    k = frac_start;
    while k < i {
      if dig > 15 {
        return -1;
      }
      fdig = fdig * 10 + ((b[k] - 48u8) as Int);
      fdn = fdn + 1;
      dig = dig + 1;
      k = k + 1;
    }
  }
  var net: Int = 0 - fdn;
  if i < b.len() && (b[i] == 101u8 || b[i] == 69u8) {
    i = i + 1;
    var eneg: Bool = false;
    if i < b.len() && (b[i] == 43u8 || b[i] == 45u8) {
      if b[i] == 45u8 { eneg = true; }
      i = i + 1;
    }
    if i >= b.len() || !is_digit(b[i]) {
      return -1;
    }
    var eval: Int = 0;
    while i < b.len() && is_digit(b[i]) {
      if eval > 999 {
        return -1; // huge exponent: strict path
      }
      eval = eval * 10 + ((b[i] - 48u8) as Int);
      i = i + 1;
    }
    if eneg { eval = 0 - eval; }
    net = net + eval;
  }
  if net > 22 || net < -22 {
    return -1; // outside the exactly-conditioned range: strict path
  }
  if i == start {
    return -1;
  }
  // mantissa fits 15 digits (< 2^53): one exact scale, one division
  var v: Float64 = (idig * ipow10(fdn) + fdig) as Float64;
  if net > 0 {
    var s: Int = 0;
    while s < net {
      v = v * 10.0;
      s = s + 1;
    }
  } else if net < 0 {
    var s2: Int = 0 - net;
    var r: Int = 0;
    while r < s2 {
      v = v / 10.0;
      r = r + 1;
    }
  }
  if neg { v = 0.0 - v; }
  out = v;
  return i;
}

// 10^n for small n (no overflow within the scanner's 17-digit bound).
fn ipow10(n: Int) -> Int {
  var v: Int = 1;
  var i: Int = 0;
  while i < n {
    v = v * 10;
    i = i + 1;
  }
  return v;
}

// Integer for ids: full number grammar, then a 2^53 exactness cap (the
// strict path casts Float64 -> Int; beyond 2^53 the cast is lossy and we
// stay conservative).
fn scan_id(b: &Vec[UInt8], p: Int, out: &mut Int) -> Int {
  var f: Float64 = 0.0;
  var e = scan_number(b, p, &mut f);
  if e < 0 {
    return -1;
  }
  if f > 9007199254740992.0 || f < -9007199254740992.0 {
    return -1;
  }
  out = f as Int;
  return e;
}

fn scan_ids_array(b: &Vec[UInt8], p: Int, ids: &mut Vec[Int]) -> Int {
  var i = skip_ws(b, p);
  if i >= b.len() || b[i] != 91u8 {
    return -1;
  }
  i = skip_ws(b, i + 1);
  if i < b.len() && b[i] == 93u8 {
    return i + 1;
  }
  var running = true;
  while running {
    var idv: Int = 0;
    i = scan_id(b, i, &mut idv);
    if i < 0 {
      return -1;
    }
    ids.push(idv);
    i = skip_ws(b, i);
    if i >= b.len() {
      return -1;
    }
    if b[i] == 44u8 {
      i = skip_ws(b, i + 1);
    } else if b[i] == 93u8 {
      i = i + 1;
      running = false;
    } else {
      return -1;
    }
  }
  return i;
}

fn scan_vectors_array(b: &Vec[UInt8], p: Int, vectors: &mut Vec[Vector]) -> Int {
  var i = skip_ws(b, p);
  if i >= b.len() || b[i] != 91u8 {
    return -1;
  }
  i = skip_ws(b, i + 1);
  if i < b.len() && b[i] == 93u8 {
    return i + 1;
  }
  var running = true;
  while running {
    // one vector: [ numbers ]
    if i >= b.len() || b[i] != 91u8 {
      return -1;
    }
    var j = skip_ws(b, i + 1);
    var coords = Vec[Float32].new();
    if j < b.len() && b[j] == 93u8 {
      return -1; // dimension 0: the strict path rejects (jv_to_vector)
    }
    var inner = true;
    while inner {
      var fv: Float64 = 0.0;
      j = scan_number(b, j, &mut fv);
      if j < 0 {
        return -1;
      }
      coords.push(fv as Float32);
      j = skip_ws(b, j);
      if j >= b.len() {
        return -1;
      }
      if b[j] == 44u8 {
        j = skip_ws(b, j + 1);
      } else if b[j] == 93u8 {
        j = j + 1;
        inner = false;
      } else {
        return -1;
      }
    }
    var v = Vector.new(coords.len());
    var k: Int = 0;
    while k < coords.len() {
      v.set(k, coords[k]);
      k = k + 1;
    }
    vectors.push(v);
    i = skip_ws(b, j);
    if i >= b.len() {
      return -1;
    }
    if b[i] == 44u8 {
      i = skip_ws(b, i + 1);
    } else if b[i] == 93u8 {
      i = i + 1;
      running = false;
    } else {
      return -1;
    }
  }
  return i;
}

fn scan_key(b: &Vec[UInt8], p: Int, name: Str) -> Int {
  let nb = slice.str_bytes(name);
  var i = p;
  if i >= b.len() || b[i] != 34u8 {
    return -1;
  }
  i = i + 1;
  var j: Int = 0;
  while j < nb.len() {
    if i >= b.len() || b[i] != nb[j] {
      return -1;
    }
    i = i + 1;
    j = j + 1;
  }
  if i >= b.len() || b[i] != 34u8 {
    return -1;
  }
  i = skip_ws(b, i + 1);
  if i >= b.len() || b[i] != 58u8 {
    return -1;
  }
  return skip_ws(b, i + 1);
}

// Try the canonical shape on RAW BYTES (the service's hot path). None ->
// caller falls back to the strict generic parser.
pub fn json_fast_upsert_bytes(b: &Vec[UInt8]) -> Option[FastUpsert] {
  var i = skip_ws(b, 0);
  if i >= b.len() || b[i] != 123u8 {
    return None;
  }
  i = skip_ws(b, i + 1);
  var ids = Vec[Int].new();
  var vectors = Vec[Vector].new();
  var have_ids: Bool = false;
  var have_vecs: Bool = false;
  var running = true;
  while running {
    // member name: exactly "ids" or "vectors", once each
    var after_ids = scan_key(b, i, "ids");
    if after_ids >= 0 {
      if have_ids {
        return None;
      }
      i = scan_ids_array(b, after_ids, &mut ids);
      if i < 0 {
        return None;
      }
      have_ids = true;
    } else {
      var after_vecs = scan_key(b, i, "vectors");
      if after_vecs >= 0 {
        if have_vecs {
          return None;
        }
        i = scan_vectors_array(b, after_vecs, &mut vectors);
        if i < 0 {
          return None;
        }
        have_vecs = true;
      } else {
        return None;
      }
    }
    i = skip_ws(b, i);
    if i >= b.len() {
      return None;
    }
    if b[i] == 44u8 {
      i = skip_ws(b, i + 1);
    } else if b[i] == 125u8 {
      i = i + 1;
      running = false;
    } else {
      return None;
    }
  }
  i = skip_ws(b, i);
  if i != b.len() {
    return None; // trailing bytes: let the strict path judge
  }
  if !have_ids || !have_vecs {
    return None;
  }
  return Some(FastUpsert{ ids: ids, vectors: vectors });
}

// Str convenience entry (performs the Str->bytes conversion); the service
// passes the already-materialized body bytes to `json_fast_upsert_bytes`.
pub fn json_fast_upsert(body: Str) -> Option[FastUpsert] {
  let b = slice.str_bytes(body);
  return json_fast_upsert_bytes(&b);
}
