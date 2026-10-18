// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.durability.manifest_file

// File-backed collection registry (M-D2). The registry lists named
// collections with their durable configuration (dimension, metric, index
// kind, ANN params). Text format (LF; CRLF accepted on load):
//
//   xvector-manifest 1
//   <name> <dim> <metric_code> <kind_code> <m> <ef_construction> <ef_search>
//   ...
//
// `xvector-manifest 1` is the format header. `name` is 1..64 chars from
// [A-Za-z0-9_.-] (no spaces); metric/kind codes are the stable codes from
// `types.metric` / `index.ann_index` (part of the on-disk format).
//
// Persist is whole-file and ATOMIC: the text lands in `<path>.tmp` and is
// swapped over the target with io.rename, so a crash at any point leaves
// either the previous or the new complete file, never a torn one. All
// entries are validated BEFORE anything is written; an invalid entry (bad
// name, dim < 1, invalid params) makes persist fail with the target
// untouched.
//
// Load is byte-level and torn-tail tolerant: a missing, garbage, or
// headerless file is invalid (valid=false); a truncated or malformed file
// yields the longest prefix of COMPLETE valid entries (a malformed line ends
// the prefix). The file is never handled as a Str (defense in depth, the
// XVC-C-11 family); names are rebuilt from their token bytes.

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.vector.primitives;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal_file;

// One collection's durable configuration.
pub type RegistryEntry = {
  name: Str;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

// The whole registry. valid=false means missing/corrupt (never persisted or
// unreadable); a valid registry may still have zero entries.
pub type CollectionRegistry = {
  valid: Bool;
  version: Int;
  entries: Vec[RegistryEntry];
}

pub fn registry_entry_new(name: Str, dim: Int, metric: DistanceMetric, kind: AnnIndexKind, params: AnnParams) -> RegistryEntry {
  return RegistryEntry{
    name: name,
    dim: dim,
    metric: metric,
    kind: kind,
    m: params.m,
    ef_construction: params.ef_construction,
    ef_search: params.ef_search,
  };
}

pub fn registry_new() -> CollectionRegistry {
  var reg = CollectionRegistry{ valid: true, version: 1, entries: Vec[RegistryEntry].new() };
  return reg;
}

pub fn registry_add(reg: &mut CollectionRegistry, entry: RegistryEntry) {
  reg.entries.push(entry);
}

// Collection names: 1..64 chars from [A-Za-z0-9_.-]. Anything else is a loud
// persist failure (never a silently ambiguous file). Str is taken BY VALUE:
// `&Str` parameters mislower on v0.64.2 (unknown type -> i64 warning).
pub fn manifest_name_valid(name: Str) -> Bool {
  var b = slice.str_bytes(name);
  if b.len() < 1 || b.len() > 64 { return false; }
  var i: Int = 0;
  while i < b.len() {
    if !name_char_ok(b[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn name_char_ok(c: UInt8) -> Bool {
  if c >= 65 && c <= 90 { return true; }    // A-Z
  if c >= 97 && c <= 122 { return true; }   // a-z
  if c >= 48 && c <= 57 { return true; }    // 0-9
  if c == 95 || c == 45 || c == 46 { return true; }   // _ - .
  return false;
}

fn entry_valid(e: &RegistryEntry) -> Bool {
  if !manifest_name_valid(e.name) { return false; }
  if e.dim < 1 { return false; }
  var p = AnnParams{ m: e.m, ef_construction: e.ef_construction, ef_search: e.ef_search };
  if !ann_params_valid(&p) { return false; }
  return true;
}

// Whole-file atomic write: `<path>.tmp` then io.rename. False (target
// untouched) when any entry is invalid or on any IO error.
pub fn manifest_persist(reg: &CollectionRegistry, path: Str) -> Bool {
  var i: Int = 0;
  while i < reg.entries.len() {
    if !entry_valid(&reg.entries[i]) { return false; }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  append_bytes(&mut out, "xvector-manifest 1\n");
  i = 0;
  while i < reg.entries.len() {
    var e = reg.entries[i];
    append_bytes(&mut out, e.name);
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(e.dim));
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(metric_code(e.metric)));
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(ann_kind_code(e.kind)));
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(e.m));
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(e.ef_construction));
    append_bytes(&mut out, " ");
    append_bytes(&mut out, convert.int_to_string(e.ef_search));
    append_bytes(&mut out, "\n");
    i = i + 1;
  }
  var tmp = path + ".tmp";
  var wres = io.write_file_bytes(tmp, &out);
  match wres {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  var rres = io.rename(tmp, path);
  match rres {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Load the registry: invalid on a missing / garbage / headerless file; the
// longest prefix of complete valid entries on a truncated or malformed tail
// (a malformed line ends the prefix; valid=true is committed once the header
// parses, so a valid-but-empty registry is distinguishable from an invalid
// file).
pub fn manifest_load(path: Str) -> CollectionRegistry {
  var reg = CollectionRegistry{ valid: false, version: 0, entries: Vec[RegistryEntry].new() };
  if !io.file_exists(path) { return reg; }
  var fs = io.file_size(path);
  var sz: Int = -1;
  match fs {
    Some(n) => { sz = n; }
    None => { return reg; }
  }
  // Shortest valid manifest: the 19-byte header line. Reads below that are
  // skipped entirely (also avoids the tiny-file read defect, XVC-C-12).
  if sz < 19 { return reg; }
  var rb = io.read_file_bytes(path);
  var b = Vec[UInt8].new();
  match rb {
    Ok(x) => { b = x; }
    Err(_) => { return reg; }
  }
  var hdr = slice.str_bytes("xvector-manifest 1");
  if b.len() < hdr.len() + 1 { return reg; }
  var hi: Int = 0;
  while hi < hdr.len() {
    if b[hi] != hdr[hi] { return reg; }
    hi = hi + 1;
  }
  var pos: Int = hdr.len();
  if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
  if pos >= b.len() || b[pos] != 10 { return reg; }
  pos = pos + 1;
  reg.valid = true;
  reg.version = 1;
  var stop: Bool = false;
  while pos < b.len() && !stop {
    var tok = Vec[UInt8].new();
    var bad: Bool = false;
    while pos < b.len() && b[pos] != 32 && !bad {
      if tok.len() >= 64 || !name_char_ok(b[pos]) {
        bad = true;
      } else {
        tok.push(b[pos]);
        pos = pos + 1;
      }
    }
    if !bad && tok.len() == 0 { bad = true; }
    if !bad {
      if pos < b.len() && b[pos] == 32 { pos = pos + 1; }
      else { bad = true; }
    }
    var vals = Vec[Int].new();
    var fi: Int = 0;
    while fi < 6 && !bad {
      var r = parse_int_at(b, pos);
      if !r.ok {
        bad = true;
      } else {
        vals.push(r.value);
        pos = r.pos;
        if fi < 5 {
          if pos < b.len() && b[pos] == 32 { pos = pos + 1; }
          else { bad = true; }
        }
      }
      fi = fi + 1;
    }
    if !bad {
      if pos < b.len() && b[pos] == 13 { pos = pos + 1; }
      if pos < b.len() && b[pos] == 10 { pos = pos + 1; }
      else { bad = true; }
    }
    if bad {
      stop = true;
    } else {
      var dm: Int = vals[0];
      var mc: Int = vals[1];
      var kc: Int = vals[2];
      if dm < 1 || mc < 1 || mc > 3 || kc < 1 || kc > 3 {
        stop = true;
      } else {
        var p = AnnParams{ m: vals[3], ef_construction: vals[4], ef_search: vals[5] };
        if !ann_params_valid(&p) {
          stop = true;
        } else {
          var e = registry_entry_new(Str::from_utf8(&tok), dm, metric_from_code(mc), ann_kind_from_code(kc), p);
          reg.entries.push(e);
        }
      }
    }
  }
  return reg;
}
