// XIOM -- xiom.html: tolerant HTML sanitizer (tag allowlist, attribute policy)
// Port task: replace the xiom.html placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the scanner rules, the attribute policy,
// the dropped-block rules and the test plan):
//   * a single-pass tolerant scanner: a '<' is markup only where HTML could
//     start it (a letter, '/', '!' or '?'), everything else is text;
//   * the tag allowlist is matched case-insensitively and kept tags are
//     emitted lowercased;
//   * the attribute policy keeps only href and title: every other attribute
//     (including all on* handlers) is dropped, and an href whose scheme is
//     javascript: or data: is dropped;
//   * script and style elements are dropped together with their content,
//     even when a caller puts them in the allowlist;
//   * comments and markup declarations are dropped; text and entities are
//     preserved verbatim.
//
// The sanitizer is tolerant by design: it never rebalances tags, never decodes
// entities, and validates URLs only with the scheme check above. An opening
// or closing tag with no '>' before EOF is stray text and passes through
// verbatim (see SPEC.md, "Limitations").
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Str comparisons involving Vec[Str] elements go through
//     xiom.string.compare.str_compare (BUG 17).
//   * Byte predicates work in Int space (`(byte as Int) & 0xFF`) and cast
//     back with `as UInt8` on pushes, so no UInt8 literal arithmetic and no
//     direct UInt8 comparisons at or above 0x80 are needed.

module xiom.html

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _HTML_TAB: Int = 9;
const _HTML_LF: Int = 10;
const _HTML_FF: Int = 12;
const _HTML_CR: Int = 13;
const _HTML_SPACE: Int = 32;
const _HTML_BANG: Int = 33;
const _HTML_DQUOTE: Int = 34;
const _HTML_SQUOTE: Int = 39;
const _HTML_DASH: Int = 45;
const _HTML_SLASH: Int = 47;
const _HTML_LT: Int = 60;
const _HTML_EQ: Int = 61;
const _HTML_GT: Int = 62;
const _HTML_QUEST: Int = 63;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Numeric byte value of s[i], normalized to 0..255.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// HTML whitespace byte: space, tab, LF, CR or form feed.
fn _is_ws(b: Int) -> Bool {
  if b == _HTML_SPACE {
    return true;
  }
  if b == _HTML_TAB {
    return true;
  }
  if b == _HTML_LF {
    return true;
  }
  if b == _HTML_CR {
    return true;
  }
  if b == _HTML_FF {
    return true;
  }
  return false;
}

// ASCII letter byte (A-Z or a-z).
fn _is_alpha_byte(b: Int) -> Bool {
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 97 && b <= 122 {
    return true;
  }
  return false;
}

// Lowercase one ASCII letter byte; every other byte is returned unchanged.
fn _lower_ascii(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b + 32;
  }
  return b;
}

// Byte that terminates a tag name: whitespace, '/', '>' or '<'.
fn _is_name_end(b: Int) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _HTML_SLASH {
    return true;
  }
  if b == _HTML_GT {
    return true;
  }
  if b == _HTML_LT {
    return true;
  }
  return false;
}

// Byte that terminates an attribute name: whitespace, '=', '/', '>' or '<'.
fn _is_attr_name_end(b: Int) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _HTML_EQ {
    return true;
  }
  if b == _HTML_SLASH {
    return true;
  }
  if b == _HTML_GT {
    return true;
  }
  if b == _HTML_LT {
    return true;
  }
  return false;
}

// Byte that terminates an unquoted attribute value: whitespace, '/', '>' or '<'.
fn _is_unquoted_end(b: Int) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _HTML_SLASH {
    return true;
  }
  if b == _HTML_GT {
    return true;
  }
  if b == _HTML_LT {
    return true;
  }
  return false;
}

// Index of the first byte equal to `want` at or after `from`, -1 when absent.
fn _find_byte(s: Str, from: Int, want: Int) -> Int {
  let n = s.len();
  var i = from;
  if i < 0 {
    i = 0;
  }
  while i < n {
    if _byte(s, i) == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first occurrence of `needle` at or after `from`, -1 when absent.
fn _find_seq(s: Str, from: Int, needle: Str) -> Int {
  let n = s.len();
  let m = needle.len();
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if _byte(s, i + j) != _byte(needle, j) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first '>' outside quotes at or after `from`, -1 when absent.
// Quoted runs are skipped so that a '>' inside an attribute value does not
// end the tag; an unterminated quote means there is no tag end.
fn _find_tag_end(s: Str, from: Int) -> Int {
  let n = s.len();
  var j = from;
  while j < n {
    let b = _byte(s, j);
    if b == _HTML_DQUOTE || b == _HTML_SQUOTE {
      let q = b;
      j = j + 1;
      while j < n && _byte(s, j) != q {
        j = j + 1;
      }
      if j < n {
        j = j + 1;
      }
    } elif b == _HTML_GT {
      return j;
    } else {
      j = j + 1;
    }
  }
  return -1;
}

// True when a '<' occurs in s[from, to).
fn _contains_lt(s: Str, from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if _byte(s, i) == _HTML_LT {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Length of the tag name starting at s[from] and ending before s[to].
fn _tag_name_len(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    if _is_name_end(_byte(s, i)) {
      break;
    }
    i = i + 1;
  }
  return i - from;
}

// Case-insensitive byte comparison of s[from, to) with the literal `lit`
// (both sides ASCII-lowercased, so allowlist entries may use any case).
fn _slice_eq_ci(s: Str, from: Int, to: Int, lit: Str) -> Bool {
  if to - from != lit.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _lower_ascii(_byte(s, from + i)) != _lower_ascii(_byte(lit, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the tag name s[from, to) is in the allowlist (case-insensitive).
fn _tag_allowed(s: Str, from: Int, to: Int, tags: &Vec[Str]) -> Bool {
  var i = 0;
  while i < tags.len() {
    let entry: Str = tags[i];
    if _slice_eq_ci(s, from, to, entry) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Append s[from, to) to out with ASCII letters lowercased.
fn _push_lower(s: Str, from: Int, to: Int, out: &mut Vec[UInt8]) {
  var i = from;
  while i < to {
    out.push(_lower_ascii(_byte(s, i)) as UInt8);
    i = i + 1;
  }
}

// True when s[i, to) starts with the scheme `lit` after ASCII-lowercasing and
// skipping tab/LF/CR anywhere (browsers strip those from URLs). Spaces inside
// the scheme are NOT skipped, so "java script:" does not match.
fn _match_scheme(s: Str, from: Int, to: Int, lit: Str) -> Bool {
  var i = from;
  var k = 0;
  while k < lit.len() {
    if i >= to {
      return false;
    }
    let b = _lower_ascii(_byte(s, i));
    if b == _HTML_TAB || b == _HTML_LF || b == _HTML_CR {
      i = i + 1;
    } elif b == _byte(lit, k) {
      i = i + 1;
      k = k + 1;
    } else {
      return false;
    }
  }
  return true;
}

// True when the attribute value s[from, to) is a javascript: or data: URL.
// Leading whitespace is skipped and tab/LF/CR are skipped inside the scheme;
// entity-encoded schemes are NOT decoded (see SPEC.md).
fn _is_dangerous_url(s: Str, from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if _is_ws(_byte(s, i)) {
      i = i + 1;
    } else {
      break;
    }
  }
  if _match_scheme(s, i, to, "javascript:") {
    return true;
  }
  if _match_scheme(s, i, to, "data:") {
    return true;
  }
  return false;
}

// Append one kept attribute to out: a space, the canonical name, '="', the
// raw value bytes with '"' -> &quot; and '<' -> &lt;, then the closing '"'.
// Everything else -- including entities like &amp; -- is preserved verbatim.
fn _push_attr(s: Str, v_from: Int, v_to: Int, name: Str, out: &mut Vec[UInt8]) {
  builder.sb_push_str(out, " ");
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, "=\"");
  var i = v_from;
  while i < v_to {
    let b = _byte(s, i);
    if b == _HTML_DQUOTE {
      builder.sb_push_str(out, "&quot;");
    } elif b == _HTML_LT {
      builder.sb_push_str(out, "&lt;");
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  out.push(_HTML_DQUOTE as UInt8);
}

// Emit a kept opening tag: '<' + lowercased name + kept attributes
// (first href wins, first title wins; a dangerous href is dropped and blocks
// later duplicates) + '/' when the input self-closed + '>'.
fn _emit_open_tag(s: Str, name_from: Int, name_to: Int, gt: Int, out: &mut Vec<UInt8>) {
  out.push(_HTML_LT as UInt8);
  _push_lower(s, name_from, name_to, out);
  var j = name_to;
  var self_close = false;
  var have_href = false;
  var have_title = false;
  while j < gt {
    while j < gt && _is_ws(_byte(s, j)) {
      j = j + 1;
    }
    if j >= gt {
      break;
    }
    let b = _byte(s, j);
    if b == _HTML_SLASH {
      self_close = true;
      j = j + 1;
      continue;
    }
    let an_from = j;
    while j < gt && !_is_attr_name_end(_byte(s, j)) {
      j = j + 1;
    }
    if j == an_from {
      j = j + 1;
      continue;
    }
    let an_to = j;
    while j < gt && _is_ws(_byte(s, j)) {
      j = j + 1;
    }
    var has_value = false;
    var v_from = 0;
    var v_to = 0;
    if j < gt && _byte(s, j) == _HTML_EQ {
      j = j + 1;
      while j < gt && _is_ws(_byte(s, j)) {
        j = j + 1;
      }
      if j < gt {
        let q = _byte(s, j);
        if q == _HTML_DQUOTE || q == _HTML_SQUOTE {
          j = j + 1;
          v_from = j;
          while j < gt && _byte(s, j) != q {
            j = j + 1;
          }
          v_to = j;
          if j < gt {
            j = j + 1;
          }
        } else {
          v_from = j;
          while j < gt && !_is_unquoted_end(_byte(s, j)) {
            j = j + 1;
          }
          v_to = j;
        }
        has_value = true;
      }
    }
    if has_value {
      if !have_href && _slice_eq_ci(s, an_from, an_to, "href") {
        have_href = true;
        if !_is_dangerous_url(s, v_from, v_to) {
          _push_attr(s, v_from, v_to, "href", out);
        }
      } elif !have_title && _slice_eq_ci(s, an_from, an_to, "title") {
        have_title = true;
        _push_attr(s, v_from, v_to, "title", out);
      }
    }
  }
  if self_close {
    out.push(_HTML_SLASH as UInt8);
  }
  out.push(_HTML_GT as UInt8);
}

// Emit a kept closing tag: '</' + lowercased name + '>'.
fn _emit_close_tag(s: Str, name_from: Int, name_to: Int, out: &mut Vec<UInt8>) {
  out.push(_HTML_LT as UInt8);
  out.push(_HTML_SLASH as UInt8);
  _push_lower(s, name_from, name_to, out);
  out.push(_HTML_GT as UInt8);
}

// Index of the next "</name" (case-insensitive) at or after `from`, -1 when
// absent. Used to find the end of a dropped script/style block.
fn _find_close_tag(s: Str, from: Int, name: Str) -> Int {
  let n = s.len();
  let m = name.len();
  var i = from;
  while i + m + 2 <= n {
    if _byte(s, i) == _HTML_LT && _byte(s, i + 1) == _HTML_SLASH {
      if _slice_eq_ci(s, i + 2, i + 2 + m, name) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Skip a dropped script/style block: everything from `from` up to and
// including the next "</name ...>" (case-insensitive), or to EOF when the
// closing tag is missing.
fn _skip_element_content(s: Str, from: Int, name: Str) -> Int {
  let n = s.len();
  let close = _find_close_tag(s, from, name);
  if close < 0 {
    return n;
  }
  let gt = _find_byte(s, close + 2 + name.len(), _HTML_GT);
  if gt < 0 {
    return n;
  }
  return gt + 1;
}

// Consume the markup starting at the '<' at input[i] and append the sanitized
// result (if any) to out. Returns the index to resume scanning at, always
// greater than i. Every branch that cannot find a tag end emits the '<' as
// text and resumes right after it (documented tolerant behavior).
fn _scan_markup(s: Str, i: Int, tags: &Vec<Str>, out: &mut Vec<UInt8>) -> Int {
  let n = s.len();
  if i + 1 >= n {
    out.push(_HTML_LT as UInt8);
    return i + 1;
  }
  let c = _byte(s, i + 1);
  if c == _HTML_BANG {
    if i + 3 < n && _byte(s, i + 2) == _HTML_DASH && _byte(s, i + 3) == _HTML_DASH {
      let close = _find_seq(s, i + 4, "-->");
      if close < 0 {
        return n;
      }
      return close + 3;
    }
    let gt = _find_byte(s, i + 1, _HTML_GT);
    if gt < 0 {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    return gt + 1;
  }
  if c == _HTML_QUEST {
    let gt = _find_byte(s, i + 1, _HTML_GT);
    if gt < 0 {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    return gt + 1;
  }
  if c == _HTML_SLASH {
    if i + 2 >= n || !_is_alpha_byte(_byte(s, i + 2)) {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    let gt = _find_tag_end(s, i + 1);
    if gt < 0 || _contains_lt(s, i + 1, gt) {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    let name_len = _tag_name_len(s, i + 2, gt);
    if name_len > 0 && _tag_allowed(s, i + 2, i + 2 + name_len, tags) {
      _emit_close_tag(s, i + 2, i + 2 + name_len, out);
    }
    return gt + 1;
  }
  if _is_alpha_byte(c) {
    let gt = _find_tag_end(s, i + 1);
    if gt < 0 || _contains_lt(s, i + 1, gt) {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    let name_len = _tag_name_len(s, i + 1, gt);
    if name_len == 0 {
      out.push(_HTML_LT as UInt8);
      return i + 1;
    }
    if _slice_eq_ci(s, i + 1, i + 1 + name_len, "script") {
      return _skip_element_content(s, gt + 1, "script");
    }
    if _slice_eq_ci(s, i + 1, i + 1 + name_len, "style") {
      return _skip_element_content(s, gt + 1, "style");
    }
    if _tag_allowed(s, i + 1, i + 1 + name_len, tags) {
      _emit_open_tag(s, i + 1, i + 1 + name_len, gt, out);
    }
    return gt + 1;
  }
  out.push(_HTML_LT as UInt8);
  return i + 1;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// The default allowlist: the 21 inline/structural tags xiom.html keeps.
/// Params: none.
/// Returns: a fresh Vec[Str] with the lowercase tags a, b, blockquote, br,
/// code, em, h1-h6, hr, i, li, ol, p, pre, strong, u, ul in sorted order.
/// The caller owns the vector, so it can modify or extend the list.
/// Error case: none.
/// Complexity: O(1) (fixed 21 pushes).
pub fn html_default_allowed_tags() -> Vec[Str] {
  var tags = Vec[Str].new();
  tags.push("a");
  tags.push("b");
  tags.push("blockquote");
  tags.push("br");
  tags.push("code");
  tags.push("em");
  tags.push("h1");
  tags.push("h2");
  tags.push("h3");
  tags.push("h4");
  tags.push("h5");
  tags.push("h6");
  tags.push("hr");
  tags.push("i");
  tags.push("li");
  tags.push("ol");
  tags.push("p");
  tags.push("pre");
  tags.push("strong");
  tags.push("u");
  tags.push("ul");
  return tags;
}

/// Sanitize HTML in tolerant single-pass mode.
/// Params: input - the raw markup; allowed_tags - tag names to keep
/// (matched case-insensitively; an empty vector drops all tags and behaves
/// like html_strip_tags). script and style are never kept, even when listed.
/// Returns: input with
///   1. kept tags lowercased and reduced to href and title attributes --
///      attribute names are matched case-insensitively, the first href and
///      the first title win, an href whose scheme is javascript: or data:
///      is dropped, every other attribute (all on* handlers, class, style,
///      ...) is dropped, and values keep their entities verbatim;
///   2. script and style elements removed together with their content up to
///      the matching closing tag (or EOF);
///   3. comments `<!-- ... -->` and other `<! ... >` / `<? ... >` markup
///      removed;
///   4. disallowed tags removed but their text content kept, closing tags of
///      disallowed elements removed as well;
///   5. text, entities and stray '<' passes preserved verbatim.
/// Tolerant mode: tags are never rebalanced, an unterminated tag is emitted
/// as text, and an unclosed comment or script/style block runs to EOF.
/// Error case: none. The result is still HTML text and is not guaranteed to
/// be well-formed or to re-sanitize to itself.
/// Complexity: O(input bytes) amortized.
pub fn html_sanitize(input: Str, allowed_tags: &Vec[Str]) -> Str {
  var out = Vec[UInt8].new();
  let n = input.len();
  var i = 0;
  while i < n {
    if _byte(input, i) == _HTML_LT {
      i = _scan_markup(input, i, allowed_tags, &mut out);
    } else {
      out.push(string.byte_at(input, i));
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

/// Remove every tag plus all script/style content, keeping text and entities.
/// Params: input - the raw markup.
/// Returns: html_sanitize(input) with an empty allowlist: all tags (opening
/// and closing) are dropped, script and style blocks disappear with their
/// content, comments and declarations are dropped, and everything else --
/// including entities and stray '<' -- is preserved verbatim.
/// Error case: none.
/// Complexity: O(input bytes).
pub fn html_strip_tags(input: Str) -> Str {
  var empty = Vec[Str].new();
  return html_sanitize(input, &empty);
}

/// True when sanitizing changes nothing, i.e. the input is already clean
/// under the given allowlist.
/// Params: input - the markup to test; allowed_tags - the same allowlist
/// html_sanitize would use.
/// Returns: true when html_sanitize(input, allowed_tags) is byte-identical to
/// input; false otherwise. A false result only means the input is not
/// canonical -- it does not mean the input is dangerous.
/// Error case: none.
/// Complexity: O(input bytes).
pub fn html_is_safe(input: Str, allowed_tags: &Vec[Str]) -> Bool {
  let cleaned = html_sanitize(input, allowed_tags);
  return compare.str_compare(cleaned, input) == 0;
}
