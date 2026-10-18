// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.snapshot

// Snapshot export/import (M-D6): a point-in-time copy of the whole engine
// (every collection) as three files sharing a base path:
//   <base>.ckpt      -- compacted `xvector-wal 1` checkpoint
//                       (wal_persist_sync: fsync before rename)
//   <base>.manifest  -- the registry of record (`xvector-manifest 1`)
//   <base>.meta      -- `xvector-snapshot 1 <lsn> <collections>\n`
// snapshot_create compacts the live log FIRST (a full durable swap when
// durable mode is on, an in-memory compact otherwise), so the ckpt is live
// state, not the full mutation history. Each file is individually complete
// and self-describing; snapshot_load validates the meta header, then opens
// checkpoint + manifest through the standard recovery path with a fresh
// segment next to the import target. No new stdlib dependencies (explicit
// paths; the directory must exist).

use xiom.io;
use xiom.convert;
use xiom.convert.parse;
use xiom.string.slice;
use xiom.string.split;
use xiom.string.trim;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.primitives;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;

// "<dir>/<name>" -> base path ("" dir = current directory; both separators).
fn join(dir: Str, name: Str) -> Str {
  if dir.len() == 0 { return name; }
  let c = dir.byte_at(dir.len() - 1);
  if c == 47u8 || c == 92u8 { return dir + name; }
  return dir + "/" + name;
}

pub type SnapshotMeta = {
  valid: Bool;
  version: Int;
  lsn: Int;
  collections: Int;
}

fn invalid_meta() -> SnapshotMeta {
  return SnapshotMeta{ valid: false, version: 0, lsn: 0, collections: 0 };
}

// Strict parse of the meta line: exactly
// `xvector-snapshot 1 <lsn> <collections>` (trailing whitespace/newline
// tolerated). Anything else is invalid.
pub fn snapshot_meta_parse(text: Str) -> SnapshotMeta {
  let parts = split.str_split(trim.str_trim(text), " ");
  if parts.len() != 4 { return invalid_meta(); }
  if parts[0] != "xvector-snapshot" { return invalid_meta(); }
  var version: Int = 0;
  match parse.parse_int(parts[1]) {
    Ok(v) => { version = v; }
    Err(_) => { return invalid_meta(); }
  }
  if version != 1 { return invalid_meta(); }
  var lsn: Int = 0;
  match parse.parse_int(parts[2]) {
    Ok(v) => { lsn = v; }
    Err(_) => { return invalid_meta(); }
  }
  var cols: Int = 0;
  match parse.parse_int(parts[3]) {
    Ok(v) => { cols = v; }
    Err(_) => { return invalid_meta(); }
  }
  if lsn < 0 || cols < 0 { return invalid_meta(); }
  return SnapshotMeta{ valid: true, version: 1, lsn: lsn, collections: cols };
}

pub fn snapshot_meta_read(base: Str) -> SnapshotMeta {
  match io.read_file(base + ".meta") {
    Ok(text) => { return snapshot_meta_parse(text); }
    Err(_) => { return invalid_meta(); }
  }
}

pub fn snapshot_valid(base: Str) -> Bool {
  return snapshot_meta_read(base).valid;
}

fn write_meta(base: Str, lsn: Int, collections: Int) -> Bool {
  var text = "xvector-snapshot 1 " + convert.int_to_string(lsn) + " "
    + convert.int_to_string(collections) + "\n";
  var b = slice.str_bytes(text);
  match io.write_file_bytes(base + ".meta", &b) {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Create a snapshot at <dir>/<name>. Durable engines take a full
// checkpoint swap first (crash-safe checkpoint + rotated segment);
// in-memory engines are compacted only. Returns the base path.
pub fn snapshot_create(eng: &mut VectorEngine, dir: Str, name: Str) -> Result[Str, Str] {
  if name.len() == 0 { return Err("empty snapshot name"); }
  let base = join(dir, name);
  if eng.wal_seg_path.len() > 0 && eng.wal_ckpt_path.len() > 0 {
    match engine_checkpoint_swap(eng) {
      Ok(_) => {}
      Err(_) => { return Err("checkpoint swap failed before snapshot"); }
    }
  } else {
    let _lsn = engine_compact_log(eng);
  }
  var cur = wal_writer_current_lsn(&eng.wal);
  if !wal_persist_sync(&eng.wal, base + ".ckpt") {
    return Err("snapshot checkpoint persist failed: " + base + ".ckpt");
  }
  if !engine_manifest_save(eng, base + ".manifest") {
    return Err("snapshot manifest persist failed: " + base + ".manifest");
  }
  if !write_meta(base, cur, engine_collection_count(eng)) {
    return Err("snapshot meta write failed: " + base + ".meta");
  }
  return Ok(base);
}

// Load a snapshot: meta validity check, then open the checkpoint + manifest
// as a durable engine with a fresh segment at `seg_out` (next to the
// import target; created if missing). `dim`/`metric` are the last-resort
// defaults exactly like engine_open_durable.
pub fn snapshot_load(base: Str, seg_out: Str, dim: Int, metric: DistanceMetric) -> Result[VectorEngine, Str] {
  let meta = snapshot_meta_read(base);
  if !meta.valid {
    return Err("snapshot meta invalid or missing: " + base + ".meta");
  }
  var eng = engine_open_durable(base + ".ckpt", seg_out, base + ".manifest", dim, metric);
  return Ok(eng);
}
