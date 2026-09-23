// XIOM -- xiom.xml: XML subset parser with a flat node model, queries and escaping
// Port task: replace the xiom.xml placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (see SPEC.md for the full grammar and error catalog):
// elements, attributes with double or single quotes, text, self-closing tags,
// comments <!-- -->, the <?xml ... ?> declaration (and other processing
// instructions), and the predefined entities &amp; &lt; &gt; &quot; &apos;
// plus numeric character references &#NN; and &#xHH;. No DTD, no namespaces,
// no CDATA (documented errors instead).
//
// v0.61.3 notes that shaped this module:
//   * The document is a FLAT node list carried in parallel Vec fields
//     (Vec[StructType] is unsupported in this compiler).
//   * Ok/Err for Result[XmlDoc, Str] are constructed only in the tiny leaf
//     helpers _ok_doc/_err_doc (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison).
//   * No FFI: byte output is collected with Vec[UInt8].push and materialized
//     with xiom.string.builder.sb_to_str (one allocation per Str).

module xiom.xml

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

/// Parsed XML document: a flat node list with parallel vectors.
/// kinds[i] is 0 for an element and 1 for a text node; node 0 is the
/// synthetic document root (an element with an empty name and parent -1) and
/// is always present at index 0. names[i] holds an element's tag name ("" for
/// text nodes), texts[i] a text node's decoded content ("" for elements) and
/// parents[i] the owning node index (-1 only for node 0). Attributes form a
/// flat association list: attr_names[k] / attr_values[k] belong to node
/// attr_owners[k]. Read fields through the accessors below so that
/// out-of-range indices stay safe; duplicate attribute names keep the first
/// occurrence (xml_attr).
pub type XmlDoc = {
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[XmlDoc, Str].
fn _ok_doc(d: XmlDoc) -> Result[XmlDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[XmlDoc, Str].
fn _err_doc(m: Str) -> Result[XmlDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _X_LT: UInt8 = 60u8;
const _X_GT: UInt8 = 62u8;
const _X_SLASH: UInt8 = 47u8;
const _X_EQ: UInt8 = 61u8;
const _X_BANG: UInt8 = 33u8;
const _X_QUEST: UInt8 = 63u8;
const _X_DQUOTE: UInt8 = 34u8;
const _X_SQUOTE: UInt8 = 39u8;
const _X_HASH: UInt8 = 35u8;
const _X_AMP: UInt8 = 38u8;
const _X_SEMI: UInt8 = 59u8;
const _X_SPACE: UInt8 = 32u8;
const _X_TAB: UInt8 = 9u8;
const _X_CR: UInt8 = 13u8;
const _X_LF: UInt8 = 10u8;
const _X_DASH: UInt8 = 45u8;
const _X_LOWER_X: UInt8 = 120u8;
const _X_UPPER_X: UInt8 = 88u8;

// --------------------------------------------------
//  Parser state
// --------------------------------------------------

// Mutable parse state. `text`/`pos` are the input cursor; the node vectors
// accumulate the flat document; `stack` holds the open element node indices;
// `have_root` tracks whether a top-level element was seen; `failed`/`error`
// carry the first failure (the parse loop stops at the first `false`).
type _XmlParser = {
  text: Str;
  pos: Int;
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
  stack: Vec[Int];
  have_root: Bool;
  failed: Bool;
  error: Str;
}

fn _fail(p: &mut _XmlParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

fn _byte(p: &mut _XmlParser, i: Int) -> UInt8 {
  return string.byte_at(p.text, i);
}

fn _is_ws(b: UInt8) -> Bool {
  if b == _X_SPACE {
    return true;
  }
  if b == _X_TAB {
    return true;
  }
  if b == _X_CR {
    return true;
  }
  if b == _X_LF {
    return true;
  }
  return false;
}

// Byte that terminates a tag/attribute name: whitespace, '<', '>', '/' or '='.
fn _is_name_end(b: UInt8) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _X_LT {
    return true;
  }
  if b == _X_GT {
    return true;
  }
  if b == _X_SLASH {
    return true;
  }
  if b == _X_EQ {
    return true;
  }
  return false;
}

fn _is_ws_only(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_ws(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _skip_ws(p: &mut _XmlParser) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_byte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
}

// Index of the first occurrence of `needle` at or after p.pos, -1 when absent.
fn _find_seq(p: &mut _XmlParser, needle: Str) -> Int {
  let n = p.text.len();
  let m = needle.len();
  var i = p.pos;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if _byte(p, i + j) != string.byte_at(needle, j) {
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

// --------------------------------------------------
//  Node and attribute construction
// --------------------------------------------------

// Append one node, returning its index.
fn _push_node(p: &mut _XmlParser, kind: Int, name: Str, txt: Str, parent: Int) -> Int {
  p.kinds.push(kind);
  p.names.push(name);
  p.texts.push(txt);
  p.parents.push(parent);
  return p.kinds.len() - 1;
}

fn _push_attr(p: &mut _XmlParser, owner: Int, name: Str, value: Str) {
  p.attr_names.push(name);
  p.attr_values.push(value);
  p.attr_owners.push(owner);
}

// --------------------------------------------------
//  Entity decoding
// --------------------------------------------------

// Append the UTF-8 encoding of `code` (1..0x10FFFF) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" numeric reference body, -1 when malformed,
// out of range (> U+10FFFF) or NUL.
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if string.byte_at(body, 0) != _X_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = string.byte_at(body, i);
  if mark == _X_LOWER_X || mark == _X_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b = string.byte_at(body, i) as Int;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base {
      return -1;
    }
    v = v * base + d;
    if v > 1114111 {
      return -1;
    }
    i = i + 1;
  }
  if v == 0 {
    return -1;
  }
  return v;
}

// Decode one entity starting at raw[at] (which must be '&'); returns the
// number of input bytes consumed. Recognized references are decoded; an
// unknown, malformed or unterminated reference contributes a literal '&' and
// the scan continues with the following byte (documented leniency).
fn _push_entity(raw: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var limit = at + 11;
  if limit > end {
    limit = end;
  }
  var semi = -1;
  var j = at + 1;
  while j < limit {
    if string.byte_at(raw, j) == _X_SEMI {
      semi = j;
      break;
    }
    j = j + 1;
  }
  if semi < 0 {
    out.push(_X_AMP);
    return 1;
  }
  let body = string.str_slice(raw, at + 1, semi);
  if compare.str_compare(body, "amp") == 0 {
    out.push(_X_AMP);
    return semi - at + 1;
  }
  if compare.str_compare(body, "lt") == 0 {
    out.push(_X_LT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "gt") == 0 {
    out.push(_X_GT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "quot") == 0 {
    out.push(_X_DQUOTE);
    return semi - at + 1;
  }
  if compare.str_compare(body, "apos") == 0 {
    out.push(_X_SQUOTE);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code > 0 {
    _push_utf8(out, code);
    return semi - at + 1;
  }
  out.push(_X_AMP);
  return 1;
}

// Entity-decode raw[start, end) into a fresh Str.
fn _decode_range(raw: Str, start: Int, end: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    let b = string.byte_at(raw, i);
    if b == _X_AMP {
      let adv = _push_entity(raw, i, end, &mut out);
      i = i + adv;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Document scanning
// --------------------------------------------------

// Consume a run of character data up to the next '<' or EOF, add it as a text
// node, or reject non-whitespace text at document level.
fn _consume_text(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  var i = p.pos;
  while i < n {
    if _byte(p, i) == _X_LT {
      break;
    }
    i = i + 1;
  }
  let raw = string.str_slice(p.text, start, i);
  let txt = _decode_range(raw, 0, raw.len());
  p.pos = i;
  if p.stack.len() == 0 {
    if _is_ws_only(txt) {
      return true;
    }
    return _fail(p, "xml: text outside root element");
  }
  let parent = p.stack[p.stack.len() - 1];
  _push_node(p, 1, "", txt, parent);
  return true;
}

// Consume markup after '<': comment, processing instruction, closing tag or
// opening (possibly self-closing) tag.
fn _consume_markup(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "xml: unclosed tag");
  }
  let b = _byte(p, p.pos);
  if b == _X_BANG {
    if p.pos + 2 < n {
      if _byte(p, p.pos + 1) == _X_DASH {
        if _byte(p, p.pos + 2) == _X_DASH {
          p.pos = p.pos + 3;
          let close = _find_seq(p, "-->");
          if close < 0 {
            return _fail(p, "xml: unclosed comment");
          }
          p.pos = close + 3;
          return true;
        }
      }
    }
    return _fail(p, "xml: unsupported markup");
  }
  if b == _X_QUEST {
    p.pos = p.pos + 1;
    let close = _find_seq(p, "?>");
    if close < 0 {
      return _fail(p, "xml: unclosed processing instruction");
    }
    p.pos = close + 2;
    return true;
  }
  if b == _X_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  return _start_tag(p);
}

// Consume a start tag (p.pos at the first name byte), register the element and
// its attributes, and push it on the open-element stack unless self-closing.
fn _start_tag(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "xml: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  var parent = 0;
  if p.stack.len() > 0 {
    parent = p.stack[p.stack.len() - 1];
  } else {
    if p.have_root {
      return _fail(p, "xml: multiple root elements");
    }
    p.have_root = true;
  }
  let node = _push_node(p, 0, name, "", parent);
  var self_close = false;
  loop {
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "xml: unclosed tag");
    }
    let b = _byte(p, p.pos);
    if b == _X_GT {
      p.pos = p.pos + 1;
      break;
    }
    if b == _X_SLASH {
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n {
        return _fail(p, "xml: unclosed tag");
      }
      if _byte(p, p.pos) != _X_GT {
        return _fail(p, "xml: malformed tag");
      }
      p.pos = p.pos + 1;
      self_close = true;
      break;
    }
    let an_start = p.pos;
    while p.pos < n {
      if _is_name_end(_byte(p, p.pos)) {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos == an_start {
      return _fail(p, "xml: malformed attribute");
    }
    let aname = string.str_slice(p.text, an_start, p.pos);
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "xml: unclosed tag");
    }
    if _byte(p, p.pos) != _X_EQ {
      return _fail(p, "xml: malformed attribute");
    }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "xml: unclosed tag");
    }
    let q = _byte(p, p.pos);
    if q != _X_DQUOTE && q != _X_SQUOTE {
      return _fail(p, "xml: malformed attribute");
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    while p.pos < n {
      if _byte(p, p.pos) == q {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _fail(p, "xml: unclosed attribute value");
    }
    let raw_value = string.str_slice(p.text, v_start, p.pos);
    let value = _decode_range(raw_value, 0, raw_value.len());
    p.pos = p.pos + 1;
    _push_attr(p, node, aname, value);
  }
  if !self_close {
    p.stack.push(node);
  }
  return true;
}

// Consume a closing tag (p.pos at the first name byte after "</").
fn _close_tag(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_byte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "xml: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  _skip_ws(p);
  if p.pos >= n {
    return _fail(p, "xml: unclosed tag");
  }
  if _byte(p, p.pos) != _X_GT {
    return _fail(p, "xml: malformed tag");
  }
  p.pos = p.pos + 1;
  if p.stack.len() == 0 {
    return _fail(p, "xml: unexpected closing tag");
  }
  let open_idx = p.stack[p.stack.len() - 1];
  if compare.str_compare(p.names[open_idx], name) != 0 {
    return _fail(p, "xml: mismatched closing tag");
  }
  p.stack.pop();
  return true;
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse an XML document in the supported subset.
/// Params: text - the whole document as one Str (UTF-8 bytes pass through;
/// only markup bytes are interpreted).
/// Returns: Ok(doc) with the flat node model (node 0 is the synthetic root).
/// Error case: Err("xml: ...") on the first malformed construct; see SPEC.md
/// for the full catalog (stray '<', unclosed tag, unclosed attribute value,
/// unclosed comment, unclosed processing instruction, unsupported markup,
/// malformed tag/attribute, mismatched/unexpected closing tag, text outside
/// the root element, multiple root elements).
/// Complexity: O(n) over the document length.
pub fn xml_parse(text: Str) -> Result[XmlDoc, Str] {
  var p = _XmlParser{
    text: text; pos: 0;
    kinds: Vec[Int].new(); names: Vec[Str].new(); texts: Vec[Str].new();
    parents: Vec[Int].new(); attr_names: Vec[Str].new();
    attr_values: Vec[Str].new(); attr_owners: Vec[Int].new();
    stack: Vec[Int].new(); have_root: false; failed: false; error: "";
  };
  _push_node(&mut p, 0, "", "", -1);
  let n = text.len();
  while p.pos < n {
    let b = _byte(&mut p, p.pos);
    if b == _X_LT {
      p.pos = p.pos + 1;
      if !_consume_markup(&mut p) {
        return _err_doc(p.error);
      }
    } else {
      if !_consume_text(&mut p) {
        return _err_doc(p.error);
      }
    }
  }
  if p.stack.len() > 0 {
    return _err_doc("xml: unclosed tag");
  }
  return _ok_doc(XmlDoc{
    kinds: p.kinds; names: p.names; texts: p.texts; parents: p.parents;
    attr_names: p.attr_names; attr_values: p.attr_values; attr_owners: p.attr_owners;
  });
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// Index of the document's root element: the first element child of node 0.
/// Params: d - the parsed document.
/// Returns: the node index, or -1 when the document has no top-level element.
/// Complexity: O(nodes).
pub fn xml_root(d: &XmlDoc) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 {
      if d.parents[i] == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Number of nodes in the document, including the synthetic root.
/// Params: d - the parsed document.
/// Returns: d.kinds.len(); an empty document reports 1.
/// Complexity: O(1).
pub fn xml_node_count(d: &XmlDoc) -> Int {
  return d.kinds.len();
}

/// Node kind: 0 for an element, 1 for a text node.
/// Params: d - the parsed document; node - the node index.
/// Returns: the kind, or -1 when node is out of range.
/// Complexity: O(1).
pub fn xml_kind(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.kinds.len() {
    return -1;
  }
  return d.kinds[node];
}

/// Element tag name (empty for text nodes and the synthetic root).
/// Params: d - the parsed document; node - the node index.
/// Returns: the name, or "" when node is out of range.
/// Complexity: O(1).
pub fn xml_name(d: &XmlDoc, node: Int) -> Str {
  if node < 0 || node >= d.names.len() {
    return "";
  }
  return d.names[node];
}

/// Concatenation of a node's direct text children, in document order.
/// Params: d - the parsed document; node - the node index.
/// Returns: the concatenated text ("" for text nodes, out-of-range indices
/// and elements without text children). Nested element text is NOT included.
/// Complexity: O(nodes + text bytes).
pub fn xml_text(d: &XmlDoc, node: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 1 {
      if d.parents[i] == node {
        builder.sb_push_str(&mut out, d.texts[i]);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Number of direct children (elements and text nodes) of a node.
/// Params: d - the parsed document; node - the node index.
/// Returns: the child count; 0 for out-of-range nodes.
/// Complexity: O(nodes).
pub fn xml_child_count(d: &XmlDoc, node: Int) -> Int {
  var count = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.parents[i] == node {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Direct child of a node by zero-based index (elements and text nodes count).
/// Params: d - the parsed document; node - the node index; index - the
/// zero-based child position.
/// Returns: Some(child index) on a hit; None when index is negative or out of
/// range (and for any out-of-range node).
/// Complexity: O(nodes).
pub fn xml_child(d: &XmlDoc, node: Int, index: Int) -> Option[Int] {
  if index < 0 {
    return None;
  }
  var seen = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.parents[i] == node {
      if seen == index {
        return Some(i);
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return None;
}

/// First attribute with the given name on the given node.
/// Params: d - the parsed document; node - the node index; name - the exact
/// attribute name (case-sensitive byte comparison).
/// Returns: Some(value); None when the node has no such attribute. Duplicate
/// attribute names keep the first occurrence.
/// Complexity: O(attributes).
pub fn xml_attr(d: &XmlDoc, node: Int, name: Str) -> Option[Str] {
  var i = 0;
  while i < d.attr_owners.len() {
    if d.attr_owners[i] == node {
      if compare.str_compare(d.attr_names[i], name) == 0 {
        return Some(d.attr_values[i]);
      }
    }
    i = i + 1;
  }
  return None;
}

/// All element nodes with the given tag name, in document order.
/// Params: d - the parsed document; tag - the exact tag name.
/// Returns: their node indices (empty when nothing matches); the synthetic
/// root (empty name) is never included.
/// Complexity: O(nodes).
pub fn xml_find(d: &XmlDoc, tag: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 {
      if compare.str_compare(d.names[i], tag) == 0 {
        out.push(i);
      }
    }
    i = i + 1;
  }
  return out;
}

/// First element node with the given tag name.
/// Params: d - the parsed document; tag - the exact tag name.
/// Returns: Some(node index) for the document-order-first match, None when
/// nothing matches.
/// Complexity: O(nodes).
pub fn xml_find_first(d: &XmlDoc, tag: Str) -> Option[Int] {
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 {
      if compare.str_compare(d.names[i], tag) == 0 {
        return Some(i);
      }
    }
    i = i + 1;
  }
  return None;
}

/// Concatenated direct text of the first element with the given tag name.
/// Params: d - the parsed document; tag - the exact tag name.
/// Returns: Some(xml_text of the first match) (which may be ""); None when
/// nothing matches.
/// Complexity: O(nodes + text bytes).
pub fn xml_text_of(d: &XmlDoc, tag: Str) -> Option[Str] {
  let found = xml_find_first(d, tag);
  match found {
    Some(node) => { return Some(xml_text(d, node)); },
    None => {},
  }
  return None;
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

/// Escape the five XML metacharacters as named entities.
/// Params: s - the text to escape.
/// Returns: s with & -> &amp;, < -> &lt;, > -> &gt;, " -> &quot; and
/// ' -> &apos;; every other byte (including UTF-8 sequences) passes through.
/// Complexity: O(s.len()).
pub fn xml_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _X_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _X_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _X_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _X_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } elif b == _X_SQUOTE {
      builder.sb_push_str(&mut out, "&apos;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode the predefined and numeric entities (inverse of most of xml_escape).
/// Params: s - the text to decode.
/// Returns: s with &amp; &lt; &gt; &quot; &apos; &#NN; and &#xHH; decoded;
/// unknown or malformed references pass through verbatim.
/// Complexity: O(s.len()).
pub fn xml_unescape(s: Str) -> Str {
  return _decode_range(s, 0, s.len());
}
