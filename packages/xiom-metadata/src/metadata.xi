// XIOM -- xiom.metadata: deterministic metadata block model
// Port task: replace the xiom.metadata placeholder with a real, tested,
// pure-XIOM package: ordered key-value blocks (section, key, value) with
// case-insensitive keys, dotted block scoping and nesting, first/last/error
// duplicate-key policies as explicit codes, two-source merge with precedence
// and provenance, block diff, canonical serialization with parse round-trip,
// and a pinned validation error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a MetaBlock is a flat list of entries, each entry an index-aligned
// (section, key, value, origin) record. On this compiler Vec[StructType] is
// unusable and `Vec[Str].push` mis-lowers (stride 8, i8 store at clang), so
// every string list is a Str pool plus a parallel Vec[Int] of end offsets:
// entry i's string is str_slice(data, ends[i-1] or 0, ends[i]). Three pools
// (sections, keys, values) plus the provenance Vec[Int] share one length.
//
// Semantics (SPEC.md is normative):
//   * entry identity is the ASCII-case-folded (section, key) pair; folding
//     lowercases only bytes A-Z, and all Str equality goes through
//     xiom.string.compare.str_compare (BUG 17: `==` on Str values from
//     Vec[Str] elements is a pointer compare);
//   * entries keep first-seen insertion order; duplicate handling is an
//     explicit policy code: first keeps the first value, last replaces the
//     value in place (position kept), error rejects the assignment;
//   * md_merge(base, over) is over-wins per (section, key) pair: base
//     entries first in base order, then over-only entries; origin 0 means
//     the value came from base (primary), origin 1 from over (override);
//   * canonical text is insertion order, one `section.key = value` line per
//     entry (a root entry has no dot), LF separated with no trailing LF;
//     md_serialize_sorted emits the same lines sorted by folded section
//     then folded key (stable);
//   * md_parse accepts that shape: first '=' splits key path from value,
//     the last dot in the left side splits section from key, full-line
//     '#'/';' comments and blank lines are skipped, CRLF is accepted, keys
//     and values are trimmed, and every line is validated.
//
// v0.62.2 notes that shaped this module:
//   * no Vec[Str] anywhere: local pokes into a Str pool plus Vec[Int] of
//     end offsets are the proven workaround for the Vec[Str].push
//     mis-lowering (xiom.consensus uses the same shape);
//   * every Vec element read is bound with a typed `let` first;
//   * Ok/Err for Result[MetaBlock, Str] are constructed only in the leaf
//     helpers _mb_ok/_mb_err;
//   * byte_at comparisons against UInt8 literals are direct (fixed in
//     v0.62.2), so no widen/mask copies;
//   * no `&mut Int` / `&mut Str` parameters (writes are dropped): scalar
//     state is threaded through returns and pools are mutated through
//     `&mut MetaBlock` fields only;
//   * no lambdas, no fn tables, no `self`, no generic-named helpers.

module xiom.metadata

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Byte constants and policy codes
// --------------------------------------------------

const _MD_NUL: UInt8 = 0u8;
const _MD_TAB: UInt8 = 9u8;
const _MD_LF: UInt8 = 10u8;
const _MD_CR: UInt8 = 13u8;
const _MD_SPACE: UInt8 = 32u8;
const _MD_HASH: UInt8 = 35u8;
const _MD_DOT: UInt8 = 46u8;
const _MD_SEMI: UInt8 = 59u8;
const _MD_EQ: UInt8 = 61u8;
const _MD_LBRACKET: UInt8 = 91u8;
const _MD_RBRACKET: UInt8 = 93u8;

// Duplicate-key policies (md_dup_*).
const _MD_DUP_FIRST: Int = 0;
const _MD_DUP_LAST: Int = 1;
const _MD_DUP_ERROR: Int = 2;

// Provenance codes (md_origin_*): which side of a merge supplied the value.
const _MD_ORIGIN_PRIMARY: Int = 0;
const _MD_ORIGIN_OVERRIDE: Int = 1;

// Diff kinds (md_kind_*).
const _MD_KIND_ADDED: Int = 0;
const _MD_KIND_REMOVED: Int = 1;
const _MD_KIND_CHANGED: Int = 2;

// Validation codes (md_val_*).
const _MD_VAL_OK: Int = 0;
const _MD_VAL_BAD_SECTION: Int = 1;
const _MD_VAL_BAD_KEY: Int = 2;
const _MD_VAL_BAD_VALUE: Int = 3;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// An ordered metadata block. `sec_data`/`sec_end`, `key_data`/`key_end`
/// and `val_data`/`val_end` are three index-aligned Str pools: entry i's
/// section is str_slice(sec_data, sec_end[i-1] or 0, sec_end[i]), and the
/// same for key and value. `origin[i]` is the provenance code of entry i.
/// Build blocks with md_new/md_set/md_merge/md_parse so the four tracks
/// stay aligned.
pub type MetaBlock = {
  sec_data: Str;
  sec_end: Vec[Int];
  key_data: Str;
  key_end: Vec[Int];
  val_data: Str;
  val_end: Vec[Int];
  origin: Vec[Int];
}

/// A block-to-block diff. `added` holds entries present only in the right
/// block, `removed` entries present only in the left block, `changed`
/// entries present in both with different raw values (value = left value);
/// `changed_new` is index-aligned with `changed` and holds the right value
/// (same section and key). Query with md_diff_len/md_diff_*/md_diff_render.
pub type MetaDiff = {
  added: MetaBlock;
  removed: MetaBlock;
  changed: MetaBlock;
  changed_new: MetaBlock;
}

// --------------------------------------------------
//  Result leaves (Ok/Err construction is confined here)
// --------------------------------------------------

// Ok(m) for Result[MetaBlock, Str].
fn _mb_ok(m: MetaBlock) -> Result[MetaBlock, Str] {
  return Ok(m);
}

// Err(msg) for Result[MetaBlock, Str].
fn _mb_err(msg: Str) -> Result[MetaBlock, Str] {
  return Err(msg);
}

// --------------------------------------------------
//  Policy / catalog accessors
// --------------------------------------------------

/// Duplicate policy "first": an assignment to an existing key is ignored,
/// so the first value and position win.
pub fn md_dup_first() -> Int {
  return _MD_DUP_FIRST;
}

/// Duplicate policy "last": an assignment to an existing key replaces the
/// value in place, so the last assignment wins and the position is kept.
pub fn md_dup_last() -> Int {
  return _MD_DUP_LAST;
}

/// Duplicate policy "error": an assignment to an existing key fails.
pub fn md_dup_error() -> Int {
  return _MD_DUP_ERROR;
}

/// Human name of a duplicate policy code ("first", "last", "error",
/// "unknown").
pub fn md_dup_name(policy: Int) -> Str {
  if policy == _MD_DUP_FIRST {
    return "first";
  }
  if policy == _MD_DUP_LAST {
    return "last";
  }
  if policy == _MD_DUP_ERROR {
    return "error";
  }
  return "unknown";
}

/// Provenance code for a value supplied by the merge base.
pub fn md_origin_primary() -> Int {
  return _MD_ORIGIN_PRIMARY;
}

/// Provenance code for a value supplied by the merge override.
pub fn md_origin_override() -> Int {
  return _MD_ORIGIN_OVERRIDE;
}

/// Human name of a provenance code ("primary", "override", "unknown").
pub fn md_origin_name(origin: Int) -> Str {
  if origin == _MD_ORIGIN_PRIMARY {
    return "primary";
  }
  if origin == _MD_ORIGIN_OVERRIDE {
    return "override";
  }
  return "unknown";
}

/// Diff kind "added" (present only in the right block).
pub fn md_kind_added() -> Int {
  return _MD_KIND_ADDED;
}

/// Diff kind "removed" (present only in the left block).
pub fn md_kind_removed() -> Int {
  return _MD_KIND_REMOVED;
}

/// Diff kind "changed" (present in both, different raw values).
pub fn md_kind_changed() -> Int {
  return _MD_KIND_CHANGED;
}

/// Human name of a diff kind code ("added", "removed", "changed",
/// "unknown").
pub fn md_kind_name(kind: Int) -> Str {
  if kind == _MD_KIND_ADDED {
    return "added";
  }
  if kind == _MD_KIND_REMOVED {
    return "removed";
  }
  if kind == _MD_KIND_CHANGED {
    return "changed";
  }
  return "unknown";
}

/// Validation code for a valid (section, key, value) triple.
pub fn md_val_ok() -> Int {
  return _MD_VAL_OK;
}

/// Validation code for an invalid section path.
pub fn md_val_bad_section() -> Int {
  return _MD_VAL_BAD_SECTION;
}

/// Validation code for an invalid key.
pub fn md_val_bad_key() -> Int {
  return _MD_VAL_BAD_KEY;
}

/// Validation code for an invalid value.
pub fn md_val_bad_value() -> Int {
  return _MD_VAL_BAD_VALUE;
}

/// Human name of a validation code ("ok", "invalid-section",
/// "invalid-key", "invalid-value", "unknown").
pub fn md_val_name(code: Int) -> Str {
  if code == _MD_VAL_OK {
    return "ok";
  }
  if code == _MD_VAL_BAD_SECTION {
    return "invalid-section";
  }
  if code == _MD_VAL_BAD_KEY {
    return "invalid-key";
  }
  if code == _MD_VAL_BAD_VALUE {
    return "invalid-value";
  }
  return "unknown";
}

// --------------------------------------------------
//  Case folding and Str primitives
// --------------------------------------------------

/// Fold a section path or key for identity comparison: bytes A-Z are
/// lowercased, every other byte (including UTF-8 continuation bytes) is
/// kept verbatim. Deterministic and table-free.
pub fn md_fold_key(k: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < k.len() {
    let b = string.byte_at(k, i);
    if b >= 65u8 && b <= 90u8 {
      out.push(b + 32u8);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Folded Str equality through str_compare (BUG 17).
fn _streq_fold(a: Str, b: Str) -> Bool {
  return compare.str_compare(md_fold_key(a), md_fold_key(b)) == 0;
}

// The canonical dotted rendering of one entry path: `section.key`, or just
// `key` for a root entry.
fn _qualified(section: Str, key: Str) -> Str {
  if section.len() == 0 {
    return key;
  }
  return section + "." + key;
}

// --------------------------------------------------
//  Pool mechanics
// --------------------------------------------------

// String i of a Str pool (`data` plus end offsets `ends`).
fn _mp_get(data: Str, ends: &Vec[Int], i: Int) -> Str {
  let end: Int = ends[i];
  var start = 0;
  if i > 0 {
    let prev: Int = ends[i - 1];
    start = prev;
  }
  return string.str_slice(data, start, end);
}

// Append one aligned entry. The three pools and the provenance track grow
// together, so they can never drift apart.
fn _mb_push(m: &mut MetaBlock, section: Str, key: Str, value: Str, origin: Int) {
  m.sec_data = m.sec_data + section;
  m.key_data = m.key_data + key;
  m.val_data = m.val_data + value;
  let sl = m.sec_data.len();
  let kl = m.key_data.len();
  let vl = m.val_data.len();
  m.sec_end.push(sl);
  m.key_end.push(kl);
  m.val_end.push(vl);
  m.origin.push(origin);
}

// Replace the value (and provenance) of entry idx in place; the section,
// key and position are untouched, so the insertion order is stable.
fn _mb_patch(m: &mut MetaBlock, idx: Int, value: Str, origin: Int) {
  var nd = "";
  var ne = Vec[Int].new();
  var i = 0;
  while i < m.val_end.len() {
    var cur = _mp_get(m.val_data, &m.val_end, i);
    if i == idx {
      cur = value;
    }
    nd = nd + cur;
    let l = nd.len();
    ne.push(l);
    i = i + 1;
  }
  m.val_data = nd;
  m.val_end.clear();
  var q = 0;
  while q < ne.len() {
    let e: Int = ne[q];
    m.val_end.push(e);
    q = q + 1;
  }
  if idx >= 0 && idx < m.origin.len() {
    m.origin[idx] = origin;
  }
}

// Index of the first entry whose folded (section, key) pair matches, or -1.
fn _mb_find(m: &MetaBlock, section: Str, key: Str) -> Int {
  let fs = md_fold_key(section);
  let fk = md_fold_key(key);
  var i = 0;
  while i < m.key_end.len() {
    let s = _mp_get(m.sec_data, &m.sec_end, i);
    let k = _mp_get(m.key_data, &m.key_end, i);
    if compare.str_compare(md_fold_key(s), fs) == 0 {
      if compare.str_compare(md_fold_key(k), fk) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// An empty block with all four tracks at length zero.
fn _mb_empty() -> MetaBlock {
  return MetaBlock{
    sec_data: "";
    sec_end: Vec[Int].new();
    key_data: "";
    key_end: Vec[Int].new();
    val_data: "";
    val_end: Vec[Int].new();
    origin: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Construction and entry access
// --------------------------------------------------

/// An empty block (no entries, no sections).
pub fn md_new() -> MetaBlock {
  return _mb_empty();
}

/// Number of entries in the block.
pub fn md_len(m: &MetaBlock) -> Int {
  return m.key_end.len();
}

/// Section path of entry i ("" is the root scope); "" also when i is out
/// of range.
pub fn md_entry_section(m: &MetaBlock, i: Int) -> Str {
  if i < 0 || i >= m.key_end.len() {
    return "";
  }
  return _mp_get(m.sec_data, &m.sec_end, i);
}

/// Key of entry i; "" also when i is out of range.
pub fn md_entry_key(m: &MetaBlock, i: Int) -> Str {
  if i < 0 || i >= m.key_end.len() {
    return "";
  }
  return _mp_get(m.key_data, &m.key_end, i);
}

/// Value of entry i; "" also when i is out of range.
pub fn md_entry_value(m: &MetaBlock, i: Int) -> Str {
  if i < 0 || i >= m.key_end.len() {
    return "";
  }
  return _mp_get(m.val_data, &m.val_end, i);
}

/// Provenance code of entry i; -1 when i is out of range.
pub fn md_entry_origin(m: &MetaBlock, i: Int) -> Int {
  if i < 0 || i >= m.origin.len() {
    return -1;
  }
  let o: Int = m.origin[i];
  return o;
}

// --------------------------------------------------
//  Lookup
// --------------------------------------------------

/// Index of the entry for (section, key) under ASCII-case-folded identity,
/// or -1 when absent. The first match wins (blocks should not contain
/// duplicates; md_first_duplicate detects them).
pub fn md_index(m: &MetaBlock, section: Str, key: Str) -> Int {
  return _mb_find(m, section, key);
}

/// True when the block contains the (section, key) pair.
pub fn md_has(m: &MetaBlock, section: Str, key: Str) -> Bool {
  return _mb_find(m, section, key) >= 0;
}

/// Value of the (section, key) pair, or None when absent. Lookup is
/// case-insensitive on ASCII letters in both the section path and the key.
pub fn md_get(m: &MetaBlock, section: Str, key: Str) -> Option[Str] {
  let idx = _mb_find(m, section, key);
  if idx < 0 {
    return None;
  }
  let v = _mp_get(m.val_data, &m.val_end, idx);
  return Some(v);
}

/// Provenance code of the (section, key) pair, or None when absent.
pub fn md_origin(m: &MetaBlock, section: Str, key: Str) -> Option[Int] {
  let idx = _mb_find(m, section, key);
  if idx < 0 {
    return None;
  }
  let o: Int = m.origin[idx];
  return Some(o);
}

// --------------------------------------------------
//  Policy-driven assignment
// --------------------------------------------------

/// Apply one assignment (section, key) = value under `policy` and return
/// the resulting block; the input is never modified.
/// Policies: md_dup_first keeps the existing value and position,
/// md_dup_last replaces the value in place, md_dup_error fails with
/// "metadata: duplicate key: <section.key>". A new pair is appended with
/// provenance md_origin_primary. An unknown policy code fails with
/// "metadata: unknown duplicate policy: <n>". Arguments are stored
/// verbatim; call md_validate to check them.
pub fn md_set(m: &MetaBlock, section: Str, key: Str, value: Str, policy: Int) -> Result[MetaBlock, Str] {
  if policy != _MD_DUP_FIRST && policy != _MD_DUP_LAST && policy != _MD_DUP_ERROR {
    return _mb_err("metadata: unknown duplicate policy: " + convert.int_to_string(policy));
  }
  let idx = _mb_find(m, section, key);
  if idx < 0 {
    var out = _mb_copy(m);
    _mb_push(&mut out, section, key, value, _MD_ORIGIN_PRIMARY);
    return _mb_ok(out);
  }
  if policy == _MD_DUP_ERROR {
    return _mb_err("metadata: duplicate key: " + _qualified(section, key));
  }
  if policy == _MD_DUP_FIRST {
    return _mb_ok(_mb_copy(m));
  }
  var out2 = _mb_copy(m);
  _mb_patch(&mut out2, idx, value, _MD_ORIGIN_PRIMARY);
  return _mb_ok(out2);
}

/// Append one entry without any duplicate check, in insertion order, with
/// provenance md_origin_primary. This is the only constructor that can
/// produce a block with repeated folded (section, key) pairs: md_set and
/// md_parse apply an explicit duplicate policy instead. Arguments are
/// stored verbatim; md_first_duplicate detects duplicates in the result.
pub fn md_append(m: &MetaBlock, section: Str, key: Str, value: Str) -> MetaBlock {
  var out = _mb_copy(m);
  _mb_push(&mut out, section, key, value, _MD_ORIGIN_PRIMARY);
  return out;
}

// Deep copy: entries are rebuilt through _mb_push, so the copy owns fresh
// pools and the original is unaffected.
fn _mb_copy(m: &MetaBlock) -> MetaBlock {
  var out = _mb_empty();
  var i = 0;
  while i < m.key_end.len() {
    let s = _mp_get(m.sec_data, &m.sec_end, i);
    let k = _mp_get(m.key_data, &m.key_end, i);
    let v = _mp_get(m.val_data, &m.val_end, i);
    let o: Int = m.origin[i];
    _mb_push(&mut out, s, k, v, o);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Scoping and nesting
// --------------------------------------------------

/// Re-parent the whole block under `prefix`: root entries move to the
/// prefix itself, entries already in a section move to
/// "<prefix>.<section>". An empty prefix returns a copy unchanged, so
/// md_scoped(m, "") is the identity. Nesting is by dotted paths; no other
/// rewriting is done.
pub fn md_scoped(m: &MetaBlock, prefix: Str) -> MetaBlock {
  var out = _mb_empty();
  var i = 0;
  while i < m.key_end.len() {
    let s = md_entry_section(m, i);
    let k = md_entry_key(m, i);
    let v = md_entry_value(m, i);
    let o: Int = m.origin[i];
    var ns = s;
    if prefix.len() > 0 {
      if s.len() == 0 {
        ns = prefix;
      } else {
        ns = prefix + "." + s;
      }
    }
    _mb_push(&mut out, ns, k, v, o);
    i = i + 1;
  }
  return out;
}

/// Extract the sub-block at section path `path` (case-insensitive, exact
/// match): its entries are re-rooted to section "" and keep their order,
/// values and provenance. An unknown path yields an empty block.
pub fn md_subblock(m: &MetaBlock, path: Str) -> MetaBlock {
  var out = _mb_empty();
  var i = 0;
  while i < m.key_end.len() {
    let s = md_entry_section(m, i);
    if _streq_fold(s, path) {
      let k = md_entry_key(m, i);
      let v = md_entry_value(m, i);
      let o: Int = m.origin[i];
      _mb_push(&mut out, "", k, v, o);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Merge
// --------------------------------------------------

/// Merge `over` onto `base` with over-wins precedence per folded
/// (section, key) pair. Result order: all base entries in base order (a
/// base pair keeps its position and spelling), then over-only entries in
/// over order. For a pair present on both sides the base entry keeps its
/// position but takes the over value, key spelling and section spelling
/// already stored (first-seen spelling wins). Provenance describes this
/// merge only: base-supplied values are md_origin_primary, over-supplied
/// values are md_origin_override, even when a side was itself a merge
/// result. Pure: neither input is modified.
pub fn md_merge(base: &MetaBlock, over: &MetaBlock) -> MetaBlock {
  var out = _mb_empty();
  var i = 0;
  while i < base.key_end.len() {
    let s = _mp_get(base.sec_data, &base.sec_end, i);
    let k = _mp_get(base.key_data, &base.key_end, i);
    let v = _mp_get(base.val_data, &base.val_end, i);
    _mb_push(&mut out, s, k, v, _MD_ORIGIN_PRIMARY);
    i = i + 1;
  }
  var j = 0;
  while j < over.key_end.len() {
    let s2 = _mp_get(over.sec_data, &over.sec_end, j);
    let k2 = _mp_get(over.key_data, &over.key_end, j);
    let v2 = _mp_get(over.val_data, &over.val_end, j);
    let idx = _mb_find(&out, s2, k2);
    if idx < 0 {
      _mb_push(&mut out, s2, k2, v2, _MD_ORIGIN_OVERRIDE);
    } else {
      _mb_patch(&mut out, idx, v2, _MD_ORIGIN_OVERRIDE);
    }
    j = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Validation
// --------------------------------------------------

// One key/section-segment byte: above space, and not a dot, '=', '[', ']',
// '#', or ';'. Bytes >= 128 (UTF-8) are allowed and kept byte-exact.
fn _key_byte_ok(b: UInt8) -> Bool {
  if b <= _MD_SPACE {
    return false;
  }
  if b == _MD_DOT || b == _MD_EQ {
    return false;
  }
  if b == _MD_LBRACKET || b == _MD_RBRACKET {
    return false;
  }
  if b == _MD_HASH || b == _MD_SEMI {
    return false;
  }
  return true;
}

/// True when `k` is a valid key: non-empty and every byte passes the
/// segment rule (no dot, so a key is one segment).
pub fn md_key_valid(k: Str) -> Bool {
  if k.len() == 0 {
    return false;
  }
  var i = 0;
  while i < k.len() {
    let b = string.byte_at(k, i);
    if !_key_byte_ok(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when `s` is a valid section path: the empty path (root scope) or
/// one or more dot-separated segments, each non-empty with bytes passing
/// the segment rule. Leading, trailing and doubled dots are invalid.
pub fn md_section_valid(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return true;
  }
  var prev_dot = true;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _MD_DOT {
      if prev_dot {
        return false;
      }
      prev_dot = true;
    } else {
      if !_key_byte_ok(b) {
        return false;
      }
      prev_dot = false;
    }
    i = i + 1;
  }
  if prev_dot {
    return false;
  }
  return true;
}

/// True when `v` is a valid value: any bytes except NUL, LF and CR, and no
/// leading or trailing space/TAB. These restrictions make every valid value
/// survive the canonical `key = value` round trip byte-exact.
pub fn md_value_valid(v: Str) -> Bool {
  let n = v.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(v, i);
    if b == _MD_NUL || b == _MD_LF || b == _MD_CR {
      return false;
    }
    i = i + 1;
  }
  if n > 0 {
    let first = string.byte_at(v, 0);
    let last = string.byte_at(v, n - 1);
    if first == _MD_SPACE || first == _MD_TAB {
      return false;
    }
    if last == _MD_SPACE || last == _MD_TAB {
      return false;
    }
  }
  return true;
}

/// Validation code of a triple: md_val_ok, md_val_bad_section,
/// md_val_bad_key or md_val_bad_value (first failure wins, in that order).
pub fn md_validate_code(section: Str, key: Str, value: Str) -> Int {
  if !md_section_valid(section) {
    return _MD_VAL_BAD_SECTION;
  }
  if !md_key_valid(key) {
    return _MD_VAL_BAD_KEY;
  }
  if !md_value_valid(value) {
    return _MD_VAL_BAD_VALUE;
  }
  return _MD_VAL_OK;
}

/// Pinned message for a triple: "" when valid, else
/// "metadata: invalid section: <section>",
/// "metadata: invalid key: <key>" or
/// "metadata: invalid value: <value>".
pub fn md_validate_message(section: Str, key: Str, value: Str) -> Str {
  let code = md_validate_code(section, key, value);
  if code == _MD_VAL_BAD_SECTION {
    return "metadata: invalid section: " + section;
  }
  if code == _MD_VAL_BAD_KEY {
    return "metadata: invalid key: " + key;
  }
  if code == _MD_VAL_BAD_VALUE {
    return "metadata: invalid value: " + value;
  }
  return "";
}

/// Validate every entry in insertion order; "" when all entries are valid,
/// else the first failure message. Duplicates are not a lexical error; see
/// md_first_duplicate.
pub fn md_validate(m: &MetaBlock) -> Str {
  var i = 0;
  while i < m.key_end.len() {
    let s = md_entry_section(m, i);
    let k = md_entry_key(m, i);
    let v = md_entry_value(m, i);
    let msg = md_validate_message(s, k, v);
    if msg.len() > 0 {
      return msg;
    }
    i = i + 1;
  }
  return "";
}

/// Index of the first entry whose folded (section, key) pair was already
/// seen at a lower index, or -1 when the block has no duplicates. The
/// returned entry is the later occurrence.
pub fn md_first_duplicate(m: &MetaBlock) -> Int {
  var i = 1;
  while i < m.key_end.len() {
    let si = md_entry_section(m, i);
    let ki = md_entry_key(m, i);
    var j = 0;
    while j < i {
      let sj = md_entry_section(m, j);
      let kj = md_entry_key(m, j);
      if _streq_fold(si, sj) {
        if _streq_fold(ki, kj) {
          return i;
        }
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Serialization
// --------------------------------------------------

// Canonical line of entry i: `section.key = value`, or `key = value` for a
// root entry. Values are written verbatim.
fn _entry_line(m: &MetaBlock, i: Int) -> Str {
  let s = md_entry_section(m, i);
  let k = md_entry_key(m, i);
  let v = md_entry_value(m, i);
  return _qualified(s, k) + " = " + v;
}

// True when entry i sorts strictly before entry j: folded section, then
// folded key, then insertion order (stable).
fn _entry_less(m: &MetaBlock, i: Int, j: Int) -> Bool {
  let si = md_fold_key(md_entry_section(m, i));
  let sj = md_fold_key(md_entry_section(m, j));
  let c = compare.str_compare(si, sj);
  if c < 0 {
    return true;
  }
  if c > 0 {
    return false;
  }
  let ki = md_fold_key(md_entry_key(m, i));
  let kj = md_fold_key(md_entry_key(m, j));
  return compare.str_compare(ki, kj) < 0;
}

/// Canonical text in insertion order: one `section.key = value` line per
/// entry, LF separated, no trailing LF. An empty block emits "". Every
/// valid block round-trips exactly through md_parse (see SPEC.md).
pub fn md_serialize(m: &MetaBlock) -> Str {
  var out = "";
  var i = 0;
  while i < m.key_end.len() {
    if i > 0 {
      out = out + "\n";
    }
    out = out + _entry_line(m, i);
    i = i + 1;
  }
  return out;
}

/// Canonical text sorted by folded section then folded key (ties keep
/// insertion order); same line shape as md_serialize. Duplicate pairs make
/// the order depend on the stable tie rule.
pub fn md_serialize_sorted(m: &MetaBlock) -> Str {
  let n = m.key_end.len();
  var used = Vec[Int].new();
  var i = 0;
  while i < n {
    used.push(0);
    i = i + 1;
  }
  var out = "";
  var emitted = 0;
  while emitted < n {
    var best = -1;
    var j = 0;
    while j < n {
      let u: Int = used[j];
      if u == 0 {
        if best < 0 {
          best = j;
        } else {
          if _entry_less(m, j, best) {
            best = j;
          }
        }
      }
      j = j + 1;
    }
    if best < 0 {
      emitted = n;
    } else {
      used[best] = 1;
      if emitted > 0 {
        out = out + "\n";
      }
      out = out + _entry_line(m, best);
      emitted = emitted + 1;
    }
  }
  return out;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Byte index of the first '=' in `s`, or -1.
fn _find_eq(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) == _MD_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Byte index of the last '.' in `s`, or -1.
fn _last_dot(s: Str) -> Int {
  var last = -1;
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) == _MD_DOT {
      last = i;
    }
    i = i + 1;
  }
  return last;
}

/// Parse canonical text into a block.
/// Params: text - LF or CRLF separated lines; policy - one of md_dup_first,
/// md_dup_last, md_dup_error applied to repeated folded (section, key)
/// pairs.
/// Grammar: blank lines and full-line '#'/';' comments are skipped; every
/// other line must contain '='; the left side is trimmed, then the last dot
/// splits section from key (no dot = root scope); the right side is trimmed
/// into the value. Every line is validated, so invalid sections, keys and
/// values fail with the pinned messages. With md_dup_error a repeated pair
/// fails; with md_dup_first the first value wins; with md_dup_last the last
/// value wins in place.
/// Returns: Ok(MetaBlock) or Err("metadata: ...").
/// Complexity: O(lines * entries * line length) because duplicate detection
/// scans the block per line; O(total input length) with a hash index.
pub fn md_parse(text: Str, policy: Int) -> Result[MetaBlock, Str] {
  if policy != _MD_DUP_FIRST && policy != _MD_DUP_LAST && policy != _MD_DUP_ERROR {
    return _mb_err("metadata: unknown duplicate policy: " + convert.int_to_string(policy));
  }
  var out = _mb_empty();
  var bad = "";
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len && bad.len() == 0 {
    if i == len || string.byte_at(text, i) == _MD_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _MD_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let trimmed = string.str_trim(line);
      let n = trimmed.len();
      if n > 0 {
        let b0 = string.byte_at(trimmed, 0);
        if b0 != _MD_HASH && b0 != _MD_SEMI {
          let eq = _find_eq(trimmed);
          if eq < 0 {
            bad = "metadata: expected '=' in line: " + trimmed;
          } else {
            let lhs = string.str_trim(string.str_slice(trimmed, 0, eq));
            let value = string.str_trim(string.str_slice(trimmed, eq + 1, n));
            if lhs.len() == 0 {
              bad = "metadata: empty key in line: " + trimmed;
            } else {
              var section = "";
              var key = lhs;
              let dot = _last_dot(lhs);
              if dot >= 0 {
                section = string.str_slice(lhs, 0, dot);
                key = string.str_slice(lhs, dot + 1, lhs.len());
              }
              if dot >= 0 && section.len() == 0 {
                bad = "metadata: invalid section: " + section;
              } else if !md_section_valid(section) {
                bad = "metadata: invalid section: " + section;
              } else if key.len() == 0 {
                bad = "metadata: empty key in line: " + trimmed;
              } else if !md_key_valid(key) {
                bad = "metadata: invalid key: " + key;
              } else if !md_value_valid(value) {
                bad = "metadata: invalid value: " + value;
              } else {
                let idx = _mb_find(&out, section, key);
                if idx >= 0 {
                  if policy == _MD_DUP_ERROR {
                    bad = "metadata: duplicate key: " + _qualified(section, key);
                  } else if policy == _MD_DUP_LAST {
                    _mb_patch(&mut out, idx, value, _MD_ORIGIN_PRIMARY);
                  }
                } else {
                  _mb_push(&mut out, section, key, value, _MD_ORIGIN_PRIMARY);
                }
              }
            }
          }
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  if bad.len() > 0 {
    return _mb_err(bad);
  }
  return _mb_ok(out);
}

// --------------------------------------------------
//  Diff
// --------------------------------------------------

/// Diff `left` against `right` over folded (section, key) identity:
/// added = pairs only in right (right order, right spelling and value);
/// removed = pairs only in left (left order, left spelling and value);
/// changed = pairs in both whose raw values differ (left order; changed
/// carries the left value, changed_new the aligned right value). Value
/// comparison is byte-exact and case-sensitive; keys and sections are
/// case-insensitive. Pure: neither input is modified.
pub fn md_diff(left: &MetaBlock, right: &MetaBlock) -> MetaDiff {
  var added = _mb_empty();
  var removed = _mb_empty();
  var changed = _mb_empty();
  var changed_new = _mb_empty();
  var j = 0;
  while j < right.key_end.len() {
    let s = _mp_get(right.sec_data, &right.sec_end, j);
    let k = _mp_get(right.key_data, &right.key_end, j);
    let v = _mp_get(right.val_data, &right.val_end, j);
    let idx = _mb_find(left, s, k);
    if idx < 0 {
      _mb_push(&mut added, s, k, v, _MD_ORIGIN_PRIMARY);
    } else {
      let lv = md_entry_value(left, idx);
      if compare.str_compare(lv, v) != 0 {
        _mb_push(&mut changed, s, k, lv, _MD_ORIGIN_PRIMARY);
        _mb_push(&mut changed_new, s, k, v, _MD_ORIGIN_PRIMARY);
      }
    }
    j = j + 1;
  }
  var i = 0;
  while i < left.key_end.len() {
    let s2 = _mp_get(left.sec_data, &left.sec_end, i);
    let k2 = _mp_get(left.key_data, &left.key_end, i);
    let v2 = _mp_get(left.val_data, &left.val_end, i);
    if _mb_find(right, s2, k2) < 0 {
      _mb_push(&mut removed, s2, k2, v2, _MD_ORIGIN_PRIMARY);
    }
    i = i + 1;
  }
  return MetaDiff{ added: added; removed: removed; changed: changed; changed_new: changed_new; };
}

/// Number of entries of `kind` (md_kind_added/removed/changed) in the
/// diff; 0 for an unknown kind.
pub fn md_diff_len(d: &MetaDiff, kind: Int) -> Int {
  if kind == _MD_KIND_ADDED {
    return d.added.key_end.len();
  }
  if kind == _MD_KIND_REMOVED {
    return d.removed.key_end.len();
  }
  if kind == _MD_KIND_CHANGED {
    return d.changed.key_end.len();
  }
  return 0;
}

/// Section path of diff entry (kind, i); "" when the kind or index is out
/// of range.
pub fn md_diff_section(d: &MetaDiff, kind: Int, i: Int) -> Str {
  if kind == _MD_KIND_ADDED {
    return md_entry_section(&d.added, i);
  }
  if kind == _MD_KIND_REMOVED {
    return md_entry_section(&d.removed, i);
  }
  if kind == _MD_KIND_CHANGED {
    return md_entry_section(&d.changed, i);
  }
  return "";
}

/// Key of diff entry (kind, i); "" when the kind or index is out of range.
pub fn md_diff_key(d: &MetaDiff, kind: Int, i: Int) -> Str {
  if kind == _MD_KIND_ADDED {
    return md_entry_key(&d.added, i);
  }
  if kind == _MD_KIND_REMOVED {
    return md_entry_key(&d.removed, i);
  }
  if kind == _MD_KIND_CHANGED {
    return md_entry_key(&d.changed, i);
  }
  return "";
}

/// Value of diff entry (kind, i): for added the right value, for removed
/// the left value, for changed the left (old) value; "" when out of range.
pub fn md_diff_value(d: &MetaDiff, kind: Int, i: Int) -> Str {
  if kind == _MD_KIND_ADDED {
    return md_entry_value(&d.added, i);
  }
  if kind == _MD_KIND_REMOVED {
    return md_entry_value(&d.removed, i);
  }
  if kind == _MD_KIND_CHANGED {
    return md_entry_value(&d.changed, i);
  }
  return "";
}

/// Right (new) value aligned with changed entry i; "" when out of range.
pub fn md_diff_new_value(d: &MetaDiff, i: Int) -> Str {
  return md_entry_value(&d.changed_new, i);
}

/// Canonical one-line-per-entry report, added lines first, then removed,
/// then changed, each in diff order: "+ section.key = value",
/// "- section.key = value", "~ section.key = old -> new". An empty diff
/// renders as "".
pub fn md_diff_render(d: &MetaDiff) -> Str {
  var out = "";
  var written = 0;
  var i = 0;
  while i < d.added.key_end.len() {
    if written > 0 {
      out = out + "\n";
    }
    out = out + "+ " + _entry_line(&d.added, i);
    written = written + 1;
    i = i + 1;
  }
  i = 0;
  while i < d.removed.key_end.len() {
    if written > 0 {
      out = out + "\n";
    }
    out = out + "- " + _entry_line(&d.removed, i);
    written = written + 1;
    i = i + 1;
  }
  i = 0;
  while i < d.changed.key_end.len() {
    if written > 0 {
      out = out + "\n";
    }
    let nw = md_entry_value(&d.changed_new, i);
    out = out + "~ " + _entry_line(&d.changed, i) + " -> " + nw;
    written = written + 1;
    i = i + 1;
  }
  return out;
}
