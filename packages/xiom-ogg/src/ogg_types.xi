// xiom.ogg -- shared types for the libogg packet layer (pure XIOM).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Flat outcome structs only (finding B-26).

module xiom.ogg.types

/// One complete Ogg page copied out of libogg: `found` is false when more
/// data must be fed; `header` is the 27 + segment-count byte page header
/// (with its stored checksum), `body` the page payload.
pub type PageOut = {
  found: Bool;
  header: Vec[UInt8];
  body: Vec[UInt8];
  serialno: Int;
  pageno: Int;
  continued: Bool;
  bos: Bool;
  eos: Bool;
  granulepos: Int;
  packets: Int;
}

/// One complete packet copied out of libogg: `size` is the full upstream
/// packet size (data.len() < size means the copy was truncated by `cap`).
pub type PacketOut = {
  found: Bool;
  data: Vec[UInt8];
  size: Int;
  b_o_s: Bool;
  e_o_s: Bool;
  granulepos: Int;
  packetno: Int;
}
