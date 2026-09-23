// XIOM -- xiom.markdown: Markdown subset to HTML renderer
// Port task: replace the xiom.markdown placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Block subset (line-based; LF separates lines and one trailing CR per line is
// stripped, so CRLF input works):
//   "# " .. "###### " headings           -> <h1> .. <h6>
//   blank-line separated paragraphs     -> <p> (continuation lines joined by one space)
//   contiguous "- " / "* " lines        -> <ul> with one <li> per line
//   contiguous "1. " lines (any digits) -> <ol> with one <li> per line
//   contiguous "> " lines               -> <blockquote> (content rendered recursively)
//   "---" / "***" alone                 -> <hr>
//   fenced ``` blocks (optional tag)    -> <pre><code[ class="language-X"]> ...
// Inline subset (headings, paragraphs, list items, blockquote content):
//   **bold** -> <strong>, *italic* -> <em>, `code` -> <code>, [text](url) -> <a>
// Every text run emitted into HTML goes through the same escaper (& < > "),
// including inline-code content and link URLs (attribute-escaped). See SPEC.md
// for the exact rendering tables, the documented limits (no emphasis nesting,
// no images, no reference links, no tables, no raw HTML) and the test plan.
//
// v0.61.3 notes that shaped this module:
//   * All Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); block markers are classified byte-wise instead.
//   * Byte output is collected in Vec[UInt8] builders and materialized with
//     xiom.string.builder.sb_to_str (one allocation per Str).
//   * No FFI, no Vec[StructType], no inline lambdas, free functions only.

module xiom.markdown

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (ASCII only, so byte_at comparisons stay safe)
// --------------------------------------------------

const _MD_LF: UInt8 = 10u8;
const _MD_CR: UInt8 = 13u8;
const _MD_TAB: UInt8 = 9u8;
const _MD_SPACE: UInt8 = 32u8;
const _MD_HASH: UInt8 = 35u8;
const _MD_STAR: UInt8 = 42u8;
const _MD_DASH: UInt8 = 45u8;
const _MD_DOT: UInt8 = 46u8;
const _MD_GT: UInt8 = 62u8;
const _MD_LBRACKET: UInt8 = 91u8;
const _MD_RBRACKET: UInt8 = 93u8;
const _MD_LPAREN: UInt8 = 40u8;
const _MD_RPAREN: UInt8 = 41u8;
const _MD_TICK: UInt8 = 96u8;
const _MD_AMP: UInt8 = 38u8;
const _MD_LT: UInt8 = 60u8;
const _MD_QUOTE: UInt8 = 34u8;

// --------------------------------------------------
//  Small byte and line helpers
// --------------------------------------------------

fn _is_hspace(b: UInt8) -> Bool {
  if b == _MD_SPACE { return true; }
  if b == _MD_TAB { return true; }
  return false;
}

// True when `line` starts with the literal `lit` (byte comparison; never Str
// equality, so BUG 17 cannot bite).
fn _starts_with(line: Str, lit: Str) -> Bool {
  if line.len() < lit.len() { return false; }
  var i = 0;
  while i < lit.len() {
    if string.byte_at(line, i) != string.byte_at(lit, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Drop trailing spaces/tabs.
fn _rstrip(s: Str) -> Str {
  var end = s.len();
  while end > 0 {
    if !_is_hspace(string.byte_at(s, end - 1)) { break; }
    end = end - 1;
  }
  return string.str_slice(s, 0, end);
}

// Drop one trailing CR (CRLF line endings).
fn _rstrip_cr(line: Str) -> Str {
  let len = line.len();
  if len > 0 {
    if string.byte_at(line, len - 1) == _MD_CR {
      return string.str_slice(line, 0, len - 1);
    }
  }
  return line;
}

// Split into lines on LF, dropping one trailing CR per line. A trailing LF
// produces no extra empty line; empty input yields zero lines.
fn _split_lines(md: Str) -> Vec[Str] {
  var lines = Vec[Str].new();
  let n = md.len();
  var start = 0;
  var i = 0;
  while i < n {
    if string.byte_at(md, i) == _MD_LF {
      lines.push(_rstrip_cr(string.str_slice(md, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < n {
    lines.push(_rstrip_cr(string.str_slice(md, start, n)));
  }
  return lines;
}

// Blank means empty or whitespace-only (Unicode whitespace via str_trim).
fn _is_blank(line: Str) -> Bool {
  return string.str_trim(line).len() == 0;
}

// --------------------------------------------------
//  HTML escaping
// --------------------------------------------------

// Append `s` with & < > " replaced by named entities; every other byte
// (including UTF-8 sequences) passes through verbatim.
fn _push_escaped(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _MD_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _MD_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _MD_GT {
      builder.sb_push_str(out, "&gt;");
    } elif b == _MD_QUOTE {
      builder.sb_push_str(out, "&quot;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

/// Escape `&`, `<`, `>` and `"` as HTML entities.
/// Params: s - arbitrary text (UTF-8 bytes; only those four ASCII bytes are
/// rewritten).
/// Returns: the escaped text; every other byte passes through verbatim.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn markdown_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  _push_escaped(&mut out, s);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Inline scanning
// --------------------------------------------------

// First index of byte `target` at or after `from`; -1 when absent.
fn _find_byte(s: Str, from: Int, target: UInt8) -> Int {
  var i = from;
  if i < 0 { i = 0; }
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

// First index of the two-byte sequence "**" at or after `from`; -1 when absent.
fn _find_double_star(s: Str, from: Int) -> Int {
  var i = from;
  if i < 0 { i = 0; }
  while i + 1 < s.len() {
    if string.byte_at(s, i) == _MD_STAR {
      if string.byte_at(s, i + 1) == _MD_STAR { return i; }
    }
    i = i + 1;
  }
  return -1;
}

// First index of the two-byte sequence "](" at or after `from`; -1 when absent.
fn _find_bracket_paren(s: Str, from: Int) -> Int {
  var i = from;
  if i < 0 { i = 0; }
  while i + 1 < s.len() {
    if string.byte_at(s, i) == _MD_RBRACKET {
      if string.byte_at(s, i + 1) == _MD_LPAREN { return i; }
    }
    i = i + 1;
  }
  return -1;
}

// If a strong span starts at `at` ("**"), append it and return the index after
// its closing "**"; return -1 (emitting nothing) otherwise. The span body is
// escaped literal text: emphasis never nests.
fn _try_strong(out: &mut Vec[UInt8], s: Str, at: Int) -> Int {
  if at + 1 >= s.len() { return -1; }
  if string.byte_at(s, at + 1) != _MD_STAR { return -1; }
  let close = _find_double_star(s, at + 2);
  if close < 0 { return -1; }
  let body = string.str_slice(s, at + 2, close);
  builder.sb_push_str(out, "<strong>");
  _push_escaped(out, body);
  builder.sb_push_str(out, "</strong>");
  return close + 2;
}

// If a non-empty italic span starts at `at` (a single "*"), append it and
// return the index after its closing "*"; return -1 (emitting nothing)
// otherwise. The span body is escaped literal text: emphasis never nests.
fn _try_em(out: &mut Vec[UInt8], s: Str, at: Int) -> Int {
  let close = _find_byte(s, at + 1, _MD_STAR);
  if close < 0 { return -1; }
  if close == at + 1 { return -1; }
  let body = string.str_slice(s, at + 1, close);
  builder.sb_push_str(out, "<em>");
  _push_escaped(out, body);
  builder.sb_push_str(out, "</em>");
  return close + 1;
}

// If a code span starts at `at` ("`"), append it and return the index after
// the closing backtick; return -1 (emitting nothing) otherwise.
fn _try_code(out: &mut Vec[UInt8], s: Str, at: Int) -> Int {
  let close = _find_byte(s, at + 1, _MD_TICK);
  if close < 0 { return -1; }
  let body = string.str_slice(s, at + 1, close);
  builder.sb_push_str(out, "<code>");
  _push_escaped(out, body);
  builder.sb_push_str(out, "</code>");
  return close + 1;
}

// If an inline link "[text](url)" starts at `at`, append it and return the
// index after the closing ")"; return -1 (emitting nothing) otherwise. The
// URL is escaped into the href attribute; the link text is parsed for inline
// markup recursively.
fn _try_link(out: &mut Vec[UInt8], s: Str, at: Int) -> Int {
  let mid = _find_bracket_paren(s, at + 1);
  if mid < 0 { return -1; }
  let close = _find_byte(s, mid + 2, _MD_RPAREN);
  if close < 0 { return -1; }
  let label = string.str_slice(s, at + 1, mid);
  let url = string.str_slice(s, mid + 2, close);
  builder.sb_push_str(out, "<a href=\"");
  _push_escaped(out, url);
  builder.sb_push_str(out, "\">");
  _push_inline(out, label);
  builder.sb_push_str(out, "</a>");
  return close + 1;
}

// Append the inline rendering of `s` (see the module header for the subset).
// Runs that open no recognized span emit their first byte literally and the
// scan continues (left-to-right, non-nesting matching).
fn _push_inline(out: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _MD_TICK {
      let next = _try_code(out, s, i);
      if next < 0 {
        out.push(b);
        i = i + 1;
      } else {
        i = next;
      }
    } elif b == _MD_STAR {
      var next = _try_strong(out, s, i);
      if next < 0 { next = _try_em(out, s, i); }
      if next < 0 {
        out.push(b);
        i = i + 1;
      } else {
        i = next;
      }
    } elif b == _MD_LBRACKET {
      let next = _try_link(out, s, i);
      if next < 0 {
        out.push(b);
        i = i + 1;
      } else {
        i = next;
      }
    } else {
      let start = i;
      while i < n {
        let c = string.byte_at(s, i);
        if c == _MD_TICK || c == _MD_STAR || c == _MD_LBRACKET { break; }
        i = i + 1;
      }
      let run = string.str_slice(s, start, i);
      _push_escaped(out, run);
    }
  }
}

// --------------------------------------------------
//  Block classification
// --------------------------------------------------

// 1..6 when the line is 1..6 '#' followed by a space or end of line; 0
// otherwise (7+ hashes and '#' without a following space are paragraphs).
fn _heading_level(line: Str) -> Int {
  let len = line.len();
  var count = 0;
  while count < len {
    if string.byte_at(line, count) != _MD_HASH { break; }
    count = count + 1;
  }
  if count == 0 || count > 6 { return 0; }
  if count == len { return count; }
  if string.byte_at(line, count) == _MD_SPACE { return count; }
  return 0;
}

// True for "---" or "***" (trailing spaces/tabs ignored).
fn _is_hr(line: Str) -> Bool {
  let t = _rstrip(line);
  if compare.str_compare(t, "---") == 0 { return true; }
  if compare.str_compare(t, "***") == 0 { return true; }
  return false;
}

fn _is_blockquote(line: Str) -> Bool {
  if line.len() == 0 { return false; }
  return string.byte_at(line, 0) == _MD_GT;
}

// Blockquote content after the marker: "> " drops two bytes, ">" drops one.
fn _blockquote_content(line: Str) -> Str {
  let len = line.len();
  if len <= 1 { return ""; }
  if string.byte_at(line, 1) == _MD_SPACE {
    return string.str_slice(line, 2, len);
  }
  return string.str_slice(line, 1, len);
}

// 1 or 2 for a "-"/"*" bullet marker (alone or before a space), 0 otherwise.
fn _ul_marker_len(line: Str) -> Int {
  let len = line.len();
  if len == 0 { return 0; }
  let b = string.byte_at(line, 0);
  if b != _MD_DASH && b != _MD_STAR { return 0; }
  if len == 1 { return 1; }
  if string.byte_at(line, 1) == _MD_SPACE { return 2; }
  return 0;
}

// Marker length for digits followed by "." (alone or before a space), 0
// otherwise. The digits are not interpreted; any count is accepted.
fn _ol_marker_len(line: Str) -> Int {
  let len = line.len();
  var digits = 0;
  while digits < len {
    let b = string.byte_at(line, digits) as Int;
    if b < 48 || b > 57 { break; }
    digits = digits + 1;
  }
  if digits == 0 || digits >= len { return 0; }
  if string.byte_at(line, digits) != _MD_DOT { return 0; }
  if digits + 1 == len { return digits + 1; }
  if string.byte_at(line, digits + 1) == _MD_SPACE { return digits + 2; }
  return 0;
}

fn _fence_open(line: Str) -> Bool {
  return _starts_with(line, "```");
}

// First whitespace-delimited token after the opening backticks, "" when none.
fn _fence_lang(line: Str) -> Str {
  let body = string.str_slice(line, 3, line.len());
  let trimmed = string.str_trim(body);
  var i = 0;
  while i < trimmed.len() {
    let b = string.byte_at(trimmed, i);
    if b == _MD_SPACE || b == _MD_TAB { break; }
    i = i + 1;
  }
  return string.str_slice(trimmed, 0, i);
}

// Closing fence: "```" after dropping trailing spaces/tabs.
fn _fence_close(line: Str) -> Bool {
  let t = _rstrip(line);
  return compare.str_compare(t, "```") == 0;
}

// True when `line` can only start a new block (blank, fence, heading, hr,
// blockquote or list item) and therefore must not join a paragraph.
fn _is_block_start(line: Str) -> Bool {
  if _is_blank(line) { return true; }
  if _fence_open(line) { return true; }
  if _heading_level(line) > 0 { return true; }
  if _is_hr(line) { return true; }
  if _is_blockquote(line) { return true; }
  if _ul_marker_len(line) > 0 { return true; }
  if _ol_marker_len(line) > 0 { return true; }
  return false;
}

// --------------------------------------------------
//  Block rendering
// --------------------------------------------------

// Render the fenced code block whose opening line is at index `open`; returns
// the index of the first line after the block (or the line count when the
// fence is never closed -- lenient EOF close, documented).
fn _render_fence(lines: &Vec[Str], open: Int, blocks: &mut Vec[Str]) -> Int {
  let lang = _fence_lang(lines[open]);
  var body = Vec[UInt8].new();
  var first = true;
  var i = open + 1;
  while i < lines.len() {
    let line = lines[i];
    if _fence_close(line) {
      i = i + 1;
      break;
    }
    if !first { builder.sb_push_str(&mut body, "\n"); }
    _push_escaped(&mut body, line);
    first = false;
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<pre><code");
  if lang.len() > 0 {
    builder.sb_push_str(&mut out, " class=\"language-");
    _push_escaped(&mut out, lang);
    builder.sb_push_str(&mut out, "\"");
  }
  builder.sb_push_str(&mut out, ">");
  let code = builder.sb_to_str(&body);
  builder.sb_push_str(&mut out, code);
  builder.sb_push_str(&mut out, "</code></pre>");
  blocks.push(builder.sb_to_str(&out));
  return i;
}

fn _render_heading(blocks: &mut Vec[Str], line: Str) {
  let level = _heading_level(line);
  let rest = string.str_slice(line, level, line.len());
  let text = string.str_trim(rest);
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<h");
  builder.sb_push_int(&mut out, level);
  builder.sb_push_str(&mut out, ">");
  _push_inline(&mut out, text);
  builder.sb_push_str(&mut out, "</h");
  builder.sb_push_int(&mut out, level);
  builder.sb_push_str(&mut out, ">");
  blocks.push(builder.sb_to_str(&out));
}

fn _render_ul(lines: &Vec[Str], open: Int, blocks: &mut Vec[Str]) -> Int {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<ul>");
  var i = open;
  while i < lines.len() {
    let line = lines[i];
    let marker = _ul_marker_len(line);
    if marker == 0 { break; }
    let text = string.str_slice(line, marker, line.len());
    builder.sb_push_str(&mut out, "\n<li>");
    _push_inline(&mut out, text);
    builder.sb_push_str(&mut out, "</li>");
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "\n</ul>");
  blocks.push(builder.sb_to_str(&out));
  return i;
}

fn _render_ol(lines: &Vec[Str], open: Int, blocks: &mut Vec[Str]) -> Int {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<ol>");
  var i = open;
  while i < lines.len() {
    let line = lines[i];
    let marker = _ol_marker_len(line);
    if marker == 0 { break; }
    let text = string.str_slice(line, marker, line.len());
    builder.sb_push_str(&mut out, "\n<li>");
    _push_inline(&mut out, text);
    builder.sb_push_str(&mut out, "</li>");
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "\n</ol>");
  blocks.push(builder.sb_to_str(&out));
  return i;
}

// Collect contiguous ">" lines, strip the marker, join with LF and render the
// result recursively as blocks.
fn _render_blockquote(lines: &Vec[Str], open: Int, blocks: &mut Vec[Str]) -> Int {
  var inner = Vec[UInt8].new();
  var first = true;
  var i = open;
  while i < lines.len() {
    let line = lines[i];
    if !_is_blockquote(line) { break; }
    if !first { builder.sb_push_str(&mut inner, "\n"); }
    let content = _blockquote_content(line);
    builder.sb_push_str(&mut inner, content);
    first = false;
    i = i + 1;
  }
  let inner_md = builder.sb_to_str(&inner);
  let inner_html = markdown_to_html(inner_md);
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<blockquote>");
  if inner_html.len() > 0 {
    builder.sb_push_str(&mut out, "\n");
    builder.sb_push_str(&mut out, inner_html);
    builder.sb_push_str(&mut out, "\n");
  }
  builder.sb_push_str(&mut out, "</blockquote>");
  blocks.push(builder.sb_to_str(&out));
  return i;
}

// Consume plain lines and render them as one <p>, joining lines with a space.
fn _render_paragraph(lines: &Vec[Str], open: Int, blocks: &mut Vec[Str]) -> Int {
  var text = Vec[UInt8].new();
  var first = true;
  var i = open;
  while i < lines.len() {
    let line = lines[i];
    if _is_block_start(line) { break; }
    if !first { builder.sb_push_str(&mut text, " "); }
    builder.sb_push_str(&mut text, line);
    first = false;
    i = i + 1;
  }
  let plain = builder.sb_to_str(&text);
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<p>");
  _push_inline(&mut out, plain);
  builder.sb_push_str(&mut out, "</p>");
  blocks.push(builder.sb_to_str(&out));
  return i;
}

// Join the rendered blocks with a single LF between consecutive blocks.
fn _join_blocks(blocks: &Vec[Str]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < blocks.len() {
    if i > 0 { builder.sb_push_str(&mut out, "\n"); }
    builder.sb_push_str(&mut out, blocks[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Render the supported Markdown subset to HTML.
/// Params: md - the whole document as one Str (LF or CRLF line endings).
/// Returns: the HTML of the recognized blocks in document order, consecutive
/// blocks separated by a single LF; text that opens no recognized construct
/// stays literal (escaped). Empty or whitespace-only input returns "".
/// Error case: none.
/// Complexity: O(n) over the input for the block scan; inline scanning is
/// O(m^2) worst case over a text run of length m.
pub fn markdown_to_html(md: Str) -> Str {
  let lines = _split_lines(md);
  var blocks = Vec[Str].new();
  var i = 0;
  while i < lines.len() {
    let line = lines[i];
    if _is_blank(line) {
      i = i + 1;
    } elif _fence_open(line) {
      i = _render_fence(&lines, i, &mut blocks);
    } elif _heading_level(line) > 0 {
      _render_heading(&mut blocks, line);
      i = i + 1;
    } elif _is_hr(line) {
      blocks.push("<hr>");
      i = i + 1;
    } elif _is_blockquote(line) {
      i = _render_blockquote(&lines, i, &mut blocks);
    } elif _ul_marker_len(line) > 0 {
      i = _render_ul(&lines, i, &mut blocks);
    } elif _ol_marker_len(line) > 0 {
      i = _render_ol(&lines, i, &mut blocks);
    } else {
      i = _render_paragraph(&lines, i, &mut blocks);
    }
  }
  return _join_blocks(&blocks);
}
