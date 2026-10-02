// XIOM -- xiom.l10n-unicode: Unicode subset utilities for l10n
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Module xiom.l10n.unicode implements a self-contained, table-driven Unicode
// subset: general-category / combining-class / script / block lookup (the
// unicode_data concern), Unicode-aware case conversion and case folding
// (unicode_case), NFD/NFC/NFKD/NFKC normalization (unicode_norm), and
// grapheme / word / sentence boundary segmentation (unicode_seg).
//
// Coverage is a documented subset, not all of Unicode. The exact covered
// ranges live in xiom.l10n.unicode.tables.tbl_covered() and are listed in
// SPEC.md; code points outside the subset return "" from category() and
// script()/block(), and default to category Cn / class Other / ccc 0 inside
// the segmentation and normalization engines. is_covered() is the explicit
// coverage probe.
//
// Implementation notes (compiler traps observed for this ecosystem):
//   * every table is materialized at run time into a local Vec[Int] by an
//     explicit push loop in xiom.l10n.unicode.tables; there are no
//     module-level tables;
//   * Vec[Int] element reads are always bound to typed locals before use;
//   * UTF-8 bytes are widened as (byte_at(i) as Int) & 0xFF before any
//     comparison (UInt8 -> Int sign-extends);
//   * &mut Vec parameters are called with an explicit &mut at every site;
//   * no Vec[Str] and no Vec[StructType] are used anywhere;
//   * Str values are never compared with ==; str_compare is used instead;
//   * strings containing a U+0000 byte, and strings that are not well-formed
//     UTF-8, are passed through unchanged by the Str-returning functions and
//     yield empty results from the boundary/count functions (documented).

module xiom.l10n.unicode

use xiom.l10n.unicode.tables;
use xiom.string.builder;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Table encodings (must match xiom.l10n.unicode.tables)
// ---------------------------------------------------------------------------

const RANGE_STRIDE: Int = 3;   // [lo, hi, value]
const SIMPLE_STRIDE: Int = 2;  // [cp, mapped]
const MULTI_STRIDE: Int = 6;   // [kind, cp, n, v0, v1, v2]
const DECOMP_STRIDE: Int = 6;  // [cp, n, d0, d1, d2, d3]

// Case-map kinds used by the multi table.
const CASE_UPPER: Int = 0;
const CASE_LOWER: Int = 1;
const CASE_TITLE: Int = 2;
const CASE_FOLD: Int = 3;
const CASE_FOLD_TURKIC: Int = 4;

// Grapheme_Cluster_Break subset ids.
const GCB_OTHER: Int = 0;
const GCB_CR: Int = 1;
const GCB_LF: Int = 2;
const GCB_CONTROL: Int = 3;
const GCB_EXTEND: Int = 4;
const GCB_ZWJ: Int = 5;
const GCB_RI: Int = 6;

// Word_Break subset ids.
const WB_OTHER: Int = 0;
const WB_CR: Int = 1;
const WB_LF: Int = 2;
const WB_NEWLINE: Int = 3;
const WB_EXTEND: Int = 4;
const WB_ZWJ: Int = 5;
const WB_FORMAT: Int = 6;
const WB_ALETTER: Int = 7;
const WB_NUMERIC: Int = 8;
const WB_EXTENDNUMLET: Int = 9;
const WB_MIDLETTER: Int = 10;
const WB_MIDNUM: Int = 11;
const WB_MIDNUMLET: Int = 12;
const WB_SINGLEQUOTE: Int = 13;
const WB_DOUBLEQUOTE: Int = 14;
const WB_WSEGSPACE: Int = 15;
const WB_RI: Int = 16;

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _str_ok(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Masked byte read: `as Int` sign-extends UInt8 values >= 0x80, so always
// mask to 0xFF before comparing.
fn _widened_byte(s: Str, i: Int) -> Int {
  return (s.byte_at(i) as Int) & 0xFF;
}

// ---------------------------------------------------------------------------
// UTF-8 codec over Str (bytes in, code points out, and back)
// ---------------------------------------------------------------------------

// Valid UTF-8 lead byte -> sequence length (1..4); 0 when the byte cannot
// start a sequence (bare continuation byte, C0/C1 overlong pair, F5..FF).
fn _lead_kind(b0: Int) -> Int {
  if b0 <= 0x7F { return 1; }
  if b0 >= 0xC2 && b0 <= 0xDF { return 2; }
  if b0 >= 0xE0 && b0 <= 0xEF { return 3; }
  if b0 >= 0xF0 && b0 <= 0xF4 { return 4; }
  return 0;
}

// Validate the sequence of `seq` bytes starting at `i` (caller guarantees
// i + seq <= s.len() and seq >= 1).
fn _valid_seq(s: Str, i: Int, seq: Int) -> Bool {
  if seq == 1 { return true; }
  let b1 = _widened_byte(s, i + 1);
  if (b1 & 0xC0) != 0x80 { return false; }
  if seq == 2 { return true; }
  let b2 = _widened_byte(s, i + 2);
  if (b2 & 0xC0) != 0x80 { return false; }
  let b0 = _widened_byte(s, i);
  if seq == 3 {
    if b0 == 0xE0 && b1 < 0xA0 { return false; }
    if b0 == 0xED && b1 > 0x9F { return false; }
    return true;
  }
  let b3 = _widened_byte(s, i + 3);
  if (b3 & 0xC0) != 0x80 { return false; }
  if b0 == 0xF0 && b1 < 0x90 { return false; }
  if b0 == 0xF4 && b1 > 0x8F { return false; }
  return true;
}

// Decode a validated sequence to its code point.
fn _decode_seq(s: Str, i: Int, seq: Int) -> Int {
  let b0 = _widened_byte(s, i);
  if seq == 1 { return b0; }
  let b1 = _widened_byte(s, i + 1);
  if seq == 2 {
    return ((b0 & 0x1F) << 6) | (b1 & 0x3F);
  }
  let b2 = _widened_byte(s, i + 2);
  if seq == 3 {
    return ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
  }
  let b3 = _widened_byte(s, i + 3);
  return ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
}

// True when `s` is well-formed UTF-8 and contains no 0x00 byte. The NUL
// exclusion is deliberate: sb_to_str cannot materialize a Str containing
// 0x00 (its length contract aborts), so public Str-returning functions
// refuse such input up front and pass it through unchanged.
fn _clean_utf8(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b0 = _widened_byte(s, i);
    if b0 == 0x00 { return false; }
    let seq = _lead_kind(b0);
    if seq == 0 { return false; }
    if i + seq > n { return false; }
    if !_valid_seq(s, i, seq) { return false; }
    i = i + seq;
  }
  return true;
}

// Decode every code point of `s`; invalid bytes are preserved as byte-valued
// code points (only reachable from callers that did not pre-validate).
fn _decode_str(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    if seq == 0 {
      out.push(b0);
      i = i + 1;
    } elif i + seq > n {
      out.push(b0);
      i = i + 1;
    } elif !_valid_seq(s, i, seq) {
      out.push(b0);
      i = i + 1;
    } else {
      out.push(_decode_seq(s, i, seq));
      i = i + seq;
    }
  }
  return out;
}

// Encode one code point as UTF-8 bytes appended to `out`.
fn _emit_cp(out: &mut Vec[UInt8], cp: Int) {
  if cp <= 0x7F {
    out.push(cp as UInt8);
  } elif cp <= 0x7FF {
    out.push((0xC0 | (cp >> 6)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  } elif cp <= 0xFFFF {
    out.push((0xE0 | (cp >> 12)) as UInt8);
    out.push((0x80 | ((cp >> 6) & 0x3F)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  } else {
    out.push((0xF0 | (cp >> 18)) as UInt8);
    out.push((0x80 | ((cp >> 12) & 0x3F)) as UInt8);
    out.push((0x80 | ((cp >> 6) & 0x3F)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  }
}

// Encode a code point vector into a Str via the string builder.
fn _encode_cps(v: &Vec[Int]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let cp: Int = v[i];
    _emit_cp(&mut out, cp);
    i = i + 1;
  }
  return sb_to_str(&out);
}

// ---------------------------------------------------------------------------
// Table lookups
// ---------------------------------------------------------------------------

// First range row whose [lo, hi] contains `cp`, or -1.
fn _range_find(t: &Vec[Int], cp: Int) -> Int {
  var i = 0;
  let rows = t.len() / RANGE_STRIDE;
  while i < rows {
    let lo: Int = t[i * RANGE_STRIDE];
    let hi: Int = t[i * RANGE_STRIDE + 1];
    if cp >= lo && cp <= hi {
      let v: Int = t[i * RANGE_STRIDE + 2];
      return v;
    }
    i = i + 1;
  }
  return -1;
}

// Sorted stride-2 table membership/shape check.
fn _pair_has(t: &Vec[Int], cp: Int) -> Bool {
  var i = 0;
  let rows = t.len() / SIMPLE_STRIDE;
  while i < rows {
    let lo: Int = t[i * SIMPLE_STRIDE];
    let hi: Int = t[i * SIMPLE_STRIDE + 1];
    if cp >= lo && cp <= hi { return true; }
    if lo > cp { return false; }
    i = i + 1;
  }
  return false;
}

// Sorted stride-2 map lookup; returns the mapped value or -1.
fn _simple_find(t: &Vec[Int], cp: Int) -> Int {
  var i = 0;
  let rows = t.len() / SIMPLE_STRIDE;
  while i < rows {
    let key: Int = t[i * SIMPLE_STRIDE];
    if key == cp {
      let v: Int = t[i * SIMPLE_STRIDE + 1];
      return v;
    }
    if key > cp { return -1; }
    i = i + 1;
  }
  return -1;
}

// Sorted stride-6 decomposition lookup; returns the index of the `n` field
// (row start + 1) or -1.
fn _decomp_find(t: &Vec[Int], cp: Int) -> Int {
  var i = 0;
  let rows = t.len() / DECOMP_STRIDE;
  while i < rows {
    let key: Int = t[i * DECOMP_STRIDE];
    if key == cp {
      return i * DECOMP_STRIDE + 1;
    }
    if key > cp { return -1; }
    i = i + 1;
  }
  return -1;
}

fn _ccc_val(t: &Vec[Int], cp: Int) -> Int {
  let v = _range_find(t, cp);
  if v < 0 { return 0; }
  return v;
}

// ---------------------------------------------------------------------------
// unicode_data: property and category lookup
// ---------------------------------------------------------------------------

// Unicode character-data version backing the generated tables.
pub fn l10n_unicode_version() -> Str {
  return tables.tbl_version();
}

// True when `cp` is inside the documented covered subset.
pub fn l10n_unicode_is_covered(cp: Int) -> Bool {
  if cp < 0 { return false; }
  let t = tables.tbl_covered();
  return _pair_has(&t, cp);
}

// Category id (see tables.tbl_cat header comment for the id list) or -1 when
// `cp` is outside the covered subset.
pub fn l10n_unicode_category_id(cp: Int) -> Int {
  if cp < 0 { return -1; }
  let t = tables.tbl_cat();
  return _range_find(&t, cp);
}

// Two-letter general category ("Lu", "Ll", ...), "Cn" for unassigned code
// points inside the covered ranges, "" outside the covered subset.
pub fn l10n_unicode_category(cp: Int) -> Str {
  let id = l10n_unicode_category_id(cp);
  if id < 0 { return ""; }
  return tables.cat_name(id);
}

// Canonical combining class (0 when none / outside the subset).
pub fn l10n_unicode_combining_class(cp: Int) -> Int {
  if cp < 0 { return 0; }
  let t = tables.tbl_ccc();
  return _ccc_val(&t, cp);
}

// Coarse script name ("Latin", "Greek", "Cyrillic", "Common", "Inherited");
// "" outside the covered subset. Script assignment is block-level, not per
// code point (see SPEC.md).
pub fn l10n_unicode_script(cp: Int) -> Str {
  if cp < 0 { return ""; }
  let t = tables.tbl_script();
  let id = _range_find(&t, cp);
  if id < 0 { return ""; }
  return tables.script_name(id);
}

// Unicode block name; "" outside the covered subset.
pub fn l10n_unicode_block(cp: Int) -> Str {
  if cp < 0 { return ""; }
  let t = tables.tbl_block();
  let id = _range_find(&t, cp);
  if id < 0 { return ""; }
  return tables.block_name(id);
}

fn _cat_between(cp: Int, lo: Int, hi: Int) -> Bool {
  let id = l10n_unicode_category_id(cp);
  return id >= lo && id <= hi;
}

pub fn l10n_unicode_is_letter(cp: Int) -> Bool {
  return _cat_between(cp, 0, 4);
}

pub fn l10n_unicode_is_mark(cp: Int) -> Bool {
  return _cat_between(cp, 5, 7);
}

pub fn l10n_unicode_is_digit(cp: Int) -> Bool {
  return _cat_between(cp, 8, 8);
}

pub fn l10n_unicode_is_number(cp: Int) -> Bool {
  return _cat_between(cp, 8, 10);
}

pub fn l10n_unicode_is_punct(cp: Int) -> Bool {
  return _cat_between(cp, 11, 18);
}

pub fn l10n_unicode_is_symbol(cp: Int) -> Bool {
  return _cat_between(cp, 18, 21);
}

pub fn l10n_unicode_is_separator(cp: Int) -> Bool {
  return _cat_between(cp, 22, 24);
}

pub fn l10n_unicode_is_control(cp: Int) -> Bool {
  return _cat_between(cp, 25, 25);
}

pub fn l10n_unicode_is_format(cp: Int) -> Bool {
  return _cat_between(cp, 26, 26);
}

pub fn l10n_unicode_is_uppercase(cp: Int) -> Bool {
  return _cat_between(cp, 0, 0);
}

pub fn l10n_unicode_is_lowercase(cp: Int) -> Bool {
  return _cat_between(cp, 1, 1);
}

pub fn l10n_unicode_is_cased(cp: Int) -> Bool {
  return _cat_between(cp, 0, 2);
}

// White_Space property for the covered subset.
pub fn l10n_unicode_is_whitespace(cp: Int) -> Bool {
  if cp >= 0x0009 && cp <= 0x000D { return true; }
  if cp == 0x0020 || cp == 0x0085 || cp == 0x00A0 { return true; }
  if cp >= 0x2000 && cp <= 0x200A { return true; }
  if cp == 0x2028 || cp == 0x2029 { return true; }
  if cp == 0x202F || cp == 0x205F { return true; }
  return false;
}

pub fn l10n_unicode_is_combining_mark(cp: Int) -> Bool {
  return l10n_unicode_is_mark(cp);
}

// Grapheme_Cluster_Break class name for the covered subset; uncovered code
// points are "Other".
pub fn l10n_unicode_grapheme_class(cp: Int) -> Str {
  if cp < 0 { return ""; }
  let t = tables.tbl_gcb();
  let id = _range_find(&t, cp);
  if id < 0 { return "Other"; }
  return tables.gcb_name(id);
}

// Word_Break class name for the covered subset; uncovered code points are
// "Other".
pub fn l10n_unicode_word_class(cp: Int) -> Str {
  if cp < 0 { return ""; }
  let t = tables.tbl_wb();
  let id = _range_find(&t, cp);
  if id < 0 { return "Other"; }
  return tables.wb_name(id);
}

// Extended_Pictographic membership for the covered subset.
pub fn l10n_unicode_is_extended_pictographic(cp: Int) -> Bool {
  if cp < 0 { return false; }
  let t = tables.tbl_extpic();
  return _range_find(&t, cp) >= 0;
}

// ---------------------------------------------------------------------------
// unicode_case: full case mapping and folding
// ---------------------------------------------------------------------------

fn _case_kind_table(kind: Int) -> Vec[Int] {
  if kind == CASE_UPPER { return tables.tbl_upper_simple(); }
  if kind == CASE_LOWER { return tables.tbl_lower_simple(); }
  if kind == CASE_TITLE { return tables.tbl_title_simple(); }
  return tables.tbl_fold_simple();
}

fn _multi_find(m: &Vec[Int], kind: Int, cp: Int) -> Int {
  var i = 0;
  let rows = m.len() / MULTI_STRIDE;
  while i < rows {
    let k: Int = m[i * MULTI_STRIDE];
    let c: Int = m[i * MULTI_STRIDE + 1];
    if k == kind && c == cp {
      return i * MULTI_STRIDE + 2;
    }
    i = i + 1;
  }
  return -1;
}

// Full case mapping of one code point. Returns a non-empty Vec[Int]:
// the mapping (1..3 code points) or the input itself when unmapped.
// kind 4 is Turkic folding (I -> dotless i, dotted I -> i, then fold).
fn _case_map(kind: Int, cp: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if kind == CASE_FOLD_TURKIC {
    if cp == 0x0049 { out.push(0x0131); return out; }
    if cp == 0x0130 { out.push(0x0069); return out; }
    return _case_map(CASE_FOLD, cp);
  }
  let m = tables.tbl_multi();
  let mr = _multi_find(&m, kind, cp);
  if mr >= 0 {
    let n: Int = m[mr];
    var i = 0;
    while i < n {
      let v: Int = m[mr + 1 + i];
      out.push(v);
      i = i + 1;
    }
    return out;
  }
  let st = _case_kind_table(kind);
  let v = _simple_find(&st, cp);
  if v >= 0 {
    out.push(v);
    return out;
  }
  out.push(cp);
  return out;
}

// Map every code point of `s` through `_case_map`. Malformed UTF-8 or NUL
// input is returned unchanged.
fn _case_string(s: Str, kind: Int) -> Str {
  if !_clean_utf8(s) { return s; }
  let n = s.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    let cp = _decode_seq(s, i, seq);
    let mapped = _case_map(kind, cp);
    var k = 0;
    while k < mapped.len() {
      let v: Int = mapped[k];
      _emit_cp(&mut out, v);
      k = k + 1;
    }
    i = i + seq;
  }
  return sb_to_str(&out);
}

// Full uppercase of one code point ("ß" -> "SS").
pub fn l10n_unicode_upper_cp(cp: Int) -> Vec[Int] {
  return _case_map(CASE_UPPER, cp);
}

// Full lowercase of one code point ("İ" -> "i" + U+0307).
pub fn l10n_unicode_lower_cp(cp: Int) -> Vec[Int] {
  return _case_map(CASE_LOWER, cp);
}

// Full titlecase mapping of one code point.
pub fn l10n_unicode_title_cp(cp: Int) -> Vec[Int] {
  return _case_map(CASE_TITLE, cp);
}

// Full case folding of one code point ("ß" -> "ss").
pub fn l10n_unicode_fold_cp(cp: Int) -> Vec[Int] {
  return _case_map(CASE_FOLD, cp);
}

pub fn l10n_unicode_upper(s: Str) -> Str {
  return _case_string(s, CASE_UPPER);
}

pub fn l10n_unicode_lower(s: Str) -> Str {
  return _case_string(s, CASE_LOWER);
}

// Word-aware titlecasing: the first cased code point of every cased run gets
// the title mapping, the rest the lowercase mapping. All other code points
// pass through.
pub fn l10n_unicode_title(s: Str) -> Str {
  if !_clean_utf8(s) { return s; }
  let cats = tables.tbl_cat();
  let n = s.len();
  var out = Vec[UInt8].new();
  var i = 0;
  var prev_cased = false;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    let cp = _decode_seq(s, i, seq);
    let cid = _range_find(&cats, cp);
    var cased = false;
    if cid >= 0 && cid <= 2 { cased = true; }
    if !cased {
      _emit_cp(&mut out, cp);
    } else {
      var kind = CASE_TITLE;
      if prev_cased { kind = CASE_LOWER; }
      let mapped = _case_map(kind, cp);
      var k = 0;
      while k < mapped.len() {
        let v: Int = mapped[k];
        _emit_cp(&mut out, v);
        k = k + 1;
      }
    }
    prev_cased = cased;
    i = i + seq;
  }
  return sb_to_str(&out);
}

// Full case folding (Unicode default, not Turkic).
pub fn l10n_unicode_fold(s: Str) -> Str {
  return _case_string(s, CASE_FOLD);
}

// Turkic case folding: I -> dotless i and dotted I -> i before folding.
pub fn l10n_unicode_fold_turkic(s: Str) -> Str {
  return _case_string(s, CASE_FOLD_TURKIC);
}

// ---------------------------------------------------------------------------
// unicode_norm: NFD / NFC / NFKD / NFKC
// ---------------------------------------------------------------------------

// Recursive single-step decomposition of `cp` into a fresh Vec[Int].
// mode 0 = canonical only, mode 1 = canonical + compatibility.
fn _decomp_list(cp: Int, canon: &Vec[Int], compat: &Vec[Int], mode: Int, depth: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if depth > 6 {
    out.push(cp);
    return out;
  }
  if mode == 1 {
    let cr = _decomp_find(compat, cp);
    if cr >= 0 {
      let cnt: Int = compat[cr];
      var i = 0;
      while i < cnt {
        let v: Int = compat[cr + 1 + i];
        let sub = _decomp_list(v, canon, compat, mode, depth + 1);
        var k = 0;
        while k < sub.len() {
          let sv: Int = sub[k];
          out.push(sv);
          k = k + 1;
        }
        i = i + 1;
      }
      return out;
    }
  }
  let rr = _decomp_find(canon, cp);
  if rr < 0 {
    out.push(cp);
    return out;
  }
  let cnt: Int = canon[rr];
  var i = 0;
  while i < cnt {
    let v: Int = canon[rr + 1 + i];
    let sub = _decomp_list(v, canon, compat, mode, depth + 1);
    var k = 0;
    while k < sub.len() {
      let sv: Int = sub[k];
      out.push(sv);
      k = k + 1;
    }
    i = i + 1;
  }
  return out;
}

// Fully decompose every code point of `src`.
fn _decompose_cps(src: &Vec[Int], mode: Int) -> Vec[Int] {
  let canon = tables.tbl_canon();
  var compat = Vec[Int].new();
  if mode == 1 {
    compat = tables.tbl_compat();
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    let cp: Int = src[i];
    let d = _decomp_list(cp, &canon, &compat, mode, 0);
    var k = 0;
    while k < d.len() {
      let v: Int = d[k];
      out.push(v);
      k = k + 1;
    }
    i = i + 1;
  }
  return out;
}

// Stable canonical ordering: insertion-sort combining marks by combining
// class within each starter run (marks with ccc 0 act as starters).
fn _canonical_order(v: Vec[Int], ccc: &Vec[Int]) -> Vec[Int] {
  var i = 1;
  while i < v.len() {
    let cur: Int = v[i];
    let cur_cc = _ccc_val(ccc, cur);
    if cur_cc != 0 {
      var j = i;
      while j > 0 {
        let prev: Int = v[j - 1];
        let prev_cc = _ccc_val(ccc, prev);
        if prev_cc == 0 || prev_cc <= cur_cc {
          break;
        }
        v[j] = prev;
        v[j - 1] = cur;
        j = j - 1;
      }
    }
    i = i + 1;
  }
  return v;
}

// Full composition exclusions that intersect the covered subset (singleton
// decompositions are excluded by the n == 2 requirement alone).
fn _comp_excluded(cp: Int) -> Bool {
  if cp == 0x0340 { return true; }
  if cp == 0x0341 { return true; }
  if cp == 0x0343 { return true; }
  if cp == 0x0344 { return true; }
  if cp == 0x0374 { return true; }
  if cp == 0x037E { return true; }
  if cp == 0x0385 { return true; }
  if cp == 0x0387 { return true; }
  return false;
}

// Primary composite of the pair (a, b), or -1 when none / excluded.
fn _compose_pair(a: Int, b: Int, canon: &Vec[Int]) -> Int {
  var i = 0;
  let rows = canon.len() / DECOMP_STRIDE;
  while i < rows {
    let cp: Int = canon[i * DECOMP_STRIDE];
    let n: Int = canon[i * DECOMP_STRIDE + 1];
    if n == 2 {
      let d0: Int = canon[i * DECOMP_STRIDE + 2];
      if d0 == a {
        let d1: Int = canon[i * DECOMP_STRIDE + 3];
        if d1 == b && !_comp_excluded(cp) {
          return cp;
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

// Canonical composition with blocking (starter + combining mark only;
// Hangul syllable composition is not in the covered subset).
fn _compose_cps(d: Vec[Int], ccc: &Vec[Int]) -> Vec[Int] {
  let canon = tables.tbl_canon();
  var out = Vec[Int].new();
  var starter = -1;
  var last_cc = 0;
  var i = 0;
  while i < d.len() {
    let c: Int = d[i];
    let cc = _ccc_val(ccc, c);
    if cc != 0 && starter >= 0 && last_cc < cc {
      let s: Int = out[starter];
      let comp = _compose_pair(s, c, &canon);
      if comp >= 0 {
        out[starter] = comp;
        i = i + 1;
        continue;
      }
    }
    out.push(c);
    if cc == 0 {
      starter = out.len() - 1;
    }
    last_cc = cc;
    i = i + 1;
  }
  return out;
}

// form: 0 NFD, 1 NFC, 2 NFKD, 3 NFKC.
fn _normalized_form(s: Str, form: Int) -> Str {
  if !_clean_utf8(s) { return s; }
  let src = _decode_str(s);
  var mode = 0;
  if form >= 2 { mode = 1; }
  let ccc = tables.tbl_ccc();
  let d0 = _decompose_cps(&src, mode);
  let d1 = _canonical_order(d0, &ccc);
  if form == 1 || form == 3 {
    let d2 = _compose_cps(d1, &ccc);
    return _encode_cps(&d2);
  }
  return _encode_cps(&d1);
}

pub fn l10n_unicode_nfd(s: Str) -> Str {
  return _normalized_form(s, 0);
}

pub fn l10n_unicode_nfc(s: Str) -> Str {
  return _normalized_form(s, 1);
}

pub fn l10n_unicode_nfkd(s: Str) -> Str {
  return _normalized_form(s, 2);
}

pub fn l10n_unicode_nfkc(s: Str) -> Str {
  return _normalized_form(s, 3);
}

fn _form_code(form: Str) -> Int {
  if _streq(form, "NFD") { return 0; }
  if _streq(form, "NFC") { return 1; }
  if _streq(form, "NFKD") { return 2; }
  if _streq(form, "NFKC") { return 3; }
  return -1;
}

// Normalize to the named form; unknown form is an error, as is malformed
// UTF-8 / NUL-bearing input.
pub fn l10n_unicode_normalize(s: Str, form: Str) -> Result[Str, Str] {
  let f = _form_code(form);
  if f < 0 {
    return _str_err("l10n-unicode: unknown normalization form: " + form);
  }
  if !_clean_utf8(s) {
    return _str_err("l10n-unicode: invalid UTF-8 input");
  }
  return _str_ok(_normalized_form(s, f));
}

// True when `s` is already in the named form (false for unknown forms and
// malformed input).
pub fn l10n_unicode_is_normalized(s: Str, form: Str) -> Bool {
  let f = _form_code(form);
  if f < 0 { return false; }
  if !_clean_utf8(s) { return false; }
  let r = _normalized_form(s, f);
  return _streq(r, s);
}

// ---------------------------------------------------------------------------
// unicode_seg: grapheme / word / sentence boundaries
// ---------------------------------------------------------------------------

// Byte offsets of grapheme cluster starts, plus the end offset. Empty vector
// for empty / malformed input; otherwise first == 0 and last == s.len().
pub fn l10n_unicode_grapheme_boundaries(s: Str) -> Vec[Int] {
  var bounds = Vec[Int].new();
  if !_clean_utf8(s) { return bounds; }
  let n = s.len();
  if n == 0 { return bounds; }
  let gcb = tables.tbl_gcb();
  let ext = tables.tbl_extpic();
  bounds.push(0);
  var i = 0;
  var prev_cls = -1;
  var ri_run = 0;
  var ext_run = false;
  var zwj_armed = false;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    let cp_off = i;
    let cp = _decode_seq(s, i, seq);
    var cls = _range_find(&gcb, cp);
    if cls < 0 { cls = GCB_OTHER; }
    let is_ext = _range_find(&ext, cp) >= 0;
    var brk = false;
    if prev_cls < 0 {
      brk = false;                                   // sot
    } elif prev_cls == GCB_CR && cls == GCB_LF {
      brk = false;                                   // GB3
    } elif prev_cls == GCB_CR || prev_cls == GCB_LF || prev_cls == GCB_CONTROL {
      brk = true;                                    // GB4
    } elif cls == GCB_CR || cls == GCB_LF || cls == GCB_CONTROL {
      brk = true;                                    // GB5
    } elif cls == GCB_EXTEND || cls == GCB_ZWJ {
      brk = false;                                   // GB9
    } elif is_ext && zwj_armed {
      brk = false;                                   // GB11
    } elif cls == GCB_RI && prev_cls == GCB_RI && ri_run % 2 == 1 {
      brk = false;                                   // GB12/GB13
    } else {
      brk = true;                                    // GB999
    }
    if brk {
      bounds.push(cp_off);
    }
    // RI run state: counts consecutive RI code points ending at this one.
    if cls == GCB_RI {
      if !brk && prev_cls == GCB_RI {
        ri_run = ri_run + 1;
      } else {
        ri_run = 1;
      }
    } else {
      ri_run = 0;
    }
    // GB11 context: Extended_Pictographic Extend* ZWJ, armed for the next
    // Extended_Pictographic.
    if is_ext {
      ext_run = true;
      zwj_armed = false;
    } elif cls == GCB_EXTEND {
      if zwj_armed {
        ext_run = false;
        zwj_armed = false;
      }
    } elif cls == GCB_ZWJ {
      if ext_run {
        zwj_armed = true;
      }
      ext_run = false;
    } else {
      ext_run = false;
      zwj_armed = false;
    }
    prev_cls = cls;
    i = i + seq;
  }
  bounds.push(n);
  return bounds;
}

// Number of grapheme clusters (0 for empty / malformed input).
pub fn l10n_unicode_grapheme_count(s: Str) -> Int {
  let b = l10n_unicode_grapheme_boundaries(s);
  if b.len() == 0 { return 0; }
  return b.len() - 1;
}

fn _wb_ignorable(cls: Int) -> Bool {
  return cls == WB_EXTEND || cls == WB_FORMAT || cls == WB_ZWJ;
}

fn _wb_ahletter(cls: Int) -> Bool {
  return cls == WB_ALETTER;
}

fn _wb_mid3(cls: Int) -> Bool {
  return cls == WB_MIDLETTER || cls == WB_MIDNUMLET || cls == WB_SINGLEQUOTE;
}

fn _wb_midnum3(cls: Int) -> Bool {
  return cls == WB_MIDNUM || cls == WB_MIDNUMLET || cls == WB_SINGLEQUOTE;
}

fn _wb_wordish(cls: Int) -> Bool {
  return cls == WB_ALETTER || cls == WB_NUMERIC || cls == WB_EXTENDNUMLET;
}

// UAX #29 word-break decision for the covered subset. Returns true when a
// boundary falls between the previous character and `cur`.
fn _wb_break(prev_sig: Int, prev2_sig: Int, cur: Int, next_sig: Int,
             prev_raw: Int, cur_cp: Int, ri_run: Int) -> Bool {
  if prev_raw == WB_CR && cur == WB_LF { return false; }             // WB3
  if prev_raw == WB_CR || prev_raw == WB_LF || prev_raw == WB_NEWLINE {
    return true;                                                     // WB3a
  }
  if cur == WB_CR || cur == WB_LF || cur == WB_NEWLINE {
    return true;                                                     // WB3b
  }
  if prev_raw == WB_ZWJ && l10n_unicode_is_extended_pictographic(cur_cp) {
    return false;                                                    // WB3c
  }
  if prev_raw == WB_WSEGSPACE && cur == WB_WSEGSPACE {
    return false;                                                    // WB3d
  }
  if _wb_ignorable(cur) { return false; }                            // WB4
  if _wb_ahletter(prev_sig) && _wb_ahletter(cur) { return false; }   // WB5
  if _wb_ahletter(prev_sig) && _wb_mid3(cur) && _wb_ahletter(next_sig) {
    return false;                                                    // WB6
  }
  if _wb_mid3(prev_sig) && _wb_ahletter(cur) && _wb_ahletter(prev2_sig) {
    return false;                                                    // WB7
  }
  if prev_sig == WB_NUMERIC && cur == WB_NUMERIC { return false; }   // WB8
  if _wb_ahletter(prev_sig) && cur == WB_NUMERIC { return false; }   // WB9
  if prev_sig == WB_NUMERIC && _wb_ahletter(cur) { return false; }   // WB10
  if prev_sig == WB_NUMERIC && _wb_midnum3(cur) && next_sig == WB_NUMERIC {
    return false;                                                    // WB11
  }
  if _wb_midnum3(prev_sig) && cur == WB_NUMERIC && prev2_sig == WB_NUMERIC {
    return false;                                                    // WB12
  }
  if _wb_wordish(prev_sig) && cur == WB_EXTENDNUMLET { return false; }  // WB13a
  if prev_sig == WB_EXTENDNUMLET && _wb_wordish(cur) { return false; }  // WB13b
  if prev_sig == WB_RI && cur == WB_RI {
    return ri_run % 2 == 0;                                          // WB15/16
  }
  return true;                                                       // WB999
}

// Byte offsets of UAX #29 word boundaries (covered subset), including 0 and
// s.len(); empty vector for empty / malformed input.
pub fn l10n_unicode_word_boundaries(s: Str) -> Vec[Int] {
  var bounds = Vec[Int].new();
  if !_clean_utf8(s) { return bounds; }
  let n = s.len();
  if n == 0 { return bounds; }
  let wb = tables.tbl_wb();
  // Parallel vectors: code points, byte offsets, raw classes (mirrored pushes).
  var cps = Vec[Int].new();
  var offs = Vec[Int].new();
  var cls = Vec[Int].new();
  var i = 0;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    let cp = _decode_seq(s, i, seq);
    var c = _range_find(&wb, cp);
    if c < 0 { c = WB_OTHER; }
    cps.push(cp);
    offs.push(i);
    cls.push(c);
    i = i + seq;
  }
  let m = cps.len();
  // Significant class strictly before each index (ignoring Extend/Format/ZWJ)
  // and the one before that.
  var ps = Vec[Int].new();
  var p2 = Vec[Int].new();
  var a = -1;
  var b = -1;
  var k = 0;
  while k < m {
    ps.push(a);
    p2.push(b);
    let c: Int = cls[k];
    if !_wb_ignorable(c) {
      b = a;
      a = c;
    }
    k = k + 1;
  }
  // Significant class strictly after each index, built reversed.
  var nsr = Vec[Int].new();
  var z = -1;
  var k2 = m - 1;
  while k2 >= 0 {
    nsr.push(z);
    let c: Int = cls[k2];
    if !_wb_ignorable(c) {
      z = c;
    }
    k2 = k2 - 1;
  }
  bounds.push(0);
  var ri = 0;
  var j = 1;
  while j < m {
    let prev_raw: Int = cls[j - 1];
    let cur: Int = cls[j];
    let prev_sig: Int = ps[j];
    let prev2_sig: Int = p2[j];
    let next_sig: Int = nsr[m - 1 - j];
    let cur_cp: Int = cps[j];
    let brk = _wb_break(prev_sig, prev2_sig, cur, next_sig, prev_raw, cur_cp, ri);
    if brk {
      let off: Int = offs[j];
      bounds.push(off);
    }
    if cur == WB_RI {
      if !brk && prev_sig == WB_RI {
        ri = ri + 1;
      } else {
        ri = 1;
      }
    } elif !_wb_ignorable(cur) {
      ri = 0;
    }
    j = j + 1;
  }
  bounds.push(n);
  return bounds;
}

// Number of maximal word spans containing at least one letter / digit /
// extend-numlet code point.
pub fn l10n_unicode_word_count(s: Str) -> Int {
  let bounds = l10n_unicode_word_boundaries(s);
  if bounds.len() < 2 { return 0; }
  let wb = tables.tbl_wb();
  var count = 0;
  var t = 0;
  while t + 1 < bounds.len() {
    let lo: Int = bounds[t];
    let hi: Int = bounds[t + 1];
    var has_word = false;
    var k = lo;
    while k < hi {
      let b0 = _widened_byte(s, k);
      let seq = _lead_kind(b0);
      let cp = _decode_seq(s, k, seq);
      var c = _range_find(&wb, cp);
      if c < 0 { c = WB_OTHER; }
      if c == WB_ALETTER || c == WB_NUMERIC || c == WB_EXTENDNUMLET {
        has_word = true;
      }
      k = k + seq;
    }
    if has_word { count = count + 1; }
    t = t + 1;
  }
  return count;
}

fn _is_sentence_term(cp: Int) -> Bool {
  if cp == 0x002E || cp == 0x0021 || cp == 0x003F { return true; }
  if cp == 0x2026 { return true; }
  if cp == 0xFF0E || cp == 0xFF01 || cp == 0xFF1F { return true; }
  return false;
}

fn _is_sentence_close(cp: Int) -> Bool {
  if cp == 0x0022 || cp == 0x0027 || cp == 0x0029 || cp == 0x005D { return true; }
  if cp == 0x00BB || cp == 0x203A { return true; }
  if cp == 0x2019 || cp == 0x201D { return true; }
  return false;
}

fn _is_ascii_digit_at(s: Str, i: Int) -> Bool {
  if i < 0 || i >= s.len() { return false; }
  let b = _widened_byte(s, i);
  return b >= 0x30 && b <= 0x39;
}

// Byte offsets of sentence starts plus the end offset. Simplified,
// deterministic rule set (see SPEC.md): a terminator run (. ! ? … and their
// fullwidth forms) ends a sentence when followed by whitespace, a closing
// quote/bracket, or end of input; a '.' between ASCII digits is a decimal
// point. There is no abbreviation dictionary.
pub fn l10n_unicode_sentence_boundaries(s: Str) -> Vec[Int] {
  var bounds = Vec[Int].new();
  if !_clean_utf8(s) { return bounds; }
  let n = s.len();
  if n == 0 { return bounds; }
  bounds.push(0);
  var i = 0;
  var term = false;
  var space_seen = false;
  while i < n {
    let b0 = _widened_byte(s, i);
    let seq = _lead_kind(b0);
    let cp = _decode_seq(s, i, seq);
    let next_i = i + seq;
    if _is_sentence_term(cp) {
      var is_term = true;
      if cp == 0x002E && _is_ascii_digit_at(s, i - 1) && _is_ascii_digit_at(s, next_i) {
        is_term = false;
      }
      if is_term {
        term = true;
        space_seen = false;
      }
    } elif term {
      if _is_sentence_close(cp) {
        // closing punctuation after the terminator: still the same boundary
      } elif l10n_unicode_is_whitespace(cp) {
        space_seen = true;
      } else {
        if space_seen {
          bounds.push(i);
        }
        term = false;
        space_seen = false;
      }
    }
    i = next_i;
  }
  let last: Int = bounds[bounds.len() - 1];
  if last != n {
    bounds.push(n);
  }
  return bounds;
}

// Number of sentences (0 for empty / malformed input).
pub fn l10n_unicode_sentence_count(s: Str) -> Int {
  let b = l10n_unicode_sentence_boundaries(s);
  if b.len() == 0 { return 0; }
  return b.len() - 1;
}
