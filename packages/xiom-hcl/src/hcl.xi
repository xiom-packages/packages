// XIOM -- xiom.hcl: structural HCL2 subset parser with a canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Expressions are NOT evaluated: an attribute value is the raw byte text
// between '=' and the end of its logical line, trimmed at both ends.
//
// Model: one document is fourteen parallel vectors plus the source text.
// Attributes are index-aligned across `attr_names`, `attr_values`,
// `attr_lines`, `attr_parents` (owning block index, -1 = top level) and
// `attr_offsets` (byte offset of the name, used to keep document order in
// the emitter). Blocks are index-aligned across `block_types`,
// `block_label_counts`, `block_label_starts`, `block_parents`,
// `block_body_starts`, `block_body_ends`, `block_lines` and `block_offsets`;
// every block's labels live in the shared flat `block_labels` pool at
// `[block_label_starts[i], block_label_starts[i] + block_label_counts[i])`.
// Body ranges are half-open byte ranges into `source` between the block's
// braces. Vec[StructType] is unsupported in this compiler, so the document is
// deliberately flat instead of a tree of block structs.
//
// Subset (see SPEC.md for the full statement):
//   * attributes:  name = <expression>   (expression = raw text to end of
//                                            line, quoted strings and nested
//                                            [ ] { } ( ) captured whole)
//   * blocks:      type "label" "label2" { ... }   (nested, any depth)
//   * comments:    # and // to end of line, /* ... */ block comments
//   * whitespace:  spaces, tabs, CRLF and blank lines anywhere between
//                  statements; newlines are tolerated inside expressions at
//                  bracket depth > 0
// Non-goals: no expression evaluation, no type system, no heredocs (rejected
// with a clear error), no functions/for-expressions, no interpolation.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[HclDoc, Str] are constructed only in the tiny leaf
//     helpers _ok_doc/_err_doc (struct payloads need leaf constructors).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec elements are read into typed locals first.
//   * Output bytes are collected in Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str; the parser rejects NUL bytes so the
//     emitter can never hand a NUL-containing buffer to sb_to_str.

module xiom.hcl

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _HCL_TAB: UInt8 = 9u8;
const _HCL_LF: UInt8 = 10u8;
const _HCL_CR: UInt8 = 13u8;
const _HCL_SPACE: UInt8 = 32u8;
const _HCL_HASH: UInt8 = 35u8;
const _HCL_DQUOTE: UInt8 = 34u8;
const _HCL_LPAREN: UInt8 = 40u8;
const _HCL_RPAREN: UInt8 = 41u8;
const _HCL_STAR: UInt8 = 42u8;
const _HCL_SLASH: UInt8 = 47u8;
const _HCL_LT: UInt8 = 60u8;
const _HCL_EQ: UInt8 = 61u8;
const _HCL_LBRACKET: UInt8 = 91u8;
const _HCL_BACKSLASH: UInt8 = 92u8;
const _HCL_RBRACKET: UInt8 = 93u8;
const _HCL_LBRACE: UInt8 = 123u8;
const _HCL_RBRACE: UInt8 = 125u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed HCL2 subset document. Top level parents are -1; both attribute
/// and block index spaces are document order, and `attr_offsets` /
/// `block_offsets` are the byte offsets of each name/type in `source`, so a
/// body can be emitted in original interleaved order. `block_body_starts`
/// and `block_body_ends` delimit the raw text between a block's braces.
pub type HclDoc = {
  source: Str;
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_lines: Vec[Int];
  attr_parents: Vec[Int];
  attr_offsets: Vec[Int];
  block_types: Vec[Str];
  block_label_counts: Vec[Int];
  block_label_starts: Vec[Int];
  block_labels: Vec[Str];
  block_parents: Vec[Int];
  block_body_starts: Vec[Int];
  block_body_ends: Vec[Int];
  block_lines: Vec[Int];
  block_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (struct payload -> leaf helpers)
// --------------------------------------------------

// Ok(d) for Result[HclDoc, Str].
fn _ok_doc(d: HclDoc) -> Result[HclDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[HclDoc, Str].
fn _err_doc(m: Str) -> Result[HclDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

// True for an ASCII space or horizontal tab (intra-line whitespace).
fn _is_h_ws(b: UInt8) -> Bool {
  return b == _HCL_SPACE || b == _HCL_TAB;
}

// True for an ASCII digit.
fn _is_digit(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// True for an ASCII letter.
fn _is_alpha(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }
  return b >= 97u8 && b <= 122u8;
}

// True for a byte that may start an identifier: letter or underscore.
fn _is_ident_start(b: UInt8) -> Bool {
  return _is_alpha(b) || b == 95u8;
}

// True for a byte that may continue an identifier: letter, digit, _ or -.
fn _is_ident_byte(b: UInt8) -> Bool {
  return _is_alpha(b) || _is_digit(b) || b == 95u8 || b == 45u8;
}

// --------------------------------------------------
//  Scanning helpers
// --------------------------------------------------

// Byte index of the next LF at or after `pos`, or the text length.
fn _skip_to_eol(text: Str, pos: Int) -> Int {
  var i = pos;
  let n = text.len();
  while i < n {
    if string.byte_at(text, i) == _HCL_LF { return i; }
    i = i + 1;
  }
  return n;
}

// Number of LF bytes in text[start, end).
fn _count_lf(text: Str, start: Int, end: Int) -> Int {
  var count = 0;
  var i = start;
  while i < end {
    if string.byte_at(text, i) == _HCL_LF { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// pos points at the '/' of "/*". Returns the index just after the closing
// "*/", or -1 when the comment is unterminated. Block comments do not nest:
// the first "*/" closes the comment.
fn _skip_block_comment(text: Str, pos: Int) -> Int {
  var i = pos + 2;
  let n = text.len();
  while i + 1 < n {
    if string.byte_at(text, i) == _HCL_STAR && string.byte_at(text, i + 1) == _HCL_SLASH {
      return i + 2;
    }
    i = i + 1;
  }
  return -1;
}

// Current open-block index on the parse stack, or -1 at top level.
fn _stack_parent(stack: &Vec[Int]) -> Int {
  if stack.len() == 0 { return -1; }
  let top: Int = stack[stack.len() - 1];
  return top;
}

// Capture the raw text of an attribute expression that starts at `start`.
// Returns the exclusive end index (the LF, the start of a depth-0 comment,
// or the text length), or -1 for an unterminated string and -2 for
// unbalanced or mismatched brackets. Quoted strings skip escaped bytes;
// [ ] { } ( ) nest and must close in order; at depth 0 an LF, '#', "//" or
// "/*" ends the expression, while at depth > 0 everything is raw so
// multi-line lists and objects are captured whole.
fn _capture_expr(text: Str, start: Int) -> Int {
  let n = text.len();
  var closers = Vec[UInt8].new();
  var in_str = false;
  var i = start;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if in_str {
      if b == _HCL_BACKSLASH {
        if i + 1 >= n { return -1; }
        i = i + 2;
      } elif b == _HCL_DQUOTE {
        in_str = false;
        i = i + 1;
      } elif b == _HCL_LF {
        return -1;
      } else {
        i = i + 1;
      }
    } elif b == _HCL_DQUOTE {
      in_str = true;
      i = i + 1;
    } elif b == _HCL_LBRACKET {
      closers.push(_HCL_RBRACKET);
      i = i + 1;
    } elif b == _HCL_LBRACE {
      closers.push(_HCL_RBRACE);
      i = i + 1;
    } elif b == _HCL_LPAREN {
      closers.push(_HCL_RPAREN);
      i = i + 1;
    } elif b == _HCL_RBRACKET || b == _HCL_RBRACE || b == _HCL_RPAREN {
      if closers.len() == 0 { return -2; }
      let top: UInt8 = closers[closers.len() - 1];
      if top != b { return -2; }
      closers.pop();
      i = i + 1;
    } elif closers.len() == 0 && b == _HCL_LF {
      return i;
    } elif closers.len() == 0 && b == _HCL_HASH {
      return i;
    } elif closers.len() == 0 && b == _HCL_SLASH && i + 1 < n && (string.byte_at(text, i + 1) == _HCL_SLASH || string.byte_at(text, i + 1) == _HCL_STAR) {
      return i;
    } else {
      i = i + 1;
    }
  }
  if in_str { return -1; }
  if closers.len() > 0 { return -2; }
  return n;
}

// Validate a quoted block label that starts at `start` (the opening quote).
// Returns the index just after the closing quote, -1 for an unterminated
// label (LF or EOF first) and -2 for an invalid escape. Only \" and \\
// are recognized; every other backslash escape is an error.
fn _label_end(text: Str, start: Int) -> Int {
  let n = text.len();
  var i = start + 1;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if b == _HCL_BACKSLASH {
      if i + 1 >= n { return -1; }
      let e: UInt8 = string.byte_at(text, i + 1);
      if e == _HCL_DQUOTE || e == _HCL_BACKSLASH {
        i = i + 2;
      } else {
        return -2;
      }
    } elif b == _HCL_DQUOTE {
      return i + 1;
    } elif b == _HCL_LF {
      return -1;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Decode a validated label into its text; `end` is the index after the
// closing quote. \" becomes " and \\ becomes \; everything else is verbatim.
fn _decode_label(text: Str, start: Int, end: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = start + 1;
  let stop = end - 1;
  while i < stop {
    let b: UInt8 = string.byte_at(text, i);
    if b == _HCL_BACKSLASH {
      let e: UInt8 = string.byte_at(text, i + 1);
      if e == _HCL_DQUOTE { out.push(_HCL_DQUOTE); } else { out.push(_HCL_BACKSLASH); }
      i = i + 2;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Document mutation helpers (no parallel-vector drift)
// --------------------------------------------------

// Append one attribute row to all five attribute vectors.
fn _push_attr(d: &mut HclDoc, name: Str, value: Str, line: Int, parent: Int, offset: Int) {
  d.attr_names.push(name);
  d.attr_values.push(value);
  d.attr_lines.push(line);
  d.attr_parents.push(parent);
  d.attr_offsets.push(offset);
}

// Append one block row and copy its labels into the flat label pool.
fn _push_block(d: &mut HclDoc, type_name: Str, labels: &Vec[Str], parent: Int, body_start: Int, line: Int, offset: Int) {
  let label_start = d.block_labels.len();
  d.block_types.push(type_name);
  d.block_label_counts.push(labels.len());
  d.block_label_starts.push(label_start);
  d.block_parents.push(parent);
  d.block_body_starts.push(body_start);
  d.block_body_ends.push(-1);
  d.block_lines.push(line);
  d.block_offsets.push(offset);
  var i = 0;
  while i < labels.len() {
    let lb: Str = labels[i];
    d.block_labels.push(lb);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// Append `level` two-space indentation units.
fn _emit_indent(out: &mut Vec[UInt8], level: Int) {
  var i = 0;
  while i < level * 2 {
    out.push(_HCL_SPACE);
    i = i + 1;
  }
}

// Append one quoted, escaped label.
fn _emit_label(out: &mut Vec[UInt8], label: Str) {
  builder.sb_push_str(out, "\"");
  var i = 0;
  while i < label.len() {
    let b: UInt8 = string.byte_at(label, i);
    if b == _HCL_DQUOTE {
      builder.sb_push_str(out, "\\\"");
    } elif b == _HCL_BACKSLASH {
      builder.sb_push_str(out, "\\\\");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  builder.sb_push_str(out, "\"");
}

// Number of direct children (attributes plus blocks) of `parent`.
fn _child_total(d: &HclDoc, parent: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.attr_names.len() {
    let p: Int = d.attr_parents[i];
    if p == parent { count = count + 1; }
    i = i + 1;
  }
  i = 0;
  while i < d.block_types.len() {
    let p: Int = d.block_parents[i];
    if p == parent { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// Emit one block: header, then either " {}" or an indented body.
fn _emit_block(out: &mut Vec[UInt8], d: &HclDoc, idx: Int, level: Int) {
  _emit_indent(out, level);
  let type_name: Str = d.block_types[idx];
  builder.sb_push_str(out, type_name);
  let label_count: Int = d.block_label_counts[idx];
  let label_start: Int = d.block_label_starts[idx];
  var k = 0;
  while k < label_count {
    builder.sb_push_str(out, " ");
    let lb: Str = d.block_labels[label_start + k];
    _emit_label(out, lb);
    k = k + 1;
  }
  if _child_total(d, idx) == 0 {
    builder.sb_push_str(out, " {}");
    out.push(_HCL_LF);
    return;
  }
  builder.sb_push_str(out, " {");
  out.push(_HCL_LF);
  _emit_body(out, d, idx, level + 1);
  _emit_indent(out, level);
  out.push(_HCL_RBRACE);
  out.push(_HCL_LF);
}

// Emit every direct child of `parent` at `level`, in document order: the
// attribute and block cursors advance by original byte offset.
fn _emit_body(out: &mut Vec[UInt8], d: &HclDoc, parent: Int, level: Int) {
  let attr_n = d.attr_names.len();
  let block_n = d.block_types.len();
  var ai = 0;
  var bi = 0;
  while true {
    while ai < attr_n {
      let p: Int = d.attr_parents[ai];
      if p == parent { break; }
      ai = ai + 1;
    }
    while bi < block_n {
      let p: Int = d.block_parents[bi];
      if p == parent { break; }
      bi = bi + 1;
    }
    if ai >= attr_n && bi >= block_n { return; }
    var take_attr = false;
    if ai < attr_n {
      if bi >= block_n {
        take_attr = true;
      } else {
        let ao: Int = d.attr_offsets[ai];
        let bo: Int = d.block_offsets[bi];
        if ao < bo { take_attr = true; }
      }
    }
    if take_attr {
      _emit_indent(out, level);
      let an: Str = d.attr_names[ai];
      builder.sb_push_str(out, an);
      builder.sb_push_str(out, " = ");
      let av: Str = d.attr_values[ai];
      builder.sb_push_str(out, av);
      out.push(_HCL_LF);
      ai = ai + 1;
    } else {
      _emit_block(out, d, bi, level);
      bi = bi + 1;
    }
  }
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse one in-memory HCL2 subset document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(HclDoc) for a valid document (including an empty one); Err
/// with an "hcl: ..." message on malformed syntax (see SPEC.md section 5 for
/// the error catalog). Expressions are captured as raw text and never
/// evaluated; comments are parsed but not stored.
/// Complexity: O(total input length) for a document whose expressions do not
/// span lines; O(total input length) amortized otherwise.
pub fn hcl_parse(text: Str) -> Result[HclDoc, Str] {
  var d = HclDoc{
    source: text;
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_lines: Vec[Int].new();
    attr_parents: Vec[Int].new();
    attr_offsets: Vec[Int].new();
    block_types: Vec[Str].new();
    block_label_counts: Vec[Int].new();
    block_label_starts: Vec[Int].new();
    block_labels: Vec[Str].new();
    block_parents: Vec[Int].new();
    block_body_starts: Vec[Int].new();
    block_body_ends: Vec[Int].new();
    block_lines: Vec[Int].new();
    block_offsets: Vec[Int].new();
  };
  let len = text.len();
  // Reject NUL up front: sb_to_str truncates at a NUL, so a NUL byte could
  // otherwise make hcl_emit lose output silently.
  var scan = 0;
  var scan_line = 1;
  while scan < len {
    let sb: UInt8 = string.byte_at(text, scan);
    if sb == 0u8 {
      return _err_doc("hcl: NUL byte in input at line " + convert.int_to_string(scan_line));
    }
    if sb == _HCL_LF { scan_line = scan_line + 1; }
    scan = scan + 1;
  }
  var stack = Vec[Int].new();
  var pos = 0;
  var line = 1;
  while pos < len {
    let b: UInt8 = string.byte_at(text, pos);
    if b == _HCL_LF {
      line = line + 1;
      pos = pos + 1;
    } elif b == _HCL_SPACE || b == _HCL_TAB || b == _HCL_CR {
      pos = pos + 1;
    } elif b == _HCL_HASH {
      pos = _skip_to_eol(text, pos);
    } elif b == _HCL_SLASH && pos + 1 < len && string.byte_at(text, pos + 1) == _HCL_SLASH {
      pos = _skip_to_eol(text, pos);
    } elif b == _HCL_SLASH && pos + 1 < len && string.byte_at(text, pos + 1) == _HCL_STAR {
      let after = _skip_block_comment(text, pos);
      if after < 0 {
        return _err_doc("hcl: unterminated block comment at line " + convert.int_to_string(line));
      }
      line = line + _count_lf(text, pos, after);
      pos = after;
    } elif b == _HCL_RBRACE {
      if stack.len() == 0 {
        return _err_doc("hcl: unmatched '}' at line " + convert.int_to_string(line));
      }
      let top: Int = stack[stack.len() - 1];
      d.block_body_ends[top] = pos;
      stack.pop();
      pos = pos + 1;
    } elif b == _HCL_LBRACE {
      return _err_doc("hcl: block has no type at line " + convert.int_to_string(line));
    } elif b == _HCL_DQUOTE {
      return _err_doc("hcl: block has no type at line " + convert.int_to_string(line));
    } elif b == _HCL_EQ {
      return _err_doc("hcl: invalid attribute name at line " + convert.int_to_string(line));
    } elif _is_ident_start(b) {
      var name_end = pos + 1;
      while name_end < len && _is_ident_byte(string.byte_at(text, name_end)) {
        name_end = name_end + 1;
      }
      let name = string.str_slice(text, pos, name_end);
      var p1 = name_end;
      while p1 < len && _is_h_ws(string.byte_at(text, p1)) {
        p1 = p1 + 1;
      }
      if p1 < len && string.byte_at(text, p1) == _HCL_EQ {
        // The statement's line is captured before a multi-line value can
        // advance the running line counter.
        let attr_line = line;
        var value_start = p1 + 1;
        while value_start < len && _is_h_ws(string.byte_at(text, value_start)) {
          value_start = value_start + 1;
        }
        let value_end = _capture_expr(text, value_start);
        if value_end < 0 {
          if value_end == -1 {
            return _err_doc("hcl: unterminated string in expression at line " + convert.int_to_string(attr_line));
          }
          return _err_doc("hcl: unbalanced brackets in expression at line " + convert.int_to_string(attr_line));
        }
        line = line + _count_lf(text, value_start, value_end);
        let value = string.str_trim(string.str_slice(text, value_start, value_end));
        if value.len() == 0 {
          return _err_doc("hcl: missing attribute value at line " + convert.int_to_string(attr_line));
        }
        if value.len() >= 2 && string.byte_at(value, 0) == _HCL_LT && string.byte_at(value, 1) == _HCL_LT {
          return _err_doc("hcl: heredocs are not supported at line " + convert.int_to_string(attr_line));
        }
        let parent = _stack_parent(&stack);
        _push_attr(&mut d, name, value, attr_line, parent, pos);
        pos = value_end;
      } elif p1 < len && string.byte_at(text, p1) == _HCL_DQUOTE {
        var labels = Vec[Str].new();
        var label_err = 0;
        var p2 = p1;
        while true {
          let label_stop = _label_end(text, p2);
          if label_stop < 0 {
            if label_stop == -1 { label_err = 1; } else { label_err = 2; }
            break;
          }
          let label = _decode_label(text, p2, label_stop);
          var duplicate = false;
          var q = 0;
          while q < labels.len() {
            let prev: Str = labels[q];
            if compare.str_compare(prev, label) == 0 {
              duplicate = true;
              break;
            }
            q = q + 1;
          }
          if duplicate {
            label_err = 4;
            break;
          }
          labels.push(label);
          p2 = label_stop;
          while p2 < len && _is_h_ws(string.byte_at(text, p2)) {
            p2 = p2 + 1;
          }
          let next_is_label = p2 < len && string.byte_at(text, p2) == _HCL_DQUOTE;
          let next_is_brace = p2 < len && string.byte_at(text, p2) == _HCL_LBRACE;
          if next_is_brace { break; }
          if !next_is_label {
            label_err = 3;
            break;
          }
        }
        if label_err == 1 {
          return _err_doc("hcl: unterminated string in block label at line " + convert.int_to_string(line));
        }
        if label_err == 2 {
          return _err_doc("hcl: invalid escape in block label at line " + convert.int_to_string(line));
        }
        if label_err == 3 {
          return _err_doc("hcl: expected '{' after block labels at line " + convert.int_to_string(line));
        }
        if label_err == 4 {
          return _err_doc("hcl: duplicate block label at line " + convert.int_to_string(line));
        }
        let parent = _stack_parent(&stack);
        let block_idx = d.block_types.len();
        _push_block(&mut d, name, &labels, parent, p2 + 1, line, pos);
        stack.push(block_idx);
        pos = p2 + 1;
      } elif p1 < len && string.byte_at(text, p1) == _HCL_LBRACE {
        let parent = _stack_parent(&stack);
        let block_idx = d.block_types.len();
        let no_labels = Vec[Str].new();
        _push_block(&mut d, name, &no_labels, parent, p1 + 1, line, pos);
        stack.push(block_idx);
        pos = p1 + 1;
      } else {
        return _err_doc("hcl: expected '=' or '{' after '" + name + "' at line " + convert.int_to_string(line));
      }
    } else {
      return _err_doc("hcl: stray token at line " + convert.int_to_string(line));
    }
  }
  if stack.len() > 0 {
    let top: Int = stack[stack.len() - 1];
    let block_line: Int = d.block_lines[top];
    return _err_doc("hcl: unterminated block starting at line " + convert.int_to_string(block_line));
  }
  return _ok_doc(d);
}

// --------------------------------------------------
//  Public API -- counts
// --------------------------------------------------

/// Total number of attributes in the document (all nesting levels).
pub fn hcl_attr_total(d: &HclDoc) -> Int {
  return d.attr_names.len();
}

/// Total number of blocks in the document (all nesting levels).
pub fn hcl_block_total(d: &HclDoc) -> Int {
  return d.block_types.len();
}

/// Number of attributes directly inside `parent` (-1 = top level).
pub fn hcl_attr_count_in(d: &HclDoc, parent: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.attr_names.len() {
    let p: Int = d.attr_parents[i];
    if p == parent { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Number of top-level attributes.
pub fn hcl_attr_count(d: &HclDoc) -> Int {
  return hcl_attr_count_in(d, -1);
}

/// Number of blocks directly inside `parent` (-1 = top level).
pub fn hcl_block_count_in(d: &HclDoc, parent: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.block_types.len() {
    let p: Int = d.block_parents[i];
    if p == parent { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Number of top-level blocks.
pub fn hcl_block_count(d: &HclDoc) -> Int {
  return hcl_block_count_in(d, -1);
}

/// Number of direct children (attributes plus blocks) of `parent`.
pub fn hcl_child_total(d: &HclDoc, parent: Int) -> Int {
  return _child_total(d, parent);
}

// --------------------------------------------------
//  Public API -- attribute access
// --------------------------------------------------

/// Name of attribute `idx`; "" for an out-of-range index.
pub fn hcl_attr_name(d: &HclDoc, idx: Int) -> Str {
  if idx < 0 || idx >= d.attr_names.len() { return ""; }
  let v: Str = d.attr_names[idx];
  return v;
}

/// Raw (trimmed) expression text of attribute `idx`; "" for an out-of-range
/// index.
pub fn hcl_attr_value(d: &HclDoc, idx: Int) -> Str {
  if idx < 0 || idx >= d.attr_values.len() { return ""; }
  let v: Str = d.attr_values[idx];
  return v;
}

/// 1-based line on which attribute `idx` starts; 0 for an out-of-range index.
pub fn hcl_attr_line(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.attr_lines.len() { return 0; }
  let v: Int = d.attr_lines[idx];
  return v;
}

/// Owning block index of attribute `idx` (-1 = top level); -2 for an
/// out-of-range index.
pub fn hcl_attr_parent(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.attr_parents.len() { return -2; }
  let v: Int = d.attr_parents[idx];
  return v;
}

// --------------------------------------------------
//  Public API -- block access
// --------------------------------------------------

/// Type name of block `idx`; "" for an out-of-range index.
pub fn hcl_block_type(d: &HclDoc, idx: Int) -> Str {
  if idx < 0 || idx >= d.block_types.len() { return ""; }
  let v: Str = d.block_types[idx];
  return v;
}

/// 1-based line on which block `idx` starts; 0 for an out-of-range index.
pub fn hcl_block_line(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.block_lines.len() { return 0; }
  let v: Int = d.block_lines[idx];
  return v;
}

/// Parent block index of block `idx` (-1 = top level); -2 for an
/// out-of-range index.
pub fn hcl_block_parent(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.block_parents.len() { return -2; }
  let v: Int = d.block_parents[idx];
  return v;
}

/// Number of labels of block `idx`; 0 for an out-of-range index.
pub fn hcl_block_label_count(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.block_label_counts.len() { return 0; }
  let v: Int = d.block_label_counts[idx];
  return v;
}

/// Label `k` of block `idx`, decoded (\" and \\ resolved); "" for an
/// out-of-range block or label.
pub fn hcl_block_label(d: &HclDoc, idx: Int, k: Int) -> Str {
  if idx < 0 || idx >= d.block_label_counts.len() { return ""; }
  let count: Int = d.block_label_counts[idx];
  if k < 0 || k >= count { return ""; }
  let start: Int = d.block_label_starts[idx];
  let v: Str = d.block_labels[start + k];
  return v;
}

/// All labels of block `idx`, decoded, in header order (a fresh copy).
pub fn hcl_block_labels(d: &HclDoc, idx: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if idx < 0 || idx >= d.block_label_counts.len() { return out; }
  let start: Int = d.block_label_starts[idx];
  let count: Int = d.block_label_counts[idx];
  var k = 0;
  while k < count {
    let v: Str = d.block_labels[start + k];
    out.push(v);
    k = k + 1;
  }
  return out;
}

/// Byte offset of block `idx`'s first body byte (just after "{"); -1 for an
/// out-of-range index.
pub fn hcl_block_body_start(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.block_body_starts.len() { return -1; }
  let v: Int = d.block_body_starts[idx];
  return v;
}

/// Byte offset of block `idx`'s closing "}"; -1 for an out-of-range index.
pub fn hcl_block_body_end(d: &HclDoc, idx: Int) -> Int {
  if idx < 0 || idx >= d.block_body_ends.len() { return -1; }
  let v: Int = d.block_body_ends[idx];
  return v;
}

/// Raw text between block `idx`'s braces, verbatim (a slice of `source`);
/// "" for an out-of-range index.
pub fn hcl_block_body(d: &HclDoc, idx: Int) -> Str {
  if idx < 0 || idx >= d.block_body_ends.len() { return ""; }
  let start: Int = d.block_body_starts[idx];
  let end: Int = d.block_body_ends[idx];
  if start < 0 || end < start || end > d.source.len() { return ""; }
  return string.str_slice(d.source, start, end);
}

/// Index of the `k`-th block directly inside `parent` (-1 = top level), or
/// -1 when there is no such child.
pub fn hcl_child_block(d: &HclDoc, parent: Int, k: Int) -> Int {
  if k < 0 { return -1; }
  var seen = 0;
  var i = 0;
  while i < d.block_types.len() {
    let p: Int = d.block_parents[i];
    if p == parent {
      if seen == k { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the `k`-th attribute directly inside `parent` (-1 = top level),
/// or -1 when there is no such child.
pub fn hcl_child_attr(d: &HclDoc, parent: Int, k: Int) -> Int {
  if k < 0 { return -1; }
  var seen = 0;
  var i = 0;
  while i < d.attr_names.len() {
    let p: Int = d.attr_parents[i];
    if p == parent {
      if seen == k { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the first attribute named `name` directly inside `parent`
/// (-1 = top level), or -1. Duplicate attributes are allowed at parse time;
/// lookup always returns the first (lowest index).
pub fn hcl_attr_lookup_in(d: &HclDoc, parent: Int, name: Str) -> Int {
  var i = 0;
  while i < d.attr_names.len() {
    let p: Int = d.attr_parents[i];
    if p == parent {
      let n: Str = d.attr_names[i];
      if compare.str_compare(n, name) == 0 { return i; }
    }
    i = i + 1;
  }
  return -1;
}

/// Index of the first top-level attribute named `name`, or -1.
pub fn hcl_attr_lookup(d: &HclDoc, name: Str) -> Int {
  return hcl_attr_lookup_in(d, -1, name);
}

/// Value of the first attribute named `name` inside `parent` (-1 = top
/// level); None when absent.
pub fn hcl_attr_value_in(d: &HclDoc, parent: Int, name: Str) -> Option[Str] {
  let idx = hcl_attr_lookup_in(d, parent, name);
  if idx < 0 { return None; }
  let v: Str = d.attr_values[idx];
  return Some(v);
}

// --------------------------------------------------
//  Public API -- emitter
// --------------------------------------------------

/// Emit the canonical form of `d`: one statement per line, LF line endings
/// (the output ends with LF unless the document is empty), attributes as
/// `name = value` with single spaces around '=', blocks as
/// `type "label" "label2" {`, `{}` for an empty body, and two spaces of
/// indentation per nesting level. Documents are emitted in original
/// document order (attributes and blocks interleaved as parsed); comments
/// and original whitespace are not preserved. Attribute values are written
/// verbatim, so a value containing LFs keeps its own internal indentation.
pub fn hcl_emit(d: &HclDoc) -> Str {
  var out = Vec[UInt8].new();
  _emit_body(&mut out, d, -1, 0);
  return builder.sb_to_str(&out);
}
