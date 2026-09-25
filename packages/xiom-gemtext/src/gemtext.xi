// XIOM -- xiom.gemtext: Gemtext line codec (parser + canonical emitter)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM codec for Gemtext, the line-based text format of the Gemini
// protocol. The parser classifies every input line into one of eight kinds
// and stores the document flat: parallel Vecs for kinds, texts, link urls,
// link labels and heading levels, plus a pair of Vecs describing the
// preformatted spans. The emitter writes the canonical form: every line in
// document order with normalized markers and exactly one trailing LF; the
// empty document emits the empty string.
//
// Line kinds (gemtext_kind):
//   "text"              any line that opens no other construct
//   "link"              "=>" [whitespace] URL [whitespace label]; URL required
//   "heading"           1..3 '#' then a space (0x20) or end of line
//   "list-item"         "*" alone or "* text"
//   "quote"             ">" alone or "> text" (the space is optional)
//   "preformatted"      a ``` toggle; an opening toggle's text is its alt text
//   "preformatted-text" a raw line inside a preformatted block
//   "blank"             empty or whitespace-only line
//
// Grammar and decisions (SPEC.md holds the full tables):
//   * CRLF is normalized to LF: one CR immediately before an LF is stripped.
//     Any other control byte (C0 except TAB/LF/CR, plus DEL) is rejected with
//     Err("gemtext: control byte <byte> at <pos>").
//   * A "=>" line whose remainder is empty or whitespace-only is
//     Err("gemtext: link with missing url at <pos>"), <pos> being the byte
//     offset of the line's first byte.
//   * URLs may not contain whitespace: the URL ends at the first space/tab
//     and the rest of the line is the optional label (leading whitespace
//     dropped, trailing whitespace kept). There is no URL validation beyond
//     non-empty and whitespace-free.
//   * Heading markers need a literal space; "#### x", "#x" and "##\tx" are
//     text lines. Heading text is whitespace-trimmed.
//   * A preformatted block opens on a line starting with ``` and closes on
//     the next line starting with ``` (EOF closes leniently). Inside the
//     block every line is raw "preformatted-text", even if it starts with
//     "=>" or "#"; the closing toggle's trailing bytes are ignored, and the
//     opening toggle's trailing bytes (trimmed) are the alt text.
//
// Language notes (XIOM v0.61.3): free functions only; no Vec[StructType]
// (all storage is parallel Vecs); no inline lambdas; Str values read from
// Vec[Str] elements are compared with xiom.string.compare.str_compare
// (BUG 17: `==` on such elements lowers to a pointer comparison); Vec[Int]
// element reads are bound to typed locals; Ok/Err are constructed only in
// the leaf helpers _ok_doc/_err_doc; `as` is a reserved keyword.

module xiom.gemtext

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Document container
// --------------------------------------------------

// A parsed Gemtext document in flat storage. Index i of kinds/texts/urls/
// labels/levels describes the same source line: urls and labels are "" outside
// "link" lines, levels is 0 outside "heading" lines. pre_starts/pre_ends hold
// one line-index pair per preformatted block: the opening toggle line and one
// past the closing toggle line, so the block occupies the half-open range
// [start, end) and includes both toggle lines. Parsing always keeps all seven
// Vecs aligned; use the accessors below (they range-check) instead of reading
// the fields directly.
pub type GemtextDoc = {
  kinds: Vec[Str];
  texts: Vec[Str];
  urls: Vec[Str];
  labels: Vec[Str];
  levels: Vec[Int];
  pre_starts: Vec[Int];
  pre_ends: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[GemtextDoc, Str].
fn _ok_doc(v: GemtextDoc) -> Result[GemtextDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[GemtextDoc, Str].
fn _err_doc(m: Str) -> Result[GemtextDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and small predicates
// --------------------------------------------------

const _GT_TAB: UInt8 = 9u8;
const _GT_LF: UInt8 = 10u8;
const _GT_CR: UInt8 = 13u8;
const _GT_SPACE: UInt8 = 32u8;
const _GT_HASH: UInt8 = 35u8;
const _GT_STAR: UInt8 = 42u8;
const _GT_GT: UInt8 = 62u8;
const _GT_TICK: UInt8 = 96u8;
const _GT_DEL: UInt8 = 127u8;

// Space or tab: the whitespace bytes recognized inside a line.
fn _is_hspace(b: UInt8) -> Bool {
  if b == _GT_SPACE { return true; }
  if b == _GT_TAB { return true; }
  return false;
}

// True when `line` starts with the literal byte sequence `lit` (byte-wise;
// never Str equality, so BUG 17 cannot bite).
fn _starts_with(line: Str, lit: Str) -> Bool {
  if line.len() < lit.len() { return false; }
  var i = 0;
  while i < lit.len() {
    if string.byte_at(line, i) != string.byte_at(lit, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Blank: empty or whitespace-only (whitespace via str_trim).
fn _is_blank(line: Str) -> Bool {
  return string.str_trim(line).len() == 0;
}

// 1, 2 or 3 when the line is that many '#' followed by a literal space (0x20)
// or by the end of the line; 0 otherwise (so "#### x", "#x", "##\tx" and
// " # x" are text lines).
fn _heading_level(line: Str) -> Int {
  let len = line.len();
  var count = 0;
  while count < len {
    if string.byte_at(line, count) != _GT_HASH { break; }
    count = count + 1;
  }
  if count == 0 || count > 3 { return 0; }
  if count == len { return count; }
  if string.byte_at(line, count) == _GT_SPACE { return count; }
  return 0;
}

// True for a list-item marker: "*" alone or "*" followed by a space.
fn _is_list_item(line: Str) -> Bool {
  let len = line.len();
  if len == 0 { return false; }
  if string.byte_at(line, 0) != _GT_STAR { return false; }
  if len == 1 { return true; }
  return string.byte_at(line, 1) == _GT_SPACE;
}

// Item text after the marker: "" for a lone "*", the rest otherwise.
fn _list_text(line: Str) -> Str {
  let len = line.len();
  if len <= 1 { return ""; }
  return string.str_slice(line, 2, len);
}

// True for a quote line: a non-empty line whose first byte is ">".
fn _is_quote(line: Str) -> Bool {
  if line.len() == 0 { return false; }
  return string.byte_at(line, 0) == _GT_GT;
}

// Quote text after the marker: "> " drops two bytes, ">" drops one.
fn _quote_text(line: Str) -> Str {
  let len = line.len();
  if len <= 1 { return ""; }
  if string.byte_at(line, 1) == _GT_SPACE {
    return string.str_slice(line, 2, len);
  }
  return string.str_slice(line, 1, len);
}

// --------------------------------------------------
//  Character validation and line splitting
// --------------------------------------------------

// Byte offset of the first byte that may not appear in a Gemtext document, or
// -1 when the input is clean. TAB, LF and CR immediately before LF are the
// only accepted control bytes; every other C0 byte (including NUL) and DEL is
// rejected. Bytes >= 0x80 pass through untouched (no UTF-8 validation).
fn _first_control_byte(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    // Widen every byte with `& 0xFF` before range comparisons so bytes >= 0x80
    // (UTF-8 lead/continuation bytes) can never sign-extend into the C0 range.
    let b = string.byte_at(s, i);
    let v = (b as Int) & 0xFF;
    if v == 9 || v == 10 {
      i = i + 1;
    } elif v == 13 {
      if i + 1 < n {
        let next = (string.byte_at(s, i + 1) as Int) & 0xFF;
        if next == 10 {
          i = i + 1;
        } else {
          return i;
        }
      } else {
        return i;
      }
    } elif v < 32 {
      return i;
    } elif v == (_GT_DEL as Int) & 0xFF {
      return i;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Drop one trailing CR (CRLF line endings).
fn _drop_cr(line: Str) -> Str {
  let len = line.len();
  if len > 0 {
    if string.byte_at(line, len - 1) == _GT_CR {
      return string.str_slice(line, 0, len - 1);
    }
  }
  return line;
}

// Split `s` on LF into `lines`, pushing each line's byte offset into `starts`
// (both Vecs are passed by &mut and receive one entry per line). One trailing
// CR per line is dropped; a trailing LF adds no extra empty line; empty input
// yields zero lines.
fn _split_lines(s: Str, lines: &mut Vec[Str], starts: &mut Vec[Int]) {
  let n = s.len();
  var start = 0;
  var i = 0;
  while i < n {
    if string.byte_at(s, i) == _GT_LF {
      starts.push(start);
      lines.push(_drop_cr(string.str_slice(s, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < n {
    starts.push(start);
    lines.push(_drop_cr(string.str_slice(s, start, n)));
  }
}

// --------------------------------------------------
//  Line classification
// --------------------------------------------------

// The url and optional label of a "=>" line. ok is false when no URL is
// present (the remainder is empty or whitespace-only).
type _LinkParts = {
  ok: Bool;
  url: Str;
  label: Str;
}

// Split a "=>" line into url and label. Whitespace after "=>" is optional;
// the URL runs to the first space/tab; the label is the rest of the line with
// its leading whitespace dropped (trailing whitespace is kept).
fn _link_parts(line: Str) -> _LinkParts {
  let len = line.len();
  var j = 2;
  while j < len {
    if !_is_hspace(string.byte_at(line, j)) { break; }
    j = j + 1;
  }
  if j >= len {
    return _LinkParts{ ok: false; url: ""; label: ""; };
  }
  let url_start = j;
  while j < len {
    if _is_hspace(string.byte_at(line, j)) { break; }
    j = j + 1;
  }
  let url = string.str_slice(line, url_start, j);
  while j < len {
    if !_is_hspace(string.byte_at(line, j)) { break; }
    j = j + 1;
  }
  let label = string.str_slice(line, j, len);
  return _LinkParts{ ok: true; url: url; label: label; };
}

// Classification of one line outside a preformatted block. ok is false only
// for a "=>" line with a missing URL.
type _LineInfo = {
  ok: Bool;
  kind: Str;
  text: Str;
  url: Str;
  label: Str;
  level: Int;
}

// Classify one non-preformatted line (first match wins): blank, preformatted
// toggle, link, heading, list-item, quote, text. See SPEC.md for the exact
// line grammar.
fn _classify(line: Str) -> _LineInfo {
  if _is_blank(line) {
    return _LineInfo{ ok: true; kind: "blank"; text: ""; url: ""; label: ""; level: 0; };
  }
  if _starts_with(line, "```") {
    let alt = string.str_trim(string.str_slice(line, 3, line.len()));
    return _LineInfo{ ok: true; kind: "preformatted"; text: alt; url: ""; label: ""; level: 0; };
  }
  if _starts_with(line, "=>") {
    let parts = _link_parts(line);
    if !parts.ok {
      return _LineInfo{ ok: false; kind: ""; text: ""; url: ""; label: ""; level: 0; };
    }
    return _LineInfo{ ok: true; kind: "link"; text: ""; url: parts.url; label: parts.label; level: 0; };
  }
  let lvl = _heading_level(line);
  if lvl > 0 {
    let htext = string.str_trim(string.str_slice(line, lvl, line.len()));
    return _LineInfo{ ok: true; kind: "heading"; text: htext; url: ""; label: ""; level: lvl; };
  }
  if _is_list_item(line) {
    return _LineInfo{ ok: true; kind: "list-item"; text: _list_text(line); url: ""; label: ""; level: 0; };
  }
  if _is_quote(line) {
    return _LineInfo{ ok: true; kind: "quote"; text: _quote_text(line); url: ""; label: ""; level: 0; };
  }
  return _LineInfo{ ok: true; kind: "text"; text: line; url: ""; label: ""; level: 0; };
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse a Gemtext document. Input is a UTF-8 byte buffer; its lines are
/// classified and stored flat, in order, one entry per line.
/// Params: text - the whole document (LF or CRLF line endings; TAB, LF and
/// CR-before-LF are the only accepted control bytes).
/// Returns: Ok(GemtextDoc). CRLF is normalized to LF; the empty document has
/// zero lines; a trailing LF adds no empty line.
/// Error case:
///   * Err("gemtext: control byte <byte> at <pos>") for the first C0 byte
///     other than TAB/LF and CR-before-LF, or DEL; <pos> is its 0-based byte
///     offset and <byte> its unsigned decimal value.
///   * Err("gemtext: link with missing url at <pos>") for a "=>" line whose
///     remainder is empty or whitespace-only; <pos> is the byte offset of the
///     line's first byte.
/// Complexity: O(n) over the input bytes.
pub fn gemtext_parse(text: Str) -> Result[GemtextDoc, Str] {
  let bad = _first_control_byte(text);
  if bad >= 0 {
    let b = string.byte_at(text, bad);
    let v = (b as Int) & 0xFF;
    return _err_doc("gemtext: control byte " + int_to_string(v) + " at " + int_to_string(bad));
  }
  var lines = Vec[Str].new();
  var starts = Vec[Int].new();
  _split_lines(text, &mut lines, &mut starts);
  var kinds = Vec[Str].new();
  var texts = Vec[Str].new();
  var urls = Vec[Str].new();
  var labels = Vec[Str].new();
  var levels = Vec[Int].new();
  var pre_starts = Vec[Int].new();
  var pre_ends = Vec[Int].new();
  var in_pre = false;
  var i = 0;
  while i < lines.len() {
    let line: Str = lines[i];
    if in_pre {
      if _starts_with(line, "```") {
        kinds.push("preformatted");
        texts.push("");
        urls.push("");
        labels.push("");
        levels.push(0);
        pre_ends.push(i + 1);
        in_pre = false;
      } else {
        kinds.push("preformatted-text");
        texts.push(line);
        urls.push("");
        labels.push("");
        levels.push(0);
      }
    } else {
      let info = _classify(line);
      if !info.ok {
        let ls: Int = starts[i];
        return _err_doc("gemtext: link with missing url at " + int_to_string(ls));
      }
      kinds.push(info.kind);
      texts.push(info.text);
      urls.push(info.url);
      labels.push(info.label);
      levels.push(info.level);
      if compare.str_compare(info.kind, "preformatted") == 0 {
        pre_starts.push(i);
        in_pre = true;
      }
    }
    i = i + 1;
  }
  if in_pre {
    pre_ends.push(lines.len());
  }
  return _ok_doc(GemtextDoc{
    kinds: kinds;
    texts: texts;
    urls: urls;
    labels: labels;
    levels: levels;
    pre_starts: pre_starts;
    pre_ends: pre_ends;
  });
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of lines in `d` (one entry per source line, in document order).
/// Params: d - the document.
/// Returns: the line count; 0 for the empty document.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_line_count(d: &GemtextDoc) -> Int {
  return d.kinds.len();
}

/// Kind of line `i` (see the module header for the eight kind strings).
/// Params: d - the document; i - the zero-based line index.
/// Returns: the kind string; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_kind(d: &GemtextDoc, i: Int) -> Str {
  if i < 0 || i >= d.kinds.len() {
    return "";
  }
  return d.kinds[i];
}

/// Text of line `i`: the line text for "text", the heading text for "heading",
/// the item text for "list-item", the quote text for "quote", the alt text on
/// an opening toggle for "preformatted", the raw line for "preformatted-text"
/// and "" for "blank", "link" and a closing toggle.
/// Params: d - the document; i - the zero-based line index.
/// Returns: the line text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_text(d: &GemtextDoc, i: Int) -> Str {
  if i < 0 || i >= d.texts.len() {
    return "";
  }
  return d.texts[i];
}

/// URL of link line `i`.
/// Params: d - the document; i - the zero-based line index.
/// Returns: the URL; "" when `i` is out of range or line `i` is not a link.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_link_url(d: &GemtextDoc, i: Int) -> Str {
  if i < 0 || i >= d.urls.len() {
    return "";
  }
  return d.urls[i];
}

/// Label of link line `i` (may be "" when the link has no label).
/// Params: d - the document; i - the zero-based line index.
/// Returns: the label; "" when `i` is out of range or line `i` is not a link.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_link_label(d: &GemtextDoc, i: Int) -> Str {
  if i < 0 || i >= d.labels.len() {
    return "";
  }
  return d.labels[i];
}

/// Heading level of line `i`: 1, 2 or 3.
/// Params: d - the document; i - the zero-based line index.
/// Returns: the heading level; 0 when `i` is out of range or line `i` is not
/// a heading.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_heading_level(d: &GemtextDoc, i: Int) -> Int {
  if i < 0 || i >= d.levels.len() {
    return 0;
  }
  let lvl: Int = d.levels[i];
  return lvl;
}

/// Number of preformatted blocks in `d` (one span per opening/closing toggle
/// pair).
/// Params: d - the document.
/// Returns: the span count; 0 when the document has no preformatted block.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_preformatted_span_count(d: &GemtextDoc) -> Int {
  var n = d.pre_starts.len();
  if d.pre_ends.len() < n { n = d.pre_ends.len(); }
  return n;
}

/// First line index of preformatted span `s` (the opening toggle line).
/// Params: d - the document; s - the zero-based span index.
/// Returns: the opening toggle line index; -1 when `s` is negative or out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_preformatted_start(d: &GemtextDoc, s: Int) -> Int {
  if s < 0 || s >= d.pre_starts.len() { return -1; }
  if s >= d.pre_ends.len() { return -1; }
  let v: Int = d.pre_starts[s];
  return v;
}

/// One past the last line index of preformatted span `s` (one past the
/// closing toggle line, so the span covers [start, end); a block left open at
/// end of input closes leniently at the line count).
/// Params: d - the document; s - the zero-based span index.
/// Returns: the exclusive end line index; -1 when `s` is negative or out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn gemtext_preformatted_end(d: &GemtextDoc, s: Int) -> Int {
  if s < 0 || s >= d.pre_ends.len() { return -1; }
  if s >= d.pre_starts.len() { return -1; }
  let v: Int = d.pre_ends[s];
  return v;
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

/// Emit the canonical Gemtext form of `d`: every line in document order with
/// markers normalized (one space after `=>`, `#`, `##`, `###`, `*`, `>`, and
/// after an opening ``` when the alt text is non-empty) and exactly one LF
/// after every line. The empty document emits "".
/// Params: d - the document (parse-produced documents round-trip exactly;
/// hand-built documents are emitted best-effort and heading levels outside
/// 1..3 are clamped to that range).
/// Returns: the canonical document text.
/// Error case: none. Parse never yields an unpaired toggle; if a hand-built
/// document leaves a preformatted block open, the output keeps it open (its
/// parse would close leniently at EOF).
/// Complexity: O(n) over the emitted bytes.
pub fn gemtext_emit(d: &GemtextDoc) -> Str {
  var out = Vec[UInt8].new();
  let n = d.kinds.len();
  var in_pre = false;
  var i = 0;
  while i < n {
    let k: Str = d.kinds[i];
    if compare.str_compare(k, "preformatted") == 0 {
      builder.sb_push_str(&mut out, "```");
      if !in_pre {
        let alt = gemtext_text(d, i);
        if alt.len() > 0 {
          builder.sb_push_str(&mut out, " ");
          builder.sb_push_str(&mut out, alt);
        }
        in_pre = true;
      } else {
        in_pre = false;
      }
    } elif compare.str_compare(k, "preformatted-text") == 0 {
      builder.sb_push_str(&mut out, gemtext_text(d, i));
    } elif compare.str_compare(k, "blank") == 0 {
      // A blank line emits as an empty line.
    } elif compare.str_compare(k, "link") == 0 {
      builder.sb_push_str(&mut out, "=>");
      let url = gemtext_link_url(d, i);
      let lbl = gemtext_link_label(d, i);
      if url.len() > 0 {
        builder.sb_push_str(&mut out, " ");
        builder.sb_push_str(&mut out, url);
        if lbl.len() > 0 {
          builder.sb_push_str(&mut out, " ");
          builder.sb_push_str(&mut out, lbl);
        }
      } elif lbl.len() > 0 {
        builder.sb_push_str(&mut out, " ");
        builder.sb_push_str(&mut out, lbl);
      }
    } elif compare.str_compare(k, "heading") == 0 {
      var lvl = gemtext_heading_level(d, i);
      if lvl < 1 { lvl = 1; }
      if lvl > 3 { lvl = 3; }
      var h = 0;
      while h < lvl {
        out.push(_GT_HASH);
        h = h + 1;
      }
      let txt = gemtext_text(d, i);
      if txt.len() > 0 {
        builder.sb_push_str(&mut out, " ");
        builder.sb_push_str(&mut out, txt);
      }
    } elif compare.str_compare(k, "list-item") == 0 {
      out.push(_GT_STAR);
      let txt = gemtext_text(d, i);
      if txt.len() > 0 {
        builder.sb_push_str(&mut out, " ");
        builder.sb_push_str(&mut out, txt);
      }
    } elif compare.str_compare(k, "quote") == 0 {
      out.push(_GT_GT);
      let txt = gemtext_text(d, i);
      if txt.len() > 0 {
        builder.sb_push_str(&mut out, " ");
        builder.sb_push_str(&mut out, txt);
      }
    } else {
      builder.sb_push_str(&mut out, gemtext_text(d, i));
    }
    out.push(_GT_LF);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
