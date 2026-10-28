// XIOM ORBITDB -- byte-IO shim (M1.2 S2 seam; swapped in S4, 2026-10-13).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The block store NEVER calls io.* for block IO directly; it goes through
// these functions so the stdlib swap stays a one-file change. As of M1.2 S4
// (2026-10-13) the O(file) whole-file fallbacks are GONE: reads/writes use
// the real byte primitives landed in stdlib waves 115/117 (io.read_at /
// io.write_at / io.append_file_bytes / io.file_size / io.truncate_file) and
// the sync seam is a REAL fsync (sync_io.sync_fd), plus `byteio_sync_dir`
// for rename durability (sync_io.fsync_dir; wave 118). Byte convention:
// Vec[Int] with elements 0..255 everywhere in the storage layer; the
// conversion to Vec[UInt8] happens only here (Vec casts were always
// zero-extending; the C-ORBIT-08B fixed-array mask workaround was retired
// on v0.64.5 -- m260).
//
// Fault gates are EXACTLY where they were -- one gate call per public op,
// kind 0 = write-ish, kind 1 = sync -- so the fault probe's arming counts
// are unchanged (modes: 1 skip, 2 partial/torn, 3 fail; kill exits).
//
// Runtime note: v0.64.5 (adopted 2026-10-15) re-vendors stdlib/runtime with
// wave 139 >> the 115/117/118 primitives this file rides, so the stock pin
// needs NO XIOM_RUNTIME_DIR override (the S4 lane-runtime override is
// retired; scripts/dev-env.* unsets it).
//
// Design: docs/BYTE-PAGE-FORMAT-V2.md section 4.

module xiom.db.storage.byte_io

use xiom.io;
use xiom.os.sync_io;
use xiom.string;
use xiom.db.storage.fault;

// Vec[Int] (0..255) -> Vec[UInt8].
fn bytes_to_u8(data: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    out.push((data[i] & 0xFF) as UInt8);
    i = i + 1;
  }
  return out;
}

// Vec[UInt8] -> Vec[Int] with zero-extension (Vec element casts are
// zero-extending by contract; plain cast suffices).
fn u8_to_bytes(b: &Vec[UInt8]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < b.len() {
    out.push(b[i] as Int);
    i = i + 1;
  }
  return out;
}

// Byte read as Vec[Int]; None on IO error or a short read (offset+len past
// EOF), matching the old whole-file contract.
pub fn byteio_read_at(path: Str, offset: Int, len: Int) -> Option[Vec[Int]] {
  if offset < 0 || len < 0 { return None; }
  if len == 0 { return Some(Vec[Int].new()); }
  match io.read_at(path, offset, len) {
    Ok(b) => {
      if b.len() != len { return None; }
      return Some(u8_to_bytes(&b));
    }
    Err(_) => { return None; }
  }
}

// Caller-buffer read: io.read_at_into clears/reuses `buf` and allocates no
// fresh Vec per call (stdlib main 9bad232; REL-20261020-1731-orbitdb). Used
// by the block-store scan so a large v2 file does not retain one page buffer
// per block (m375 fallback). Returns true only for a full-length read.
pub fn byteio_read_at_into(path: Str, offset: Int, buf: &mut Vec[UInt8],
                           len: Int) -> Bool {
  if offset < 0 || len < 0 { return false; }
  match io.read_at_into(path, offset, buf, len) {
    Ok(n) => { return n == len; }
    Err(_) => { return false; }
  }
}

// Write at offset (creates the file, zero-fills a gap past EOF). The fault
// gate can skip, shorten (torn write) or fail the operation.
pub fn byteio_write_at(path: Str, offset: Int, data: &Vec[Int]) -> Bool {
  if offset < 0 { return false; }
  let fa = fault_gate(0);
  if fa == 1 { return true; }
  if fa == 3 { return false; }
  if fa == 2 {
    var cut = Vec[Int].new();
    let t = fault_partial_tail(data.len());
    var c = 0;
    while c < t && c < data.len() {
      cut.push(data[c]);
      c = c + 1;
    }
    return byteio_write_at_real(path, offset, &cut);
  }
  return byteio_write_at_real(path, offset, data);
}

fn byteio_write_at_real(path: Str, offset: Int, data: &Vec[Int]) -> Bool {
  let b = bytes_to_u8(data);
  match io.write_at(path, offset, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Byte-buffer write (no Vec[Int] round-trip). Same fault gate/partial-write
// discipline as byteio_write_at; used by the page writer's reused buffer.
pub fn byteio_write_at_bytes(path: Str, offset: Int, data: &Vec[UInt8]) -> Bool {
  if offset < 0 { return false; }
  let fa = fault_gate(0);
  if fa == 1 { return true; }
  if fa == 3 { return false; }
  if fa == 2 {
    var cut = Vec[UInt8].new();
    let t = fault_partial_tail(data.len());
    var c = 0;
    while c < t && c < data.len() {
      cut.push(data[c]);
      c = c + 1;
    }
    match io.write_at(path, offset, &cut) {
      Ok(_) => { return true; }
      Err(_) => { return false; }
    }
  }
  match io.write_at(path, offset, data) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Append bytes (binary, creates the file). Same gate discipline as write.
pub fn byteio_append(path: Str, data: &Vec[Int]) -> Bool {
  let fa = fault_gate(0);
  if fa == 1 { return true; }
  if fa == 3 { return false; }
  if fa == 2 {
    var cut = Vec[Int].new();
    let t = fault_partial_tail(data.len());
    var c = 0;
    while c < t && c < data.len() {
      cut.push(data[c]);
      c = c + 1;
    }
    let bcut = bytes_to_u8(&cut);
    match io.append_file_bytes(path, &bcut) {
      Ok(_) => { return true; }
      Err(_) => { return false; }
    }
  }
  let b = bytes_to_u8(data);
  match io.append_file_bytes(path, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// File size in bytes; 0 when the file does not exist.
pub fn byteio_file_size(path: Str) -> Int {
  match io.file_size(path) {
    Some(s) => { return s; }
    None => { return 0; }
  }
}

// ftruncate semantics: cut to len, or extend with zero bytes.
pub fn byteio_truncate(path: Str, len: Int) -> Bool {
  if len < 0 { return false; }
  let fa = fault_gate(0);
  if fa == 1 || fa == 2 { return true; }
  if fa == 3 { return false; }
  match io.truncate_file(path, len) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Durability seam: a REAL fsync on the path (open-append handle + sync_fd +
// close_fd). Skips with success when the file does not exist (nothing to
// sync; the open must not create it as a side effect). The fault gate can
// fail this (syncfail), which the engine maps to a latched failed handle.
pub fn byteio_sync(path: Str) -> Bool {
  let fa = fault_gate(1);
  if fa == 3 { return false; }
  if fa == 1 || fa == 2 { return true; }
  if !io.file_exists(path) { return true; }
  match sync_io.open_append(path) {
    Err(_) => { return false; }
    Ok(fd) => {
      var ok = false;
      match sync_io.sync_fd(fd) {
        Ok(_) => { ok = true; }
        Err(_) => {}
      }
      let _ = sync_io.close_fd(fd);
      return ok;
    }
  }
}

// Rename durability (P3 adoption): after a publish-by-rename, sync the
// directory that received it so the new name is durable. Not fault-gated
// (not part of the pre-publish durability contract).
pub fn byteio_sync_dir(path: Str) -> Bool {
  let dir = byteio_dir_of(path);
  var ok = false;
  match sync_io.fsync_dir(dir) {
    Ok(_) => { ok = true; }
    Err(_) => {}
  }
  return ok;
}

// --- held-handle variants (BENCH-1 perf slice, 2026-10-16) ------------------
// The WAL auto-commit paths opened one append handle per RECORD
// (io.append_line) and one more per durability sync; on Windows the
// open/close pairs dominate write cost (docs/BENCH-1.md finding #1). These
// helpers let the WAL do one open per record (combined durable append) or
// one open per TRANSACTION (held fd), without touching the fault-gate
// discipline: WAL appends were NEVER gated (io.append_line) and stay
// ungated here; only the sync seam is gated (kind 1), exactly as byteio_sync.

// Open a held append handle. Not fault-gated (opening is not a write); the
// caller owns the fd and must close it (byteio_close_append).
pub fn byteio_open_append(path: Str) -> Option[Int] {
  match sync_io.open_append(path) {
    Ok(fd) => { return Some(fd); }
    Err(_) => { return None; }
  }
}

// Append bytes through a held handle. UNGATED, mirroring the historical
// io.append_line WAL path (fault arming counts are unchanged by design).
pub fn byteio_append_fd(fd: Int, data: &Vec[Int]) -> Bool {
  let b = bytes_to_u8(data);
  match sync_io.write_all(fd, &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Durability seam on a held handle. Same gate discipline as byteio_sync
// (kind 1): syncfail fails it; skip/partial succeed without syncing.
pub fn byteio_sync_fd(fd: Int) -> Bool {
  let fa = fault_gate(1);
  if fa == 3 { return false; }
  if fa == 1 || fa == 2 { return true; }
  match sync_io.sync_fd(fd) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Close a held append handle (best-effort; not fault-gated).
pub fn byteio_close_append(fd: Int) -> Bool {
  match sync_io.close_fd(fd) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Parent directory of a path for fsync_dir: text before the last slash or
// backslash; "." when the path has no separator, "/" for a root-level path.
fn byteio_dir_of(path: Str) -> Str {
  var at = -1;
  match string.last_index_of(path, "/") {
    Some(i) => { if i > at { at = i; } }
    None => {}
  }
  match string.last_index_of(path, "\\") {
    Some(i) => { if i > at { at = i; } }
    None => {}
  }
  if at < 0 { return "."; }
  if at == 0 { return "/"; }
  return string.str_slice(path, 0, at);
}
