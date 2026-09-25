// XIOM -- xiom.sgf: Smart Game Format (SGF) codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM, in-memory SGF codec. It parses a collection of game trees
// `(;...)(;...)` into flat parallel vectors: nodes in depth-first document
// order with parent links and contiguous child ranges, properties and
// multi-values flattened in document order. Validation is structural only:
// there is no Go, chess or any other game semantics and no coordinate
// interpretation beyond text.
//
// Document subset (see SPEC.md for the exact statement):
//   * collection:  zero or more game trees; whitespace between trees is
//                  ignored (an empty document parses as an empty collection);
//   * game tree:   "(" Sequence GameTree* ")" -- child trees are variations
//                  attached to the last node of the sequence;
//   * sequence:    one or more nodes;
//   * node:        ";" followed by zero or more properties;
//   * property:    an identifier of one or more ASCII letters, normalized to
//                  uppercase (lookup is case-insensitive), immediately
//                  followed by one or more values `[value]`; each identifier
//                  may repeat on a node and multi-values stay in order;
//   * value:       bytes between "[" and the matching unescaped "]"; `\]`
//                  decodes to "]", `\\` to "\", a backslash before any other
//                  byte is dropped and the byte kept, a backslash before a
//                  line break removes the break (soft line break), and an
//                  unescaped LF, CRLF or lone CR becomes a single space
//                  (tabs and all other bytes are kept verbatim);
//   * canonical emit: no whitespace inside a tree; a first child written after
//                  ";" (node_seq == 1) continues the sequence and any later
//                  children are emitted as parenthesized trees, otherwise all
//                  children are emitted as variations; one tree per line, each
//                  terminated by LF.
//
// Explicit non-goals: Go/chess semantics, coordinate interpretation beyond
// text, FF[1] legacy differences, the SimpleText/Text distinction, composed
// value types (point lists, ranges, numbers) and property meaning of any
// kind.
//
// Grammar:
//   collection = *( ws | game-tree )
//   game-tree  = "(" ws* sequence *( ws* game-tree ) ws* ")"
//   sequence   = node+
//   node       = ";" *( ws* property ) ws*
//   property   = prop-ident value+
//   prop-ident = 1*( "A".."Z" | "a".."z" )        ; normalized to uppercase
//   value      = "[" *( escaped | byte except "]" ) "]"
//   escaped    = "\\" byte | "\\" line-break      ; see the value rules above
//   ws         = " " | TAB | LF | CR
//
// Language notes (XIOM v0.61.3): free functions only; no Vec[StructType] --
// the collection is a set of parallel Vec fields; Str equality goes through
// xiom.string.compare.str_compare (BUG 17: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison); every Vec[Str] and
// Vec[Int] read binds a typed local; Str values are materialized from a
// Vec[UInt8] buffer with xiom.string.builder.sb_to_str; Ok/Err for the public
// Result types are constructed only in the leaf helpers _ok_coll/_err_coll
// and _ok_pos/_err_pos.

module xiom.sgf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed SGF collection, flattened into parallel vectors. Nodes are stored
/// in depth-first document order; each node's properties and each property's
/// values are contiguous slices of the property/value arrays.
/// Invariants: all node_* vectors have the same length; node_parent[n] is -1
/// exactly for the node indices listed in `roots`; the children of node n are
/// `children[node_child_start[n] .. +node_child_count[n]]` in document order;
/// the properties of node n are `prop_ids[node_prop_start[n] ..
/// +node_prop_count[n]]`; the values of property p are
/// `val_texts[prop_val_start[p] .. +prop_val_count[p]]`. A child with
/// node_seq == 1 continues its parent's sequence; the other children (and all
/// children of a node whose first child has node_seq == 0) are variations.
pub type SgfCollection = {
  node_parent: Vec[Int];      // parent node index, -1 for a game-tree root
  node_depth: Vec[Int];       // ancestor count: 0 for a root
  node_seq: Vec[Int];         // 1 when the node continues its parent's
                              // sequence (introduced by ";"), 0 when it is a
                              // variation root or a game-tree root
  node_start: Vec[Int];       // byte offset of the node's ';' in the input
  node_child_start: Vec[Int]; // offset into `children` of the first child
  node_child_count: Vec[Int]; // number of direct children
  children: Vec[Int];         // child node indices, grouped by parent
  node_prop_start: Vec[Int];  // offset into `prop_ids` of the first property
  node_prop_count: Vec[Int];  // number of properties on the node
  prop_ids: Vec[Str];         // identifiers, normalized to uppercase
  prop_val_start: Vec[Int];   // offset into `val_texts` of the first value
  prop_val_count: Vec[Int];   // number of values of the property
  val_texts: Vec[Str];        // decoded value text
  val_starts: Vec[Int];       // byte offset of the value's '[' in the input
  roots: Vec[Int];            // node indices of the top-level game trees
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[SgfCollection, Str].
fn _ok_coll(v: SgfCollection) -> Result[SgfCollection, Str] {
  return Ok(v);
}

// Err(m) for Result[SgfCollection, Str].
fn _err_coll(m: Str) -> Result[SgfCollection, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_pos(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_pos(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _SGF_TAB: UInt8 = 9u8;
const _SGF_LF: UInt8 = 10u8;
const _SGF_CR: UInt8 = 13u8;
const _SGF_SPACE: UInt8 = 32u8;
const _SGF_LPAREN: UInt8 = 40u8;
const _SGF_RPAREN: UInt8 = 41u8;
const _SGF_SEMI: UInt8 = 59u8;
const _SGF_LBRACKET: UInt8 = 91u8;
const _SGF_BACKSLASH: UInt8 = 92u8;
const _SGF_RBRACKET: UInt8 = 93u8;

const _PH_TOP: Int = 0; // at collection level, expecting "("
const _PH_INIT: Int = 1; // just after "(", expecting the first ";"
const _PH_SEQ: Int = 2; // inside a sequence with at least one node
const _PH_VAR: Int = 3; // inside a tree after at least one child tree closed

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_ws(b: UInt8) -> Bool {
  if b == _SGF_SPACE { return true; }
  if b == _SGF_TAB { return true; }
  if b == _SGF_LF { return true; }
  return b == _SGF_CR;
}

// ASCII letter byte: A-Z or a-z.
fn _is_alpha(b: UInt8) -> Bool {
  let v: Int = (b as Int) & 0xFF;
  if v >= 65 && v <= 90 {
    return true;
  }
  return v >= 97 && v <= 122;
}

// Uppercase an ASCII letter; other bytes pass through.
fn _to_upper(b: UInt8) -> UInt8 {
  let v: Int = (b as Int) & 0xFF;
  if v >= 97 && v <= 122 {
    return ((v - 32) as UInt8);
  }
  return b;
}

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// "prefix" + decimal position, the fixed shape of every position-carrying
// error message.
fn _at(prefix: Str, pos: Int) -> Str {
  return prefix + int_to_string(pos);
}

// Case-insensitive equality of two identifiers; used by sgf_prop_find so that
// a query may be written in any case. Str params are copied into locals before
// len/byte_at (BUG 17 family).
fn _id_equals(a: Str, b: Str) -> Bool {
  let x: Str = a;
  let y: Str = b;
  let nx = x.len();
  if nx != y.len() {
    return false;
  }
  var i = 0;
  while i < nx {
    let ca: UInt8 = string.byte_at(x, i);
    let cb: UInt8 = string.byte_at(y, i);
    if _to_upper(ca) != _to_upper(cb) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Global property-array index of property `p` of node `n`, or -1 when either
// index is out of range.
fn _prop_index(c: &SgfCollection, n: Int, p: Int) -> Int {
  if n < 0 || n >= c.node_prop_start.len() {
    return -1;
  }
  let cnt: Int = c.node_prop_count[n];
  if p < 0 || p >= cnt {
    return -1;
  }
  let off: Int = c.node_prop_start[n];
  return off + p;
}

// --------------------------------------------------
//  Value scanning
// --------------------------------------------------

// Scan one `[value]` starting at the "[" at `at`, decoding escapes and
// normalizing line breaks into `sb`, and return the position just after the
// closing "]". Rules: `\]` -> "]", `\\` -> "\", a backslash before any other
// byte is dropped and the byte kept, a backslash before LF/CR/CRLF removes
// the break, and an unescaped LF/CR/CRLF becomes one space. A missing closing
// "]" is Err("sgf: unterminated value at <at>").
fn _scan_value(text: Str, at: Int, sb: &mut Vec[UInt8]) -> Result[Int, Str] {
  let n = text.len();
  var i = at + 1;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _SGF_RBRACKET {
      return _ok_pos(i + 1);
    }
    if b == _SGF_BACKSLASH {
      if i + 1 >= n {
        return _err_pos(_at("sgf: unterminated value at ", at));
      }
      let e = string.byte_at(text, i + 1);
      if e == _SGF_LF {
        i = i + 2;
      } elif e == _SGF_CR {
        i = i + 2;
        if i < n && string.byte_at(text, i) == _SGF_LF {
          i = i + 1;
        }
      } else {
        sb.push(e);
        i = i + 2;
      }
    } elif b == _SGF_LF {
      sb.push(_SGF_SPACE);
      i = i + 1;
    } elif b == _SGF_CR {
      sb.push(_SGF_SPACE);
      i = i + 1;
      if i < n && string.byte_at(text, i) == _SGF_LF {
        i = i + 1;
      }
    } else {
      sb.push(b);
      i = i + 1;
    }
  }
  return _err_pos(_at("sgf: unterminated value at ", at));
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory SGF collection.
/// Params: text - the whole document (one or more game trees; LF, CRLF or
/// lone CR line endings; whitespace is ignored between trees, nodes,
/// properties and around parentheses, but not between a property identifier
/// and its first value nor between consecutive values).
/// Returns: Ok(SgfCollection) with the flattened node/property/value model,
/// or Err with a fixed "sgf: ..." message from the SPEC.md catalog. Property
/// identifiers are normalized to uppercase; `\]`/`\\` are decoded and line
/// breaks inside values become single spaces; nested variations are preserved
/// as parent/child links. An empty or whitespace-only document parses as an
/// empty collection.
/// Error case: see SPEC.md section 6 -- unterminated value, missing ; after (,
/// stray ), empty property id, bad property id char, unmatched ( and trailing
/// garbage, each carrying a byte offset.
/// Complexity: O(input length).
pub fn sgf_parse(text: Str) -> Result[SgfCollection, Str] {
  var coll = SgfCollection{
    node_parent: Vec[Int].new();
    node_depth: Vec[Int].new();
    node_seq: Vec[Int].new();
    node_start: Vec[Int].new();
    node_child_start: Vec[Int].new();
    node_child_count: Vec[Int].new();
    children: Vec[Int].new();
    node_prop_start: Vec[Int].new();
    node_prop_count: Vec[Int].new();
    prop_ids: Vec[Str].new();
    prop_val_start: Vec[Int].new();
    prop_val_count: Vec[Int].new();
    val_texts: Vec[Str].new();
    val_starts: Vec[Int].new();
    roots: Vec[Int].new();
  };
  var first_child = Vec[Int].new();
  var next_sibling = Vec[Int].new();
  var last_child = Vec[Int].new();
  var fr_open = Vec[Int].new();
  var fr_parent = Vec[Int].new();
  var fr_last = Vec[Int].new();
  let n = text.len();
  var i = 0;
  var phase = _PH_TOP;
  while i < n {
    let b = string.byte_at(text, i);
    if _is_ws(b) {
      i = i + 1;
    } elif _is_alpha(b) {
      if phase == _PH_SEQ {
        // One property: identifier then one or more adjacent values.
        var idb = Vec[UInt8].new();
        var j = i;
        while j < n && _is_alpha(string.byte_at(text, j)) {
          idb.push(_to_upper(string.byte_at(text, j)));
          j = j + 1;
        }
        if j >= n || string.byte_at(text, j) != _SGF_LBRACKET {
          return _err_coll(_at("sgf: bad property id char at ", j));
        }
        let top: Int = fr_last.len() - 1;
        let nd: Int = fr_last[top];
        let vstart: Int = coll.val_texts.len();
        var vcount: Int = 0;
        var k = j;
        while k < n && string.byte_at(text, k) == _SGF_LBRACKET {
          var vsb = Vec[UInt8].new();
          let vr = _scan_value(text, k, &mut vsb);
          match vr {
            Ok(next) => {
              coll.val_texts.push(builder.sb_to_str(&vsb));
              coll.val_starts.push(k);
              vcount = vcount + 1;
              k = next;
            },
            Err(e) => { return _err_coll(e); },
          }
        }
        let id: Str = builder.sb_to_str(&idb);
        coll.prop_ids.push(id);
        coll.prop_val_start.push(vstart);
        coll.prop_val_count.push(vcount);
        let pc: Int = coll.node_prop_count[nd];
        coll.node_prop_count[nd] = pc + 1;
        i = k;
      } elif phase == _PH_INIT {
        return _err_coll(_at("sgf: missing ; after ( at ", i));
      } else {
        return _err_coll(_at("sgf: trailing garbage at ", i));
      }
    } elif b == _SGF_LPAREN {
      if phase == _PH_INIT {
        return _err_coll(_at("sgf: missing ; after ( at ", i));
      }
      var par: Int = -1;
      if phase == _PH_SEQ || phase == _PH_VAR {
        let top: Int = fr_last.len() - 1;
        let pv: Int = fr_last[top];
        par = pv;
      }
      fr_open.push(i);
      fr_parent.push(par);
      fr_last.push(-1);
      phase = _PH_INIT;
      i = i + 1;
    } elif b == _SGF_RPAREN {
      if phase == _PH_TOP {
        return _err_coll(_at("sgf: stray ) at ", i));
      }
      if phase == _PH_INIT {
        return _err_coll(_at("sgf: missing ; after ( at ", i));
      }
      fr_open.pop();
      fr_parent.pop();
      fr_last.pop();
      if fr_open.len() == 0 {
        phase = _PH_TOP;
      } else {
        phase = _PH_VAR;
      }
      i = i + 1;
    } elif b == _SGF_SEMI {
      if phase == _PH_TOP || phase == _PH_VAR {
        return _err_coll(_at("sgf: trailing garbage at ", i));
      }
      var par: Int = -1;
      var seqflag: Int = 1;
      if phase == _PH_INIT {
        let ptop: Int = fr_parent.len() - 1;
        let pv: Int = fr_parent[ptop];
        par = pv;
        seqflag = 0;
      } else {
        let stop: Int = fr_last.len() - 1;
        let sv: Int = fr_last[stop];
        par = sv;
      }
      let idx: Int = coll.node_parent.len();
      var dep: Int = 0;
      if par >= 0 {
        let pdep: Int = coll.node_depth[par];
        dep = pdep + 1;
      }
      let pstart: Int = coll.prop_ids.len();
      coll.node_parent.push(par);
      coll.node_depth.push(dep);
      coll.node_seq.push(seqflag);
      coll.node_start.push(i);
      first_child.push(-1);
      next_sibling.push(-1);
      last_child.push(-1);
      coll.node_prop_start.push(pstart);
      coll.node_prop_count.push(0);
      if par >= 0 {
        let tail: Int = last_child[par];
        if tail == -1 {
          first_child[par] = idx;
        } else {
          next_sibling[tail] = idx;
        }
        last_child[par] = idx;
      } else {
        coll.roots.push(idx);
      }
      let ltop: Int = fr_last.len() - 1;
      fr_last[ltop] = idx;
      phase = _PH_SEQ;
      i = i + 1;
    } elif b == _SGF_LBRACKET {
      if phase == _PH_INIT {
        return _err_coll(_at("sgf: missing ; after ( at ", i));
      }
      if phase == _PH_SEQ {
        return _err_coll(_at("sgf: empty property id at ", i));
      }
      return _err_coll(_at("sgf: trailing garbage at ", i));
    } else {
      if phase == _PH_INIT {
        return _err_coll(_at("sgf: missing ; after ( at ", i));
      }
      if phase == _PH_SEQ {
        return _err_coll(_at("sgf: bad property id char at ", i));
      }
      return _err_coll(_at("sgf: trailing garbage at ", i));
    }
  }
  if phase == _PH_INIT {
    return _err_coll(_at("sgf: missing ; after ( at ", n));
  }
  if phase == _PH_SEQ || phase == _PH_VAR {
    let top: Int = fr_open.len() - 1;
    let op: Int = fr_open[top];
    return _err_coll(_at("sgf: unmatched ( at ", op));
  }
  // Finalize the child ranges: walk each node's sibling chain in node order
  // so that children[] holds contiguous per-parent blocks.
  var q = 0;
  let ncount: Int = coll.node_parent.len();
  while q < ncount {
    let off: Int = coll.children.len();
    coll.node_child_start.push(off);
    var c: Int = first_child[q];
    var cc: Int = 0;
    while c != -1 {
      coll.children.push(c);
      cc = cc + 1;
      let nx: Int = next_sibling[c];
      c = nx;
    }
    coll.node_child_count.push(cc);
    q = q + 1;
  }
  return _ok_coll(coll);
}

// --------------------------------------------------
//  Canonical emit
// --------------------------------------------------

// Append every byte of `s` to `sb`.
fn _push_str(sb: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    sb.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append a value's text with `\` and `]` re-escaped for the `[...]` form.
fn _push_escaped(sb: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _SGF_BACKSLASH || b == _SGF_RBRACKET {
      sb.push(_SGF_BACKSLASH);
    }
    sb.push(b);
    i = i + 1;
  }
}

// Emit one node: ";" then every property as ID "[" value "]" ("[...]" per
// value).
fn _emit_node(c: &SgfCollection, n: Int, sb: &mut Vec[UInt8]) {
  sb.push(_SGF_SEMI);
  let pstart: Int = c.node_prop_start[n];
  let pcount: Int = c.node_prop_count[n];
  var p = 0;
  while p < pcount {
    let prop: Int = pstart + p;
    let id: Str = c.prop_ids[prop];
    _push_str(sb, id);
    let vstart: Int = c.prop_val_start[prop];
    let vcount: Int = c.prop_val_count[prop];
    var v = 0;
    while v < vcount {
      sb.push(_SGF_LBRACKET);
      let txt: Str = c.val_texts[vstart + v];
      _push_escaped(sb, txt);
      sb.push(_SGF_RBRACKET);
      v = v + 1;
    }
    p = p + 1;
  }
}

// Emit one game tree iteratively (no recursion, so deep trees cannot overflow
// the call stack). Work stack kinds: 0 = emit a sequence starting at a node,
// 1 = emit a parenthesized tree rooted at a node, 2 = emit a closing ")".
fn _emit_tree(c: &SgfCollection, root: Int, sb: &mut Vec[UInt8]) {
  var st_kind = Vec[Int].new();
  var st_node = Vec[Int].new();
  st_kind.push(1);
  st_node.push(root);
  while st_kind.len() > 0 {
    let top: Int = st_kind.len() - 1;
    let kind: Int = st_kind[top];
    let cur: Int = st_node[top];
    st_kind.pop();
    st_node.pop();
    if kind == 0 {
      _emit_node(c, cur, sb);
      let cc: Int = c.node_child_count[cur];
      if cc > 0 {
        let base: Int = c.node_child_start[cur];
        let first: Int = c.children[base];
        let firstseq: Int = c.node_seq[first];
        if firstseq == 1 {
          // The first child continues the sequence; any other children are
          // variations (not produced by the parser, but handled uniformly).
          var j: Int = cc - 1;
          while j >= 1 {
            let child: Int = c.children[base + j];
            st_kind.push(1);
            st_node.push(child);
            j = j - 1;
          }
          st_kind.push(0);
          st_node.push(first);
        } else {
          // Every child is a variation of this node.
          var j2: Int = cc - 1;
          while j2 >= 0 {
            let child2: Int = c.children[base + j2];
            st_kind.push(1);
            st_node.push(child2);
            j2 = j2 - 1;
          }
        }
      }
    } elif kind == 1 {
      sb.push(_SGF_LPAREN);
      st_kind.push(2);
      st_node.push(0);
      st_kind.push(0);
      st_node.push(cur);
    } else {
      sb.push(_SGF_RPAREN);
    }
  }
}

/// Canonical serialization of a parsed collection.
/// Format: one game tree per output line, each tree = "(" sequence variations
/// ")" with no whitespace; when a node's first child was introduced by ";"
/// (node_seq == 1) it continues the sequence and the remaining children are
/// emitted as parenthesized trees, otherwise all of the node's children are
/// emitted as parenthesized variation trees. Property
/// identifiers are emitted as stored (uppercase after parsing) and values are
/// re-escaped (`\` -> `\\`, `]` -> `\]`); every other byte is emitted
/// verbatim. An empty collection emits "".
/// Params: c - the collection to serialize.
/// Returns: the canonical text; "" for an empty collection.
/// Error case: none. Values that contain raw LF/CR (impossible after parsing,
/// which normalizes them to spaces) are emitted verbatim, not re-normalized.
/// Complexity: O(output length).
pub fn sgf_emit(c: &SgfCollection) -> Str {
  var sb = Vec[UInt8].new();
  var g = 0;
  while g < c.roots.len() {
    let root: Int = c.roots[g];
    _emit_tree(c, root, &mut sb);
    sb.push(_SGF_LF);
    g = g + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Structural accessors
// --------------------------------------------------

/// Number of top-level game trees in the collection.
/// Params: c - the collection.
/// Returns: the game count; 0 for an empty collection.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_game_count(c: &SgfCollection) -> Int {
  return c.roots.len();
}

/// Root node index of game `g`.
/// Params: c - the collection; g - the zero-based game index.
/// Returns: the node index of the game tree's root; -1 when `g` is negative or
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_root(c: &SgfCollection, g: Int) -> Int {
  if g < 0 || g >= c.roots.len() {
    return -1;
  }
  let v: Int = c.roots[g];
  return v;
}

/// Total number of nodes across all game trees (variations included).
/// Params: c - the collection.
/// Returns: the node count; 0 for an empty collection.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_count(c: &SgfCollection) -> Int {
  return c.node_parent.len();
}

/// Parent node index of node `n`.
/// Params: c - the collection; n - the zero-based node index.
/// Returns: the parent node index, -1 for a game-tree root and also -1 when
/// `n` is negative or out of range (use sgf_root/sgf_node_depth to tell roots
/// apart from bad indices).
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_parent(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_parent.len() {
    return -1;
  }
  let v: Int = c.node_parent[n];
  return v;
}

/// Depth of node `n`: its number of ancestors, so every root has depth 0.
/// Params: c - the collection; n - the zero-based node index.
/// Returns: the depth; -1 when `n` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_depth(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_depth.len() {
    return -1;
  }
  let v: Int = c.node_depth[n];
  return v;
}

/// Sequence flag of node `n`: 1 when the node continues its parent's sequence
/// (it was introduced by `;`), 0 when it is a variation root or a game-tree
/// root. It records the syntactic shape, so `(;A;B)` (B seq 1) and
/// `(;A(;B))` (B seq 0) are distinguishable even though their links match.
/// Params: c - the collection; n - the zero-based node index.
/// Returns: 1 or 0; -1 when `n` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_seq(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_seq.len() {
    return -1;
  }
  let v: Int = c.node_seq[n];
  return v;
}

/// Byte offset of node `n`'s ";" in the parsed input.
/// Params: c - the collection; n - the zero-based node index.
/// Returns: the offset; -1 when `n` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_start(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_start.len() {
    return -1;
  }
  let v: Int = c.node_start[n];
  return v;
}

/// Number of direct children of node `n` (sequence continuation and variations
/// combined).
/// Params: c - the collection; n - the zero-based node index.
/// Returns: the child count; -1 when `n` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_child_count(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_child_count.len() {
    return -1;
  }
  let v: Int = c.node_child_count[n];
  return v;
}

/// Direct child `k` of node `n` (children are in document order: child 0 is
/// the sequence continuation when the node has one, later children are
/// variations).
/// Params: c - the collection; n - the zero-based node index; k - the
/// zero-based child index.
/// Returns: the child node index; -1 when `n` or `k` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_child(c: &SgfCollection, n: Int, k: Int) -> Int {
  if n < 0 || n >= c.node_child_start.len() {
    return -1;
  }
  let cnt: Int = c.node_child_count[n];
  if k < 0 || k >= cnt {
    return -1;
  }
  let off: Int = c.node_child_start[n];
  let v: Int = c.children[off + k];
  return v;
}

// --------------------------------------------------
//  Property accessors
// --------------------------------------------------

/// Number of properties directly on node `n` (duplicates counted).
/// Params: c - the collection; n - the zero-based node index.
/// Returns: the property count; -1 when `n` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_prop_count(c: &SgfCollection, n: Int) -> Int {
  if n < 0 || n >= c.node_prop_count.len() {
    return -1;
  }
  let v: Int = c.node_prop_count[n];
  return v;
}

/// Identifier of property `p` on node `n`, normalized to uppercase.
/// Params: c - the collection; n - the zero-based node index; p - the
/// zero-based property index.
/// Returns: the identifier; "" when `n` or `p` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_prop_id(c: &SgfCollection, n: Int, p: Int) -> Str {
  let i: Int = _prop_index(c, n, p);
  if i < 0 {
    return "";
  }
  let v: Str = c.prop_ids[i];
  return v;
}

/// Number of values of property `p` on node `n` (at least 1 for every parsed
/// property).
/// Params: c - the collection; n - the zero-based node index; p - the
/// zero-based property index.
/// Returns: the value count; -1 when `n` or `p` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_value_count(c: &SgfCollection, n: Int, p: Int) -> Int {
  let i: Int = _prop_index(c, n, p);
  if i < 0 {
    return -1;
  }
  let v: Int = c.prop_val_count[i];
  return v;
}

/// Decoded value `v` of property `p` on node `n`: `\]`/`\\` decoded, other
/// backslash escapes resolved and line breaks normalized to single spaces.
/// Params: c - the collection; n - the zero-based node index; p - the
/// zero-based property index; v - the zero-based value index.
/// Returns: the value text; "" when any index is out of range (an empty value
/// `X[]` also returns "", so use sgf_node_value_count to tell them apart).
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_value(c: &SgfCollection, n: Int, p: Int, v: Int) -> Str {
  let i: Int = _prop_index(c, n, p);
  if i < 0 {
    return "";
  }
  let cnt: Int = c.prop_val_count[i];
  if v < 0 || v >= cnt {
    return "";
  }
  let off: Int = c.prop_val_start[i];
  let s: Str = c.val_texts[off + v];
  return s;
}

/// Byte offset of value `v`'s "[" in the parsed input.
/// Params: c - the collection; n - the zero-based node index; p - the
/// zero-based property index; v - the zero-based value index.
/// Returns: the offset; -1 when any index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sgf_node_value_start(c: &SgfCollection, n: Int, p: Int, v: Int) -> Int {
  let i: Int = _prop_index(c, n, p);
  if i < 0 {
    return -1;
  }
  let cnt: Int = c.prop_val_count[i];
  if v < 0 || v >= cnt {
    return -1;
  }
  let off: Int = c.prop_val_start[i];
  let s: Int = c.val_starts[off + v];
  return s;
}

/// Index of the first property on node `n` whose identifier equals `id`
/// ignoring ASCII case; -1 when the node has no such property.
/// Params: c - the collection; n - the zero-based node index; id - the
/// identifier to look for (any case).
/// Returns: the zero-based property index of the first match, else -1.
/// Error case: none.
/// Complexity: O(properties on the node).
pub fn sgf_prop_find(c: &SgfCollection, n: Int, id: Str) -> Int {
  if n < 0 || n >= c.node_prop_start.len() {
    return -1;
  }
  let off: Int = c.node_prop_start[n];
  let cnt: Int = c.node_prop_count[n];
  var p = 0;
  while p < cnt {
    let cur: Str = c.prop_ids[off + p];
    if _id_equals(cur, id) {
      return p;
    }
    p = p + 1;
  }
  return -1;
}

/// First value of the first property on node `n` with identifier `id`
/// (case-insensitive), the common single-value fetch.
/// Params: c - the collection; n - the zero-based node index; id - the
/// identifier to look for (any case).
/// Returns: the decoded first value, or "" when the property is absent or has
/// no values.
/// Error case: none.
/// Complexity: O(properties on the node).
pub fn sgf_prop_value(c: &SgfCollection, n: Int, id: Str) -> Str {
  let p: Int = sgf_prop_find(c, n, id);
  if p < 0 {
    return "";
  }
  let v: Str = sgf_node_value(c, n, p, 0);
  return v;
}

/// First value of the first property with identifier `id` on the root node of
/// game `g` -- the usual way to read FF, GM, SZ, CA and friends.
/// Params: c - the collection; g - the zero-based game index; id - the
/// identifier to look for (any case).
/// Returns: the decoded first value, or "" when `g` is out of range or the
/// property is absent.
/// Error case: none.
/// Complexity: O(properties on the root).
pub fn sgf_root_prop_value(c: &SgfCollection, g: Int, id: Str) -> Str {
  let r: Int = sgf_root(c, g);
  if r < 0 {
    return "";
  }
  let v: Str = sgf_prop_value(c, r, id);
  return v;
}
