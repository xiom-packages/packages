// XIOM -- xiom.vdf: Valve KeyValues (VDF) text codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM codec for the Valve KeyValues text format (the ".vdf" files
// shipped with Source-engine games and tools): nested `"key" "value"` pairs
// and `"key" { ... }` blocks, `//` line comments, and quoted strings with the
// four common escapes `\n` `\t` `\"` `\\`. Unquoted tokens are accepted only
// where a value is expected; keys must be quoted.
//
// Model: one parsed document is five parallel vectors -- a flat, child-
// contiguous node array. `keys`, `values`, `kinds`, `child_firsts` and
// `child_counts` are index-aligned: node i has key keys[i], scalar text
// values[i], kind kinds[i] (0 = value, 1 = block) and owns the direct-child
// range [child_firsts[i], child_firsts[i] + child_counts[i]) over the same
// flat arrays. Node 0 is a virtual root block with the empty key; it is never
// emitted, so every document has exactly one owner for every node.
// Vec[StructType] is unsupported in this compiler, so the document is
// deliberately flat (parallel homogeneous vectors) instead of a node tree.
//
// Node order: storage is breadth-first, so a block's direct children are
// contiguous. The parser builds a temporary linked structure (first/last/next
// child) and the flattening pass reorders it; both passes are linear.
//
// Case and duplicates: lookup is ASCII case-insensitive (keys are stored
// byte-exact, duplicates and case variants are all preserved); when the same
// key occurs several times among the children of one block, the last
// occurrence wins for every `vdf_get_*` lookup. Emitting preserves every
// occurrence, in document order.
//
// Grammar and error catalog: see SPEC.md.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Vdf, Str] are constructed only in the tiny leaf
//     helpers _ok_vdf/_err_vdf.
//   * Str equality goes through xiom.string.compare (BUG 17: `==` on Str
//     values read from Vec[Str] elements lowers to a pointer comparison);
//     case-insensitive key lookup uses str_compare_ignore_case.
//   * Every Vec element read is bound to a typed local before use.

module xiom.vdf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Node kinds stored in Vdf.kinds.
const _VDF_KIND_VALUE: Int = 0;
const _VDF_KIND_BLOCK: Int = 1;

// Byte constants used by the scanner.
const _VDF_TAB: UInt8 = 9u8;
const _VDF_LF: UInt8 = 10u8;
const _VDF_CR: UInt8 = 13u8;
const _VDF_SPACE: UInt8 = 32u8;
const _VDF_QUOTE: UInt8 = 34u8;
const _VDF_SLASH: UInt8 = 47u8;
const _VDF_BACKSLASH: UInt8 = 92u8;
const _VDF_LBRACE: UInt8 = 123u8;
const _VDF_RBRACE: UInt8 = 125u8;

// Maximum number of simultaneously open blocks accepted by the parser.
const _VDF_MAX_DEPTH: Int = 64;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[Vdf, Str].
fn _ok_vdf(d: Vdf) -> Result[Vdf, Str] {
  return Ok(d);
}

// Err(m) for Result[Vdf, Str].
fn _err_vdf(m: Str) -> Result[Vdf, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed VDF document: five index-aligned parallel vectors. Node 0 is the
/// virtual root block (empty key, never emitted). For node i, `kinds[i]` is 0
/// (value) or 1 (block); a block owns the direct-child range
/// [child_firsts[i], child_firsts[i] + child_counts[i]) over the same arrays;
/// `child_firsts[i]` is -1 when a node has no children. Duplicate keys are all
/// preserved in document order.
pub type Vdf = {
  keys: Vec[Str];
  values: Vec[Str];
  kinds: Vec[Int];
  child_firsts: Vec[Int];
  child_counts: Vec[Int];
}

// --------------------------------------------------
//  Scanning helpers
// --------------------------------------------------

// Skip whitespace and `//` comments starting at `start`; returns the index of
// the first significant byte (or text.len()).
fn _skip_ws(text: Str, start: Int) -> Int {
  let n = text.len();
  var i = start;
  var again = true;
  while again {
    while i < n {
      let b = string.byte_at(text, i);
      if b == _VDF_SPACE || b == _VDF_TAB || b == _VDF_LF || b == _VDF_CR {
        i = i + 1;
      } else {
        break;
      }
    }
    if i + 1 < n && string.byte_at(text, i) == _VDF_SLASH && string.byte_at(text, i + 1) == _VDF_SLASH {
      i = i + 2;
      while i < n && string.byte_at(text, i) != _VDF_LF {
        i = i + 1;
      }
    } else {
      again = false;
    }
  }
  return i;
}

// End of the unquoted token starting at `start`: the first byte that is
// whitespace, `{` or `}`. An unquoted token is never empty because `start`
// itself is a significant byte.
fn _token_end(text: Str, start: Int) -> Int {
  let n = text.len();
  var i = start;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _VDF_SPACE || b == _VDF_TAB || b == _VDF_LF || b == _VDF_CR || b == _VDF_LBRACE || b == _VDF_RBRACE {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Scan the quoted string whose opening quote is at `start`. On success appends
// the decoded bytes to `out` and returns the index just after the closing
// quote. Returns -1 when the string is unterminated (EOF, LF or CR before the
// closing quote) and -2 for an escape other than \n \t \" \\.
fn _scan_quoted(text: Str, start: Int, out: &mut Vec[UInt8]) -> Int {
  let n = text.len();
  var i = start + 1;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _VDF_BACKSLASH {
      if i + 1 >= n {
        return -1;
      }
      let e = string.byte_at(text, i + 1);
      if e == 110 {
        out.push(10u8);
      } elif e == 116 {
        out.push(9u8);
      } elif e == 34 {
        out.push(34u8);
      } elif e == 92 {
        out.push(92u8);
      } else {
        return -2;
      }
      i = i + 2;
    } elif b == _VDF_QUOTE {
      return i + 1;
    } elif b == _VDF_LF || b == _VDF_CR {
      return -1;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return -1;
}

// The two bytes of the first invalid escape sequence at or after `start`
// (which points at the opening quote), used only to build the error message.
fn _bad_escape_text(text: Str, start: Int) -> Str {
  let n = text.len();
  var j = start + 1;
  while j < n {
    let b = string.byte_at(text, j);
    if b == _VDF_BACKSLASH {
      if j + 1 >= n {
        return "";
      }
      let e = string.byte_at(text, j + 1);
      if e == 110 || e == 116 || e == 34 || e == 92 {
        j = j + 2;
      } else {
        return string.str_slice(text, j, j + 2);
      }
    } elif b == _VDF_QUOTE || b == _VDF_LF || b == _VDF_CR {
      return "";
    } else {
      j = j + 1;
    }
  }
  return "";
}

// Append node `idx` to the linked child list of `parent`: O(1) with the
// first/last/next parallel vectors.
fn _link_child(parent: Int, idx: Int, firsts: &mut Vec[Int], lasts: &mut Vec[Int], nexts: &mut Vec[Int]) {
  let head: Int = firsts[parent];
  if head < 0 {
    firsts[parent] = idx;
  } else {
    let tail: Int = lasts[parent];
    nexts[tail] = idx;
  }
  lasts[parent] = idx;
}

// --------------------------------------------------
//  Traversal helpers
// --------------------------------------------------

// One past the last direct child of `block`; -1 when the block is empty.
fn _child_end(d: &Vdf, block: Int) -> Int {
  let first: Int = d.child_firsts[block];
  if first < 0 {
    return -1;
  }
  let count: Int = d.child_counts[block];
  return first + count;
}

// Last direct child of `parent` whose key matches `key` under
// str_compare_ignore_case (ASCII case-insensitive), or -1 when none does.
fn _find_child(d: &Vdf, parent: Int, key: Str) -> Int {
  var found = -1;
  var c: Int = d.child_firsts[parent];
  let end = _child_end(d, parent);
  while c >= 0 && c < end {
    let child_key: Str = d.keys[c];
    if compare.str_compare_ignore_case(child_key, key) == 0 {
      found = c;
    }
    c = c + 1;
  }
  return found;
}

// Resolve a dotted path to a node index. "" and paths of only empty segments
// resolve to the virtual root (0). Every other segment is matched against the
// direct children of the current block, case-insensitively, last occurrence
// wins. Returns -1 when the path does not resolve.
fn _resolve(d: &Vdf, path: Str) -> Int {
  if path.len() == 0 {
    return 0;
  }
  var current = 0;
  var segs = string.str_split(path, ".");
  var s = 0;
  while s < segs.len() {
    let seg: Str = segs[s];
    if seg.len() == 0 {
      return -1;
    }
    current = _find_child(d, current, seg);
    if current < 0 {
      return -1;
    }
    s = s + 1;
  }
  return current;
}

// Keys of every direct child of `block`, in document order (a fresh copy).
fn _collect_keys(d: &Vdf, block: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  var c: Int = d.child_firsts[block];
  let end = _child_end(d, block);
  while c >= 0 && c < end {
    let k: Str = d.keys[c];
    out.push(k);
    c = c + 1;
  }
  return out;
}

// Decimal Int for `s` when it is an optional '-' followed by one or more ASCII
// digits; None otherwise. Overflow is not detected (documented in SPEC.md).
fn _parse_int_opt(s: Str) -> Option[Int] {
  let n = s.len();
  if n == 0 {
    return None;
  }
  var i = 0;
  var neg = false;
  if string.byte_at(s, 0) == 45 {
    neg = true;
    i = 1;
  }
  if i >= n {
    return None;
  }
  var acc = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if !(b >= 48 && b <= 57) {
      return None;
    }
    acc = acc * 10 + (b as Int - 48);
    i = i + 1;
  }
  if neg {
    return Some(0 - acc);
  }
  return Some(acc);
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// Push `depth` TAB bytes.
fn _indent(out: &mut Vec[UInt8], depth: Int) {
  var i = 0;
  while i < depth {
    out.push(_VDF_TAB);
    i = i + 1;
  }
}

// Push `s` as a quoted VDF token, escaping \ " LF TAB with \n \t \" \\.
fn _emit_quoted(out: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  out.push(_VDF_QUOTE);
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _VDF_BACKSLASH {
      out.push(_VDF_BACKSLASH);
      out.push(_VDF_BACKSLASH);
    } elif b == _VDF_QUOTE {
      out.push(_VDF_BACKSLASH);
      out.push(_VDF_QUOTE);
    } elif b == _VDF_LF {
      out.push(_VDF_BACKSLASH);
      out.push(110u8);
    } elif b == _VDF_TAB {
      out.push(_VDF_BACKSLASH);
      out.push(116u8);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  out.push(_VDF_QUOTE);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory Valve KeyValues (VDF) text document.
/// Params: text - the whole document (LF or CRLF line endings; a UTF-8 BOM is
/// not stripped).
/// Returns: Ok(Vdf) for a valid document, including an empty one; Err with a
/// "vdf: ..." message on an unterminated quoted string, an unterminated
/// block, an unexpected '}', a stray unquoted token where a key is expected,
/// a bad escape, a key without a value, an empty key, or nesting deeper than
/// 64 open blocks. Duplicate keys are not an error: all occurrences are
/// preserved and lookup keeps the last one.
/// Complexity: O(total input length); the temporary parse structure and the
/// breadth-first flattening pass are both linear in the node count.
pub fn vdf_parse(text: Str) -> Result[Vdf, Str] {
  var t_keys = Vec[Str].new();
  var t_values = Vec[Str].new();
  var t_kinds = Vec[Int].new();
  var t_first = Vec[Int].new();
  var t_last = Vec[Int].new();
  var t_next = Vec[Int].new();
  // Node 0 is the virtual root block.
  t_keys.push("");
  t_values.push("");
  t_kinds.push(_VDF_KIND_BLOCK);
  t_first.push(-1);
  t_last.push(-1);
  t_next.push(-1);
  var stack = Vec[Int].new();
  stack.push(0);
  let n = text.len();
  var i = 0;
  loop {
    i = _skip_ws(text, i);
    if i >= n {
      break;
    }
    let b = string.byte_at(text, i);
    if b == _VDF_RBRACE {
      if stack.len() <= 1 {
        return _err_vdf("vdf: unexpected '}'");
      }
      stack.pop();
      i = i + 1;
      continue;
    }
    var key = "";
    if b == _VDF_QUOTE {
      var buf = Vec[UInt8].new();
      let st = _scan_quoted(text, i, &mut buf);
      if st == -1 {
        return _err_vdf("vdf: unterminated quoted string");
      }
      if st == -2 {
        return _err_vdf("vdf: bad escape: " + _bad_escape_text(text, i));
      }
      key = builder.sb_to_str(&buf);
      if key.len() == 0 {
        return _err_vdf("vdf: empty key");
      }
      i = st;
    } else {
      var te = _token_end(text, i);
      if te == i {
        te = i + 1;
      }
      return _err_vdf("vdf: stray token: " + string.str_slice(text, i, te));
    }
    i = _skip_ws(text, i);
    if i >= n {
      return _err_vdf("vdf: key without value: " + key);
    }
    let b2 = string.byte_at(text, i);
    if b2 == _VDF_LBRACE {
      if stack.len() - 1 >= _VDF_MAX_DEPTH {
        return _err_vdf("vdf: depth exceeded (max 64)");
      }
      let top: Int = stack[stack.len() - 1];
      t_keys.push(key);
      t_values.push("");
      t_kinds.push(_VDF_KIND_BLOCK);
      t_first.push(-1);
      t_last.push(-1);
      t_next.push(-1);
      let idx = t_keys.len() - 1;
      _link_child(top, idx, &mut t_first, &mut t_last, &mut t_next);
      stack.push(idx);
      i = i + 1;
      continue;
    }
    if b2 == _VDF_RBRACE {
      return _err_vdf("vdf: key without value: " + key);
    }
    var value = "";
    if b2 == _VDF_QUOTE {
      var buf2 = Vec[UInt8].new();
      let st2 = _scan_quoted(text, i, &mut buf2);
      if st2 == -1 {
        return _err_vdf("vdf: unterminated quoted string");
      }
      if st2 == -2 {
        return _err_vdf("vdf: bad escape: " + _bad_escape_text(text, i));
      }
      value = builder.sb_to_str(&buf2);
      i = st2;
    } else {
      let te2 = _token_end(text, i);
      value = string.str_slice(text, i, te2);
      i = te2;
    }
    let top2: Int = stack[stack.len() - 1];
    t_keys.push(key);
    t_values.push(value);
    t_kinds.push(_VDF_KIND_VALUE);
    t_first.push(-1);
    t_last.push(-1);
    t_next.push(-1);
    let idx2 = t_keys.len() - 1;
    _link_child(top2, idx2, &mut t_first, &mut t_last, &mut t_next);
  }
  if stack.len() > 1 {
    return _err_vdf("vdf: unterminated block");
  }
  // Flatten breadth-first so every block owns a contiguous child range. The
  // FIFO queue guarantees that the children of one node are dequeued (and so
  // get final indices) consecutively.
  let t_count = t_keys.len();
  var map = Vec[Int].new();
  var z = 0;
  while z < t_count {
    map.push(-1);
    z = z + 1;
  }
  var queue = Vec[Int].new();
  var keys = Vec[Str].new();
  var values = Vec[Str].new();
  var kinds = Vec[Int].new();
  var firsts = Vec[Int].new();
  var counts = Vec[Int].new();
  queue.push(0);
  var head = 0;
  while head < queue.len() {
    let t: Int = queue[head];
    head = head + 1;
    map[t] = keys.len();
    let k: Str = t_keys[t];
    let v: Str = t_values[t];
    let kd: Int = t_kinds[t];
    keys.push(k);
    values.push(v);
    kinds.push(kd);
    firsts.push(-1);
    counts.push(0);
    var c: Int = t_first[t];
    while c >= 0 {
      queue.push(c);
      let nxt: Int = t_next[c];
      c = nxt;
    }
  }
  var t2 = 0;
  while t2 < t_count {
    let f: Int = map[t2];
    let c2: Int = t_first[t2];
    if c2 >= 0 {
      let cf: Int = map[c2];
      firsts[f] = cf;
      var cnt = 0;
      var c3 = c2;
      while c3 >= 0 {
        cnt = cnt + 1;
        let nxt3: Int = t_next[c3];
        c3 = nxt3;
      }
      counts[f] = cnt;
    }
    t2 = t2 + 1;
  }
  let doc = Vdf{
    keys: keys;
    values: values;
    kinds: kinds;
    child_firsts: firsts;
    child_counts: counts;
  };
  return _ok_vdf(doc);
}

/// Keys of the root block in document order, duplicates kept (a fresh copy).
pub fn vdf_root_keys(d: &Vdf) -> Vec[Str] {
  return _collect_keys(d, 0);
}

/// Keys of the direct children of the block at `path`, in document order,
/// duplicates kept (a fresh copy). `""` addresses the root block. An absent
/// path, a path that lands on a value node, or an empty segment yields an
/// empty vector.
pub fn vdf_child_keys(d: &Vdf, path: Str) -> Vec[Str] {
  let idx = _resolve(d, path);
  if idx < 0 {
    return Vec[Str].new();
  }
  let kind: Int = d.kinds[idx];
  if kind != _VDF_KIND_BLOCK {
    return Vec[Str].new();
  }
  return _collect_keys(d, idx);
}

/// True when `path` resolves to a node (value or block). `""` resolves to the
/// root block, so `vdf_has(d, "")` is always true.
pub fn vdf_has(d: &Vdf, path: Str) -> Bool {
  return _resolve(d, path) >= 0;
}

/// Scalar value at `path`; None when the path is absent or resolves to a
/// block. Path segments match keys ASCII case-insensitively; when a key
/// repeats, the last occurrence wins.
pub fn vdf_get_str(d: &Vdf, path: Str) -> Option[Str] {
  let idx = _resolve(d, path);
  if idx < 0 {
    return None;
  }
  let kind: Int = d.kinds[idx];
  if kind != _VDF_KIND_VALUE {
    return None;
  }
  let v: Str = d.values[idx];
  return Some(v);
}

/// Integer at `path`: an optional leading '-' followed by one or more ASCII
/// digits. None when the path is absent, resolves to a block, or the value is
/// not a decimal integer (leading zeros are accepted, overflow is not
/// detected).
pub fn vdf_get_int(d: &Vdf, path: Str) -> Option[Int] {
  let idx = _resolve(d, path);
  if idx < 0 {
    return None;
  }
  let kind: Int = d.kinds[idx];
  if kind != _VDF_KIND_VALUE {
    return None;
  }
  let v: Str = d.values[idx];
  return _parse_int_opt(v);
}

/// Boolean at `path`: "1" or "true" (ASCII case-insensitive) is true, "0" or
/// "false" is false; None when the path is absent, resolves to a block, or
/// the value is none of those four literals.
pub fn vdf_get_bool(d: &Vdf, path: Str) -> Option[Bool] {
  let idx = _resolve(d, path);
  if idx < 0 {
    return None;
  }
  let kind: Int = d.kinds[idx];
  if kind != _VDF_KIND_VALUE {
    return None;
  }
  let v: Str = d.values[idx];
  if compare.str_eq_ignore_case(v, "1") {
    return Some(true);
  }
  if compare.str_eq_ignore_case(v, "true") {
    return Some(true);
  }
  if compare.str_eq_ignore_case(v, "0") {
    return Some(false);
  }
  if compare.str_eq_ignore_case(v, "false") {
    return Some(false);
  }
  return None;
}

/// Canonical text form of `d`.
/// Params: d - the document to serialize.
/// Returns: one node per line; each nesting level is indented with one TAB;
/// value nodes are `"key" "value"`, block nodes are `"key"` then an indented
/// `{`, their children, and an indented `}`. Every line, including the last,
/// ends with LF; an empty document emits "". Keys and values are quoted and
/// escaped (\ " LF TAB); duplicates are emitted in order. Nodes reachable
/// from the root are emitted exactly once.
/// Error case: none.
/// Complexity: O(total output length); the traversal stack is O(depth).
pub fn vdf_emit(d: &Vdf) -> Str {
  var out = Vec[UInt8].new();
  var open_nodes = Vec[Int].new();
  var open_ends = Vec[Int].new();
  var open_next = Vec[Int].new();
  open_nodes.push(0);
  open_ends.push(_child_end(d, 0));
  let root_first: Int = d.child_firsts[0];
  open_next.push(root_first);
  while open_nodes.len() > 0 {
    let top = open_nodes.len() - 1;
    let next_child: Int = open_next[top];
    let end: Int = open_ends[top];
    if next_child < 0 || next_child >= end {
      open_nodes.pop();
      open_ends.pop();
      open_next.pop();
      let depth = open_nodes.len() - 1;
      if depth >= 0 {
        _indent(&mut out, depth);
        out.push(_VDF_RBRACE);
        out.push(_VDF_LF);
      }
    } else {
      let child = next_child;
      open_next[top] = child + 1;
      let depth = open_nodes.len() - 1;
      _indent(&mut out, depth);
      let key: Str = d.keys[child];
      _emit_quoted(&mut out, key);
      let kind: Int = d.kinds[child];
      if kind == _VDF_KIND_BLOCK {
        out.push(_VDF_LF);
        _indent(&mut out, depth);
        out.push(_VDF_LBRACE);
        out.push(_VDF_LF);
        open_nodes.push(child);
        open_ends.push(_child_end(d, child));
        let child_first: Int = d.child_firsts[child];
        open_next.push(child_first);
      } else {
        out.push(_VDF_SPACE);
        let value: Str = d.values[child];
        _emit_quoted(&mut out, value);
        out.push(_VDF_LF);
      }
    }
  }
  return builder.sb_to_str(&out);
}
