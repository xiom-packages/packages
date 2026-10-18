// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: manifest file (M-D2 collection registry). Persists registries to
// real files under out/, then verifies: multi-entry roundtrip (names, dim,
// metric, index kind, ANN params), overwrite, invalid-name/params refusal
// with the target untouched, atomic temp+rename behaviour (no temp left;
// staged-complete and partial temps are never the readable state),
// byte-truncation sweep (longest complete-entry prefix; header-only = valid
// empty; truncated header = invalid), malformed lines stopping the prefix,
// engine save + open paths (file registry wins, in-WAL manifest migration
// fallback, caller fallback when neither exists), and a 500-entry scale
// guard for the linear byte builder. Exit = failed checks.

module probe_manifest_file

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.durability.wal;
use xiom.vector.durability.manifest_file;
use xiom.vectors;
use xiom.vector.payload.payload;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, coords: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 4001) as Float32;
    coords.push(c / 1000.0 - 2.0);
    i = i + 1;
  }
  return s;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.set(i, coords[i]);
    i = i + 1;
  }
  return v;
}

fn entry_eq(a: &RegistryEntry, b: &RegistryEntry) -> Bool {
  if !(a.name == b.name) { return false; }
  if a.dim != b.dim { return false; }
  if a.metric != b.metric { return false; }
  if a.kind != b.kind { return false; }
  if a.m != b.m { return false; }
  if a.ef_construction != b.ef_construction { return false; }
  if a.ef_search != b.ef_search { return false; }
  return true;
}

// Loads `path`; requires the expected validity/version and exactly `want`
// entries, each field-equal to the corresponding entry of `full`.
fn loaded_prefix_ok(path: Str, full: &CollectionRegistry, want: Int, want_valid: Bool) -> Bool {
  var reg = manifest_load(path);
  if reg.valid != want_valid { return false; }
  if !want_valid { return reg.entries.len() == 0; }
  if reg.version != 1 { return false; }
  if reg.entries.len() != want { return false; }
  var i: Int = 0;
  while i < want {
    if !entry_eq(&reg.entries[i], &full.entries[i]) { return false; }
    i = i + 1;
  }
  return true;
}

// Byte offset just after the n-th newline (1-based); length if fewer.
fn byte_after_nth_newline(b: &Vec[UInt8], n: Int) -> Int {
  var seen: Int = 0;
  var i: Int = 0;
  while i < b.len() {
    if b[i] == 10 {
      seen = seen + 1;
      if seen == n { return i + 1; }
    }
    i = i + 1;
  }
  return b.len();
}

// Newline count within the first `count` bytes.
fn newlines_in(b: &Vec[UInt8], count: Int) -> Int {
  var seen: Int = 0;
  var i: Int = 0;
  var n: Int = count;
  if n > b.len() { n = b.len(); }
  while i < n {
    if b[i] == 10 { seen = seen + 1; }
    i = i + 1;
  }
  return seen;
}

fn write_slice(b: &Vec[UInt8], count: Int, path: Str) -> Bool {
  var out = Vec[UInt8].new();
  var i: Int = 0;
  var n: Int = count;
  if n > b.len() { n = b.len(); }
  while i < n {
    out.push(b[i]);
    i = i + 1;
  }
  var res = io.write_file_bytes(path, &out);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn hnsw_params() -> AnnParams {
  return AnnParams{ m: 8, ef_construction: 50, ef_search: 20 };
}

fn main() -> Int {
  io.println("=== xvector probe: manifest file ===");
  var fails: Int = 0;
  var dim: Int = 4;
  var pm = "out/manifest_probe.txt";
  var pt = "out/manifest_probe_torn.txt";
  var pg = "out/manifest_probe_garbage.txt";
  var pmiss = "out/manifest_probe_missing.txt";

  // 3-entry registry with distinct names/metrics/kinds/params. The params
  // helpers return FRESH values at every call: AnnParams is a move type, so
  // a stored local must not be passed twice.
  var p_def_vals = ann_params_default();
  var def_m: Int = p_def_vals.m;
  var p_hnsw_vals = hnsw_params();
  var hm: Int = p_hnsw_vals.m;
  var hc: Int = p_hnsw_vals.ef_construction;
  var he: Int = p_hnsw_vals.ef_search;
  var reg = registry_new();
  registry_add(&mut reg, registry_entry_new("docs-v1", 4, DistanceMetric.Cosine, AnnIndexKind.Hnsw, hnsw_params()));
  registry_add(&mut reg, registry_entry_new("images.v2", 128, DistanceMetric.Euclidean, AnnIndexKind.Flat, ann_params_default()));
  registry_add(&mut reg, registry_entry_new("tmp_3", 7, DistanceMetric.DotProduct, AnnIndexKind.Ivf, ann_params_default()));

  fails = check(manifest_persist(&reg, pm), "persist: 3-entry registry written", fails);
  var lr = manifest_load(pm);
  fails = check(lr.valid && lr.version == 1 && lr.entries.len() == 3,
    "roundtrip: valid, version 1, 3 entries", fails);
  var names_ok: Bool = false;
  if lr.entries.len() == 3 {
    names_ok = lr.entries[0].name == "docs-v1"
      && lr.entries[1].name == "images.v2"
      && lr.entries[2].name == "tmp_3";
  }
  fails = check(names_ok, "roundtrip: names exact", fails);
  fails = check(loaded_prefix_ok(pm, &reg, 3, true),
    "roundtrip: dim/metric/kind/params exact", fails);

  // Overwrite + empty registry (header-only is valid).
  var reg1 = registry_new();
  registry_add(&mut reg1, registry_entry_new("solo", 3, DistanceMetric.Euclidean, AnnIndexKind.Hnsw, hnsw_params()));
  fails = check(manifest_persist(&reg1, pm), "overwrite: 1-entry persist", fails);
  fails = check(loaded_prefix_ok(pm, &reg1, 1, true), "overwrite: old 3-entry file replaced", fails);
  var reg0 = registry_new();
  fails = check(manifest_persist(&reg0, pm) && loaded_prefix_ok(pm, &reg0, 0, true),
    "empty registry: header-only file persists and loads valid-empty", fails);
  fails = check(manifest_persist(&reg, pm), "restore: 3-entry registry re-persisted", fails);

  // Invalid entries are refused loudly; the target is untouched.
  var regbad = registry_new();
  registry_add(&mut regbad, registry_entry_new("has space", 4, DistanceMetric.Cosine, AnnIndexKind.Flat, ann_params_default()));
  fails = check(!manifest_persist(&regbad, pm), "bad name (space): persist refused", fails);
  fails = check(loaded_prefix_ok(pm, &reg, 3, true), "bad name: previous file untouched", fails);
  var regbad2 = registry_new();
  registry_add(&mut regbad2, registry_entry_new("", 4, DistanceMetric.Cosine, AnnIndexKind.Flat, ann_params_default()));
  fails = check(!manifest_persist(&regbad2, pm), "bad name (empty): persist refused", fails);
  var regbad3 = registry_new();
  registry_add(&mut regbad3, registry_entry_new("ok", 0, DistanceMetric.Cosine, AnnIndexKind.Flat, ann_params_default()));
  fails = check(!manifest_persist(&regbad3, pm), "bad dim (0): persist refused", fails);
  var regbad4 = registry_new();
  registry_add(&mut regbad4, registry_entry_new("ok", 4, DistanceMetric.Cosine, AnnIndexKind.Flat, AnnParams{ m: 0, ef_construction: 200, ef_search: 64 }));
  fails = check(!manifest_persist(&regbad4, pm), "bad ann params (m=0): persist refused", fails);

  // Atomic swap (M-D1 family): temp+rename; temps are never readable state.
  fails = check(!io.file_exists(pm + ".tmp"), "atomic: no .tmp remains after a persist", fails);
  var reg2 = registry_new();
  registry_add(&mut reg2, registry_entry_new("next", 5, DistanceMetric.Cosine, AnnIndexKind.Hnsw, hnsw_params()));
  fails = check(manifest_persist(&reg2, pm + ".tmp"),
    "atomic: stage complete temp (kill before rename)", fails);
  fails = check(loaded_prefix_ok(pm, &reg, 3, true),
    "atomic: target intact after interrupted persist", fails);
  fails = check(loaded_prefix_ok(pm + ".tmp", &reg2, 1, true),
    "atomic: staged temp holds the new registry", fails);
  var tmpb_res = io.read_file_bytes(pm + ".tmp");
  var tmpb = Vec[UInt8].new();
  match tmpb_res { Ok(b) => { tmpb = b; } Err(_) => { fails = fails + 1; } }
  var part = Vec[UInt8].new();
  var pi: Int = 0;
  var plim: Int = tmpb.len() / 2;
  while pi < plim { part.push(tmpb[pi]); pi = pi + 1; }
  match io.write_file_bytes(pm + ".tmp", &part) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  fails = check(loaded_prefix_ok(pm, &reg, 3, true),
    "atomic: partial temp cannot damage the target", fails);
  match io.remove_file(pm + ".tmp") { Ok(_) => {} Err(_) => { fails = fails + 1; } }

  // Engine save: a live Hnsw+Cosine config persisted through the facade
  // (D3: the whole registry; a legacy create names the collection "default").
  var eng = engine_new();
  create_collection(&mut eng, dim, DistanceMetric.Cosine);
  var s: Int = 991117;
  var i: Int = 1;
  while i <= 6 {
    var c = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c);
    upsert(&mut eng, i, vec_from_coords(&c));
    i = i + 1;
  }
  set_index(&mut eng, AnnIndexKind.Hnsw, hnsw_params());
  fails = check(save_manifest(&mut eng, pm), "engine save: manifest written", fails);
  var lre = manifest_load(pm);
  var eng_ok: Bool = lre.valid && lre.entries.len() == 1 && lre.entries[0].name == "default";
  if eng_ok {
    eng_ok = lre.entries[0].dim == dim
      && lre.entries[0].metric == DistanceMetric.Cosine
      && lre.entries[0].kind == AnnIndexKind.Hnsw
      && lre.entries[0].m == hm
      && lre.entries[0].ef_construction == hc
      && lre.entries[0].ef_search == he;
  }
  fails = check(eng_ok, "engine save: loaded entry equals the live config", fails);

  // Bare WAL (no manifest record): 6 inserts, dim 4.
  var wvecs = Vec[Vector].new();
  var wr = wal_writer_new();
  s = 424242;
  i = 1;
  while i <= 6 {
    var c2 = Vec[Float32].new();
    s = rand_coords(s, dim, &mut c2);
    var v = vec_from_coords(&c2);
    wvecs.push(v);
    wal_writer_append_payload(&mut wr, WalOpKind.Insert, i, 1, vector_encode(&v));
    i = i + 1;
  }

  // Open: the file registry governs when the WAL has no manifest.
  var ropen = open_engine(&wr, pm, dim, DistanceMetric.Euclidean);
  fails = check(engine_size(&ropen) == 6
    && ropen.index_kind == AnnIndexKind.Hnsw
    && ropen.metric == DistanceMetric.Cosine
    && ropen.ann.m == hm
    && ropen.ann.ef_construction == hc
    && ropen.ann.ef_search == he,
    "open: file registry governs (no WAL manifest)", fails);
  var qres = search(&ropen, &wvecs[2], 1);
  var hit_ok: Bool = false;
  match qres {
    Ok(h) => { if h.items.len() == 1 && h.items[0].id == 3 { hit_ok = true; } }
    Err(_) => {}
  }
  fails = check(hit_ok, "open: search works on the file-configured Hnsw graph", fails);

  // Conflicting WAL manifest (Euclidean Flat): the file registry wins.
  var eng2 = engine_new();
  create_collection(&mut eng2, dim, DistanceMetric.Euclidean);
  var rwin = open_engine(&eng2.wal, pm, dim, DistanceMetric.Euclidean);
  fails = check(rwin.metric == DistanceMetric.Cosine && rwin.index_kind == AnnIndexKind.Hnsw,
    "open: file registry wins over a conflicting WAL manifest", fails);

  // Migration fallbacks: missing / corrupt file -> in-WAL manifest.
  io.remove_file(pmiss);
  var rmiss = open_engine(&eng2.wal, pmiss, dim, DistanceMetric.Euclidean);
  fails = check(rmiss.metric == DistanceMetric.Euclidean && rmiss.index_kind == AnnIndexKind.Flat
    && rmiss.ann.m == def_m,
    "fallback: missing file -> in-WAL manifest", fails);
  var gbytes = slice.str_bytes("not a manifest\n");
  match io.write_file_bytes(pg, &gbytes) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var rcor = open_engine(&eng2.wal, pg, dim, DistanceMetric.Euclidean);
  fails = check(rcor.metric == DistanceMetric.Euclidean && rcor.index_kind == AnnIndexKind.Flat,
    "fallback: corrupt file -> in-WAL manifest", fails);

  // Neither source: caller dim/metric + Flat + default params.
  var rnone = open_engine(&wr, pmiss, dim, DistanceMetric.Euclidean);
  fails = check(rnone.metric == DistanceMetric.Euclidean && rnone.index_kind == AnnIndexKind.Flat
    && rnone.ann.m == def_m && engine_size(&rnone) == 6,
    "fallback: no file, no WAL manifest -> caller config", fails);

  // Registry-level degradation.
  var lmiss = manifest_load(pmiss);
  fails = check(!lmiss.valid && lmiss.entries.len() == 0, "missing file -> invalid empty registry", fails);
  fails = check(!manifest_load(pg).valid, "garbage header -> invalid registry", fails);
  var ebytes = Vec[UInt8].new();
  match io.write_file_bytes(pg, &ebytes) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var lempty = manifest_load(pg);
  fails = check(!lempty.valid && lempty.entries.len() == 0, "empty file -> invalid empty registry", fails);

  // Byte-truncation sweep: every prefix loads as a complete-entry prefix.
  fails = check(manifest_persist(&reg, pt), "torn: persist 3-entry registry", fails);
  var fbres = io.read_file_bytes(pt);
  var fb = Vec[UInt8].new();
  match fbres { Ok(b) => { fb = b; } Err(_) => { fails = fails + 1; } }
  var cuts = Vec[Int].new();
  cuts.push(0); cuts.push(1); cuts.push(10); cuts.push(18);
  cuts.push(19);
  cuts.push(30);
  cuts.push(byte_after_nth_newline(&fb, 2));
  cuts.push(byte_after_nth_newline(&fb, 3));
  cuts.push(fb.len() - 1);
  cuts.push(fb.len());
  var bad_cuts: Int = 0;
  var ci: Int = 0;
  while ci < cuts.len() {
    var cut: Int = cuts[ci];
    if !write_slice(&fb, cut, pt + ".cut") { bad_cuts = bad_cuts + 1; }
    var regc = manifest_load(pt + ".cut");
    var expected: Int = 0;
    var exp_valid: Bool = false;
    if cut >= 19 {
      exp_valid = true;
      expected = newlines_in(&fb, cut) - 1;
      if expected < 0 { expected = 0; }
    }
    if regc.valid != exp_valid { bad_cuts = bad_cuts + 1; }
    if regc.entries.len() != expected { bad_cuts = bad_cuts + 1; }
    var ei: Int = 0;
    while ei < regc.entries.len() {
      if ei >= reg.entries.len() {
        bad_cuts = bad_cuts + 1;
      } elif !entry_eq(&regc.entries[ei], &reg.entries[ei]) {
        bad_cuts = bad_cuts + 1;
      }
      ei = ei + 1;
    }
    io.println("    diag cut ci=" + convert.int_to_string(ci) + " len=" + convert.int_to_string(cut)
      + " entries=" + convert.int_to_string(regc.entries.len())
      + " expected=" + convert.int_to_string(expected)
      + " valid=" + convert.int_to_string(if regc.valid { 1 } else { 0 }));
    ci = ci + 1;
  }
  fails = check(bad_cuts == 0, "torn file: 10 cut points load as complete-entry prefixes", fails);
  fails = check(write_slice(&fb, fb.len(), pt + ".cut") && loaded_prefix_ok(pt + ".cut", &reg, 3, true),
    "full cut: complete file loads all 3 entries", fails);

  // Malformed entry lines stop the prefix (bad dim; bad name char).
  var reg12 = registry_new();
  registry_add(&mut reg12, registry_entry_new("one", 4, DistanceMetric.Cosine, AnnIndexKind.Hnsw, hnsw_params()));
  fails = check(manifest_persist(&reg12, pt), "malformed: seed 1-entry file", fails);
  var oneb_res = io.read_file_bytes(pt);
  var oneb = Vec[UInt8].new();
  match oneb_res { Ok(b) => { oneb = b; } Err(_) => { fails = fails + 1; } }
  var badb = slice.str_bytes("bad 0 1 1 1 1 1\n");
  var ji: Int = 0;
  while ji < badb.len() { oneb.push(badb[ji]); ji = ji + 1; }
  match io.write_file_bytes(pt, &oneb) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  fails = check(loaded_prefix_ok(pt, &reg12, 1, true),
    "malformed entry (dim 0): prefix keeps the valid entry", fails);
  fails = check(manifest_persist(&reg12, pt), "malformed: reseed 1-entry file", fails);
  var oneb2_res = io.read_file_bytes(pt);
  var oneb2 = Vec[UInt8].new();
  match oneb2_res { Ok(b) => { oneb2 = b; } Err(_) => { fails = fails + 1; } }
  var badb2 = slice.str_bytes("no/pe 4 1 2 8 50 20\n");
  ji = 0;
  while ji < badb2.len() { oneb2.push(badb2[ji]); ji = ji + 1; }
  match io.write_file_bytes(pt, &oneb2) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  fails = check(loaded_prefix_ok(pt, &reg12, 1, true),
    "malformed entry (bad name char): prefix keeps the valid entry", fails);

  // Scale guard for the linear byte builder: 500 entries round-trip exactly.
  var bigreg = registry_new();
  var bi: Int = 1;
  while bi <= 500 {
    registry_add(&mut bigreg, registry_entry_new("c" + convert.int_to_string(bi), bi, DistanceMetric.Euclidean, AnnIndexKind.Hnsw, hnsw_params()));
    bi = bi + 1;
  }
  fails = check(manifest_persist(&bigreg, pt), "scale: 500-entry registry persists", fails);
  var lbig = manifest_load(pt);
  var big_ok: Bool = lbig.valid && lbig.entries.len() == 500;
  if big_ok {
    big_ok = entry_eq(&lbig.entries[0], &bigreg.entries[0])
      && entry_eq(&lbig.entries[499], &bigreg.entries[499])
      && lbig.entries[499].name == "c500";
  }
  fails = check(big_ok, "scale: 500-entry roundtrip exact (first/last)", fails);

  io.remove_file(pm);
  io.remove_file(pt);
  io.remove_file(pt + ".cut");
  io.remove_file(pg);
  io.println("");
  io.println("probe_manifest_file: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
