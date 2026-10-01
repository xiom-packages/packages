// XIOM -- xiom.text_markup: a deterministic BBCode-style inline markup codec
// Port task: replace the xiom.text-markup placeholder with a pure-XIOM module
// (no FFI, no IO, no Vec[StructType], no lambdas, no fn-table dispatch).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: five inline tags -- [b], [i], [u], [code] and [url=target] -- parsed
// with proper-nesting validation, exposed as span records over the source
// text, stripped by a plain-text renderer and re-emitted by a canonical
// serializer. This is deliberately distinct from xiom.markdown: the input is
// [tag]-style, tags carry attributes ([url=...]), nesting is validated with
// exact errors instead of being silently tolerated, and the output is spans +
// plain text rather than HTML. See SPEC.md for the full statement.
//
// Grammar (as implemented):
//   Open:  '[' name ( '=' attr )? ']'      name in b|i|u|code|url
//   Close: '[' '/' name ']'
//   Text:  escapes  '\[' '\]' '\\'; entities '&amp;' '&lt;' '&gt;' '&quot;'
//   Code:  the bytes between [code] and the first [/code] are literal (no
//          tags, escapes or entities are interpreted inside).
//   Attrs: only url takes one; the attr value is the raw bytes up to ']' and
//          must be non-empty.
//
// Error catalog (exact messages, positions are 0-based byte offsets):
//   markup: unterminated tag at P           '[' with no ']' before EOF
//   markup: unknown tag '<name>' at P       name not in b|i|u|code|url
//   markup: bad attribute for '<tag>' at P  attr on b|i|u|code, or empty url attr
//   markup: invalid escape at P             '\' before none of [ ] \
//   markup: stray close tag '<name>' at P   close with no matching open
//   markup: cross-nested tags '<o>' and '<c>' at P   close skipping the top
//   markup: unclosed tag '<name>' at P      open still on the stack at EOF
//
// Language notes (XIOM v0.62.2): free functions only; no Vec[Str] at all --
// span attributes are kept as source offsets and the output is built in
// Vec[UInt8] with xiom.string.builder, so the mis-lowered Vec[Str].push path
// is never reached; no &mut scalar params (the parse loop threads every
// counter as a local and pushes where it already is); every byte read passes
// through `(b as Int) & 0xFF`; Str payloads compared with str_compare; every
// Int read from a Vec goes through a typed local; Ok/Err literals exist only
// in the leaf helpers at the bottom.

module xiom.text_markup

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Tag codes
// ---------------------------------------------------------------------------

/// Not a tag (lookup miss / out-of-range tag code).
pub const MARKUP_TAG_NONE: Int = 0;

/// `[b] ... [/b]` bold.
pub const MARKUP_TAG_B: Int = 1;

/// `[i] ... [/i]` italic.
pub const MARKUP_TAG_I: Int = 2;

/// `[u] ... [/u]` underline.
pub const MARKUP_TAG_U: Int = 3;

/// `[code] ... [/code]` literal code (content is copied verbatim).
pub const MARKUP_TAG_CODE: Int = 4;

/// `[url=target] ... [/url]` link; `[url] ... [/url]` has no attribute.
pub const MARKUP_TAG_URL: Int = 5;

// ---------------------------------------------------------------------------
// Byte constants (ASCII; all comparisons happen in the Int domain)
// ---------------------------------------------------------------------------

const _MU_LBRACKET: Int = 91;
const _MU_RBRACKET: Int = 93;
const _MU_SLASH: Int = 47;
const _MU_EQUALS: Int = 61;
const _MU_BACKSLASH: Int = 92;
const _MU_AMP: Int = 38;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// The parse result: one record per successfully closed tag pair, held as
/// parallel Vec fields (XIOM cannot hold a Vec[StructType]).
///
/// Record `i` describes the pair opened by the i-th open tag in source order:
/// `tags[i]` is the tag code; `open_starts[i]`/`open_ends[i]` are the byte
/// span of the opening tag (`[b]`); `close_starts[i]`/`close_ends[i]` are the
/// byte span of the closing tag (`[/b]`); `attr_starts[i]`/`attr_ends[i]` are
/// the byte span of the raw attribute value, or -1/-1 when the tag has none.
/// `close_order` lists the record indices in closing order: its k-th entry is
/// the record whose close tag is the k-th close tag in the source. Renderers
/// merge `open_starts` (ascending) with the close positions reached through
/// `close_order` (also ascending).
pub type Markup = {
  tags: Vec[Int];
  open_starts: Vec[Int];
  open_ends: Vec[Int];
  close_starts: Vec[Int];
  close_ends: Vec[Int];
  attr_starts: Vec[Int];
  attr_ends: Vec[Int];
  close_order: Vec[Int];
}

// One scanned tag: whether it is a close tag (1) or an open tag (0), the tag
// code, the raw attribute span (-1/-1 when absent) and the index just after
// the closing ']'.
type TagScan = {
  is_close: Int;
  tag: Int;
  attr_start: Int;
  attr_end: Int;
  end: Int;
}

// ---------------------------------------------------------------------------
// Byte access and small predicates
// ---------------------------------------------------------------------------

// Byte at `pos` as 0..255, or -1 when out of bounds (negative or at/after the
// end). Bounds are checked before byte_at, so this never traps.
fn _mu_byte(source: Str, pos: Int) -> Int {
  if pos < 0 {
    return -1;
  }
  if pos >= source.len() {
    return -1;
  }
  let raw: UInt8 = string.byte_at(source, pos);
  return (raw as Int) & 0xFF;
}

// First index of byte `target` at or after `from`; -1 when absent.
fn _mu_find(source: Str, from: Int, target: Int) -> Int {
  var i = from;
  if i < 0 {
    i = 0;
  }
  while i < source.len() {
    if _mu_byte(source, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the literal `lit` starts at `at` (byte comparison only, so BUG 17
// on Str equality can never be involved).
fn _mu_match_lit(source: Str, at: Int, lit: Str) -> Bool {
  if at < 0 {
    return false;
  }
  if at + lit.len() > source.len() {
    return false;
  }
  var k = 0;
  while k < lit.len() {
    if _mu_byte(source, at + k) != _mu_byte(lit, k) {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// The " at <pos>" suffix shared by every error message.
fn _mu_err_pos(text: Str, pos: Int) -> Str {
  return "markup: " + text + " at " + int_to_string(pos);
}

// ---------------------------------------------------------------------------
// Tag table
// ---------------------------------------------------------------------------

/// Canonical lowercase name of a tag code: "b", "i", "u", "code", "url", or
/// "none" for MARKUP_TAG_NONE and any unknown code.
/// Params: code - a MARKUP_TAG_* value.
/// Returns: the name, or "none" when unknown.
/// Error case: none.
/// Complexity: O(1).
pub fn markup_tag_name(code: Int) -> Str {
  if code == MARKUP_TAG_B {
    return "b";
  }
  if code == MARKUP_TAG_I {
    return "i";
  }
  if code == MARKUP_TAG_U {
    return "u";
  }
  if code == MARKUP_TAG_CODE {
    return "code";
  }
  if code == MARKUP_TAG_URL {
    return "url";
  }
  return "none";
}

/// Exact, case-sensitive lookup of a tag name.
/// Params: name - the text between '[' and ']' (without the leading '/' of a
/// close tag and without any '=attr' suffix).
/// Returns: the MARKUP_TAG_* code, or MARKUP_TAG_NONE when unregistered.
/// Error case: none.
/// Complexity: O(len(name)).
pub fn markup_tag_code(name: Str) -> Int {
  if compare.str_compare(name, "b") == 0 {
    return MARKUP_TAG_B;
  }
  if compare.str_compare(name, "i") == 0 {
    return MARKUP_TAG_I;
  }
  if compare.str_compare(name, "u") == 0 {
    return MARKUP_TAG_U;
  }
  if compare.str_compare(name, "code") == 0 {
    return MARKUP_TAG_CODE;
  }
  if compare.str_compare(name, "url") == 0 {
    return MARKUP_TAG_URL;
  }
  return MARKUP_TAG_NONE;
}

// ---------------------------------------------------------------------------
// Tag scanning
// ---------------------------------------------------------------------------

// Scan one tag starting at the '[' at `at`. Validates the tag name, the
// optional attribute and the presence of the closing ']'.
//
// Resolution: '[' '/' name ']' is a close tag (no attribute allowed on close
// tags; its whole body after '/' is the name); '[' name ']' and
// '[' name '=' value ']' are open tags, where only url may carry an
// attribute and the value must be non-empty.
//
// Returns: Ok(TagScan) with the classification and spans.
// Error case: Err("markup: unterminated tag at <at>"),
// Err("markup: unknown tag '<name>' at <at>"),
// Err("markup: bad attribute for '<tag>' at <at>").
// Complexity: O(tag length).
fn _mu_scan_tag(source: Str, at: Int) -> Result[TagScan, Str] {
  let close = _mu_find(source, at + 1, _MU_RBRACKET);
  if close < 0 {
    return _err_tag(_mu_err_pos("unterminated tag", at));
  }
  var is_close = 0;
  var name_start = at + 1;
  if _mu_byte(source, name_start) == _MU_SLASH {
    is_close = 1;
    name_start = name_start + 1;
  }
  var name_end = close;
  var has_eq = false;
  if is_close == 0 {
    var p = name_start;
    while p < close {
      if _mu_byte(source, p) == _MU_EQUALS {
        has_eq = true;
        break;
      }
      p = p + 1;
    }
    if has_eq {
      name_end = p;
    }
  }
  let name = string.str_slice(source, name_start, name_end);
  let code = markup_tag_code(name);
  if code == MARKUP_TAG_NONE {
    return _err_tag(_mu_err_pos("unknown tag '" + name + "'", at));
  }
  var attr_start = -1;
  var attr_end = -1;
  if has_eq {
    if code != MARKUP_TAG_URL {
      return _err_tag(_mu_err_pos("bad attribute for '" + markup_tag_name(code) + "'", at));
    }
    attr_start = name_end + 1;
    attr_end = close;
    if attr_end <= attr_start {
      return _err_tag(_mu_err_pos("bad attribute for 'url'", at));
    }
  }
  return _ok_tag(TagScan{ is_close: is_close; tag: code; attr_start: attr_start; attr_end: attr_end; end: close + 1; });
}

// Length of the literal `[/code]` at `at`, or 0 when absent. Used while inside
// a code span, where nothing else is interpreted.
fn _mu_match_code_close(source: Str, at: Int) -> Int {
  if _mu_match_lit(source, at, "[/code]") {
    return 7;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Entity recognition (for the two renderers)
// ---------------------------------------------------------------------------

// Byte length of a recognized named entity at `at`, or 0. Recognized:
// &amp; (5) &lt; (4) &gt; (4) &quot; (6). Every other '&' is literal text.
fn _mu_entity_len(source: Str, at: Int) -> Int {
  if _mu_byte(source, at) != _MU_AMP {
    return 0;
  }
  if _mu_match_lit(source, at, "&amp;") {
    return 5;
  }
  if _mu_match_lit(source, at, "&lt;") {
    return 4;
  }
  if _mu_match_lit(source, at, "&gt;") {
    return 4;
  }
  if _mu_match_lit(source, at, "&quot;") {
    return 6;
  }
  return 0;
}

// Decoded byte of a recognized entity (caller checks _mu_entity_len > 0):
// '&' for &amp;, '<' for &lt;, '>' for &gt;, '"' for &quot;.
fn _mu_entity_byte(source: Str, at: Int) -> Int {
  let c = _mu_byte(source, at + 1);
  if c == 97 {
    return 38;
  }
  if c == 108 {
    return 60;
  }
  if c == 103 {
    return 62;
  }
  return 34;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Parse `source` into span records, validating proper nesting.
///
/// Tags are recognized outside code spans; within `[code] ... [/code]` every
/// byte up to the first `[/code]` is literal. Text escapes (`\[`, `\]`, `\\`)
/// are validated, entities are not interpreted during parsing, and a close tag
/// must match the innermost open tag.
///
/// Params: source - the whole markup text.
/// Returns: Ok(Markup) with one record per closed tag pair, in open order.
/// Error case: the first error in source order, one of the exact messages in
/// the catalog at the top of this file.
/// Complexity: O(n * spans) worst case (stack search on mismatches).
pub fn markup_parse(source: Str) -> Result[Markup, Str] {
  var tags = Vec[Int].new();
  var open_starts = Vec[Int].new();
  var open_ends = Vec[Int].new();
  var close_starts = Vec[Int].new();
  var close_ends = Vec[Int].new();
  var attr_starts = Vec[Int].new();
  var attr_ends = Vec[Int].new();
  var close_order = Vec[Int].new();
  var stack_tags = Vec[Int].new();
  var stack_spans = Vec[Int].new();
  let n = source.len();
  var i = 0;
  var code_span = -1;
  while i < n {
    let b = _mu_byte(source, i);
    if code_span >= 0 {
      var clen = 0;
      if b == _MU_LBRACKET {
        clen = _mu_match_code_close(source, i);
      }
      if clen > 0 {
        close_starts[code_span] = i;
        close_ends[code_span] = i + clen;
        close_order.push(code_span);
        stack_tags.pop();
        stack_spans.pop();
        code_span = -1;
        i = i + clen;
      } else {
        i = i + 1;
      }
    } elif b == _MU_BACKSLASH {
      let e = _mu_byte(source, i + 1);
      if e == _MU_LBRACKET || e == _MU_RBRACKET || e == _MU_BACKSLASH {
        i = i + 2;
      } else {
        return _err_markup(_mu_err_pos("invalid escape", i));
      }
    } elif b == _MU_LBRACKET {
      let r = _mu_scan_tag(source, i);
      if !r.is_ok {
        return _err_markup(r.error);
      }
      let ts: TagScan = r.value;
      if ts.is_close == 1 {
        if stack_tags.len() == 0 {
          return _err_markup(_mu_err_pos("stray close tag '" + markup_tag_name(ts.tag) + "'", i));
        }
        let last = stack_tags.len() - 1;
        let top: Int = stack_tags[last];
        if top != ts.tag {
          var found = -1;
          var k = 0;
          while k < stack_tags.len() {
            let st: Int = stack_tags[k];
            if st == ts.tag {
              found = k;
            }
            k = k + 1;
          }
          if found < 0 {
            return _err_markup(_mu_err_pos("stray close tag '" + markup_tag_name(ts.tag) + "'", i));
          }
          return _err_markup(_mu_err_pos("cross-nested tags '" + markup_tag_name(top) + "' and '" + markup_tag_name(ts.tag) + "'", i));
        }
        let span: Int = stack_spans[last];
        close_starts[span] = i;
        close_ends[span] = ts.end;
        close_order.push(span);
        stack_tags.pop();
        stack_spans.pop();
        i = ts.end;
      } else {
        let span = tags.len();
        tags.push(ts.tag);
        open_starts.push(i);
        open_ends.push(ts.end);
        close_starts.push(-1);
        close_ends.push(-1);
        attr_starts.push(ts.attr_start);
        attr_ends.push(ts.attr_end);
        stack_tags.push(ts.tag);
        stack_spans.push(span);
        if ts.tag == MARKUP_TAG_CODE {
          code_span = span;
        }
        i = ts.end;
      }
    } else {
      i = i + 1;
    }
  }
  if stack_tags.len() > 0 {
    let last = stack_tags.len() - 1;
    let t: Int = stack_tags[last];
    let sp: Int = stack_spans[last];
    let o: Int = open_starts[sp];
    return _err_markup(_mu_err_pos("unclosed tag '" + markup_tag_name(t) + "'", o));
  }
  return _ok_markup(Markup{
    tags: tags;
    open_starts: open_starts;
    open_ends: open_ends;
    close_starts: close_starts;
    close_ends: close_ends;
    attr_starts: attr_starts;
    attr_ends: attr_ends;
    close_order: close_order;
  });
}

/// True when `source` parses without errors. Complexity: as markup_parse.
pub fn markup_is_valid(source: Str) -> Bool {
  let r = markup_parse(source);
  return r.is_ok;
}

// ---------------------------------------------------------------------------
// Span accessors
// ---------------------------------------------------------------------------

/// Number of tag-pair records. Complexity: O(1).
pub fn markup_span_count(m: &Markup) -> Int {
  return m.tags.len();
}

/// Tag code of record `i`, or MARKUP_TAG_NONE when `i` is out of range.
/// Complexity: O(1).
pub fn markup_span_tag(m: &Markup, i: Int) -> Int {
  if i < 0 || i >= m.tags.len() {
    return MARKUP_TAG_NONE;
  }
  let v: Int = m.tags[i];
  return v;
}

/// Start byte offset (inclusive) of the open tag of record `i`, or -1 when
/// out of range. Complexity: O(1).
pub fn markup_span_open_start(m: &Markup, i: Int) -> Int {
  if i < 0 || i >= m.open_starts.len() {
    return -1;
  }
  let v: Int = m.open_starts[i];
  return v;
}

/// End byte offset (exclusive) of the open tag of record `i`, or -1 when out
/// of range. Complexity: O(1).
pub fn markup_span_open_end(m: &Markup, i: Int) -> Int {
  if i < 0 || i >= m.open_ends.len() {
    return -1;
  }
  let v: Int = m.open_ends[i];
  return v;
}

/// Start byte offset (inclusive) of the close tag of record `i`, or -1 when
/// out of range. Complexity: O(1).
pub fn markup_span_close_start(m: &Markup, i: Int) -> Int {
  if i < 0 || i >= m.close_starts.len() {
    return -1;
  }
  let v: Int = m.close_starts[i];
  return v;
}

/// End byte offset (exclusive) of the close tag of record `i`, or -1 when out
/// of range. Complexity: O(1).
pub fn markup_span_close_end(m: &Markup, i: Int) -> Int {
  if i < 0 || i >= m.close_ends.len() {
    return -1;
  }
  let v: Int = m.close_ends[i];
  return v;
}

/// Raw attribute value of record `i` as a source slice, or "" when the tag has
/// no attribute or `i` is out of range. Params: source - the parsed text;
/// m - the parse result; i - the record index. Complexity: O(attr length).
pub fn markup_span_attr(source: Str, m: &Markup, i: Int) -> Str {
  if i < 0 || i >= m.attr_starts.len() {
    return "";
  }
  let a: Int = m.attr_starts[i];
  let e: Int = m.attr_ends[i];
  if a < 0 || e < a {
    return "";
  }
  return string.str_slice(source, a, e);
}

/// Raw inner text of record `i` (bytes between the open tag's end and the
/// close tag's start), or "" when out of range. No decoding is applied.
/// Complexity: O(inner length).
pub fn markup_span_inner(source: Str, m: &Markup, i: Int) -> Str {
  if i < 0 || i >= m.tags.len() {
    return "";
  }
  let a: Int = m.open_ends[i];
  let e: Int = m.close_starts[i];
  if a < 0 || e < a {
    return "";
  }
  return string.str_slice(source, a, e);
}

// ---------------------------------------------------------------------------
// Text emission
// ---------------------------------------------------------------------------

// Copy [from, to) verbatim.
fn _mu_copy_verbatim(out: &mut Vec[UInt8], source: Str, from: Int, to: Int) {
  var i = from;
  while i < to {
    let b = _mu_byte(source, i);
    builder.sb_push_byte(out, b as UInt8);
    i = i + 1;
  }
}

// Emit [from, to) with markup escapes and named entities decoded. The caller
// guarantees the range was accepted by markup_parse, so every '\' opens one
// of the three valid escapes; a defensive literal fallback is kept anyway.
fn _mu_emit_plain(out: &mut Vec[UInt8], source: Str, from: Int, to: Int) {
  var i = from;
  while i < to {
    let b = _mu_byte(source, i);
    if b == _MU_BACKSLASH {
      let e = _mu_byte(source, i + 1);
      if e == _MU_LBRACKET || e == _MU_RBRACKET || e == _MU_BACKSLASH {
        builder.sb_push_byte(out, e as UInt8);
        i = i + 2;
      } else {
        builder.sb_push_byte(out, _MU_BACKSLASH as UInt8);
        i = i + 1;
      }
    } elif b == _MU_AMP {
      let elen = _mu_entity_len(source, i);
      if elen > 0 {
        builder.sb_push_byte(out, _mu_entity_byte(source, i) as UInt8);
        i = i + elen;
      } else {
        builder.sb_push_byte(out, _MU_AMP as UInt8);
        i = i + 1;
      }
    } else {
      builder.sb_push_byte(out, b as UInt8);
      i = i + 1;
    }
  }
}

// Append one decoded byte to a canonical output: '[' ']' '\' are re-escaped
// with a backslash, every other byte is emitted verbatim.
fn _mu_push_canon(out: &mut Vec[UInt8], b: Int) {
  if b == _MU_LBRACKET || b == _MU_RBRACKET || b == _MU_BACKSLASH {
    builder.sb_push_byte(out, _MU_BACKSLASH as UInt8);
  }
  builder.sb_push_byte(out, b as UInt8);
}

// Emit [from, to) in canonical escaping: decode escapes and entities first,
// then re-escape only '[' ']' '\'. So "\[" stays "\[", "&amp;" becomes "&",
// and "&" stays "&" (it is not special outside entities).
fn _mu_emit_canon(out: &mut Vec[UInt8], source: Str, from: Int, to: Int) {
  var i = from;
  while i < to {
    let b = _mu_byte(source, i);
    if b == _MU_BACKSLASH {
      let e = _mu_byte(source, i + 1);
      if e == _MU_LBRACKET || e == _MU_RBRACKET || e == _MU_BACKSLASH {
        _mu_push_canon(out, e);
        i = i + 2;
      } else {
        _mu_push_canon(out, _MU_BACKSLASH);
        i = i + 1;
      }
    } elif b == _MU_AMP {
      let elen = _mu_entity_len(source, i);
      if elen > 0 {
        _mu_push_canon(out, _mu_entity_byte(source, i));
        i = i + elen;
      } else {
        _mu_push_canon(out, _MU_AMP);
        i = i + 1;
      }
    } else {
      _mu_push_canon(out, b);
      i = i + 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Renderers
// ---------------------------------------------------------------------------

/// Render `source` to plain text: every tag is stripped, `\[`, `\]`, `\\`
/// decode to `[`, `]`, `\`, and `&amp;`, `&lt;`, `&gt;`, `&quot;` decode to
/// `&`, `<`, `>`, `"`. Code content is copied verbatim (literal).
/// Params: source - the parsed text; m - its parse result.
/// Returns: the decoded text.
/// Error case: none (m is assumed to describe source).
/// Complexity: O(n) bytes plus O(spans).
pub fn markup_to_plain(source: Str, m: &Markup) -> Str {
  var out = Vec[UInt8].new();
  let n = source.len();
  let count = m.tags.len();
  var i = 0;
  var next_open = 0;
  var next_close = 0;
  var code_span = -1;
  while i < n {
    var open_at = -1;
    if next_open < count {
      open_at = m.open_starts[next_open];
    }
    var close_at = -1;
    if next_close < count {
      let ck: Int = m.close_order[next_close];
      close_at = m.close_starts[ck];
    }
    if open_at == i {
      let t: Int = m.tags[next_open];
      let oe: Int = m.open_ends[next_open];
      if t == MARKUP_TAG_CODE {
        code_span = next_open;
      }
      i = oe;
      next_open = next_open + 1;
    } elif close_at == i {
      let ck: Int = m.close_order[next_close];
      let ce: Int = m.close_ends[ck];
      if code_span == ck {
        code_span = -1;
      }
      i = ce;
      next_close = next_close + 1;
    } else {
      var stop = n;
      if open_at >= 0 && open_at < stop {
        stop = open_at;
      }
      if close_at >= 0 && close_at < stop {
        stop = close_at;
      }
      if code_span >= 0 {
        _mu_copy_verbatim(&mut out, source, i, stop);
      } else {
        _mu_emit_plain(&mut out, source, i, stop);
      }
      i = stop;
    }
  }
  return builder.sb_to_str(&out);
}

// Append the canonical open tag of record k: '[name]' or '[name=attr]'.
fn _mu_push_open_tag(out: &mut Vec[UInt8], source: Str, m: &Markup, k: Int) {
  builder.sb_push_str(out, "[");
  builder.sb_push_str(out, markup_tag_name(markup_span_tag(m, k)));
  let a: Int = m.attr_starts[k];
  if a >= 0 {
    let e: Int = m.attr_ends[k];
    builder.sb_push_str(out, "=");
    builder.sb_push_str(out, string.str_slice(source, a, e));
  }
  builder.sb_push_str(out, "]");
}

// Append the canonical close tag of record k: '[/name]'.
fn _mu_push_close_tag(out: &mut Vec[UInt8], m: &Markup, k: Int) {
  builder.sb_push_str(out, "[/");
  builder.sb_push_str(out, markup_tag_name(markup_span_tag(m, k)));
  builder.sb_push_str(out, "]");
}

/// Re-serialize `source` canonically: tags are re-emitted in their original
/// spelling ([b], [url=attr], ...), text is emitted with minimal escaping
/// ('[' ']' '\' escaped), escapes and named entities are decoded first, and
/// code content is copied verbatim.
/// Params: source - the parsed text; m - its parse result.
/// Returns: the canonical serialization; reparsing it yields the same records
/// and the same decoded plain text.
/// Error case: none.
/// Complexity: O(n) bytes plus O(spans).
pub fn markup_to_canonical(source: Str, m: &Markup) -> Str {
  var out = Vec[UInt8].new();
  let n = source.len();
  let count = m.tags.len();
  var i = 0;
  var next_open = 0;
  var next_close = 0;
  var code_span = -1;
  while i < n {
    var open_at = -1;
    if next_open < count {
      open_at = m.open_starts[next_open];
    }
    var close_at = -1;
    if next_close < count {
      let ck: Int = m.close_order[next_close];
      close_at = m.close_starts[ck];
    }
    if open_at == i {
      let t: Int = m.tags[next_open];
      let oe: Int = m.open_ends[next_open];
      _mu_push_open_tag(&mut out, source, m, next_open);
      if t == MARKUP_TAG_CODE {
        code_span = next_open;
      }
      i = oe;
      next_open = next_open + 1;
    } elif close_at == i {
      let ck: Int = m.close_order[next_close];
      let ce: Int = m.close_ends[ck];
      _mu_push_close_tag(&mut out, m, ck);
      if code_span == ck {
        code_span = -1;
      }
      i = ce;
      next_close = next_close + 1;
    } else {
      var stop = n;
      if open_at >= 0 && open_at < stop {
        stop = open_at;
      }
      if close_at >= 0 && close_at < stop {
        stop = close_at;
      }
      if code_span >= 0 {
        _mu_copy_verbatim(&mut out, source, i, stop);
      } else {
        _mu_emit_canon(&mut out, source, i, stop);
      }
      i = stop;
    }
  }
  return builder.sb_to_str(&out);
}

/// Parse then render to plain text in one call.
/// Params: source - the markup text.
/// Returns: Ok(plain text) on a valid document; Err(message) otherwise.
/// Complexity: as markup_parse plus markup_to_plain.
pub fn markup_plain(source: Str) -> Result[Str, Str] {
  let r = markup_parse(source);
  if !r.is_ok {
    return _err_text(r.error);
  }
  let m: Markup = r.value;
  return _ok_text(markup_to_plain(source, &m));
}

/// Parse then re-serialize canonically in one call.
/// Params: source - the markup text.
/// Returns: Ok(canonical text) on a valid document; Err(message) otherwise.
/// Complexity: as markup_parse plus markup_to_canonical.
pub fn markup_canonical(source: Str) -> Result[Str, Str] {
  let r = markup_parse(source);
  if !r.is_ok {
    return _err_text(r.error);
  }
  let m: Markup = r.value;
  return _ok_text(markup_to_canonical(source, &m));
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only -- see the module header)
// ---------------------------------------------------------------------------

fn _ok_tag(t: TagScan) -> Result[TagScan, Str] {
  return Ok(t);
}

fn _err_tag(m: Str) -> Result[TagScan, Str] {
  return Err(m);
}

fn _ok_markup(v: Markup) -> Result[Markup, Str] {
  return Ok(v);
}

fn _err_markup(m: Str) -> Result[Markup, Str] {
  return Err(m);
}

fn _ok_text(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_text(m: Str) -> Result[Str, Str] {
  return Err(m);
}
