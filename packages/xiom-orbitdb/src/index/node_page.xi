// XIOM ORBITDB -- B-tree node page codec (v1 legacy + v2 payload section).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Moved out of engine/snapshot.xi (M1.1b A2) so the pager in index/btree.xi
// can decode a node page on a lazy-load miss without importing the snapshot
// module; snapshot.xi imports this module for both v1 and v2 codecs.

module xiom.db.index.node_page

use xiom.db.storage.tuple;
use xiom.db.index.btree;

pub const NODE_PAGE_MAGIC: Int = 0x4F;        // 'O'
pub const NODE_PAGE_VERSION: Int = 1;       // legacy node page version
pub const NODE_PAGE_V2: Int = 2;            // + payload section (M5.3)
pub const NODE_PAGE_KIND: Int = 0x4E;       // 'N'
pub const NODE_PAGE_HEADER_BYTES: Int = 28;

pub fn node_page_bytes(node: &BTreeNode) -> Vec[Int] {
  var out = Vec[Int].new();
  node_page_bytes_into(&mut out, node);
  return out;
}

// Reused-buffer form (m375 write-path fallback): clears and refills `out`;
// capacity is reused across pages, so the flush loop allocates no per-node
// payload Vec.
pub fn node_page_bytes_into(out: &mut Vec[Int], node: &BTreeNode) {
  while out.len() > 0 {
    let _ = out.pop();
  }
  out.push(NODE_PAGE_MAGIC);
  out.push(NODE_PAGE_V2);
  out.push(NODE_PAGE_KIND);
  var leaf = 0;
  if node.is_leaf { leaf = 1; }
  out.push(leaf);
  tuple_push_int_le(out, node.keys.len());
  tuple_push_int_le(out, node.children.len());
  tuple_push_int_le(out, 0); // reserved
  var i = 0;
  while i < node.keys.len() {
    tuple_push_int_le(out, node.keys[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.values.len() {
    tuple_push_int_le(out, node.values[i]);
    i = i + 1;
  }
  i = 0;
  while i < node.children.len() {
    tuple_push_int_le(out, node.children[i]);
    i = i + 1;
  }
  // Payload section (node version 2): u64 LE count + per entry u64 LE length
  // + bytes (the node-page family's integer width). Parallel to keys; empty
  // = plain int entry.
  tuple_push_int_le(out, node.keys.len());
  i = 0;
  while i < node.keys.len() {
    let p = node_payload(node, i);
    tuple_push_int_le(out, p.len());
    var k = 0;
    while k < p.len() {
      out.push(p[k] & 0xFF);
      k = k + 1;
    }
    i = i + 1;
  }
}

// Strict decode: magic/version/kind, exact length, sane flags and counts.
// Accepts node version 1 (legacy: no payload section -> empty payloads) and
// version 2 (payload section). Returns None on any violation -- a snapshot
// either restores whole or not.
pub fn node_page_decode(data: &Vec[Int]) -> Option[BTreeNode] {
  if data.len() < NODE_PAGE_HEADER_BYTES { return None; }
  if data[0] != NODE_PAGE_MAGIC { return None; }
  let version = data[1];
  if version != NODE_PAGE_VERSION && version != NODE_PAGE_V2 { return None; }
  if data[2] != NODE_PAGE_KIND { return None; }
  let key_count = tuple_read_int_le(data, 4);
  let child_count = tuple_read_int_le(data, 12);
  if key_count < 0 { return None; }
  if child_count < 0 { return None; }

  let base = NODE_PAGE_HEADER_BYTES + 16 * key_count + 8 * child_count;
  if version == NODE_PAGE_V2 {
    if data.len() < base + 8 { return None; }
    let pcount = tuple_read_int_le(data, base);
    if pcount != key_count { return None; }
    var at = base + 8;
    var j = 0;
    while j < pcount {
      if at + 8 > data.len() { return None; }
      let plen = tuple_read_int_le(data, at);
      if plen < 0 { return None; }
      at = at + 8 + plen;
      if at > data.len() { return None; }
      j = j + 1;
    }
    if at != data.len() { return None; }
  } else {
    if data.len() != base { return None; }
  }

  var keys = Vec[Int].new();
  var values = Vec[Int].new();
  var children = Vec[Int].new();
  var at = NODE_PAGE_HEADER_BYTES;
  var i = 0;
  while i < key_count {
    keys.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < key_count {
    values.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }
  i = 0;
  while i < child_count {
    children.push(tuple_read_int_le(data, at));
    at = at + 8;
    i = i + 1;
  }

  var payloads = Vec[Vec[Int]].new();
  if version == NODE_PAGE_V2 {
    var at2 = base + 8;
    var j2 = 0;
    while j2 < key_count {
      let plen2 = tuple_read_int_le(data, at2);
      at2 = at2 + 8;
      var p = Vec[Int].new();
      var k2 = 0;
      while k2 < plen2 {
        p.push(data[at2 + k2] & 0xFF);
        k2 = k2 + 1;
      }
      payloads.push(p);
      at2 = at2 + plen2;
      j2 = j2 + 1;
    }
  } else {
    var j3 = 0;
    while j3 < key_count {
      payloads.push(Vec[Int].new());
      j3 = j3 + 1;
    }
  }

  let leaf = data[3] == 1;
  if leaf && child_count != 0 { return None; }
  if !leaf && child_count == 0 { return None; }
  return Some(BTreeNode{ keys: keys, values: values, payloads: payloads,
                         children: children, is_leaf: leaf });
}