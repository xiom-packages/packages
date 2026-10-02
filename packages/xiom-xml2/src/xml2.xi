// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.xml2: a pure-XIOM XML model (parser subset, DOM tree,
// serializer, namespaces, XPath-LITE). No FFI, no libxml2, no dependency
// beyond xiom.std.
//
// Covered surface (see SPEC.md for the exact subset, error catalog and
// non-goals):
//   * Parser subset: elements, attributes (double or single quoted),
//     character data, CDATA sections, comments, processing instructions,
//     an XML declaration (stored as a PI node named "xml"), and a DOCTYPE
//     subset (<!DOCTYPE name>, SYSTEM "lit", PUBLIC "pub" "sys"); an
//     internal DTD subset ("[...]") is rejected.
//   * Entity decoding: the five predefined entities plus &#NN; and &#xHH;.
//     Unknown, malformed and unterminated references are errors (strict;
//     there is no lenient pass-through).
//   * Well-formedness errors carry byte offsets: bad names, stray '<',
//     unclosed/malformed tags and attribute values, duplicate attributes,
//     mismatched/unexpected closing tags, text outside the root, multiple
//     roots, unclosed comments/CDATA/PIs, malformed DOCTYPEs.
//   * Bounded work: 1 MiB input, depth 64, 16384 nodes, 256 attributes per
//     element.
//   * DOM tree over parallel vectors: each node knows its parent, first
//     child, last child and next sibling. Node 0 is the synthetic document
//     node; its child chain holds the document-level nodes (DOCTYPE,
//     comments, PIs and the root element).
//   * Node kinds: 0 element, 1 text, 2 CDATA, 3 comment, 4 PI, 5 DOCTYPE.
//   * Serializer with documented escaping (text: & < >; attributes: & < "),
//     double-quoted attributes, canonical attribute order (ascending byte
//     order by name) and verbatim comment/PI/DOCTYPE emission.
//   * Namespaces: prefix/local split, scoped prefix resolution through
//     xmlns / xmlns:prefix declarations, the fixed xml prefix, unbound
//     prefix errors, the default namespace for elements, no-namespace for
//     unprefixed attributes, and listing the declarations visible on a node.
//   * XPath-LITE: absolute and relative child paths, name tests (local-only
//     when unprefixed, namespace-aware when prefixed), @attr steps, text(),
//     positional predicates [n] (1-based, per context node) and attribute
//     equality predicates [@a='v'].
//
// v0.62.2 compiler notes that shaped this module:
//   * free functions only, no methods, no lambdas, no mut match patterns,
//     no Vec of structs, no Vec[fn] dispatch;
//   * Result payloads with struct/Vec payloads are constructed only through
//     the tiny leaf helpers below (direct construction inside larger
//     functions miscompiles);
//   * every Str read out of a Vec[Str] element goes through a typed local
//     and equality uses xiom.string.compare.str_compare (BUG 17);
//   * every byte read from a Str/Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic;
//   * &mut Vec call sites pass an explicit &mut;
//   * the parser is iterative with an explicit open-element stack; the
//     serializer and the deep-text collector are recursive but the parse
//     depth cap (64) bounds them;
//   * every parallel vector is pushed only through _push_node/_push_attr,
//     which keep all arrays in lockstep and link each new node into its
//     parent's first-child/next-sibling chain.

module xiom.xml2

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Element node kind.
pub const XML2_KIND_ELEMENT: Int = 0;

/// Character-data (text) node kind.
pub const XML2_KIND_TEXT: Int = 1;

/// CDATA section node kind.
pub const XML2_KIND_CDATA: Int = 2;

/// Comment node kind.
pub const XML2_KIND_COMMENT: Int = 3;

/// Processing instruction node kind.
pub const XML2_KIND_PI: Int = 4;

/// DOCTYPE declaration node kind.
pub const XML2_KIND_DOCTYPE: Int = 5;

/// Maximum accepted input size in bytes (1 MiB).
pub const XML2_MAX_INPUT: Int = 1048576;

/// Maximum open-element nesting depth.
pub const XML2_MAX_DEPTH: Int = 64;

/// Maximum node count per document, including the synthetic document node.
pub const XML2_MAX_NODES: Int = 16384;

/// Maximum attributes per element.
pub const XML2_MAX_ATTRS: Int = 256;

/// The fixed URI bound to the reserved `xml` prefix.
pub const XML2_NS_XML: Str = "http://www.w3.org/XML/1998/namespace";

/// The URI bound to the reserved `xmlns` prefix (not resolvable as a prefix).
pub const XML2_NS_XMLNS: Str = "http://www.w3.org/2000/xmlns/";

/// XPath-LITE result kind: the expression ended in a node test.
pub const XML2_XPATH_KIND_NODES: Int = 0;

/// XPath-LITE result kind: the expression ended in an @attr step.
pub const XML2_XPATH_KIND_ATTRS: Int = 1;

// Byte constants, in Int space so comparisons never sign-extend.
const _B_HT: Int = 9;
const _B_LF: Int = 10;
const _B_CR: Int = 13;
const _B_SP: Int = 32;
const _B_BANG: Int = 33;
const _B_DQ: Int = 34;
const _B_HASH: Int = 35;
const _B_AMP: Int = 38;
const _B_SQ: Int = 39;
const _B_LP: Int = 40;
const _B_RP: Int = 41;
const _B_DASH: Int = 45;
const _B_SLASH: Int = 47;
const _B_COLON: Int = 58;
const _B_SEMI: Int = 59;
const _B_LT: Int = 60;
const _B_EQ: Int = 61;
const _B_GT: Int = 62;
const _B_QUEST: Int = 63;
const _B_AT: Int = 64;
const _B_LBR: Int = 91;
const _B_RBR: Int = 93;
const _B_LOWER_X: Int = 120;
const _B_UPPER_X: Int = 88;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed XML document as a flat node list with parallel vectors.
///
/// kinds[i] is the node kind (XML2_KIND_*). Node 0 is the synthetic document
/// node: an element-kind node with an empty name and parent -1, always
/// present. names[i] holds an element's qualified name, a PI's target, or a
/// DOCTYPE's name ("" for the other kinds). texts[i] holds a text/CDATA
/// node's content, a comment's body, a PI's data (leading whitespace
/// trimmed), or a DOCTYPE's canonical external identifier ("" for the
/// others). parents[i] is the owning node index (-1 only for node 0).
/// first_child[i]/last_child[i]/next_sibling[i] link the DOM tree; all are
/// -1 when absent. opens[i]/closes[i] bound the source byte range
/// [opens[i], closes[i]) of node i. Attributes form a flat association
/// list: attr_names[k] / attr_values[k] belong to node attr_owners[k], in
/// source order. src holds the whole input for raw-span work.
///
/// Read fields through the accessors below so out-of-range indices stay
/// safe. The parser never lets the parallel vectors drift.
pub type XmlDoc = {
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  first_child: Vec[Int];
  last_child: Vec[Int];
  next_sibling: Vec[Int];
  opens: Vec[Int];
  closes: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
  src: Vec[UInt8];
}

/// XPath-LITE evaluation result. kind is XML2_XPATH_KIND_NODES (0) or
/// XML2_XPATH_KIND_ATTRS (1). For a node result, nodes holds the matched
/// element/text/CDATA node indices and values is empty. For an attribute
/// result, values holds the matched attribute values and nodes holds the
/// owner element indices in lockstep (nodes.len() == values.len() == count).
/// Attribute values are stored as Str; the two vectors never drift.
pub type XPathResult = {
  kind: Int;
  count: Int;
  nodes: Vec[Int];
  values: Vec[Str];
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_strs(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_strs(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[XPathResult, Str].
fn _ok_xr(v: XPathResult) -> Result[XPathResult, Str] {
  return Ok(v);
}

// Err(m) for Result[XPathResult, Str].
fn _err_xr(m: Str) -> Result[XPathResult, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Str equality through str_compare (BUG 17 discipline).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte of s at i, widened to 0..255.
fn _sbyte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Raw bytes of a Str (one byte per index; a Str cannot contain NUL).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// True when s starts with the literal prefix p.
fn _starts_with(s: Str, p: Str) -> Bool {
  if p.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < p.len() {
    if _sbyte(s, i) != _sbyte(p, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the byte b occurs anywhere in s.
fn _contains_byte(s: Str, b: Int) -> Bool {
  var i = 0;
  while i < s.len() {
    if _sbyte(s, i) == b {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Prefix of a qualified name ("" when there is no ':'); the first ':'
// separates prefix and local part.
fn _qname_prefix(q: Str) -> Str {
  var i = 0;
  while i < q.len() {
    if _sbyte(q, i) == _B_COLON {
      return string.str_slice(q, 0, i);
    }
    i = i + 1;
  }
  return "";
}

// Local part of a qualified name (the whole name when there is no ':').
fn _qname_local(q: Str) -> Str {
  var i = 0;
  while i < q.len() {
    if _sbyte(q, i) == _B_COLON {
      return string.str_slice(q, i + 1, q.len());
    }
    i = i + 1;
  }
  return q;
}

// --------------------------------------------------
//  Parser state and internals
// --------------------------------------------------

// Mutable parse state. text/pos are the input cursor; the parallel vectors
// accumulate the document; stack holds the open element node indices;
// have_root/have_doctype track document-level constraints; failed/error
// carry the first failure (the parse loop stops at the first false).
type _XP = {
  text: Str;
  pos: Int;
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  firsts: Vec[Int];
  lasts: Vec[Int];
  nexts: Vec[Int];
  opens: Vec[Int];
  closes: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
  stack: Vec[Int];
  have_root: Bool;
  have_doctype: Bool;
  failed: Bool;
  error: Str;
}

// Record the first failure as "<m> at offset <pos>". No-op after a failure.
fn _set_fail(p: &mut _XP, m: Str) {
  if p.failed {
    return;
  }
  p.failed = true;
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, m);
  builder.sb_push_str(&mut out, " at offset ");
  builder.sb_push_int(&mut out, p.pos);
  p.error = builder.sb_to_str(&out);
}

// Set the failure and return false (for Bool-returning helpers).
fn _fail(p: &mut _XP, m: Str) -> Bool {
  _set_fail(p, m);
  return false;
}

// Byte of the parser text at i, widened to 0..255.
fn _pbyte(p: &_XP, i: Int) -> Int {
  return (string.byte_at(p.text, i) as Int) & 0xFF;
}

// True for XML whitespace: space, TAB, CR, LF.
fn _is_ws(b: Int) -> Bool {
  if b == _B_SP || b == _B_HT {
    return true;
  }
  if b == _B_CR || b == _B_LF {
    return true;
  }
  return false;
}

// True when every byte of s is XML whitespace.
fn _is_ws_only(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_ws(_sbyte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte that ends a tag or attribute name: whitespace, '<', '>', '/', '=',
// a quote, or end-of-input handled by the caller.
fn _is_name_end(b: Int) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _B_LT || b == _B_GT {
    return true;
  }
  if b == _B_SLASH || b == _B_EQ {
    return true;
  }
  if b == _B_DQ || b == _B_SQ {
    return true;
  }
  return false;
}

// True when s is a name in the supported subset: non-empty; every byte
// above 0x20; none of < > / = " ' [ ] @ #. Full XML NameStartChar rules are
// a documented non-goal (SPEC.md section 10).
fn _valid_name(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    let b = _sbyte(s, i);
    if b <= _B_SP {
      return false;
    }
    if _is_name_end(b) {
      return false;
    }
    if b == _B_LBR || b == _B_RBR {
      return false;
    }
    if b == _B_AT || b == _B_HASH {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when t is a valid XPath node test: a name, and when it carries a
// ':' both the prefix and the local part must be non-empty.
fn _valid_test_name(t: Str) -> Bool {
  if !_valid_name(t) {
    return false;
  }
  if _contains_byte(t, _B_COLON) {
    if _qname_prefix(t).len() == 0 {
      return false;
    }
    if _qname_local(t).len() == 0 {
      return false;
    }
  }
  return true;
}

// Skip whitespace from the parser position.
fn _skip_ws(p: &mut _XP) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
}

// Index of the first occurrence of `needle` at or after `from`, -1 when
// absent.
fn _find_seq(p: &_XP, from: Int, needle: Str) -> Int {
  let n = p.text.len();
  let m = needle.len();
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if _pbyte(p, i + j) != _sbyte(needle, j) {
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

// True when the literal `lit` occurs at pos.
fn _seq_at(p: &_XP, pos: Int, lit: Str) -> Bool {
  if pos + lit.len() > p.text.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _pbyte(p, pos + i) != _sbyte(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append the UTF-8 encoding of code (1..0x10FFFF) to out.
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

// Codepoint of a "#NN" or "#xHH" reference body: >0 on success; -1 for a
// NUL, malformed digits, an empty body, a surrogate or a value above
// U+10FFFF.
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if _sbyte(body, 0) != _B_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = _sbyte(body, i);
  if mark == _B_LOWER_X || mark == _B_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b = _sbyte(body, i);
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
  if v >= 55296 && v <= 57343 {
    return -1;
  }
  return v;
}

// Decode one entity starting at `at` (which must be '&'); appends the
// decoded bytes and returns the number of input bytes consumed, or -1 after
// setting the parser error. Strict: unknown and malformed references fail.
fn _push_entity(p: &mut _XP, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var limit = at + 12;
  if limit > end {
    limit = end;
  }
  var semi = -1;
  var j = at + 1;
  var found = false;
  while j < limit && !found {
    if _pbyte(p, j) == _B_SEMI {
      semi = j;
      found = true;
    }
    j = j + 1;
  }
  if semi < 0 {
    p.pos = at;
    _set_fail(p, "xml2: unterminated entity");
    return -1;
  }
  let body = string.str_slice(p.text, at + 1, semi);
  if _streq(body, "amp") {
    out.push(_B_AMP as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "lt") {
    out.push(_B_LT as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "gt") {
    out.push(_B_GT as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "quot") {
    out.push(_B_DQ as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "apos") {
    out.push(_B_SQ as UInt8);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code > 0 {
    _push_utf8(out, code);
    return semi - at + 1;
  }
  p.pos = at;
  if body.len() > 0 {
    if _sbyte(body, 0) == _B_HASH {
      _set_fail(p, "xml2: invalid character reference");
      return -1;
    }
  }
  _set_fail(p, "xml2: unknown entity");
  return -1;
}

// Entity-decode text[start, end) into out; false on the first bad entity.
fn _decode_into(p: &mut _XP, start: Int, end: Int, out: &mut Vec[UInt8]) -> Bool {
  var i = start;
  while i < end {
    let b = _pbyte(p, i);
    if b == _B_AMP {
      let adv = _push_entity(p, i, end, out);
      if adv < 0 {
        return false;
      }
      i = i + adv;
    } else {
      out.push(string.byte_at(p.text, i));
      i = i + 1;
    }
  }
  return true;
}

// Append one node (all parallel vectors in lockstep) and link it into its
// parent's child chain. Returns the node index, or -1 after a node-count
// failure. parent is -1 only for node 0.
fn _push_node(p: &mut _XP, kind: Int, name: Str, txt: Str, parent: Int, open: Int, close: Int) -> Int {
  if p.kinds.len() >= XML2_MAX_NODES {
    _set_fail(p, "xml2: too many nodes");
    return -1;
  }
  let idx = p.kinds.len();
  p.kinds.push(kind);
  p.names.push(name);
  p.texts.push(txt);
  p.parents.push(parent);
  p.firsts.push(-1);
  p.lasts.push(-1);
  p.nexts.push(-1);
  p.opens.push(open);
  p.closes.push(close);
  if parent >= 0 {
    let last: Int = p.lasts[parent];
    if last < 0 {
      p.firsts[parent] = idx;
    } else {
      p.nexts[last] = idx;
    }
    p.lasts[parent] = idx;
  }
  return idx;
}

// Append one attribute association.
fn _push_attr(p: &mut _XP, owner: Int, name: Str, value: Str) {
  p.attr_names.push(name);
  p.attr_values.push(value);
  p.attr_owners.push(owner);
}

// Consume character data up to the next '<' or EOF.
fn _consume_text(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  var i = p.pos;
  while i < n {
    if _pbyte(p, i) == _B_LT {
      break;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  if !_decode_into(p, start, i, &mut out) {
    return false;
  }
  let txt = builder.sb_to_str(&out);
  p.pos = i;
  if p.stack.len() == 0 {
    if _is_ws_only(txt) {
      return true;
    }
    p.pos = start;
    return _fail(p, "xml2: text outside root element");
  }
  let parent: Int = p.stack[p.stack.len() - 1];
  let node = _push_node(p, 1, "", txt, parent, start, i);
  if node < 0 {
    return false;
  }
  return true;
}

// Consume a comment (p.pos at the '!' after '<').
fn _consume_comment(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  p.pos = p.pos + 3;
  let body_start = p.pos;
  let close = _find_seq(p, body_start, "-->");
  if close < 0 {
    p.pos = n;
    return _fail(p, "xml2: unclosed comment");
  }
  let dh = _find_seq(p, body_start, "--");
  if dh >= 0 && dh < close {
    p.pos = dh;
    return _fail(p, "xml2: double hyphen in comment");
  }
  var parent = 0;
  if p.stack.len() > 0 {
    parent = p.stack[p.stack.len() - 1];
  }
  let body = string.str_slice(p.text, body_start, close);
  let node = _push_node(p, 3, "", body, parent, open, close + 3);
  if node < 0 {
    return false;
  }
  p.pos = close + 3;
  return true;
}

// Consume a CDATA section (p.pos at the '!' after '<').
fn _consume_cdata(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  p.pos = p.pos + 8;
  if p.stack.len() == 0 {
    p.pos = open;
    return _fail(p, "xml2: text outside root element");
  }
  let body_start = p.pos;
  let close = _find_seq(p, body_start, "]]>");
  if close < 0 {
    p.pos = n;
    return _fail(p, "xml2: unclosed CDATA section");
  }
  let parent: Int = p.stack[p.stack.len() - 1];
  let body = string.str_slice(p.text, body_start, close);
  let node = _push_node(p, 2, "", body, parent, open, close + 3);
  if node < 0 {
    return false;
  }
  p.pos = close + 3;
  return true;
}

// Consume a processing instruction (p.pos at the '?' after '<').
fn _consume_pi(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  p.pos = p.pos + 1;
  let tstart = p.pos;
  var stop = -1;
  while p.pos < n {
    let b = _pbyte(p, p.pos);
    if _is_ws(b) || b == _B_QUEST {
      stop = p.pos;
      break;
    }
    p.pos = p.pos + 1;
  }
  if stop < 0 {
    p.pos = n;
    return _fail(p, "xml2: unclosed processing instruction");
  }
  p.pos = stop;
  let target = string.str_slice(p.text, tstart, stop);
  if !_valid_name(target) {
    return _fail(p, "xml2: malformed processing instruction");
  }
  let close = _find_seq(p, p.pos, "?>");
  if close < 0 {
    p.pos = n;
    return _fail(p, "xml2: unclosed processing instruction");
  }
  var ds = p.pos;
  var skipping = true;
  while ds < close && skipping {
    if _is_ws(_pbyte(p, ds)) {
      ds = ds + 1;
    } else {
      skipping = false;
    }
  }
  let data = string.str_slice(p.text, ds, close);
  var parent = 0;
  if p.stack.len() > 0 {
    parent = p.stack[p.stack.len() - 1];
  }
  let node = _push_node(p, 4, target, data, parent, open, close + 2);
  if node < 0 {
    return false;
  }
  p.pos = close + 2;
  return true;
}

// Parse a quoted DOCTYPE literal (system or public identifier body; no
// entity decoding inside literals). Returns the literal content.
fn _parse_doctype_lit(p: &mut _XP) -> Result[Str, Str] {
  let n = p.text.len();
  if p.pos >= n {
    _set_fail(p, "xml2: malformed DOCTYPE");
    return _err_str(p.error);
  }
  let q = _pbyte(p, p.pos);
  if q != _B_DQ && q != _B_SQ {
    _set_fail(p, "xml2: malformed DOCTYPE");
    return _err_str(p.error);
  }
  p.pos = p.pos + 1;
  let start = p.pos;
  var stop = -1;
  while p.pos < n {
    if _pbyte(p, p.pos) == q {
      stop = p.pos;
      break;
    }
    p.pos = p.pos + 1;
  }
  if stop < 0 {
    p.pos = n;
    _set_fail(p, "xml2: malformed DOCTYPE");
    return _err_str(p.error);
  }
  p.pos = stop + 1;
  return _ok_str(string.str_slice(p.text, start, stop));
}

// Re-quote a DOCTYPE literal canonically: double quotes unless the content
// itself contains a double quote, in which case single quotes are used.
fn _quote_doctype_lit(s: Str) -> Str {
  if _contains_byte(s, _B_DQ) {
    return "'" + s + "'";
  }
  return "\"" + s + "\"";
}

// Consume a DOCTYPE declaration (p.pos at the '!' after '<'). Supported
// subset: `<!DOCTYPE name>`, `<!DOCTYPE name SYSTEM "lit">` and
// `<!DOCTYPE name PUBLIC "pub" "sys">`; internal subsets are rejected.
fn _consume_doctype(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  p.pos = p.pos + 8;
  if p.pos >= n || !_is_ws(_pbyte(p, p.pos)) {
    return _fail(p, "xml2: malformed DOCTYPE");
  }
  _skip_ws(p);
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "xml2: malformed DOCTYPE");
  }
  let dname = string.str_slice(p.text, name_start, p.pos);
  if !_valid_name(dname) {
    return _fail(p, "xml2: malformed DOCTYPE");
  }
  _skip_ws(p);
  var ext = "";
  if _seq_at(p, p.pos, "SYSTEM") {
    p.pos = p.pos + 6;
    if p.pos >= n || !_is_ws(_pbyte(p, p.pos)) {
      return _fail(p, "xml2: malformed DOCTYPE");
    }
    _skip_ws(p);
    let lr = _parse_doctype_lit(p);
    if !lr.is_ok {
      return false;
    }
    let lit: Str = lr.value;
    ext = "SYSTEM " + _quote_doctype_lit(lit);
  } elif _seq_at(p, p.pos, "PUBLIC") {
    p.pos = p.pos + 6;
    if p.pos >= n || !_is_ws(_pbyte(p, p.pos)) {
      return _fail(p, "xml2: malformed DOCTYPE");
    }
    _skip_ws(p);
    let l1 = _parse_doctype_lit(p);
    if !l1.is_ok {
      return false;
    }
    if p.pos >= n || !_is_ws(_pbyte(p, p.pos)) {
      return _fail(p, "xml2: malformed DOCTYPE");
    }
    _skip_ws(p);
    let l2 = _parse_doctype_lit(p);
    if !l2.is_ok {
      return false;
    }
    let pv: Str = l1.value;
    let sv: Str = l2.value;
    ext = "PUBLIC " + _quote_doctype_lit(pv) + " " + _quote_doctype_lit(sv);
  } elif p.pos < n && _pbyte(p, p.pos) == _B_LBR {
    return _fail(p, "xml2: unsupported internal DTD subset");
  } elif p.pos < n && _pbyte(p, p.pos) == _B_GT {
    ext = "";
  } else {
    return _fail(p, "xml2: malformed DOCTYPE");
  }
  _skip_ws(p);
  if p.pos >= n || _pbyte(p, p.pos) != _B_GT {
    return _fail(p, "xml2: malformed DOCTYPE");
  }
  p.pos = p.pos + 1;
  if p.have_root {
    return _fail(p, "xml2: DOCTYPE after root element");
  }
  if p.have_doctype {
    return _fail(p, "xml2: multiple DOCTYPE declarations");
  }
  p.have_doctype = true;
  let node = _push_node(p, 5, dname, ext, 0, open, p.pos);
  if node < 0 {
    return false;
  }
  return true;
}

// Consume a start tag (p.pos at the first name byte) and register the
// element plus its attributes.
fn _start_tag(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "xml2: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  if !_valid_name(name) {
    p.pos = name_start;
    return _fail(p, "xml2: malformed tag");
  }
  var parent = 0;
  if p.stack.len() > 0 {
    parent = p.stack[p.stack.len() - 1];
  } else {
    if p.have_root {
      return _fail(p, "xml2: multiple root elements");
    }
    p.have_root = true;
  }
  let node = _push_node(p, 0, name, "", parent, open, 0);
  if node < 0 {
    return false;
  }
  var seen = Vec[Str].new();
  var self_close = false;
  var done = false;
  while !done {
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "xml2: unclosed tag");
    }
    let b = _pbyte(p, p.pos);
    if b == _B_GT {
      p.pos = p.pos + 1;
      done = true;
    } elif b == _B_SLASH {
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n {
        return _fail(p, "xml2: unclosed tag");
      }
      if _pbyte(p, p.pos) != _B_GT {
        return _fail(p, "xml2: malformed tag");
      }
      p.pos = p.pos + 1;
      self_close = true;
      done = true;
    } else {
      let an_start = p.pos;
      while p.pos < n {
        if _is_name_end(_pbyte(p, p.pos)) {
          break;
        }
        p.pos = p.pos + 1;
      }
      if p.pos == an_start {
        return _fail(p, "xml2: malformed attribute");
      }
      let aname = string.str_slice(p.text, an_start, p.pos);
      if !_valid_name(aname) {
        return _fail(p, "xml2: malformed attribute");
      }
      var d = 0;
      var dup = false;
      while d < seen.len() {
        let prev: Str = seen[d];
        if _streq(prev, aname) {
          dup = true;
        }
        d = d + 1;
      }
      if dup {
        return _fail(p, "xml2: duplicate attribute");
      }
      if seen.len() >= XML2_MAX_ATTRS {
        return _fail(p, "xml2: too many attributes");
      }
      seen.push(aname);
      _skip_ws(p);
      if p.pos >= n {
        return _fail(p, "xml2: unclosed tag");
      }
      if _pbyte(p, p.pos) != _B_EQ {
        return _fail(p, "xml2: malformed attribute");
      }
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n {
        return _fail(p, "xml2: unclosed tag");
      }
      let q = _pbyte(p, p.pos);
      if q != _B_DQ && q != _B_SQ {
        return _fail(p, "xml2: malformed attribute");
      }
      p.pos = p.pos + 1;
      let v_start = p.pos;
      while p.pos < n {
        if _pbyte(p, p.pos) == q {
          break;
        }
        p.pos = p.pos + 1;
      }
      if p.pos >= n {
        return _fail(p, "xml2: unclosed attribute value");
      }
      var vout = Vec[UInt8].new();
      if !_decode_into(p, v_start, p.pos, &mut vout) {
        return false;
      }
      let value = builder.sb_to_str(&vout);
      p.pos = p.pos + 1;
      _push_attr(p, node, aname, value);
    }
  }
  if self_close {
    p.closes[node] = p.pos;
  } else {
    if p.stack.len() >= XML2_MAX_DEPTH {
      return _fail(p, "xml2: nesting too deep");
    }
    p.stack.push(node);
  }
  return true;
}

// Consume a closing tag (p.pos at the first name byte after "</").
fn _close_tag(p: &mut _XP) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "xml2: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  _skip_ws(p);
  if p.pos >= n {
    return _fail(p, "xml2: unclosed tag");
  }
  if _pbyte(p, p.pos) != _B_GT {
    return _fail(p, "xml2: malformed tag");
  }
  p.pos = p.pos + 1;
  if p.stack.len() == 0 {
    return _fail(p, "xml2: unexpected closing tag");
  }
  let open_idx: Int = p.stack[p.stack.len() - 1];
  let oname: Str = p.names[open_idx];
  if !_streq(oname, name) {
    return _fail(p, "xml2: mismatched closing tag");
  }
  p.closes[open_idx] = p.pos;
  p.stack.pop();
  return true;
}

// Consume markup after '<'.
fn _consume_markup(p: &mut _XP) -> Bool {
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "xml2: unclosed tag");
  }
  let b = _pbyte(p, p.pos);
  if b == _B_BANG {
    if _seq_at(p, p.pos, "!DOCTYPE") {
      return _consume_doctype(p);
    }
    if p.pos + 2 < n {
      if _pbyte(p, p.pos + 1) == _B_DASH {
        if _pbyte(p, p.pos + 2) == _B_DASH {
          return _consume_comment(p);
        }
      }
    }
    if _seq_at(p, p.pos, "![CDATA[") {
      return _consume_cdata(p);
    }
    return _fail(p, "xml2: unsupported markup declaration");
  }
  if b == _B_QUEST {
    return _consume_pi(p);
  }
  if b == _B_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  return _start_tag(p);
}

// Parse the whole document text into the flat node model. Node 0 is the
// synthetic document node.
fn _xml_parse(text: Str) -> Result[XmlDoc, Str] {
  if text.len() > XML2_MAX_INPUT {
    return _err_doc("xml2: document too large");
  }
  var p = _XP{
    text: text;
    pos: 0;
    kinds: Vec[Int].new();
    names: Vec[Str].new();
    texts: Vec[Str].new();
    parents: Vec[Int].new();
    firsts: Vec[Int].new();
    lasts: Vec[Int].new();
    nexts: Vec[Int].new();
    opens: Vec[Int].new();
    closes: Vec[Int].new();
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_owners: Vec[Int].new();
    stack: Vec[Int].new();
    have_root: false;
    have_doctype: false;
    failed: false;
    error: "";
  };
  _push_node(&mut p, 0, "", "", -1, 0, text.len());
  let n = text.len();
  while p.pos < n {
    let b = _pbyte(&p, p.pos);
    if b == _B_LT {
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
    _set_fail(&mut p, "xml2: unclosed element");
    return _err_doc(p.error);
  }
  if !p.have_root {
    _set_fail(&mut p, "xml2: no root element");
    return _err_doc(p.error);
  }
  let src = _str_bytes(text);
  return _ok_doc(XmlDoc{
    kinds: p.kinds;
    names: p.names;
    texts: p.texts;
    parents: p.parents;
    first_child: p.firsts;
    last_child: p.lasts;
    next_sibling: p.nexts;
    opens: p.opens;
    closes: p.closes;
    attr_names: p.attr_names;
    attr_values: p.attr_values;
    attr_owners: p.attr_owners;
    src: src;
  });
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse an XML document in the supported subset (SPEC.md section 3).
/// Params: text - the whole document as one Str (UTF-8 bytes pass through;
/// only markup bytes are interpreted; a NUL cannot occur in a Str).
/// Returns: Ok(doc) with the flat node model; node 0 is the synthetic
/// document node and its child chain holds the document-level nodes.
/// Error case: Err("xml2: ... at offset N") on the first malformed
/// construct; see SPEC.md section 9 for the catalog. Note that a Str
/// literal cannot carry a NUL, so the parser never sees one.
/// Complexity: O(n) over the document length.
pub fn xml2_parse(text: Str) -> Result[XmlDoc, Str] {
  return _xml_parse(text);
}

// --------------------------------------------------
//  DOM accessors
// --------------------------------------------------

// True when node is a valid index into the document.
fn _valid_node(d: &XmlDoc, node: Int) -> Bool {
  return node >= 0 && node < d.kinds.len();
}

/// Index of the root element: the first element-kind child of node 0.
/// Params: d - the parsed document.
/// Returns: the node index, or -1 when the document has no top-level
/// element (which a parsed document never reports).
/// Error case: none. Complexity: O(nodes).
pub fn xml2_root(d: &XmlDoc) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    let k: Int = d.kinds[i];
    if k == 0 {
      let p: Int = d.parents[i];
      if p == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Number of nodes in the document, including the synthetic document node.
/// Params: d - the parsed document. Returns: d.kinds.len(); an empty
/// document reports 1. Error case: none. Complexity: O(1).
pub fn xml2_node_count(d: &XmlDoc) -> Int {
  return d.kinds.len();
}

/// Node kind: one of the XML2_KIND_* constants.
/// Params: d - the parsed document; node - the node index.
/// Returns: the kind, or -1 when node is out of range.
/// Complexity: O(1).
pub fn xml2_kind(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let k: Int = d.kinds[node];
  return k;
}

/// Element qualified name ("" for non-element kinds and bad indices).
/// Params: d - the parsed document; node - the node index.
/// Complexity: O(1).
pub fn xml2_name(d: &XmlDoc, node: Int) -> Str {
  if !_valid_node(d, node) {
    return "";
  }
  let v: Str = d.names[node];
  return v;
}

/// Local name of an element (text after the first ':'), "" for non-elements
/// and bad indices. Complexity: O(name bytes).
pub fn xml2_local_name(d: &XmlDoc, node: Int) -> Str {
  if !_valid_node(d, node) {
    return "";
  }
  let v: Str = d.names[node];
  return _qname_local(v);
}

/// Prefix of a qualified name ("" when absent). O(name bytes).
pub fn xml2_qname_prefix(q: Str) -> Str {
  return _qname_prefix(q);
}

/// Local part of a qualified name (the whole name when unprefixed).
/// O(name bytes).
pub fn xml2_qname_local(q: Str) -> Str {
  return _qname_local(q);
}

/// Parent node index (-1 for node 0 and bad indices). O(1).
pub fn xml2_parent(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.parents[node];
  return v;
}

/// First child node index (-1 when childless or out of range). O(1).
pub fn xml2_first_child(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.first_child[node];
  return v;
}

/// Last child node index (-1 when childless or out of range). O(1).
pub fn xml2_last_child(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.last_child[node];
  return v;
}

/// Next sibling node index (-1 when last sibling or out of range). O(1).
pub fn xml2_next_sibling(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.next_sibling[node];
  return v;
}

/// Number of direct children of a node (all kinds), 0 when out of range.
/// Complexity: O(children).
pub fn xml2_child_count(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return 0;
  }
  var c = 0;
  var ch: Int = d.first_child[node];
  while ch >= 0 {
    c = c + 1;
    let nx: Int = d.next_sibling[ch];
    ch = nx;
  }
  return c;
}

/// Direct child by zero-based index over all child kinds.
/// Params: d - the document; node - the parent; k - the zero-based child
/// position. Returns: the child index, or -1 when k is out of range.
/// Complexity: O(k).
pub fn xml2_child_at(d: &XmlDoc, node: Int, k: Int) -> Int {
  if !_valid_node(d, node) || k < 0 {
    return -1;
  }
  var seen = 0;
  var ch: Int = d.first_child[node];
  while ch >= 0 {
    if seen == k {
      return ch;
    }
    seen = seen + 1;
    let nx: Int = d.next_sibling[ch];
    ch = nx;
  }
  return -1;
}

/// First element child with the given qualified name (exact byte match),
/// or -1. Params: d - the document; node - the parent; name - the exact
/// qualified name. Complexity: O(children * name).
pub fn xml2_child_by_name(d: &XmlDoc, node: Int, name: Str) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  var ch: Int = d.first_child[node];
  while ch >= 0 {
    let k: Int = d.kinds[ch];
    if k == 0 {
      let nm: Str = d.names[ch];
      if _streq(nm, name) {
        return ch;
      }
    }
    let nx: Int = d.next_sibling[ch];
    ch = nx;
  }
  return -1;
}

/// Depth of a node: the number of parent edges up to node 0 (which is 0).
/// Params: d - the document; node - the node index.
/// Returns: the depth, or -1 when node is out of range.
/// Complexity: O(depth).
pub fn xml2_depth(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  var cur = node;
  var depth = 0;
  while cur > 0 {
    let par: Int = d.parents[cur];
    if par < 0 {
      cur = 0;
    } else {
      depth = depth + 1;
      cur = par;
    }
  }
  return depth;
}

/// Concatenation of a node's direct character data (text and CDATA
/// children), in document order.
/// Params: d - the document; node - the node index.
/// Returns: the concatenated text ("" for non-containers, out-of-range
/// indices and nodes without character-data children). Nested element text
/// is NOT included; use xml2_text_deep for that.
/// Complexity: O(children + text bytes).
pub fn xml2_text(d: &XmlDoc, node: Int) -> Str {
  var out = Vec[UInt8].new();
  if _valid_node(d, node) {
    var ch: Int = d.first_child[node];
    while ch >= 0 {
      let k: Int = d.kinds[ch];
      if k == 1 || k == 2 {
        builder.sb_push_str(&mut out, d.texts[ch]);
      }
      let nx: Int = d.next_sibling[ch];
      ch = nx;
    }
  }
  return builder.sb_to_str(&out);
}

// Recursively collect all descendant character data into out.
fn _text_deep_into(d: &XmlDoc, node: Int, out: &mut Vec[UInt8]) {
  var ch: Int = d.first_child[node];
  while ch >= 0 {
    let k: Int = d.kinds[ch];
    if k == 1 || k == 2 {
      builder.sb_push_str(out, d.texts[ch]);
    } elif k == 0 {
      _text_deep_into(d, ch, out);
    }
    let nx: Int = d.next_sibling[ch];
    ch = nx;
  }
}

/// All descendant character data of a node (text and CDATA), in document
/// order, element boundaries removed. Depth is bounded by the parse-time
/// depth cap. Returns "" for bad indices. Complexity: O(subtree).
pub fn xml2_text_deep(d: &XmlDoc, node: Int) -> Str {
  var out = Vec[UInt8].new();
  if _valid_node(d, node) {
    _text_deep_into(d, node, &mut out);
  }
  return builder.sb_to_str(&out);
}

/// A node's scalar string value: text/CDATA content, a comment body, PI
/// data or DOCTYPE external identifier as stored; for an element, the
/// direct character data (xml2_text); "" for bad indices.
/// Complexity: O(node kind work).
pub fn xml2_node_string(d: &XmlDoc, node: Int) -> Str {
  if !_valid_node(d, node) {
    return "";
  }
  let k: Int = d.kinds[node];
  if k == 0 {
    return xml2_text(d, node);
  }
  let v: Str = d.texts[node];
  return v;
}

/// Source byte offset where node i starts (inclusive; -1 when bad).
/// O(1).
pub fn xml2_node_open(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.opens[node];
  return v;
}

/// Source byte offset just past node i (exclusive; -1 when bad). O(1).
pub fn xml2_node_close(d: &XmlDoc, node: Int) -> Int {
  if !_valid_node(d, node) {
    return -1;
  }
  let v: Int = d.closes[node];
  return v;
}

/// Copy of the raw source bytes of a node's span [open, close). The bytes
/// are the original document bytes, before entity decoding; "" (an empty
/// vector) for bad indices or an invalid span. Complexity: O(span).
pub fn xml2_node_raw_bytes(d: &XmlDoc, node: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if !_valid_node(d, node) {
    return out;
  }
  let a: Int = d.opens[node];
  let b: Int = d.closes[node];
  if a < 0 || b < a || b > d.src.len() {
    return out;
  }
  var i = a;
  while i < b {
    out.push(d.src[i]);
    i = i + 1;
  }
  return out;
}

/// All element nodes whose qualified name equals `name` exactly, in
/// document order. Params: d - the document; name - the qualified name.
/// Returns: their node indices (empty when nothing matches); the synthetic
/// document node is never included. Complexity: O(nodes).
pub fn xml2_find(d: &XmlDoc, name: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < d.kinds.len() {
    let k: Int = d.kinds[i];
    if k == 0 {
      let nm: Str = d.names[i];
      if _streq(nm, name) {
        out.push(i);
      }
    }
    i = i + 1;
  }
  return out;
}

/// All element nodes whose local name equals `local` (namespace-agnostic),
/// in document order. Complexity: O(nodes * name).
pub fn xml2_find_local(d: &XmlDoc, local: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < d.kinds.len() {
    let k: Int = d.kinds[i];
    if k == 0 {
      let nm: Str = d.names[i];
      let loc = _qname_local(nm);
      if _streq(loc, local) {
        out.push(i);
      }
    }
    i = i + 1;
  }
  return out;
}

/// First element node with the exact qualified name, or -1.
/// Complexity: O(nodes).
pub fn xml2_find_first(d: &XmlDoc, name: Str) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    let k: Int = d.kinds[i];
    if k == 0 {
      let nm: Str = d.names[i];
      if _streq(nm, name) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Number of attributes owned by a node (0 when out of range).
/// Complexity: O(attributes).
pub fn xml2_attr_count(d: &XmlDoc, node: Int) -> Int {
  var c = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Attribute name at zero-based position `index` among a node's attributes
/// (source order); "" when out of range. Complexity: O(attributes).
pub fn xml2_attr_name_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      if seen == index {
        let v: Str = d.attr_names[i];
        return v;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

/// Attribute value at zero-based position `index` among a node's attributes
/// (source order); "" when out of range. Complexity: O(attributes).
pub fn xml2_attr_value_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      if seen == index {
        let v: Str = d.attr_values[i];
        return v;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

// First attribute with the exact name on a node (decoded value).
fn _attr_lookup(d: &XmlDoc, node: Int, name: Str) -> Result[Str, Str] {
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      let an: Str = d.attr_names[i];
      if _streq(an, name) {
        let av: Str = d.attr_values[i];
        return _ok_str(av);
      }
    }
    i = i + 1;
  }
  return _err_str("xml2: attribute not found");
}

// True when the exact attribute name/value pair occurs on a node.
fn _attr_equals(d: &XmlDoc, node: Int, name: Str, want: Str) -> Bool {
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      let an: Str = d.attr_names[i];
      if _streq(an, name) {
        let av: Str = d.attr_values[i];
        return _streq(av, want);
      }
    }
    i = i + 1;
  }
  return false;
}

/// Attribute value by exact name.
/// Params: d - the document; node - the element; name - the exact qualified
/// attribute name (case-sensitive byte comparison).
/// Returns: Ok(value); Err("xml2: attribute not found") when absent.
/// Duplicate attribute names cannot occur (the parser rejects them).
/// Complexity: O(attributes).
pub fn xml2_attr(d: &XmlDoc, node: Int, name: Str) -> Result[Str, Str] {
  return _attr_lookup(d, node, name);
}

/// Attribute value or a caller-supplied default. O(attributes).
pub fn xml2_attr_or(d: &XmlDoc, node: Int, name: Str, dflt: Str) -> Str {
  let r = _attr_lookup(d, node, name);
  if r.is_ok {
    let v: Str = r.value;
    return v;
  }
  return dflt;
}

/// True when the exact attribute name exists on the node. O(attributes).
pub fn xml2_has_attr(d: &XmlDoc, node: Int, name: Str) -> Bool {
  let r = _attr_lookup(d, node, name);
  return r.is_ok;
}

// --------------------------------------------------
//  Namespaces
// --------------------------------------------------

// True when an attribute name is a namespace declaration (xmlns or
// xmlns:prefix).
fn _is_ns_decl_name(an: Str) -> Bool {
  if _streq(an, "xmlns") {
    return true;
  }
  return _starts_with(an, "xmlns:");
}

// Scoped prefix lookup: walk the node and its ancestors looking for
// xmlns:prefix (or xmlns for the empty prefix). The empty prefix resolves
// to the default namespace (Ok("") when none is in scope); every other
// prefix is Err when unbound.
fn _ns_lookup(d: &XmlDoc, node: Int, prefix: Str) -> Result[Str, Str] {
  if _streq(prefix, "xml") {
    return _ok_str(XML2_NS_XML);
  }
  if _streq(prefix, "xmlns") {
    return _err_str("xml2: reserved namespace prefix");
  }
  var cur = node;
  while cur >= 0 && cur < d.kinds.len() {
    var i = 0;
    while i < d.attr_owners.len() {
      let o: Int = d.attr_owners[i];
      if o == cur {
        let an: Str = d.attr_names[i];
        if _streq(prefix, "") {
          if _streq(an, "xmlns") {
            let av: Str = d.attr_values[i];
            return _ok_str(av);
          }
        } else {
          let want = "xmlns:" + prefix;
          if _streq(an, want) {
            let av: Str = d.attr_values[i];
            return _ok_str(av);
          }
        }
      }
      i = i + 1;
    }
    let par: Int = d.parents[cur];
    cur = par;
  }
  if _streq(prefix, "") {
    return _ok_str("");
  }
  return _err_str("xml2: unbound namespace prefix");
}

/// Resolve a namespace prefix in the scope of a node.
/// Params: d - the document; node - an element node; prefix - the prefix
/// ("" selects the default namespace).
/// Returns: Ok(uri). The reserved `xml` prefix is always bound to
/// XML2_NS_XML; the empty prefix resolves to the nearest xmlns declaration
/// or to "" when none is in scope; other prefixes resolve through the
/// nearest xmlns:prefix declaration on the node or an ancestor.
/// Error case: Err("xml2: namespace lookup on non-element") for a bad node;
/// Err("xml2: reserved namespace prefix") for `xmlns`;
/// Err("xml2: unbound namespace prefix") when the prefix has no
/// declaration in scope.
/// Complexity: O(depth * attributes).
pub fn xml2_ns_resolve(d: &XmlDoc, node: Int, prefix: Str) -> Result[Str, Str] {
  if !_valid_node(d, node) {
    return _err_str("xml2: namespace lookup on non-element");
  }
  let k: Int = d.kinds[node];
  let nm: Str = d.names[node];
  if k != 0 || nm.len() == 0 {
    return _err_str("xml2: namespace lookup on non-element");
  }
  return _ns_lookup(d, node, prefix);
}

/// Namespace URI of an element (its prefix resolved in its own scope; an
/// unprefixed element resolves the default namespace).
/// Error case: as xml2_ns_resolve (unbound prefixed element names).
/// Complexity: O(depth * attributes).
pub fn xml2_ns_element_uri(d: &XmlDoc, node: Int) -> Result[Str, Str] {
  if !_valid_node(d, node) {
    return _err_str("xml2: namespace lookup on non-element");
  }
  let k: Int = d.kinds[node];
  let nm: Str = d.names[node];
  if k != 0 || nm.len() == 0 {
    return _err_str("xml2: namespace lookup on non-element");
  }
  let pfx = _qname_prefix(nm);
  return _ns_lookup(d, node, pfx);
}

/// Namespace URI of an attribute on an element. Per Namespaces in XML an
/// unprefixed attribute is in no namespace (Ok("")), regardless of any
/// default namespace declaration; a prefixed attribute resolves in the
/// element's scope.
/// Error case: Err("xml2: attribute not found") when no attribute has the
/// exact name; otherwise as xml2_ns_resolve.
/// Complexity: O(attributes + depth * attributes).
pub fn xml2_ns_attr_uri(d: &XmlDoc, node: Int, name: Str) -> Result[Str, Str] {
  if !_valid_node(d, node) {
    return _err_str("xml2: namespace lookup on non-element");
  }
  let r = _attr_lookup(d, node, name);
  if !r.is_ok {
    return _err_str("xml2: attribute not found");
  }
  let pfx = _qname_prefix(name);
  if pfx.len() == 0 {
    return _ok_str("");
  }
  return _ns_lookup(d, node, pfx);
}

/// Number of namespace declarations on a node itself (xmlns or
/// xmlns:prefix attributes; the scope is walked by the resolution
/// functions). O(attributes).
pub fn xml2_ns_decl_count(d: &XmlDoc, node: Int) -> Int {
  var c = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      let an: Str = d.attr_names[i];
      if _is_ns_decl_name(an) {
        c = c + 1;
      }
    }
    i = i + 1;
  }
  return c;
}

/// Prefix of the index-th namespace declaration on a node, in source
/// order; "" for the default `xmlns` (and for out-of-range indices).
/// O(attributes).
pub fn xml2_ns_decl_prefix_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      let an: Str = d.attr_names[i];
      if _is_ns_decl_name(an) {
        if seen == index {
          if _streq(an, "xmlns") {
            return "";
          }
          return string.str_slice(an, 6, an.len());
        }
        seen = seen + 1;
      }
    }
    i = i + 1;
  }
  return "";
}

/// URI bound by the index-th namespace declaration on a node, in source
/// order; "" when out of range. O(attributes).
pub fn xml2_ns_decl_uri_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      let an: Str = d.attr_names[i];
      if _is_ns_decl_name(an) {
        if seen == index {
          let av: Str = d.attr_values[i];
          return av;
        }
        seen = seen + 1;
      }
    }
    i = i + 1;
  }
  return "";
}

// --------------------------------------------------
//  Serializer
// --------------------------------------------------

// Append s with text escaping: & -> &amp;, < -> &lt;, > -> &gt;.
fn _escape_text_into(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = _sbyte(s, i);
    if b == _B_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _B_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _B_GT {
      builder.sb_push_str(out, "&gt;");
    } else {
      builder.sb_push_byte(out, string.byte_at(s, i));
    }
    i = i + 1;
  }
}

// Append s with attribute-value escaping: & -> &amp;, < -> &lt;,
// " -> &quot;.
fn _escape_attr_into(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = _sbyte(s, i);
    if b == _B_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _B_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _B_DQ {
      builder.sb_push_str(out, "&quot;");
    } else {
      builder.sb_push_byte(out, string.byte_at(s, i));
    }
    i = i + 1;
  }
}

/// Escape a text run for serialization: & < > become &amp; &lt; &gt;;
/// every other byte (including UTF-8 sequences and quotes) passes through.
/// O(s.len()).
pub fn xml2_escape_text(s: Str) -> Str {
  var out = Vec[UInt8].new();
  _escape_text_into(&mut out, s);
  return builder.sb_to_str(&out);
}

/// Escape an attribute value for double-quoted serialization: & < " become
/// &amp; &lt; &quot;; every other byte passes through. O(s.len()).
pub fn xml2_escape_attr(s: Str) -> Str {
  var out = Vec[UInt8].new();
  _escape_attr_into(&mut out, s);
  return builder.sb_to_str(&out);
}

// Append a CDATA section; any occurrence of "]]>" is split as
// "]]]]><![CDATA[>".
fn _ser_cdata_into(out: &mut Vec[UInt8], s: Str) {
  builder.sb_push_str(out, "<![CDATA[");
  var i = 0;
  while i < s.len() {
    if i + 2 < s.len() {
      if _sbyte(s, i) == _B_RBR && _sbyte(s, i + 1) == _B_RBR && _sbyte(s, i + 2) == _B_GT {
        builder.sb_push_str(out, "]]]]><![CDATA[>");
        i = i + 3;
      } else {
        builder.sb_push_byte(out, string.byte_at(s, i));
        i = i + 1;
      }
    } else {
      builder.sb_push_byte(out, string.byte_at(s, i));
      i = i + 1;
    }
  }
  builder.sb_push_str(out, "]]>");
}

// Indices of a node's attributes sorted by ascending name byte order
// (str_compare); canonical attribute order.
fn _sorted_attr_indices(d: &XmlDoc, node: Int) -> Vec[Int] {
  var idx = Vec[Int].new();
  var i = 0;
  while i < d.attr_owners.len() {
    let o: Int = d.attr_owners[i];
    if o == node {
      idx.push(i);
    }
    i = i + 1;
  }
  var a = 1;
  while a < idx.len() {
    let key: Int = idx[a];
    var b = a - 1;
    var placed = false;
    while b >= 0 && !placed {
      let cur: Int = idx[b];
      let cn: Str = d.attr_names[cur];
      let kn: Str = d.attr_names[key];
      if compare.str_compare(cn, kn) > 0 {
        idx[b + 1] = cur;
        b = b - 1;
      } else {
        placed = true;
      }
    }
    idx[b + 1] = key;
    a = a + 1;
  }
  return idx;
}

// Serialize one node (recursive over the child chain; bounded by the
// parse-time depth cap).
fn _ser_node(d: &XmlDoc, node: Int, out: &mut Vec[UInt8]) {
  let k: Int = d.kinds[node];
  if k == 1 {
    _escape_text_into(out, d.texts[node]);
    return;
  }
  if k == 2 {
    _ser_cdata_into(out, d.texts[node]);
    return;
  }
  if k == 3 {
    builder.sb_push_str(out, "<!--");
    builder.sb_push_str(out, d.texts[node]);
    builder.sb_push_str(out, "-->");
    return;
  }
  if k == 4 {
    let target: Str = d.names[node];
    let data: Str = d.texts[node];
    builder.sb_push_str(out, "<?");
    builder.sb_push_str(out, target);
    if data.len() > 0 {
      builder.sb_push_str(out, " ");
      builder.sb_push_str(out, data);
    }
    builder.sb_push_str(out, "?>");
    return;
  }
  if k == 5 {
    let dn: Str = d.names[node];
    let ext: Str = d.texts[node];
    builder.sb_push_str(out, "<!DOCTYPE ");
    builder.sb_push_str(out, dn);
    if ext.len() > 0 {
      builder.sb_push_str(out, " ");
      builder.sb_push_str(out, ext);
    }
    builder.sb_push_str(out, ">");
    return;
  }
  let nm: Str = d.names[node];
  builder.sb_push_str(out, "<");
  builder.sb_push_str(out, nm);
  let order = _sorted_attr_indices(d, node);
  var ai = 0;
  while ai < order.len() {
    let idx: Int = order[ai];
    let an: Str = d.attr_names[idx];
    let av: Str = d.attr_values[idx];
    builder.sb_push_str(out, " ");
    builder.sb_push_str(out, an);
    builder.sb_push_str(out, "=\"");
    _escape_attr_into(out, av);
    builder.sb_push_str(out, "\"");
    ai = ai + 1;
  }
  let fc: Int = d.first_child[node];
  if fc < 0 {
    builder.sb_push_str(out, "/>");
    return;
  }
  builder.sb_push_str(out, ">");
  var ch = fc;
  while ch >= 0 {
    _ser_node(d, ch, out);
    let nx: Int = d.next_sibling[ch];
    ch = nx;
  }
  builder.sb_push_str(out, "</");
  builder.sb_push_str(out, nm);
  builder.sb_push_str(out, ">");
}

/// Serialize one node (and its subtree for elements). Node 0 serializes
/// the whole document (its child chain). Bad indices serialize to "".
/// Escaping, quoting, canonical attribute order and the empty-element form
/// are documented in SPEC.md section 6.
/// Complexity: O(subtree bytes).
pub fn xml2_serialize_node(d: &XmlDoc, node: Int) -> Str {
  var out = Vec[UInt8].new();
  if node == 0 {
    if d.kinds.len() > 0 {
      var ch: Int = d.first_child[0];
      while ch >= 0 {
        _ser_node(d, ch, &mut out);
        let nx: Int = d.next_sibling[ch];
        ch = nx;
      }
    }
  } elif node > 0 && node < d.kinds.len() {
    _ser_node(d, node, &mut out);
  }
  return builder.sb_to_str(&out);
}

/// Serialize the whole document (the child chain of node 0, in document
/// order: DOCTYPE, comments, PIs, the root element). Document-level
/// whitespace-only text is not preserved (it is not a node); whitespace
/// inside elements is. Complexity: O(document bytes).
pub fn xml2_serialize(d: &XmlDoc) -> Str {
  return xml2_serialize_node(d, 0);
}

// --------------------------------------------------
//  XPath-LITE: expression splitting and predicates
// --------------------------------------------------

// Trim XML whitespace from both ends of s.
fn _trim(s: Str) -> Str {
  var a = 0;
  var b = s.len();
  while a < b {
    if !_is_ws(_sbyte(s, a)) {
      break;
    }
    a = a + 1;
  }
  while b > a {
    if !_is_ws(_sbyte(s, b - 1)) {
      break;
    }
    b = b - 1;
  }
  return string.str_slice(s, a, b);
}

// Split an XPath-LITE expression on top-level '/' (slashes inside predicate
// brackets or quotes do not split). A leading '/' marks an absolute path;
// "//" (descendant axis) is rejected. Returns the step strings without the
// leading slash.
fn _xpath_steps(expr: Str) -> Result[Vec[Str], Str] {
  var parts = Vec[Str].new();
  let n = expr.len();
  if n == 0 {
    return _err_strs("xml2: xpath: empty expression");
  }
  var i = 0;
  if _sbyte(expr, 0) == _B_SLASH {
    i = 1;
    if i < n {
      if _sbyte(expr, i) == _B_SLASH {
        return _err_strs("xml2: xpath: descendant axis '//' is not supported");
      }
    }
  }
  if i >= n {
    return _err_strs("xml2: xpath: empty expression");
  }
  while i < n {
    let start = i;
    var depth = 0;
    var quote = 0;
    var stop = -1;
    while i < n {
      let b = _sbyte(expr, i);
      if quote != 0 {
        if b == quote {
          quote = 0;
        }
      } elif b == _B_SQ || b == _B_DQ {
        quote = b;
      } elif b == _B_LBR {
        if depth > 0 {
          return _err_strs("xml2: xpath: nested predicates are not supported");
        }
        depth = 1;
      } elif b == _B_RBR {
        if depth == 0 {
          return _err_strs("xml2: xpath: unexpected ']'");
        }
        depth = 0;
      } elif b == _B_SLASH && depth == 0 {
        stop = i;
        break;
      }
      i = i + 1;
    }
    if quote != 0 {
      return _err_strs("xml2: xpath: unterminated quote");
    }
    if depth != 0 {
      return _err_strs("xml2: xpath: unterminated predicate");
    }
    if stop < 0 {
      stop = n;
    }
    if stop == start {
      return _err_strs("xml2: xpath: empty step");
    }
    parts.push(string.str_slice(expr, start, stop));
    if stop == n {
      i = n;
    } else {
      i = stop + 1;
      if i >= n {
        return _err_strs("xml2: xpath: trailing '/'");
      }
    }
  }
  return _ok_strs(parts);
}

// Node test of a step: the text before the first '[' (predicates stripped).
fn _xpath_step_test(step: Str) -> Str {
  var i = 0;
  while i < step.len() {
    if _sbyte(step, i) == _B_LBR {
      return string.str_slice(step, 0, i);
    }
    i = i + 1;
  }
  return step;
}

// Raw predicate contents of a step, in order (brackets stripped; quotes may
// contain ']').
fn _xpath_preds(step: Str) -> Vec[Str] {
  var preds = Vec[Str].new();
  var i = 0;
  var start = -1;
  var quote = 0;
  while i < step.len() {
    let b = _sbyte(step, i);
    if quote != 0 {
      if b == quote {
        quote = 0;
      }
    } elif b == _B_SQ || b == _B_DQ {
      quote = b;
    } elif b == _B_LBR {
      start = i + 1;
    } elif b == _B_RBR {
      if start >= 0 {
        preds.push(string.str_slice(step, start, i));
        start = -1;
      }
    }
    i = i + 1;
  }
  return preds;
}

// Index of the '=' of an attribute predicate body (outside quotes), -1 when
// absent.
fn _pred_eq_index(t: Str) -> Int {
  var quote = 0;
  var i = 1;
  var eq = -1;
  var found = false;
  while i < t.len() && !found {
    let b = _sbyte(t, i);
    if quote != 0 {
      if b == quote {
        quote = 0;
      }
    } elif b == _B_SQ || b == _B_DQ {
      quote = b;
    } elif b == _B_EQ {
      eq = i;
      found = true;
    }
    i = i + 1;
  }
  return eq;
}

// Predicate classification: 0 malformed, 1 positional [n], 2 attribute
// [@name='value'].
fn _pred_kind(pred: Str) -> Int {
  let t = _trim(pred);
  if t.len() == 0 {
    return 0;
  }
  if _sbyte(t, 0) == _B_AT {
    if t.len() < 2 {
      return 0;
    }
    let eq = _pred_eq_index(t);
    if eq < 0 {
      return 0;
    }
    let name = _trim(string.str_slice(t, 1, eq));
    if !_valid_name(name) {
      return 0;
    }
    let rest = _trim(string.str_slice(t, eq + 1, t.len()));
    if rest.len() < 2 {
      return 0;
    }
    let q = _sbyte(rest, 0);
    if q != _B_SQ && q != _B_DQ {
      return 0;
    }
    if _sbyte(rest, rest.len() - 1) != q {
      return 0;
    }
    return 2;
  }
  var i = 0;
  while i < t.len() {
    let b = _sbyte(t, i);
    if b < 48 || b > 57 {
      return 0;
    }
    i = i + 1;
  }
  return 1;
}

// Position of a positional predicate (capped; callers check the range).
fn _pred_pos(pred: Str) -> Int {
  let t = _trim(pred);
  var v = 0;
  var i = 0;
  while i < t.len() {
    v = v * 10 + (_sbyte(t, i) - 48);
    if v > 1000000 {
      v = 1000001;
    }
    i = i + 1;
  }
  return v;
}

// Attribute name of an attribute predicate (valid only when _pred_kind == 2).
fn _pred_name(pred: Str) -> Str {
  let t = _trim(pred);
  let eq = _pred_eq_index(t);
  if eq < 0 {
    return "";
  }
  return _trim(string.str_slice(t, 1, eq));
}

// Attribute value of an attribute predicate (quotes stripped).
fn _pred_value(pred: Str) -> Str {
  let t = _trim(pred);
  let eq = _pred_eq_index(t);
  if eq < 0 {
    return "";
  }
  let rest = _trim(string.str_slice(t, eq + 1, t.len()));
  if rest.len() < 2 {
    return "";
  }
  return string.str_slice(rest, 1, rest.len() - 1);
}

// Apply predicates to a candidate list per context node (positional
// predicates are 1-based and re-index the list after each filter).
fn _xpath_filter_preds(d: &XmlDoc, list: Vec[Int], preds: &Vec[Str]) -> Vec[Int] {
  var cur = list;
  var p = 0;
  while p < preds.len() {
    let pred: Str = preds[p];
    let pk = _pred_kind(pred);
    var next = Vec[Int].new();
    if pk == 1 {
      let pos = _pred_pos(pred);
      if pos >= 1 && pos <= cur.len() {
        let pick: Int = cur[pos - 1];
        next.push(pick);
      }
    } else {
      let an = _pred_name(pred);
      let av = _pred_value(pred);
      var i = 0;
      while i < cur.len() {
        let e: Int = cur[i];
        if _attr_equals(d, e, an, av) {
          next.push(e);
        }
        i = i + 1;
      }
    }
    cur = next;
    p = p + 1;
  }
  return cur;
}

// Namespace-aware name test: an unprefixed test matches the candidate's
// local name; a prefixed test resolves the prefix in the context node's
// scope and in the candidate's scope and compares URIs and local names.
// When the context node cannot resolve the prefix (for example the
// synthetic document node at the start of an absolute path), the
// candidate's own scope is used.
fn _xpath_name_match(d: &XmlDoc, ctx: Int, test: Str, cand: Int) -> Bool {
  let tp = _qname_prefix(test);
  let tl = _qname_local(test);
  let cn: Str = d.names[cand];
  let cl = _qname_local(cn);
  if !_streq(cl, tl) {
    return false;
  }
  if tp.len() == 0 {
    return true;
  }
  let cp = _qname_prefix(cn);
  let cc = _ns_lookup(d, cand, cp);
  if !cc.is_ok {
    return false;
  }
  let cu: Str = cc.value;
  let tc = _ns_lookup(d, ctx, tp);
  if tc.is_ok {
    let tu: Str = tc.value;
    return _streq(tu, cu);
  }
  let tb = _ns_lookup(d, cand, tp);
  if !tb.is_ok {
    return false;
  }
  let tbu: Str = tb.value;
  return _streq(tbu, cu);
}

// Child-name step: element children matching the test, predicates applied
// per context node.
fn _xpath_child_step(d: &XmlDoc, ctxs: &Vec[Int], test: Str, preds: &Vec[Str]) -> Vec[Int] {
  var out = Vec[Int].new();
  var ci = 0;
  while ci < ctxs.len() {
    let cn: Int = ctxs[ci];
    var cand = Vec[Int].new();
    var ch: Int = d.first_child[cn];
    while ch >= 0 {
      let k: Int = d.kinds[ch];
      if k == 0 {
        if _xpath_name_match(d, cn, test, ch) {
          cand.push(ch);
        }
      }
      let nx: Int = d.next_sibling[ch];
      ch = nx;
    }
    if preds.len() > 0 {
      cand = _xpath_filter_preds(d, cand, preds);
    }
    var xi = 0;
    while xi < cand.len() {
      let cv: Int = cand[xi];
      out.push(cv);
      xi = xi + 1;
    }
    ci = ci + 1;
  }
  return out;
}

// text() step: text and CDATA children, predicates applied per context node.
fn _xpath_text_step(d: &XmlDoc, ctxs: &Vec[Int], preds: &Vec[Str]) -> Vec[Int] {
  var out = Vec[Int].new();
  var ci = 0;
  while ci < ctxs.len() {
    let cn: Int = ctxs[ci];
    var cand = Vec[Int].new();
    var ch: Int = d.first_child[cn];
    while ch >= 0 {
      let k: Int = d.kinds[ch];
      if k == 1 || k == 2 {
        cand.push(ch);
      }
      let nx: Int = d.next_sibling[ch];
      ch = nx;
    }
    if preds.len() > 0 {
      cand = _xpath_filter_preds(d, cand, preds);
    }
    var xi = 0;
    while xi < cand.len() {
      let cv: Int = cand[xi];
      out.push(cv);
      xi = xi + 1;
    }
    ci = ci + 1;
  }
  return out;
}

/// Evaluate an XPath-LITE expression (SPEC.md section 7).
/// Params: d - the document; ctx - the context node for a relative
/// expression (an element or node 0; ignored for absolute expressions);
/// expr - the expression.
/// Returns: Ok(result). kind is XML2_XPATH_KIND_NODES with the matched
/// element/text/CDATA node indices in document order, or
/// XML2_XPATH_KIND_ATTRS with matched attribute values (nodes holds the
/// owner elements in lockstep).
/// Error case: Err("xml2: xpath: ...") for empty expressions, "//",
/// malformed steps/tests/predicates, unsupported functions, a bad context
/// node and attribute-step placement violations; see SPEC.md section 9.
/// Complexity: O(steps * subtree).
pub fn xml2_xpath_eval(d: &XmlDoc, ctx: Int, expr: Str) -> Result[XPathResult, Str] {
  if expr.len() == 0 {
    return _err_xr("xml2: xpath: empty expression");
  }
  let sr = _xpath_steps(expr);
  if !sr.is_ok {
    return _err_xr(sr.error);
  }
  let steps: Vec[Str] = sr.value;
  var ctxs = Vec[Int].new();
  if _sbyte(expr, 0) == _B_SLASH {
    if xml2_root(d) < 0 {
      return _err_xr("xml2: xpath: no document root");
    }
    ctxs.push(0);
  } else {
    if ctx < 0 || ctx >= d.kinds.len() {
      return _err_xr("xml2: xpath: context node out of range");
    }
    let ck: Int = d.kinds[ctx];
    if ck != 0 {
      return _err_xr("xml2: xpath: context node is not an element");
    }
    ctxs.push(ctx);
  }
  var s = 0;
  while s < steps.len() {
    let step: Str = steps[s];
    let is_last = s + 1 == steps.len();
    let t = _xpath_step_test(step);
    if t.len() > 0 && _sbyte(t, 0) == _B_AT {
      if !is_last {
        return _err_xr("xml2: xpath: attribute step must be last");
      }
      if t.len() < 2 {
        return _err_xr("xml2: xpath: malformed attribute step");
      }
      let an = string.str_slice(t, 1, t.len());
      if !_valid_name(an) {
        return _err_xr("xml2: xpath: malformed attribute step");
      }
      let ap = _xpath_preds(step);
      if ap.len() > 0 {
        return _err_xr("xml2: xpath: predicates on attribute steps are not supported");
      }
      var owners = Vec[Int].new();
      var vals = Vec[Str].new();
      var ci = 0;
      while ci < ctxs.len() {
        let cn: Int = ctxs[ci];
        let av = _attr_lookup(d, cn, an);
        if av.is_ok {
          let avs: Str = av.value;
          owners.push(cn);
          vals.push(avs);
        }
        ci = ci + 1;
      }
      return _ok_xr(XPathResult{
        kind: XML2_XPATH_KIND_ATTRS;
        count: vals.len();
        nodes: owners;
        values: vals;
      });
    }
    let preds = _xpath_preds(step);
    var pj = 0;
    while pj < preds.len() {
      let pv: Str = preds[pj];
      if _pred_kind(pv) == 0 {
        return _err_xr("xml2: xpath: malformed predicate");
      }
      pj = pj + 1;
    }
    if _streq(t, "text()") {
      let got = _xpath_text_step(d, &ctxs, &preds);
      ctxs = got;
    } else {
      if _contains_byte(t, _B_LP) {
        return _err_xr("xml2: xpath: unsupported function");
      }
      if !_valid_test_name(t) {
        return _err_xr("xml2: xpath: malformed node test");
      }
      let got = _xpath_child_step(d, &ctxs, t, &preds);
      ctxs = got;
    }
    s = s + 1;
  }
  return _ok_xr(XPathResult{
    kind: XML2_XPATH_KIND_NODES;
    count: ctxs.len();
    nodes: ctxs;
    values: Vec[Str].new();
  });
}

/// Convenience wrapper: matched node indices only; an attribute result or
/// any error yields an empty vector.
/// Complexity: as xml2_xpath_eval.
pub fn xml2_xpath_nodes(d: &XmlDoc, ctx: Int, expr: Str) -> Vec[Int] {
  let r = xml2_xpath_eval(d, ctx, expr);
  if r.is_ok {
    let xr = r.value;
    let k: Int = xr.kind;
    if k == XML2_XPATH_KIND_NODES {
      let v: Vec[Int] = xr.nodes;
      return v;
    }
  }
  return Vec[Int].new();
}

/// Convenience wrapper: first matched node index, or -1 (also for attribute
/// results and errors). Complexity: as xml2_xpath_eval.
pub fn xml2_xpath_first(d: &XmlDoc, ctx: Int, expr: Str) -> Int {
  let v = xml2_xpath_nodes(d, ctx, expr);
  if v.len() == 0 {
    return -1;
  }
  let first: Int = v[0];
  return first;
}

/// Convenience wrapper: number of matches (nodes or attribute values), 0 on
/// error. Complexity: as xml2_xpath_eval.
pub fn xml2_xpath_count(d: &XmlDoc, ctx: Int, expr: Str) -> Int {
  let r = xml2_xpath_eval(d, ctx, expr);
  if r.is_ok {
    let xr = r.value;
    let c: Int = xr.count;
    return c;
  }
  return 0;
}

/// Convenience wrapper: string value of the first match. For an attribute
/// result that is the attribute value; for a node result it is
/// xml2_node_string of the first node (element direct text, text/CDATA
/// content); "" when there is no match or on error.
/// Complexity: as xml2_xpath_eval.
pub fn xml2_xpath_string(d: &XmlDoc, ctx: Int, expr: Str) -> Str {
  let r = xml2_xpath_eval(d, ctx, expr);
  if r.is_ok {
    let xr = r.value;
    let c: Int = xr.count;
    if c > 0 {
      let k: Int = xr.kind;
      if k == XML2_XPATH_KIND_ATTRS {
        let v: Vec[Str] = xr.values;
        let s: Str = v[0];
        return s;
      }
      let nv: Vec[Int] = xr.nodes;
      let n0: Int = nv[0];
      return xml2_node_string(d, n0);
    }
  }
  return "";
}

/// Module version string. O(1).
pub fn xml2_version() -> Str {
  return "0.1.0";
}
