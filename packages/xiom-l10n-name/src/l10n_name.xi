// XIOM -- xiom.l10n.name: locale-style personal-name display ordering, list
// formatting, initials and caller-supplied honorific resolution.
// Port task: replace the xiom.l10n.name placeholder with a pure-XIOM module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a personal name is five Str fields (prefix, given, middle, family,
// suffix) where "" is the documented "absent" sentinel and every part is used
// verbatim. There is no locale database and no global state: the caller
// passes a locale tag and the module decides display order from the fixed
// family-first set {zh, ja, ko, hu}, matched on the primary subtag
// (case-insensitively), with the given-first order as the default fallback.
// Name lists are carried as parallel Str vectors (NameList) so no
// Vec[StructType] is needed, and honorific lookup uses a caller-supplied
// parallel (key, title) table.
//
// Out of scope: transliteration or script conversion of any kind, parsing
// names from free text, built-in title/degree tables (the caller supplies
// them), locale collation, and any use of Float64, FFI or I/O.
//
// Compiler discipline (v0.62.0): free functions only; no Str `==` (every
// string decision goes through compare.str_compare on typed locals); typed
// Vec[Str] reads; parallel Vec pushes in lockstep; UInt8 comparisons stay
// below 128 and every >= 128 test widens to Int and masks with % 256.

module xiom.l10n.name

use xiom.string;
use xiom.convert;
use xiom.string.compare;

const _LN_DASH: UInt8 = 45u8;
const _LN_UNDERSCORE: UInt8 = 95u8;

/// One personal name. Every field is a Str and "" is the documented "absent"
/// sentinel; parts are used verbatim (never trimmed). Field roles: prefix
/// (e.g. "Dr."), given, middle, family, suffix (e.g. "Jr.").
pub type PersonName = {
  prefix: Str;
  given: Str;
  middle: Str;
  family: Str;
  suffix: Str;
}

/// A list of personal names as five parallel Vec[Str] vectors. Invariant:
/// prefixes[i], givens[i], middles[i], families[i] and suffixes[i] describe
/// the i-th name, so all five vectors always have the same length; build
/// lists with name_list_new/name_list_push, which push in lockstep.
pub type NameList = {
  prefixes: Vec[Str];
  givens: Vec[Str];
  middles: Vec[Str];
  families: Vec[Str];
  suffixes: Vec[Str];
}

/// A caller-supplied honorific table: keys[i] maps to titles[i]. Lookup is
/// ASCII byte-wise (compare.str_compare) and the first matching key wins.
pub type HonorificTable = {
  keys: Vec[Str];
  titles: Vec[Str];
}

// ---------------------------------------------------------------------------
// Locale classification
// ---------------------------------------------------------------------------

// Primary subtag: the text before the first '-' or '_' (whole tag when
// neither byte occurs). Byte tests stay below 128.
fn _primary_subtag(locale: Str) -> Str {
  let n = locale.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(locale, i);
    if b == _LN_DASH { return string.str_slice(locale, 0, i); }
    if b == _LN_UNDERSCORE { return string.str_slice(locale, 0, i); }
    i = i + 1;
  }
  return locale;
}

// Normalized locale key: lowercased primary subtag, so "zh-Hans", "zh_CN",
// "ZH" and "zh" all normalize to "zh"; "" stays "".
fn _norm_locale(locale: Str) -> Str {
  return string.str_lower(_primary_subtag(locale));
}

/// True when `locale` is in the family-first set {zh, ja, ko, hu}.
/// Params: locale - the locale tag, matched on its primary subtag
/// (text before the first '-' or '_'), ASCII case-insensitively.
/// Returns: Bool; "" and every other tag (including unknown tags) are false,
/// which selects the given-first default.
/// Error case: none.
/// Complexity: O(len(locale)).
pub fn name_is_family_first_locale(locale: Str) -> Bool {
  let p = _norm_locale(locale);
  if compare.str_compare(p, "zh") == 0 { return true; }
  if compare.str_compare(p, "ja") == 0 { return true; }
  if compare.str_compare(p, "ko") == 0 { return true; }
  if compare.str_compare(p, "hu") == 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// Part joining
// ---------------------------------------------------------------------------

// Join two parts with one space when both are non-empty; an empty part is
// absent and contributes nothing.
fn _join2(a: Str, b: Str) -> Str {
  if a.len() == 0 { return b; }
  if b.len() == 0 { return a; }
  return a + " " + b;
}

fn _join4(a: Str, b: Str, c: Str, d: Str) -> Str {
  return _join2(_join2(_join2(a, b), c), d);
}

fn _join5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Str {
  return _join2(_join4(a, b, c, d), e);
}

// ---------------------------------------------------------------------------
// Display ordering
// ---------------------------------------------------------------------------

/// Render one name for display in a locale.
/// Params: locale - the locale tag; name - the five parts.
/// Order: family-first locales (zh, ja, ko, hu) place the parts as
/// prefix, family, given, suffix; every other locale (the default, and the
/// fallback for unknown tags) places prefix, given, middle, family, suffix.
/// The given-first middle part is not placed in family-first order (v0.1.0
/// rule; see SPEC.md). Only non-empty parts are joined, with single spaces.
/// Returns: the display string; "" when all five parts are empty.
/// Error case: none.
/// Complexity: O(total part length).
pub fn name_display(locale: Str, name: &PersonName) -> Str {
  let prefix: Str = name.prefix;
  let given: Str = name.given;
  let middle: Str = name.middle;
  let family: Str = name.family;
  let suffix: Str = name.suffix;
  if name_is_family_first_locale(locale) {
    return _join4(prefix, family, given, suffix);
  }
  return _join5(prefix, given, middle, family, suffix);
}

/// Family-first sort key for one name, for use with byte-wise
/// compare.str_compare ordering.
/// Params: locale - accepted for interface symmetry and reserved for future
/// locale collation; v0.1.0 returns the same key for every locale.
/// name - the five parts.
/// Returns: the non-empty parts joined with single spaces in the order
/// family, given, middle, prefix, suffix; an absent family yields a key that
/// starts with the next present part. A plain lexicographic sort of these
/// keys orders names by family name first. This is a byte-wise key, not a
/// locale collation key.
/// Error case: none.
/// Complexity: O(total part length).
pub fn name_sort_key(locale: Str, name: &PersonName) -> Str {
  let prefix: Str = name.prefix;
  let given: Str = name.given;
  let middle: Str = name.middle;
  let family: Str = name.family;
  let suffix: Str = name.suffix;
  let key = _join5(family, given, middle, prefix, suffix);
  return key;
}

// ---------------------------------------------------------------------------
// Initials
// ---------------------------------------------------------------------------

// Byte length of the first UTF-8 character of s, from its leading byte:
// 0x00..0x7F -> 1, 0xC0..0xDF -> 2, 0xE0..0xEF -> 3, 0xF0..0xFF -> 4, and a
// lone continuation byte (0x80..0xBF, malformed as a leading byte) -> 1.
// The UInt8 is widened to Int and masked with % 256 before any >= 128 test.
fn _first_char_len(s: Str) -> Int {
  let n = s.len();
  if n == 0 { return 0; }
  let b0 = string.byte_at(s, 0);
  let w = ((b0 as Int) % 256);
  if w < 128 { return 1; }
  if w < 192 { return 1; }
  if w < 224 { return 2; }
  if w < 240 { return 3; }
  return 4;
}

// First UTF-8 character of s as a Str ("" for ""), clamped to s.len() so a
// truncated final character is returned as its available bytes.
fn _first_char(s: Str) -> Str {
  let n = s.len();
  if n == 0 { return ""; }
  var k = _first_char_len(s);
  if k > n { k = n; }
  return string.str_slice(s, 0, k);
}

// One initial: the first character of the part, uppercased by xiom.string,
// followed by ".".
fn _initial_of(part: Str) -> Str {
  return string.str_upper(_first_char(part)) + ".";
}

/// Initials of the given and middle parts, in that order, "J." style.
/// Params: given - the given-name part; middle - the middle-name part.
/// Rules: each non-empty part contributes its first Unicode character,
/// uppercased when the character has an uppercase form, plus ".". Initials
/// are joined with a single space. Non-letter first characters (digits,
/// punctuation, CJK ideographs) are used as-is: no transliteration.
/// Returns: e.g. ("John", "Paul") -> "J. P."; ("John", "") -> "J.";
/// ("", "") -> "".
/// Error case: none.
/// Complexity: O(1) plus the bytes of the first character.
pub fn name_initials_of(given: Str, middle: Str) -> Str {
  var out = "";
  if given.len() > 0 {
    out = _initial_of(given);
  }
  if middle.len() > 0 {
    if out.len() > 0 { out = out + " "; }
    out = out + _initial_of(middle);
  }
  return out;
}

/// Initials of a name's given and middle parts ("J. P." style).
/// Params: name - the five parts; only given and middle are used.
/// Returns: name_initials_of(given, middle); "" when both are empty.
/// Error case: none.
/// Complexity: O(1) plus the bytes of the first characters.
pub fn name_initials(name: &PersonName) -> Str {
  let g: Str = name.given;
  let m: Str = name.middle;
  return name_initials_of(g, m);
}

// ---------------------------------------------------------------------------
// Honorifics
// ---------------------------------------------------------------------------

/// An empty honorific table. Use honorific_table_push to fill it; keys and
/// titles are kept in lockstep.
pub fn honorific_table_new() -> HonorificTable {
  let t = HonorificTable{ keys: Vec[Str].new(); titles: Vec[Str].new() };
  return t;
}

/// Append one (key, title) pair, pushing to both parallel vectors in one
/// place so they never drift apart.
pub fn honorific_table_push(table: &mut HonorificTable, key: Str, title: Str) {
  table.keys.push(key);
  table.titles.push(title);
}

/// Resolve a caller-supplied honorific key to its title.
/// Params: table - the (key, title) pair table; key - the lookup key,
/// compared byte-wise with compare.str_compare.
/// Returns: the first title whose key equals `key`; "" when `key` is empty
/// or no key matches. When the table is ragged (titles shorter than keys)
/// the shorter vector bounds the search. No built-in title table exists:
/// locale-appropriateness is entirely the caller's choice of pairs.
/// Error case: none.
/// Complexity: O(number of pairs * key length).
pub fn name_honorific(table: &HonorificTable, key: Str) -> Str {
  if key.len() == 0 { return ""; }
  let ks: Vec[Str] = table.keys;
  let ts: Vec[Str] = table.titles;
  var n = ks.len();
  if ts.len() < n { n = ts.len(); }
  var i = 0;
  while i < n {
    let k: Str = ks[i];
    if compare.str_compare(k, key) == 0 {
      let t: Str = ts[i];
      return t;
    }
    i = i + 1;
  }
  return "";
}

// ---------------------------------------------------------------------------
// Name lists
// ---------------------------------------------------------------------------

/// An empty name list. Use name_list_push to append names.
pub fn name_list_new() -> NameList {
  let l = NameList{ prefixes: Vec[Str].new(); givens: Vec[Str].new(); middles: Vec[Str].new(); families: Vec[Str].new(); suffixes: Vec[Str].new() };
  return l;
}

/// Append one name, pushing all five parts in lockstep so the parallel
/// vectors keep the documented same-length invariant.
pub fn name_list_push(list: &mut NameList, name: &PersonName) {
  let a: Str = name.prefix;
  list.prefixes.push(a);
  let b: Str = name.given;
  list.givens.push(b);
  let c: Str = name.middle;
  list.middles.push(c);
  let d: Str = name.family;
  list.families.push(d);
  let e: Str = name.suffix;
  list.suffixes.push(e);
}

/// Number of names in a NameList (the shared length of its five vectors).
pub fn name_list_len(list: &NameList) -> Int {
  let g: Vec[Str] = list.givens;
  return g.len();
}

// One part of the i-th name, or "" when i is outside the vector.
fn _vec_at(v: &Vec[Str], i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.len() { return ""; }
  let s: Str = v[i];
  return s;
}

// Display string of the i-th name; every vector read is bounds-checked.
fn _list_display_at(locale: Str, list: &NameList, i: Int) -> Str {
  let ps: Vec[Str] = list.prefixes;
  let gs: Vec[Str] = list.givens;
  let ms: Vec[Str] = list.middles;
  let fs: Vec[Str] = list.families;
  let ss: Vec[Str] = list.suffixes;
  let a: Str = _vec_at(&ps, i);
  let b: Str = _vec_at(&gs, i);
  let c: Str = _vec_at(&ms, i);
  let d: Str = _vec_at(&fs, i);
  let e: Str = _vec_at(&ss, i);
  let p = PersonName{ prefix: a; given: b; middle: c; family: d; suffix: e };
  return name_display(locale, &p);
}

// List style id: 0 = default (", " between items and " and " before the last
// one), 1 = zh "、" between items, 2 = ja/ko "・" between items.
fn _list_style(locale: Str) -> Int {
  let p = _norm_locale(locale);
  if compare.str_compare(p, "zh") == 0 { return 1; }
  if compare.str_compare(p, "ja") == 0 { return 2; }
  if compare.str_compare(p, "ko") == 0 { return 2; }
  return 0;
}

/// Render a list of names for display in a locale.
/// Params: locale - the locale tag; names - the list, built with
/// name_list_new/name_list_push; max_items - truncation bound, where <= 0
/// means "no truncation".
/// Rules: each name is rendered with name_display and names that render as
/// "" are skipped. The default style joins shown items with ", " and puts
/// " and " before the last one ("A, B and C"; two items: "A and B"); zh joins
/// with "、" and ja/ko join with "・", with no special last-item word. When
/// max_items > 0 and the list holds more than max_items names, only the
/// first max_items are considered and "…" is appended to the joined text.
/// Returns: the joined string; "" when nothing renders non-empty (even when
/// truncated).
/// Error case: none.
/// Complexity: O(names * part length).
pub fn name_display_list(locale: Str, names: &NameList, max_items: Int) -> Str {
  let count = name_list_len(names);
  var limit = count;
  var truncated = false;
  if max_items > 0 && max_items < count {
    limit = max_items;
    truncated = true;
  }
  var shown = 0;
  var i = 0;
  while i < limit {
    let d = _list_display_at(locale, names, i);
    if d.len() > 0 { shown = shown + 1; }
    i = i + 1;
  }
  if shown == 0 { return ""; }
  let style = _list_style(locale);
  var out = "";
  var pos = 0;
  var j = 0;
  while j < limit {
    let d = _list_display_at(locale, names, j);
    if d.len() > 0 {
      if pos > 0 {
        if style == 0 {
          if pos == shown - 1 && !truncated { out = out + " and "; } else { out = out + ", "; }
        } elif style == 1 {
          out = out + "、";
        } else {
          out = out + "・";
        }
      }
      out = out + d;
      pos = pos + 1;
    }
    j = j + 1;
  }
  if truncated { out = out + "…"; }
  return out;
}
