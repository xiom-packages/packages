// XIOM ORBITDB -- byte-page format v2 block codec (M1.2 S1, pure).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One 4096-byte block: 40-byte header + payload. CRC32C (page_compute_checksum)
// covers the payload bytes only. PURE codec -- no IO; the block store (S2)
// layers file IO through the byte-IO shim. Design: docs/BYTE-PAGE-FORMAT-V2.md.
//
//   offset  size  field
//   0       4     magic 'O','P','G','2'
//   4       1     format_version = 2
//   5       1     kind ('H' header slot, 'P' page, 'F' free)
//   6       2     reserved (0)
//   8       8     generation (LE)
//   16      8     page_id (LE)
//   24      8     payload_len (LE, 0..4056)
//   32      8     crc32c (LE; low 32 bits used)
//   40      4056  payload (zero-padded)
//
// Header-slot payload (64 bytes, kind 'H'): magic2 'O','H','D','2' + seven
// LE fields (root, order, node_count, checkpoint_lsn, committed_generation,
// block_count, next_page_id) + 4 reserved zero bytes. The block generation
// doubles as the commit stamp and MUST equal the payload's
// committed_generation (decode enforces the match).
//
// Decode is strict: exact 4096 length, magic/version/kind, reserved zero,
// payload_len in range, CRC match, zero padding. Every failure is None --
// no partial blocks, matching the v1 "strict decode" rule.

module xiom.db.storage.block

use xiom.db.storage.page;
use xiom.db.storage.tuple;

const BLOCK_BYTES: Int = 4096;
const BLOCK_HEADER_BYTES: Int = 40;
const BLOCK_PAYLOAD_CAPACITY: Int = 4056;
const BLOCK_VERSION: Int = 2;
const KIND_HEADER: Int = 0x48;
const KIND_PAGE: Int = 0x50;
const KIND_FREE: Int = 0x46;
const HEADER_PAYLOAD_BYTES: Int = 64;

pub type BlockPage = {
  generation: Int;
  page_id: Int;
  payload: Vec[Int];
}

pub type BlockHeader = {
  root: Int;
  order: Int;
  node_count: Int;
  checkpoint_lsn: Int;
  committed_generation: Int;
  block_count: Int;
  next_page_id: Int;
}

pub type BlockView = {
  kind: Int;
  generation: Int;
  page_id: Int;
  payload: Vec[Int];
}

pub fn block_size() -> Int {
  return BLOCK_BYTES;
}

pub fn block_payload_capacity() -> Int {
  return BLOCK_PAYLOAD_CAPACITY;
}

fn put_u8(buf: &mut Vec[Int], v: Int) {
  buf.push(v & 0xFF);
}

fn put_magic(buf: &mut Vec[Int]) {
  put_u8(buf, 0x4F);
  put_u8(buf, 0x50);
  put_u8(buf, 0x47);
  put_u8(buf, 0x32);
}

// Shared encoder. Returns an EMPTY vector for invalid input (payload longer
// than the block capacity, or any element outside 0..255) -- callers treat
// the empty result as a programming error, never as data.
fn block_encode(kind: Int, generation: Int, page_id: Int, payload: &Vec[Int]) -> Vec[Int] {
  var i: Int = 0;
  while i < payload.len() {
    if (payload[i] & 0xFF) != payload[i] {
      var bad = Vec[Int].new();
      return bad;
    }
    i = i + 1;
  }
  if payload.len() > BLOCK_PAYLOAD_CAPACITY {
    var bad = Vec[Int].new();
    return bad;
  }
  var b = Vec[Int].new();
  put_magic(&mut b);
  put_u8(&mut b, BLOCK_VERSION);
  put_u8(&mut b, kind);
  put_u8(&mut b, 0);
  put_u8(&mut b, 0);
  tuple_push_int_le(&mut b, generation);
  tuple_push_int_le(&mut b, page_id);
  tuple_push_int_le(&mut b, payload.len());
  tuple_push_int_le(&mut b, page_compute_checksum(payload));
  i = 0;
  while i < payload.len() {
    b.push(payload[i]);
    i = i + 1;
  }
  while b.len() < BLOCK_BYTES {
    b.push(0);
  }
  return b;
}

pub fn block_encode_page(generation: Int, page_id: Int, payload: &Vec[Int]) -> Vec[Int] {
  return block_encode(KIND_PAGE, generation, page_id, payload);
}

pub fn block_encode_header(h: &BlockHeader) -> Vec[Int] {
  var p = Vec[Int].new();
  put_u8(&mut p, 0x4F);
  put_u8(&mut p, 0x48);
  put_u8(&mut p, 0x44);
  put_u8(&mut p, 0x32);
  tuple_push_int_le(&mut p, h.root);
  tuple_push_int_le(&mut p, h.order);
  tuple_push_int_le(&mut p, h.node_count);
  tuple_push_int_le(&mut p, h.checkpoint_lsn);
  tuple_push_int_le(&mut p, h.committed_generation);
  tuple_push_int_le(&mut p, h.block_count);
  tuple_push_int_le(&mut p, h.next_page_id);
  put_u8(&mut p, 0);
  put_u8(&mut p, 0);
  put_u8(&mut p, 0);
  put_u8(&mut p, 0);
  return block_encode(KIND_HEADER, h.committed_generation, 0, &p);
}

// Strict decode of any block kind; None for every malformed/torn case.
pub fn block_decode(bytes: &Vec[Int]) -> Option[BlockView] {
  if bytes.len() != BLOCK_BYTES { return None; }
  if bytes[0] != 0x4F || bytes[1] != 0x50 || bytes[2] != 0x47 || bytes[3] != 0x32 {
    return None;
  }
  if bytes[4] != BLOCK_VERSION { return None; }
  let kind = bytes[5];
  if kind != KIND_HEADER && kind != KIND_PAGE && kind != KIND_FREE { return None; }
  if bytes[6] != 0 || bytes[7] != 0 { return None; }
  let gen = tuple_read_int_le(bytes, 8);
  let pid = tuple_read_int_le(bytes, 16);
  let plen = tuple_read_int_le(bytes, 24);
  let crc = tuple_read_int_le(bytes, 32);
  if plen < 0 || plen > BLOCK_PAYLOAD_CAPACITY { return None; }
  var i: Int = BLOCK_HEADER_BYTES + plen;
  while i < BLOCK_BYTES {
    if bytes[i] != 0 { return None; }
    i = i + 1;
  }
  var payload = Vec[Int].new();
  i = 0;
  while i < plen {
    payload.push(bytes[BLOCK_HEADER_BYTES + i]);
    i = i + 1;
  }
  if page_compute_checksum(&payload) != crc { return None; }
  return Some(BlockView{ kind: kind, generation: gen, page_id: pid, payload: payload });
}

pub fn block_decode_page(bytes: &Vec[Int]) -> Option[BlockPage] {
  match block_decode(bytes) {
    Some(v) => {
      if v.kind != KIND_PAGE { return None; }
      return Some(BlockPage{ generation: v.generation, page_id: v.page_id, payload: v.payload });
    }
    None => { return None; }
  }
}

pub fn block_decode_header(bytes: &Vec[Int]) -> Option[BlockHeader] {
  match block_decode(bytes) {
    Some(v) => {
      if v.kind != KIND_HEADER { return None; }
      if v.page_id != 0 { return None; }
      if v.payload.len() != HEADER_PAYLOAD_BYTES { return None; }
      if v.payload[0] != 0x4F || v.payload[1] != 0x48 || v.payload[2] != 0x44 || v.payload[3] != 0x32 {
        return None;
      }
      if v.payload[60] != 0 || v.payload[61] != 0 || v.payload[62] != 0 || v.payload[63] != 0 {
        return None;
      }
      let committed = tuple_read_int_le(&v.payload, 36);
      if committed != v.generation { return None; }
      return Some(BlockHeader{
        root: tuple_read_int_le(&v.payload, 4),
        order: tuple_read_int_le(&v.payload, 12),
        node_count: tuple_read_int_le(&v.payload, 20),
        checkpoint_lsn: tuple_read_int_le(&v.payload, 28),
        committed_generation: committed,
        block_count: tuple_read_int_le(&v.payload, 44),
        next_page_id: tuple_read_int_le(&v.payload, 52),
      });
    }
    None => { return None; }
  }
}

// Fast path for the block store's scan: a dead block is skipped without the
// CRC/padding validation (kind is not covered by the payload CRC).
pub fn block_kind_is_free(bytes: &Vec[Int]) -> Bool {
  if bytes.len() != BLOCK_BYTES { return false; }
  if bytes[0] != 0x4F || bytes[1] != 0x50 || bytes[2] != 0x47 || bytes[3] != 0x32 {
    return false;
  }
  if bytes[4] != BLOCK_VERSION { return false; }
  return bytes[5] == KIND_FREE;
}
