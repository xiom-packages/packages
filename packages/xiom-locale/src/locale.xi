// XIOM -- xiom.locale: BCP-47 language tag parsing, canonicalization, RFC 4647
// lookup matching and fallback chains, and a small static language registry.
// Port task: replace the xiom.locale placeholder with a pure-XIOM module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a language tag is a sequence of '-'-separated ASCII subtags parsed by
// position into language, script, region, variants, extensions and private
// use. Nothing here uses FFI, file I/O, floating point, locale databases or
// global state; the module depends only on xiom.string, xiom.string.builder,
// xiom.string.compare and xiom.convert from xiom.std.
//
// Grammar accepted by locale_parse (the "langtag" production of RFC 5646
// 2.1 with the extlang production dropped; full statement in SPEC.md):
//   tag        = langtag / privateuse
//   langtag    = language ["-" script] ["-" region] *("-" variant)
//                *("-" extension) ["-" privateuse]
//   privateuse = "x" 1*("-" 1*8alphanum)
//   language   = 2*8ALPHA
//   script     = 4ALPHA
//   region     = 2ALPHA / 3DIGIT
//   variant    = 5*8alphanum / (DIGIT 3alphanum)
//   extension  = singleton 1*("-" 2*8alphanum)
//   singleton  = alphanum except "x"
//
// Decisions pinned by the conformance suite and SPEC.md:
//   * Subtag order is strict: script before region before variants before
//     extensions before private use. Once a singleton opens an extension,
//     every following non-singleton subtag belongs to that extension, so a
//     region or variant after an extension is rejected (RFC 5646 order).
//   * Casing is normalized during parsing: language/extension/private-use
//     subtags lower, script Titlecase, region upper, variants lower, so
//     locale_to_string(locale_parse(tag)) is the canonical form. No
//     Preferred-Value replacements (iw -> he, sh -> sr-Latn, ...) are
//     applied -- that is likely-subtag territory and out of scope.
//   * Duplicate variants and duplicate extension singletons are rejected.
//   * Str equality goes through str_compare (BUG 17: `==` on Str values read
//     from Vec[Str] elements lowers to a pointer comparison); this module
//     never uses `==` on Str.
//   * All scanning is byte-wise over ASCII via xiom.string.byte_at; Ok/Err
//     for Result[Locale, Str] and Result[Str, Str] are constructed only in
//     the tiny leaf helpers below.

module xiom.locale

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed and casing-normalized language tag. `script` and `region` are ""
/// when absent; `variants` and `extensions` are empty when absent; each
/// extension is stored with its singleton first ("u-ca-gregory"); private_use
/// is stored without the "x-" prefix ("abc-def", "" when absent). A
/// private-use-only tag ("x-abc") has every other field empty.
pub type Locale = {
  language: Str;
  script: Str;
  region: Str;
  variants: Vec[Str];
  extensions: Vec[Str];
  private_use: Str;
}

/// One curated registry row: the ISO 639 subtag, its English name and the
/// default script used for it (a curated approximation, not IANA data).
pub type LangInfo = {
  subtag: Str;
  name: Str;
  default_script: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(l) for Result[Locale, Str].
fn _ok_locale(l: Locale) -> Result[Locale, Str] {
  return Ok(l);
}

// Err(m) for Result[Locale, Str].
fn _err_locale(m: Str) -> Result[Locale, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and character classes
// --------------------------------------------------

const _L_DASH: UInt8 = 45u8;     // -
const _L_ZERO: UInt8 = 48u8;     // 0
const _L_NINE: UInt8 = 57u8;     // 9
const _L_UPPER_A: UInt8 = 65u8;  // A
const _L_UPPER_X: UInt8 = 88u8;  // X
const _L_UPPER_Z: UInt8 = 90u8;  // Z
const _L_LOWER_A: UInt8 = 97u8;  // a
const _L_LOWER_X: UInt8 = 120u8; // x
const _L_LOWER_Z: UInt8 = 122u8; // z
const _L_PIPE: UInt8 = 124u8;    // |

// True for an ASCII decimal digit byte.
fn _is_digit_b(b: UInt8) -> Bool {
  if b >= _L_ZERO && b <= _L_NINE { return true; }
  return false;
}

// True for an ASCII uppercase letter byte.
fn _is_upper_b(b: UInt8) -> Bool {
  if b >= _L_UPPER_A && b <= _L_UPPER_Z { return true; }
  return false;
}

// True for an ASCII lowercase letter byte.
fn _is_lower_b(b: UInt8) -> Bool {
  if b >= _L_LOWER_A && b <= _L_LOWER_Z { return true; }
  return false;
}

// True for an ASCII letter byte.
fn _is_alpha_b(b: UInt8) -> Bool {
  if _is_upper_b(b) { return true; }
  if _is_lower_b(b) { return true; }
  return false;
}

// True for an ASCII letter or digit byte.
fn _is_alnum_b(b: UInt8) -> Bool {
  if _is_alpha_b(b) { return true; }
  if _is_digit_b(b) { return true; }
  return false;
}

// True when every byte of s is an ASCII letter (vacuously true for "").
fn _all_alpha(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_alpha_b(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of s is an ASCII digit (vacuously true for "").
fn _all_digit(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_digit_b(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when every byte of s is an ASCII letter or digit (for "").
fn _all_alnum(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_alnum_b(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  ASCII case folding and Str equality
// --------------------------------------------------

// Copy of s with ASCII A-Z folded to a-z; non-ASCII bytes pass through.
fn _ascii_lower(s: Str) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if _is_upper_b(b) {
      builder.sb_push_byte(&mut sb, ((b as Int) + 32) as UInt8);
    } else {
      builder.sb_push_byte(&mut sb, b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Copy of s with ASCII a-z folded to A-Z; non-ASCII bytes pass through.
fn _ascii_upper(s: Str) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if _is_lower_b(b) {
      builder.sb_push_byte(&mut sb, ((b as Int) - 32) as UInt8);
    } else {
      builder.sb_push_byte(&mut sb, b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Copy of s with the first ASCII letter uppercased and the rest lowercased
// (the RFC 5646 canonical form of a script subtag).
fn _ascii_title(s: Str) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if i == 0 {
      if _is_lower_b(b) {
        builder.sb_push_byte(&mut sb, ((b as Int) - 32) as UInt8);
      } else {
        builder.sb_push_byte(&mut sb, b);
      }
    } else {
      if _is_upper_b(b) {
        builder.sb_push_byte(&mut sb, ((b as Int) + 32) as UInt8);
      } else {
        builder.sb_push_byte(&mut sb, b);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Byte-exact Str equality through str_compare (never `==` on Str).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Case-insensitive Str equality (ASCII case folding on both sides).
fn _streq_ci(a: Str, b: Str) -> Bool {
  if _streq(a, b) { return true; }
  return _streq(_ascii_lower(a), _ascii_lower(b));
}

// True when any element of v equals needle byte-exactly.
fn _vec_has(v: &Vec[Str], needle: Str) -> Bool {
  let n = v.len();
  var i = 0;
  while i < n {
    let s: Str = v[i];
    if _streq(s, needle) { return true; }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Joining helpers
// --------------------------------------------------

// Join a and b with '-', skipping either side when empty.
fn _append(a: Str, b: Str) -> Str {
  if b.len() == 0 { return a; }
  if a.len() == 0 { return b; }
  return a + "-" + b;
}

// Lowercased, '-'-joined copy of parts[from, to).
fn _join_lowered(parts: &Vec[Str], from: Int, to: Int) -> Str {
  var out = "";
  var i = from;
  while i < to {
    let p: Str = parts[i];
    out = _append(out, _ascii_lower(p));
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Subtag shapes (RFC 5646 2.1)
// --------------------------------------------------

// language = 2*8ALPHA.
fn _is_language_subtag(s: Str) -> Bool {
  let n = s.len();
  if n < 2 || n > 8 { return false; }
  return _all_alpha(s);
}

// script = 4ALPHA.
fn _is_script_subtag(s: Str) -> Bool {
  if s.len() != 4 { return false; }
  return _all_alpha(s);
}

// region = 2ALPHA / 3DIGIT.
fn _is_region_subtag(s: Str) -> Bool {
  let n = s.len();
  if n == 2 { return _all_alpha(s); }
  if n == 3 { return _all_digit(s); }
  return false;
}

// variant = 5*8alphanum / (DIGIT 3alphanum).
fn _is_variant_subtag(s: Str) -> Bool {
  let n = s.len();
  if n >= 5 && n <= 8 { return _all_alnum(s); }
  if n == 4 {
    if _is_digit_b(string.byte_at(s, 0)) { return _all_alnum(s); }
  }
  return false;
}

// extension subtag = 2*8alphanum.
fn _is_extension_subtag(s: Str) -> Bool {
  let n = s.len();
  if n < 2 || n > 8 { return false; }
  return _all_alnum(s);
}

// private-use subtag = 1*8alphanum.
fn _is_private_subtag(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 8 { return false; }
  return _all_alnum(s);
}

// True for the private-use introducer "x" in either case.
fn _is_x_singleton(s: Str) -> Bool {
  if s.len() != 1 { return false; }
  let b = string.byte_at(s, 0);
  if b == _L_LOWER_X { return true; }
  if b == _L_UPPER_X { return true; }
  return false;
}

// "" when parts[from, to) are all valid private-use subtags, else the first
// precise error message (empty sentinel avoids a Result in the hot path).
fn _private_error(parts: &Vec[Str], from: Int, to: Int) -> Str {
  var i = from;
  while i < to {
    let p: Str = parts[i];
    if !_is_private_subtag(p) {
      return "locale: invalid private-use subtag: " + p;
    }
    i = i + 1;
  }
  return "";
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Classify the pre-split subtags of a non-empty tag. `n` is parts.len().
// Private use consumes everything after "x"; extensions run from a singleton
// up to the next singleton, "x" or the end; script/region/variants are only
// accepted in that order while no extension is open.
fn _parse_parts(parts: &Vec[Str], n: Int) -> Result[Locale, Str] {
  let first: Str = parts[0];

  // Private-use-only tag: x-...
  if _is_x_singleton(first) {
    if n == 1 { return _err_locale("locale: empty private use"); }
    let perr = _private_error(parts, 1, n);
    if perr.len() > 0 { return _err_locale(perr); }
    let no_variants = Vec[Str].new();
    let no_extensions = Vec[Str].new();
    let loc0 = Locale{
      language: "";
      script: "";
      region: "";
      variants: no_variants;
      extensions: no_extensions;
      private_use: _join_lowered(parts, 1, n);
    };
    return _ok_locale(loc0);
  }

  if !_is_language_subtag(first) {
    return _err_locale("locale: invalid language: " + first);
  }

  var language = _ascii_lower(first);
  var script = "";
  var region = "";
  var variants = Vec[Str].new();
  var extensions = Vec[Str].new();
  var private_use = "";
  var seen_ext = false;
  var cur_ext = "";
  var cur_ext_has_sub = false;
  var cur_singleton = "";
  var seen_singletons = Vec[Str].new();

  var i = 1;
  while i < n {
    let p: Str = parts[i];
    if _is_x_singleton(p) {
      if i == n - 1 { return _err_locale("locale: empty private use"); }
      if seen_ext {
        if !cur_ext_has_sub {
          return _err_locale("locale: extension without subtags: " + cur_singleton);
        }
        extensions.push(cur_ext);
        seen_ext = false;
      }
      let perr = _private_error(parts, i + 1, n);
      if perr.len() > 0 { return _err_locale(perr); }
      private_use = _join_lowered(parts, i + 1, n);
      i = n;
    } elif p.len() == 1 {
      if !_is_alnum_b(string.byte_at(p, 0)) {
        if seen_ext {
          return _err_locale("locale: invalid extension subtag: " + p);
        }
        return _err_locale("locale: invalid subtag: " + p);
      }
      if seen_ext {
        if !cur_ext_has_sub {
          return _err_locale("locale: extension without subtags: " + cur_singleton);
        }
        extensions.push(cur_ext);
      }
      let low = _ascii_lower(p);
      if _vec_has(seen_singletons, low) {
        return _err_locale("locale: duplicate singleton: " + p);
      }
      seen_singletons.push(low);
      seen_ext = true;
      cur_ext = low;
      cur_ext_has_sub = false;
      cur_singleton = p;
    } elif seen_ext {
      if !_is_extension_subtag(p) {
        return _err_locale("locale: invalid extension subtag: " + p);
      }
      cur_ext = cur_ext + "-" + _ascii_lower(p);
      cur_ext_has_sub = true;
    } elif script.len() == 0 && region.len() == 0 && variants.len() == 0 && _is_script_subtag(p) {
      script = _ascii_title(p);
    } elif region.len() == 0 && variants.len() == 0 && _is_region_subtag(p) {
      region = _ascii_upper(p);
    } elif _is_variant_subtag(p) {
      let lowv = _ascii_lower(p);
      if _vec_has(variants, lowv) {
        return _err_locale("locale: duplicate variant: " + p);
      }
      variants.push(lowv);
    } else {
      return _err_locale("locale: invalid subtag: " + p);
    }
    i = i + 1;
  }

  if seen_ext {
    if !cur_ext_has_sub {
      return _err_locale("locale: extension without subtags: " + cur_singleton);
    }
    extensions.push(cur_ext);
  }

  let loc = Locale{
    language: language;
    script: script;
    region: region;
    variants: variants;
    extensions: extensions;
    private_use: private_use;
  };
  return _ok_locale(loc);
}

/// Parse a BCP-47 language tag into its normalized components.
/// Params: tag - the ASCII language tag, e.g. "zh-Hant-TW", "de-AT-1901",
/// "en-US-u-ca-gregory-x-phonebk" or the private-use-only "x-abc-def".
/// Returns: Ok(Locale) with canonical casing already applied (language lower,
/// script Titlecase, region upper, variants/extensions/private use lower).
/// Error case: Err("locale: ...") with the first precise syntax reason, in
/// this order: empty tag; empty subtag ("en-", "-en", "en--US"); private use
/// with no subtags ("x", "en-x"); invalid private-use subtag; invalid
/// language subtag; then left-to-right: invalid subtag (nothing matches the
/// position), invalid extension subtag, extension without subtags, duplicate
/// singleton, duplicate variant. Full catalog in SPEC.md.
/// Complexity: O(tag length).
pub fn locale_parse(tag: Str) -> Result[Locale, Str] {
  if tag.len() == 0 { return _err_locale("locale: empty tag"); }
  let parts = string.str_split(tag, "-");
  let n = parts.len();
  var i = 0;
  while i < n {
    let p: Str = parts[i];
    if p.len() == 0 { return _err_locale("locale: empty subtag"); }
    i = i + 1;
  }
  return _parse_parts(&parts, n);
}

// --------------------------------------------------
//  Canonical emission
// --------------------------------------------------

// language-script-region-variants of loc joined with '-' (no extensions or
// private use). For a private-use-only tag the result is "".
fn _base_tag(loc: &Locale) -> Str {
  let language: Str = loc.language;
  let script: Str = loc.script;
  let region: Str = loc.region;
  let variants: Vec[Str] = loc.variants;
  let n = variants.len();
  var out = language;
  out = _append(out, script);
  out = _append(out, region);
  var i = 0;
  while i < n {
    let v: Str = variants[i];
    out = _append(out, v);
    i = i + 1;
  }
  return out;
}

/// Render a Locale back to its canonical tag string.
/// Params: loc - a parsed Locale (stored fields are already canonical-cased).
/// Returns: language, script, region and variants joined with '-', then each
/// extension joined with '-', then "x-" + private_use when the private use is
/// non-empty. A private-use-only Locale renders as "x-..."; the empty Locale
/// (impossible from locale_parse) renders as "".
/// Error case: none.
/// Complexity: O(output length).
pub fn locale_to_string(loc: &Locale) -> Str {
  let base = _base_tag(loc);
  let ext: Vec[Str] = loc.extensions;
  let private_use: Str = loc.private_use;
  let en = ext.len();
  var out = base;
  var i = 0;
  while i < en {
    let e: Str = ext[i];
    out = _append(out, e);
    i = i + 1;
  }
  if private_use.len() > 0 {
    out = _append(out, "x-" + private_use);
  }
  return out;
}

/// Canonicalize a BCP-47 tag by parsing it and re-emitting the canonical form.
/// Params: tag - the language tag in any casing.
/// Returns: Ok(canonical) where language/extension/private-use subtags are
/// lowercased, the script is Titlecased and the region is uppercased, e.g.
/// "EN-us" -> "en-US", "zh-hant-tw" -> "zh-Hant-TW", "DE-de-1996" ->
/// "de-DE-1996". Preferred-Value substitutions are NOT applied.
/// Error case: Err(the locale_parse error message) for any invalid tag.
/// Complexity: O(tag length).
pub fn locale_canonical(tag: Str) -> Result[Str, Str] {
  let r = locale_parse(tag);
  match r {
    Ok(loc) => { return _ok_str(locale_to_string(&loc)); },
    Err(e) => { return _err_str(e); },
  }
  return _err_str("locale: canonicalization failed");
}

/// Well-formedness test for a language tag.
/// Params: tag - the candidate language tag.
/// Returns: true when locale_parse(tag) succeeds, false for any syntax error.
/// Error case: none (errors become false).
/// Complexity: O(tag length).
pub fn locale_is_valid(tag: Str) -> Bool {
  let r = locale_parse(tag);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// --------------------------------------------------
//  RFC 4647 Lookup
// --------------------------------------------------

// Truncate one step per RFC 4647 3.4: drop the rightmost subtag; while the
// new rightmost subtag is a single letter or digit (an extension singleton or
// the private-use "x"), drop it as well, since such a subtag cannot end a
// valid range. "" when nothing is left.
fn _truncate(tag: Str) -> Str {
  let n = tag.len();
  if n == 0 { return ""; }
  var d = -1;
  var i = 0;
  while i < n {
    if string.byte_at(tag, i) == _L_DASH { d = i; }
    i = i + 1;
  }
  if d < 0 { return ""; }
  var cut = string.str_slice(tag, 0, d);
  while cut.len() > 0 {
    var d2 = -1;
    var j = 0;
    while j < cut.len() {
      if string.byte_at(cut, j) == _L_DASH { d2 = j; }
      j = j + 1;
    }
    let last_len = cut.len() - (d2 + 1);
    if last_len != 1 { break; }
    if d2 < 0 { return ""; }
    cut = string.str_slice(cut, 0, d2);
  }
  return cut;
}

// First available tag matching range or one of its truncations
// (case-insensitively); "" when nothing matches. The matched available tag is
// returned exactly as it appears in `available`.
fn _lookup_one(range: Str, available: &Vec[Str]) -> Str {
  var cand = range;
  while cand.len() > 0 {
    let n = available.len();
    var i = 0;
    while i < n {
      let a: Str = available[i];
      if _streq_ci(a, cand) { return a; }
      i = i + 1;
    }
    cand = _truncate(cand);
  }
  return "";
}

/// RFC 4647 Lookup over a language priority list.
/// Params: requested - priority-ordered language ranges; available - the tags
/// on offer. A range "*" is skipped (it carries no preference); matching is
/// case-insensitive; each range is matched exactly first, then truncated step
/// by step (see _truncate); the first match over `requested` wins.
/// Returns: Some(tag) with the first available tag that matches, preserving
/// the available list's casing; None when nothing matches or `available` is
/// empty.
/// Error case: none (ill-formed ranges simply fail to match).
/// Complexity: O(requested * available * tag length).
pub fn locale_lookup(requested: &Vec[Str], available: &Vec[Str]) -> Option[Str] {
  if available.len() == 0 { return None; }
  let rn = requested.len();
  var i = 0;
  while i < rn {
    let r: Str = requested[i];
    if !_streq(r, "*") {
      let hit = _lookup_one(r, available);
      if hit.len() > 0 { return Some(hit); }
    }
    i = i + 1;
  }
  return None;
}

// --------------------------------------------------
//  Fallback chains
// --------------------------------------------------

/// Build the ordered fallback chain used to resolve a tag against default
/// data.
/// Params: tag - the requested language tag.
/// Returns: the canonical tag first, then the same tag with extensions and
/// private use dropped, then right-to-left truncations of that base (each
/// step drops the rightmost subtag, together with a trailing singleton, as in
/// locale_lookup), most specific first. Duplicates are collapsed. Returns an
/// empty Vec for an invalid tag (nothing to resolve).
/// Examples: "de-AT" -> ["de-AT", "de"];
/// "zh-Hant-CN-u-ca-chinese-x-priv" ->
/// ["zh-Hant-CN-u-ca-chinese-x-priv", "zh-Hant-CN", "zh-Hant", "zh"];
/// "x-priv" -> ["x-priv"]; "??" -> [].
/// Error case: none.
/// Complexity: O(tag length^2).
pub fn locale_fallback_chain(tag: Str) -> Vec[Str] {
  let parsed = locale_parse(tag);
  match parsed {
    Ok(loc) => {
      var chain = Vec[Str].new();
      let full = locale_to_string(&loc);
      chain.push(full);
      let base = _base_tag(&loc);
      if base.len() > 0 && !_streq(base, full) {
        chain.push(base);
      }
      var cand = _truncate(base);
      while cand.len() > 0 {
        chain.push(cand);
        cand = _truncate(cand);
      }
      return chain;
    },
    Err(_) => {
      let empty = Vec[Str].new();
      return empty;
    },
  }
  let empty2 = Vec[Str].new();
  return empty2;
}

// --------------------------------------------------
//  Static language registry
// --------------------------------------------------

// One row per curated language, packed as "subtag|name|script" to keep the
// table a single Vec[Str] (no parallel Vec pushes).
fn _registry_data() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("en|English|Latn");
  v.push("zh|Chinese|Hans");
  v.push("hi|Hindi|Deva");
  v.push("es|Spanish|Latn");
  v.push("ar|Arabic|Arab");
  v.push("bn|Bengali|Beng");
  v.push("pt|Portuguese|Latn");
  v.push("ru|Russian|Cyrl");
  v.push("ja|Japanese|Jpan");
  v.push("de|German|Latn");
  v.push("fr|French|Latn");
  v.push("ko|Korean|Kore");
  v.push("it|Italian|Latn");
  v.push("tr|Turkish|Latn");
  v.push("vi|Vietnamese|Latn");
  v.push("pl|Polish|Latn");
  v.push("uk|Ukrainian|Cyrl");
  v.push("nl|Dutch|Latn");
  v.push("th|Thai|Thai");
  v.push("fa|Persian|Arab");
  v.push("he|Hebrew|Hebr");
  v.push("el|Greek|Grek");
  v.push("sv|Swedish|Latn");
  v.push("da|Danish|Latn");
  v.push("nb|Norwegian Bokmal|Latn");
  v.push("fi|Finnish|Latn");
  v.push("cs|Czech|Latn");
  v.push("sk|Slovak|Latn");
  v.push("hu|Hungarian|Latn");
  v.push("ro|Romanian|Latn");
  v.push("bg|Bulgarian|Cyrl");
  v.push("sr|Serbian|Cyrl");
  v.push("hr|Croatian|Latn");
  v.push("sl|Slovenian|Latn");
  v.push("lt|Lithuanian|Latn");
  v.push("lv|Latvian|Latn");
  v.push("et|Estonian|Latn");
  v.push("is|Icelandic|Latn");
  v.push("ga|Irish|Latn");
  v.push("cy|Welsh|Latn");
  v.push("eu|Basque|Latn");
  v.push("ca|Catalan|Latn");
  v.push("gl|Galician|Latn");
  v.push("mt|Maltese|Latn");
  v.push("sq|Albanian|Latn");
  v.push("hy|Armenian|Armn");
  v.push("ka|Georgian|Geor");
  v.push("sw|Swahili|Latn");
  v.push("id|Indonesian|Latn");
  v.push("ms|Malay|Latn");
  return v;
}

// Index of the first `target` byte in s, or -1.
fn _index_of_byte(s: Str, target: UInt8) -> Int {
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the last `target` byte in s, or -1.
fn _last_index_of_byte(s: Str, target: UInt8) -> Int {
  var i = s.len() - 1;
  while i >= 0 {
    if string.byte_at(s, i) == target { return i; }
    i = i - 1;
  }
  return -1;
}

/// Number of rows in the curated language registry (30..50 by design).
/// Params: none.
/// Returns: the row count, currently 50.
/// Error case: none.
/// Complexity: O(1) plus table construction.
pub fn locale_registry_count() -> Int {
  let d = _registry_data();
  return d.len();
}

/// Look up a language subtag in the curated registry.
/// Params: subtag - the language subtag in any case, e.g. "en", "ZH", "ja".
/// Returns: Some(LangInfo{subtag, name, default_script}) with the canonical
/// subtag and curated English name/default script; None when the subtag is
/// unknown. Lookup is case-insensitive ASCII.
/// Error case: none.
/// Complexity: O(registry rows).
pub fn locale_registry_get(subtag: Str) -> Option[LangInfo] {
  let want = _ascii_lower(subtag);
  let data = _registry_data();
  let n = data.len();
  var i = 0;
  while i < n {
    let rec: Str = data[i];
    let sep1 = _index_of_byte(rec, _L_PIPE);
    if sep1 >= 0 {
      let code = string.str_slice(rec, 0, sep1);
      if _streq(code, want) {
        let sep2 = _last_index_of_byte(rec, _L_PIPE);
        let nm = string.str_slice(rec, sep1 + 1, sep2);
        let sc = string.str_slice(rec, sep2 + 1, rec.len());
        let info = LangInfo{ subtag: code; name: nm; default_script: sc; };
        return Some(info);
      }
    }
    i = i + 1;
  }
  return None;
}
