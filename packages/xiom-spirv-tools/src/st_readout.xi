// XIOM -- xiom.spirv-tools: safe copy-out readout helpers (probe bridge).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// WHY THIS MODULE EXISTS: SPIRV-Tools returns pointers to C-owned structs
// (spv_binary_t, spv_text_t, spv_diagnostic_t).  XIOM must never read
// through foreign pointers directly (B-20: foreign-pointer reads silently
// yield zeros on the v0.64.3 pin; the sanctioned shape is "C copies out
// into an XIOM-owned slot, XIOM reads its own bytes").  This module wraps
// a two-function C bridge (src/st_probe_bridge.c) that does exactly that
// copy: the destination is always an XIOM-owned Vec[UInt8], the source is
// only ever touched from C.
//
// BUILD NOTE: this module declares `extern "C"` bridge symbols, so any
// consumer that imports it must link src/st_probe_bridge.c.  The package's
// port.args.json does that automatically for the conformance suite
// (--c-source ${PACKAGE_DIR}/src/st_probe_bridge.c).  The core loader
// (xiom.spirv_tools) does NOT import this module and stays link-free.

module xiom.spirv_tools.readout

extern "C" {
  fn xst_copy(dst: *UInt8, src: *UInt8, n: UInt64);
  fn xst_strlen(p: *UInt8) -> UInt64;
}

/// spv_binary_t view: { code: const uint32_t*; wordCount: size_t; } (16 bytes).
pub type StBinaryView = {
  code: Int;
  word_count: Int;
}

/// spv_text_t view: { str: const char*; length: size_t; } (16 bytes).
pub type StTextView = {
  str_addr: Int;
  length: Int;
}

/// Zeroed owned slot of `n` bytes (no malloc/free -- lane discipline).
/// Complexity: O(n).
pub fn st_slot_new(n: Int) -> Vec[UInt8]
  requires: n >= 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u64 read at a byte offset of an XIOM-owned slot.
/// Complexity: O(1).
pub fn st_slot_read_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8)
    | ((buf[off + 2] as Int) << 16) | ((buf[off + 3] as Int) << 24);
  let hi = (buf[off + 4] as Int) | ((buf[off + 5] as Int) << 8)
    | ((buf[off + 6] as Int) << 16) | ((buf[off + 7] as Int) << 24);
  return lo | (hi << 32);
}

/// Little-endian u32 read at a byte offset of an XIOM-owned slot.
/// Complexity: O(1).
pub fn st_slot_read_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8)
    | ((buf[off + 2] as Int) << 16) | ((buf[off + 3] as Int) << 24);
}

/// Little-endian u64 write at a byte offset of an XIOM-owned slot
/// (byte-indexed writes only -- B-11/B-16/B-17 discipline).
/// Complexity: O(1).
pub fn st_slot_write_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  buf[off + 0] = (v & 0xFF) as UInt8;
  buf[off + 1] = ((v >> 8) & 0xFF) as UInt8;
  buf[off + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[off + 3] = ((v >> 24) & 0xFF) as UInt8;
  buf[off + 4] = ((v >> 32) & 0xFF) as UInt8;
  buf[off + 5] = ((v >> 40) & 0xFF) as UInt8;
  buf[off + 6] = ((v >> 48) & 0xFF) as UInt8;
  buf[off + 7] = ((v >> 56) & 0xFF) as UInt8;
}

/// C-side strlen of a foreign C string (the C bridge reads it; XIOM never
/// dereferences the pointer).  Complexity: O(len).
pub fn st_cstr_len(addr: Int) -> Int
  requires: addr != 0
{
  unsafe {
    return xst_strlen(addr as *UInt8) as Int;
  }
}

/// Copy `n` bytes from a foreign address into an XIOM-owned buffer.
/// The bridge (C) is the only reader of the foreign memory.
/// Complexity: O(n).
pub fn st_copy_out(dst: &mut Vec[UInt8], src_addr: Int, n: Int)
  requires: src_addr != 0
  requires: n >= 0
  requires: dst.len() >= n
{
  unsafe {
    if n > 0 {
      xst_copy(dst.as_mut_ptr(), src_addr as *UInt8, n as UInt64);
    }
  }
}

/// Copy a foreign C string into an XIOM-owned slot and decode it as Str.
/// `known_len` = 0 means "measure with C strlen first".
/// Complexity: O(len).
pub fn st_read_cstr(addr: Int, known_len: Int) -> Str
  requires: addr != 0
  requires: known_len >= 0
{
  let n = if known_len > 0 { known_len } else { st_cstr_len(addr) };
  var buf = st_slot_new(n + 1);
  st_copy_out(&mut buf, addr, n);
  buf[n] = 0 as UInt8;
  return Str::from_c_str(buf.as_mut_ptr());
}

/// View a C-owned spv_binary_t (16 bytes copied out through the bridge).
/// Complexity: O(1).
pub fn st_binary_view(bin_ptr: Int) -> StBinaryView
  requires: bin_ptr != 0
{
  var f = st_slot_new(16);
  st_copy_out(&mut f, bin_ptr, 16);
  return StBinaryView{ code: st_slot_read_u64(&f, 0); word_count: st_slot_read_u64(&f, 8) };
}

/// View a C-owned spv_text_t (16 bytes copied out through the bridge).
/// Complexity: O(1).
pub fn st_text_view(text_ptr: Int) -> StTextView
  requires: text_ptr != 0
{
  var f = st_slot_new(16);
  st_copy_out(&mut f, text_ptr, 16);
  return StTextView{ str_addr: st_slot_read_u64(&f, 0); length: st_slot_read_u64(&f, 8) };
}

/// Error message of a C-owned spv_diagnostic_t.  Layout pinned to the
/// pinned header: { spv_position_t position (3 x size_t = 24 B); char* error
/// @24; bool isTextSource; } -- 40 bytes copied out, `error` read from the
/// owned slot, string copied by the bridge.  "" when error is NULL.
/// Complexity: O(len).
pub fn st_diagnostic_error(diag_ptr: Int) -> Str
  requires: diag_ptr != 0
{
  var f = st_slot_new(40);
  st_copy_out(&mut f, diag_ptr, 40);
  let err_addr = st_slot_read_u64(&f, 24);
  if err_addr == 0 { return ""; }
  return st_read_cstr(err_addr, 0);
}

/// ASCII substring search over bytes copied into an XIOM-owned buffer
/// (used to prove disassembly output without foreign reads).
/// Complexity: O(hay * needle).
pub fn st_contains_ascii(hay: &Vec[UInt8], needle: Str) -> Bool
  requires: needle.len() > 0
{
  if needle.len() > hay.len() { return false; }
  var i = 0;
  while i + needle.len() <= hay.len() {
    var j = 0;
    var hit = true;
    while j < needle.len() {
      if (hay[i + j] as Int) != (needle[j] as Int) { hit = false; }
      j = j + 1;
    }
    if hit { return true; }
    i = i + 1;
  }
  return false;
}
