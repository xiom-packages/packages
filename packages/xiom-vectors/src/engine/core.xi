// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine.core

// VectorEngine orchestrator: owns the flat store, the WAL, the collection
// config (dimension/metric), the counters and the payload store. The
// engine_* operations are the internal engine surface; the consumer-facing
// facade (xiom.vector.engine) delegates to them. Extracted from the
// consolidated engine in the final extraction wave (acyclic: core.shim <-
// engine.core <- engine facade).

use xiom.metrics;
use xiom.vector.core.shim;
use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.vector.primitives;
use xiom.vector.storage.vector_store;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.query.search_service;
use xiom.vector.query.pagination;
use xiom.vector.query.filter_plan;
use xiom.vector.query.search_request;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.durability.wal_segment;
use xiom.vector.durability.write_ahead_events;
use xiom.vector.durability.manifest_file;
use xiom.vector.segment.segment_file;

// ---- VectorEngine ----
// The flat store is always maintained (source of truth for ids/vectors);
// when `index_kind` is Hnsw, `graph` mirrors it for approximate search.
//
// D3 (multi-collection): the top-level fields materialize the ACTIVE
// collection; `collections` holds one full entry per collection in creation
// (cid) order -- the active collection's entry is refreshed from the live
// fields by `sync_active` before any registry-wide read or a switch. Data
// ops (upsert/search/...) only touch the live fields; `active_cid` is the
// collection id stamped into WAL data records and `active_name` names it in
// v2 manifest records.
pub type VectorEngine = {
  store: VectorIndex;
  graph: HNSWGraph;
  index_kind: AnnIndexKind;
  ann: AnnParams;
  metric: DistanceMetric;
  dimension: Int;
  created: Bool;
  wal: WalWriter;
  wal_seg_path: Str;
  wal_seg_frontier: Int;
  wal_seg_needs_heal: Bool;
  wal_ckpt_path: Str;
  ckpt_every: Int;
  commits_since_ckpt: Int;
  upserts: Counter;
  deletes: Counter;
  next_collection: Int;
  payloads: PayloadStore;
  collections: Vec[CollectionEntry];
  active_idx: Int;
  active_cid: Int;
  active_name: Str;
  // M-D7 mirrors of the active collection's sealed registry + tombstones,
  // the runtime segment cache, and the opt-in roll policy/state.
  sealed: Vec[SealedEntry];
  tombstones: Vec[Int];
  sealed_cache: Vec[SealedCacheEntry];
  sealed_next_id: Int;
  seal_every: Int;
  seal_dir: Str;
  sealed_missing: Int;
}

// One named collection's full state (registry entry). The active collection
// is also materialized in the VectorEngine's top-level fields.
pub type CollectionEntry = {
  cid: Int;
  name: Str;
  store: VectorIndex;
  payloads: PayloadStore;
  graph: HNSWGraph;
  index_kind: AnnIndexKind;
  ann: AnnParams;
  dimension: Int;
  metric: DistanceMetric;
  sealed: Vec[SealedEntry];
  tombstones: Vec[Int];
}

// The registry names list (struct wrapper, the SearchHits discipline:
// Result-free Vec[Str] payloads stay behind a named shape).
pub type CollectionList = {
  names: Vec[Str];
}

// M-D7: one registered sealed segment. Registry metadata only (data lives in
// the file and, once loaded, in the engine's sealed cache).
pub type SealedEntry = {
  seg_id: Int;
  points: Int;
  head_lsn: Int;
  has_sq: Bool;
  path: Str;
}

// M-D7 runtime cache entry: a loaded sealed segment (full in-RAM copy; no
// mmap). `cid` scopes it to its collection.
pub type SealedCacheEntry = {
  cid: Int;
  seg_id: Int;
  ss: SealedSegment;
}

// M-D7 recovery accumulators (cid-tagged, because replay spans collections).
pub type SealedReg = {
  cid: Int;
  entry: SealedEntry;
}

pub type TombReg = {
  cid: Int;
  id: Int;
}

pub type ParsedSealed = {
  valid: Bool;
  kind: Int;
  entry: SealedEntry;
}

// M-D7 sealed-entry words: [kind, seg_id, points, head_lsn, has_sq,
// path_len, bytes...]. kind 1 = attach (roll/checkpoint); kind 2 = REPLACE
// the cid's existing entries (compaction).
fn sealed_words(kind: Int, seg_id: Int, points: Int, head_lsn: Int, has_sq: Bool, path: Str) -> Vec[Int] {
  var w = Vec[Int].new();
  w.push(kind);
  w.push(seg_id);
  w.push(points);
  w.push(head_lsn);
  if has_sq { w.push(1); } else { w.push(0); }
  var nb = slice.str_bytes(path);
  w.push(nb.len());
  var i: Int = 0;
  while i < nb.len() {
    w.push(nb[i] as Int);
    i = i + 1;
  }
  return w;
}

fn parse_sealed_words(words: &Vec[Int]) -> ParsedSealed {
  var bad = SealedEntry{ seg_id: 0, points: 0, head_lsn: 0, has_sq: false, path: "" };
  if words.len() < 7 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  var kind: Int = words[0];
  if kind != 1 && kind != 2 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  var seg_id: Int = words[1];
  var points: Int = words[2];
  var head: Int = words[3];
  var hs: Int = words[4];
  var nlen: Int = words[5];
  if seg_id < 1 || points < 0 || head < 0 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  if hs != 0 && hs != 1 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  if nlen < 1 || nlen > 512 || words.len() != 6 + nlen { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  var nb = Vec[UInt8].new();
  var i: Int = 0;
  while i < nlen {
    var b: Int = words[6 + i];
    if b < 1 || b > 255 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
    nb.push(b as UInt8);
    i = i + 1;
  }
  var path = Str::from_utf8(&nb);
  if path.len() == 0 { return ParsedSealed{ valid: false, kind: 0, entry: bad }; }
  return ParsedSealed{
    valid: true,
    kind: kind,
    entry: SealedEntry{ seg_id: seg_id, points: points, head_lsn: head, has_sq: hs == 1, path: path },
  };
}

fn sealed_acc_add(acc: &mut Vec[SealedReg], cid: Int, e: SealedEntry) {
  acc.push(SealedReg{ cid: cid, entry: e });
}

// kind-2 semantics: drop the cid's existing entries, then attach. Functional
// (returns a rebuilt Vec) because in-place Vec truncation is not available.
fn sealed_acc_replaced(acc: &Vec[SealedReg], cid: Int, e: SealedEntry) -> Vec[SealedReg] {
  var keep = Vec[SealedReg].new();
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid != cid { keep.push(acc[i]); }
    i = i + 1;
  }
  keep.push(SealedReg{ cid: cid, entry: e });
  return keep;
}

fn sealed_for_cid(acc: &Vec[SealedReg], cid: Int) -> Vec[SealedEntry] {
  var out = Vec[SealedEntry].new();
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid == cid { out.push(acc[i].entry); }
    i = i + 1;
  }
  return out;
}

fn tomb_add(acc: &mut Vec[TombReg], cid: Int, id: Int) {
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid == cid && acc[i].id == id { return; }
    i = i + 1;
  }
  acc.push(TombReg{ cid: cid, id: id });
}

fn tombstones_for_cid(acc: &Vec[TombReg], cid: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid == cid { out.push(acc[i].id); }
    i = i + 1;
  }
  return out;
}

fn tombs_acc_has(acc: &Vec[TombReg], cid: Int, id: Int) -> Bool {
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid == cid && acc[i].id == id { return true; }
    i = i + 1;
  }
  return false;
}

// Replay symmetry with the live upsert: a resurrection clears its shadow.
fn tombs_acc_without(acc: &Vec[TombReg], cid: Int, id: Int) -> Vec[TombReg] {
  var out = Vec[TombReg].new();
  var i: Int = 0;
  while i < acc.len() {
    if acc[i].cid != cid || acc[i].id != id { out.push(acc[i]); }
    i = i + 1;
  }
  return out;
}

fn tombs_contain(ts: &Vec[Int], id: Int) -> Bool {
  var i: Int = 0;
  while i < ts.len() {
    if ts[i] == id { return true; }
    i = i + 1;
  }
  return false;
}

// Resurrection: a re-upsert clears the id's tombstone shadow (invariant:
// tombstones and the active store are disjoint at every checkpoint, so the
// emitted Delete records can never remove a live id on replay).
fn tombs_without(ts: &Vec[Int], id: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i: Int = 0;
  while i < ts.len() {
    if ts[i] != id { out.push(ts[i]); }
    i = i + 1;
  }
  return out;
}

pub fn engine_new() -> VectorEngine {
  return VectorEngine{
    store: index_new(1),
    graph: hnsw_new(16, 4.0),
    index_kind: AnnIndexKind.Flat,
    ann: ann_params_default(),
    metric: DistanceMetric.Euclidean,
    dimension: 0,
    created: false,
    wal: wal_writer_new(),
    wal_seg_path: "",
    wal_seg_frontier: 0,
    wal_seg_needs_heal: false,
    wal_ckpt_path: "",
    ckpt_every: 0,
    commits_since_ckpt: 0,
    // Stat counters ride the xiom.metrics package (adoption 2026-10-10;
    // see docs/XIOM-METRICS-ADOPTION.md). The shim Counter was retired so
    // the program carries a single Counter type (XVC-C-14 layout shadow).
    upserts: metric_counter_new(),
    deletes: metric_counter_new(),
    next_collection: 1,
    payloads: payload_store_new(),
    collections: Vec[CollectionEntry].new(),
    active_idx: -1,
    active_cid: 0,
    active_name: "",
    sealed: Vec[SealedEntry].new(),
    tombstones: Vec[Int].new(),
    sealed_cache: Vec[SealedCacheEntry].new(),
    sealed_next_id: 1,
    seal_every: 0,
    seal_dir: "",
    sealed_missing: 0,
  };
}

// ---- Collection registry (durable config, D3) ----
// The registry maps collection ids to names + configuration. It travels in
// the WAL as ManifestUpdate records in three payload families:
//   v1 legacy: [1, dim, mc, kc, m, efc, efs]              (no name; cid 1)
//   v2 config: [2, name_len, name..., dim, mc, kc, m, efc, efs]
//                                                         (record value = cid)
//   v3 drop:   [3, name_len, name...]                     (record value = cid)
// and in the manifest file (D2) as one `<name> <dim> <mc> <kc> <m> <efc>
// <efs>` line per collection. Malformed records are ignored; legacy v1
// records upsert the canonical "default" collection (cid 1).
pub type ManifestInfo = {
  valid: Bool;
  version: Int;
  name: Str;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

fn empty_manifest_info() -> ManifestInfo {
  return ManifestInfo{
    valid: false,
    version: 0,
    name: "",
    dim: 0,
    metric: DistanceMetric.Euclidean,
    kind: AnnIndexKind.Flat,
    m: 0,
    ef_construction: 0,
    ef_search: 0,
  };
}

fn parse_manifest_info(words: &Vec[Int]) -> ManifestInfo {
  var mf = empty_manifest_info();
  if words.len() < 1 { return mf; }
  var ver: Int = words[0];
  if ver == 1 {
    if words.len() != 7 { return mf; }
    var d: Int = words[1];
    var mc: Int = words[2];
    var kc: Int = words[3];
    if d < 1 || mc < 1 || mc > 3 || kc < 1 || kc > 3 { return mf; }
    var p = AnnParams{ m: words[4], ef_construction: words[5], ef_search: words[6] };
    if !ann_params_valid(&p) { return mf; }
    mf.name = "default";
    mf.dim = d;
    mf.metric = metric_from_code(mc);
    mf.kind = ann_kind_from_code(kc);
    mf.m = p.m;
    mf.ef_construction = p.ef_construction;
    mf.ef_search = p.ef_search;
    mf.valid = true;
    mf.version = 1;
    return mf;
  }
  if ver == 2 {
    if words.len() < 3 { return mf; }
    var nlen: Int = words[1];
    if nlen < 1 || nlen > 64 { return mf; }
    if words.len() != 8 + nlen { return mf; }
    var nb = Vec[UInt8].new();
    var i: Int = 0;
    while i < nlen {
      var b: Int = words[2 + i];
      if b < 0 || b > 255 { return mf; }
      nb.push(b as UInt8);
      i = i + 1;
    }
    var nm = Str::from_utf8(&nb);
    if !manifest_name_valid(nm) { return mf; }
    var d2: Int = words[2 + nlen];
    var mc2: Int = words[3 + nlen];
    var kc2: Int = words[4 + nlen];
    if d2 < 1 || mc2 < 1 || mc2 > 3 || kc2 < 1 || kc2 > 3 { return mf; }
    var p2 = AnnParams{ m: words[5 + nlen], ef_construction: words[6 + nlen], ef_search: words[7 + nlen] };
    if !ann_params_valid(&p2) { return mf; }
    mf.name = nm;
    mf.dim = d2;
    mf.metric = metric_from_code(mc2);
    mf.kind = ann_kind_from_code(kc2);
    mf.m = p2.m;
    mf.ef_construction = p2.ef_construction;
    mf.ef_search = p2.ef_search;
    mf.valid = true;
    mf.version = 2;
    return mf;
  }
  if ver == 3 {
    if words.len() < 3 { return mf; }
    var nlen3: Int = words[1];
    if nlen3 < 1 || nlen3 > 64 { return mf; }
    if words.len() != 2 + nlen3 { return mf; }
    var nb3 = Vec[UInt8].new();
    var i3: Int = 0;
    while i3 < nlen3 {
      var b3: Int = words[2 + i3];
      if b3 < 0 || b3 > 255 { return mf; }
      nb3.push(b3 as UInt8);
      i3 = i3 + 1;
    }
    var nm3 = Str::from_utf8(&nb3);
    if !manifest_name_valid(nm3) { return mf; }
    mf.name = nm3;
    mf.valid = true;
    mf.version = 3;
    return mf;
  }
  return mf;
}

// v2 config record words (record value carries the collection id).
fn manifest_words(name: Str, dim: Int, metric: DistanceMetric, kind: AnnIndexKind, params: AnnParams) -> Vec[Int] {
  var words = Vec[Int].new();
  words.push(2);
  var nb = slice.str_bytes(name);
  words.push(nb.len());
  var i: Int = 0;
  while i < nb.len() {
    words.push(nb[i] as Int);
    i = i + 1;
  }
  words.push(dim);
  words.push(metric_code(metric));
  words.push(ann_kind_code(kind));
  words.push(params.m);
  words.push(params.ef_construction);
  words.push(params.ef_search);
  return words;
}

fn log_manifest(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) {
  var words = manifest_words(eng.active_name, eng.dimension, eng.metric, kind, params);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, eng.active_cid, words);
}

// Snapshot the live (active) collection into its registry entry. Called
// before any registry-wide read and before switching away; entry reads are
// copies (validated on v0.64.2), so this is a plain read-modify-write-back.
fn sync_active(eng: &mut VectorEngine) {
  if eng.active_idx < 0 { return; }
  var i: Int = eng.active_idx;
  var e = eng.collections[i];
  e.cid = eng.active_cid;
  e.name = eng.active_name;
  e.store = eng.store;
  e.payloads = eng.payloads;
  e.graph = eng.graph;
  e.index_kind = eng.index_kind;
  e.ann = eng.ann;
  e.dimension = eng.dimension;
  e.metric = eng.metric;
  e.sealed = eng.sealed;
  e.tombstones = eng.tombstones;
  eng.collections[i] = e;
}

// Materialize registry entry `idx` as the live active collection.
fn load_active(eng: &mut VectorEngine, idx: Int) {
  var e = eng.collections[idx];
  eng.store = e.store;
  eng.payloads = e.payloads;
  eng.graph = e.graph;
  eng.index_kind = e.index_kind;
  eng.ann = e.ann;
  eng.dimension = e.dimension;
  eng.metric = e.metric;
  eng.created = true;
  eng.active_idx = idx;
  eng.active_cid = e.cid;
  eng.active_name = e.name;
  eng.sealed = e.sealed;
  eng.tombstones = e.tombstones;
  // M-D7: every registered sealed source must be queryable -- load any
  // not-yet-cached segment now (whole-file read; no mmap). An unreadable
  // file bumps sealed_missing and stays out of the union (visible in
  // engine_sealed_missing, never silent).
  sealed_cache_ensure(eng);
}

// Load registry sealed entries of the active cid that are not in the cache.
fn sealed_cache_ensure(eng: &mut VectorEngine) {
  var i: Int = 0;
  while i < eng.sealed.len() {
    var se = eng.sealed[i];
    var have: Bool = false;
    var ci: Int = 0;
    while ci < eng.sealed_cache.len() {
      if eng.sealed_cache[ci].cid == eng.active_cid && eng.sealed_cache[ci].seg_id == se.seg_id { have = true; }
      ci = ci + 1;
    }
    if !have {
      var ss = segment_file_load(se.path);
      if ss.valid {
        eng.sealed_cache.push(SealedCacheEntry{ cid: eng.active_cid, seg_id: se.seg_id, ss: ss });
      } else {
        eng.sealed_missing = eng.sealed_missing + 1;
      }
    }
    i = i + 1;
  }
}

// Forget the live view (dropping the last collection leaves an engine that
// is ready for a fresh create).
fn reset_active(eng: &mut VectorEngine) {
  eng.store = index_new(1);
  eng.graph = hnsw_new(16, 4.0);
  eng.index_kind = AnnIndexKind.Flat;
  eng.ann = ann_params_default();
  eng.metric = DistanceMetric.Euclidean;
  eng.dimension = 0;
  eng.created = false;
  eng.payloads = payload_store_new();
  eng.active_idx = -1;
  eng.active_cid = 0;
  eng.active_name = "";
}

fn collection_find(eng: &VectorEngine, name: Str) -> Int {
  var i: Int = 0;
  while i < eng.collections.len() {
    if eng.collections[i].name == name { return i; }
    i = i + 1;
  }
  return -1;
}

pub fn engine_collection_count(eng: &VectorEngine) -> Int {
  return eng.collections.len();
}

pub fn engine_list_collections(eng: &VectorEngine) -> CollectionList {
  var names = Vec[Str].new();
  var i: Int = 0;
  while i < eng.collections.len() {
    names.push(eng.collections[i].name);
    i = i + 1;
  }
  return CollectionList{ names: names };
}

// Create a named collection (empty), make it active, and append its v2
// manifest record first (WAL-before-ack). Rejects invalid or duplicate
// names and invalid dimensions; the previous active collection is parked
// with its state intact.
pub fn engine_create_named(eng: &mut VectorEngine, name: Str, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  if !manifest_name_valid(name) {
    return Err(CoreError.InvalidInput("invalid collection name"));
  }
  if collection_find(eng, name) >= 0 {
    return Err(CoreError.InvalidInput("collection exists"));
  }
  var cid: Int = eng.next_collection;
  eng.next_collection = eng.next_collection + 1;
  var params = ann_params_default();
  var words = manifest_words(name, dim, metric, AnnIndexKind.Flat, params);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, cid, words);
  sync_active(eng);
  var e = CollectionEntry{
    cid: cid,
    name: name,
    store: index_new(dim),
    payloads: payload_store_new(),
    graph: hnsw_new(16, 4.0),
    index_kind: AnnIndexKind.Flat,
    ann: params,
    dimension: dim,
    metric: metric,
    sealed: Vec[SealedEntry].new(),
    tombstones: Vec[Int].new(),
  };
  eng.collections.push(e);
  load_active(eng, eng.collections.len() - 1);
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(collection_id(cid));
}

// Make a named collection active (no-op when it already is).
pub fn engine_select(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.InvalidInput("collection not found"));
  }
  if idx == eng.active_idx {
    return Ok(true);
  }
  sync_active(eng);
  load_active(eng, idx);
  return Ok(true);
}

// Drop a named collection: log the v3 drop record first (WAL-before-ack),
// remove the entry, and fix the active view (select the first remaining
// collection when the dropped one was active).
pub fn engine_drop(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.InvalidInput("collection not found"));
  }
  var cid: Int = eng.collections[idx].cid;
  var words = Vec[Int].new();
  words.push(3);
  var nb = slice.str_bytes(name);
  words.push(nb.len());
  var i: Int = 0;
  while i < nb.len() {
    words.push(nb[i] as Int);
    i = i + 1;
  }
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, cid, words);
  var j: Int = idx;
  while j < eng.collections.len() - 1 {
    eng.collections[j] = eng.collections[j + 1];
    j = j + 1;
  }
  eng.collections.pop();
  if idx == eng.active_idx {
    reset_active(eng);
    if eng.collections.len() > 0 {
      load_active(eng, 0);
    }
  } elif idx < eng.active_idx {
    eng.active_idx = eng.active_idx - 1;
  }
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(true);
}

// Persist the whole registry (one entry per collection, cid order): whole-
// file + atomic rename via the D2 manifest-file codec. False on IO error.
pub fn engine_manifest_save(eng: &mut VectorEngine, path: Str) -> Bool {
  sync_active(eng);
  var reg = registry_new();
  var i: Int = 0;
  while i < eng.collections.len() {
    var e = eng.collections[i];
    registry_add(&mut reg, registry_entry_new(e.name, e.dimension, e.metric, e.index_kind, e.ann));
    i = i + 1;
  }
  return manifest_persist(&reg, path);
}

// Seal the active collection as an immutable segment file (M-D4): vectors +
// payloads + the Hnsw graph codec, whole-file + atomic rename. The segment
// lifecycle is driven through the real transition table
// (Mutable -> Sealing -> Sealed) before the file is written.
pub fn engine_seal_segment(eng: &mut VectorEngine, seg_id: Int, path: Str) -> Result[Bool, CoreError]
  requires: eng.created
{
  if seg_id < 1 {
    return Err(CoreError.InvalidInput("invalid segment id"));
  }
  var ss = sealed_segment_new(seg_id, eng.active_cid, eng.dimension, eng.metric, eng.index_kind, eng.ann);
  if !sealed_segment_seal(&mut ss) {
    return Err(CoreError.InvalidState("segment lifecycle transition failed"));
  }
  ss.store = eng.store;
  ss.payloads = eng.payloads;
  if eng.index_kind == AnnIndexKind.Hnsw {
    ss.graph = eng.graph;
    ss.has_graph = true;
  }
  if !segment_file_persist(&ss, path) {
    return Err(CoreError.IOFailure("segment persist failed"));
  }
  return Ok(true);
}

// Restore the active collection's contents from a sealed segment file
// (M-D4). The segment must belong to the active collection (cid) and match
// its dimension and metric. The WAL is re-checkpointed AFTER the swap, so a
// reopen replays the restored state (durable before the ack).
pub fn engine_restore_segment(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError]
  requires: eng.created
{
  var ss = segment_file_load(path);
  if !ss.valid {
    return Err(CoreError.Corruption("segment file invalid"));
  }
  if ss.cid != eng.active_cid || ss.dim != eng.dimension || ss.metric != eng.metric {
    return Err(CoreError.InvalidInput("segment does not match the active collection"));
  }
  eng.store = ss.store;
  eng.payloads = ss.payloads;
  var params = AnnParams{ m: ss.m, ef_construction: ss.ef_construction, ef_search: ss.ef_search };
  if ss.kind == AnnIndexKind.Hnsw && ss.has_graph {
    eng.graph = ss.graph;
    eng.index_kind = AnnIndexKind.Hnsw;
    eng.ann = params;
  } else {
    apply_index(&mut eng, ss.kind, params);
  }
  engine_checkpoint_from(eng, eng.wal.next_lsn);
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(true);
}

// M-D7 roll: seal the ACTIVE collection's contents into an immutable segment
// file (same codec; SQ armed when trainable), register the entry, keep the
// written segment in the runtime cache (queries never re-read the file),
// clear the active store/graph/payloads (move semantics; configuration
// kept), and log a SegmentSeal record + commit (fsync-before-ack in durable
// mode). Returns the assigned segment id. The existing copy-out
// `seal_segment` API and its probes are untouched.
pub fn engine_roll_segment(eng: &mut VectorEngine, path: Str) -> Result[Int, CoreError]
  requires: eng.created
{
  if eng.store.ids.len() == 0 {
    return Err(CoreError.InvalidState("active collection is empty"));
  }
  if path.len() == 0 {
    return Err(CoreError.InvalidInput("empty segment path"));
  }
  var seg_id: Int = eng.sealed_next_id;
  var head: Int = wal_writer_current_lsn(&eng.wal);
  var ss = sealed_segment_new(seg_id, eng.active_cid, eng.dimension, eng.metric, eng.index_kind, eng.ann);
  if !sealed_segment_seal(&mut ss) {
    return Err(CoreError.InvalidState("segment lifecycle transition failed"));
  }
  ss.store = eng.store;
  ss.payloads = eng.payloads;
  if eng.index_kind == AnnIndexKind.Hnsw {
    ss.graph = eng.graph;
    ss.has_graph = true;
  }
  let _sq = sealed_segment_enable_sq(&mut ss);
  if !segment_file_persist(&ss, path) {
    return Err(CoreError.IOFailure("segment persist failed"));
  }
  var points: Int = ss.store.ids.len();
  var has_sq: Bool = ss.has_sq;
  eng.sealed.push(SealedEntry{ seg_id: seg_id, points: points, head_lsn: head, has_sq: has_sq, path: path });
  eng.sealed_cache.push(SealedCacheEntry{ cid: eng.active_cid, seg_id: seg_id, ss: ss });
  eng.sealed_next_id = eng.sealed_next_id + 1;
  // Move: clear the active data, keep the configuration.
  eng.store = index_new(eng.dimension);
  eng.graph = hnsw_new(eng.ann.m, 4.0);
  hnsw_set_ef_construction(&mut eng.graph, eng.ann.ef_construction);
  eng.payloads = payload_store_new();
  var words = sealed_words(1, seg_id, points, head, has_sq, path);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.SegmentSeal, 0, eng.active_cid, words);
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(seg_id);
}

// L-2 collection move -- EXPORT half (2026-10-16; COMPACTION-AWARE since
// L-5). Select the named collection and materialize its FULL live state
// as ONE segment artifact at `path`: a plain active store is rolled
// directly; a collection with pre-existing sealed segments (auto-roll
// policy or an earlier export) is merged through the D7 compaction path
// (every sealed entry + the active remainder, tombstones applied,
// active-wins) -- bit-exact with the pre-export union. The source stays
// queryable through the sealed registry in both paths. Empty collections
// are refused. The artifact carries the integrity footer; the attach
// half refuses truncated/corrupt copies. Returns the assigned segment id.
pub fn engine_export_collection(eng: &mut VectorEngine, name: Str, path: Str) -> Result[Int, CoreError]
  requires: eng.created
{
  match engine_select(eng, name) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  if eng.sealed.len() > 0 {
    return engine_compact_sealed(eng, path);
  }
  if eng.store.ids.len() == 0 {
    return Err(CoreError.InvalidState("collection is empty"));
  }
  return engine_roll_segment(eng, path);
}

// L-2 collection move -- ATTACH half (2026-10-16). Install a segment
// artifact into the ACTIVE collection (which the caller created with
// matching dim/metric). Unlike restore_segment this does NOT require a
// cid match (the artifact comes from another home) and it REQUIRES a
// verified integrity footer (declared point count + crc32), so a
// truncated or corrupted artifact copy can never attach silently.
// Re-checkpoints + commits (durable before the ack).
pub fn engine_attach_segment(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError]
  requires: eng.created
{
  var ss = segment_file_load(path);
  if !ss.valid {
    return Err(CoreError.Corruption("segment file invalid"));
  }
  if !ss.footer_seen || !ss.footer_ok {
    return Err(CoreError.Corruption("segment integrity footer missing or mismatched"));
  }
  if ss.dim != eng.dimension || ss.metric != eng.metric {
    return Err(CoreError.InvalidInput("segment does not match the active collection"));
  }
  eng.store = ss.store;
  eng.payloads = ss.payloads;
  var params = AnnParams{ m: ss.m, ef_construction: ss.ef_construction, ef_search: ss.ef_search };
  if ss.kind == AnnIndexKind.Hnsw && ss.has_graph {
    eng.graph = ss.graph;
    eng.index_kind = AnnIndexKind.Hnsw;
    eng.ann = params;
  } else {
    apply_index(&mut eng, ss.kind, params);
  }
  engine_checkpoint_from(eng, eng.wal.next_lsn);
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(true);
}

// M-D7 accessors + opt-in roll policy (P2 tuning).
pub fn engine_sealed_count(eng: &VectorEngine) -> Int {
  return eng.sealed.len();
}

pub fn engine_sealed_missing(eng: &VectorEngine) -> Int {
  return eng.sealed_missing;
}

// Cached (loaded) sealed sources of the active collection.
pub fn engine_sealed_loaded(eng: &VectorEngine) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < eng.sealed_cache.len() {
    if eng.sealed_cache[i].cid == eng.active_cid { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Auto-roll when the active collection reaches `every` points; the segment
// files land in `dir` (must exist). 0 disables. Defaults: off/manual.
pub fn engine_set_seal_policy(eng: &mut VectorEngine, every: Int, dir: Str) -> Result[Bool, CoreError] {
  if every < 0 { return Err(CoreError.InvalidInput("negative seal interval")); }
  if every > 0 {
    if dir.len() == 0 || !io.dir_exists(dir) {
      return Err(CoreError.InvalidInput("seal dir missing"));
    }
  }
  eng.seal_every = every;
  eng.seal_dir = dir;
  return Ok(true);
}

// M-D7 cache maintenance: drop every entry of `cid`, push the replacement
// (functional rebuild -- no in-place Vec truncation).
fn sealed_cache_replaced(cache: &Vec[SealedCacheEntry], cid: Int, seg_id: Int, ss: SealedSegment) -> Vec[SealedCacheEntry] {
  var keep = Vec[SealedCacheEntry].new();
  var i: Int = 0;
  while i < cache.len() {
    if cache[i].cid != cid { keep.push(cache[i]); }
    i = i + 1;
  }
  keep.push(SealedCacheEntry{ cid: cid, seg_id: seg_id, ss: ss });
  return keep;
}

// M-D7 compaction: merge every sealed entry of the active collection PLUS the
// active remainder into ONE new segment at `path` (tombstones applied,
// active-wins), swap the registry (kind-2 replace; tombstones cleared), and
// leave the old files on disk (caller cleans). Bit-exact with the
// pre-compaction union. Returns the new segment id.
pub fn engine_compact_sealed(eng: &mut VectorEngine, path: Str) -> Result[Int, CoreError]
  requires: eng.created
{
  if path.len() == 0 {
    return Err(CoreError.InvalidInput("empty segment path"));
  }
  var live_points: Int = eng.store.ids.len();
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    if eng.sealed_cache[ci].cid == eng.active_cid {
      live_points = live_points + eng.sealed_cache[ci].ss.store.ids.len();
    }
    ci = ci + 1;
  }
  if live_points == 0 {
    return Err(CoreError.InvalidState("nothing to compact"));
  }
  // Refuse when a registered sealed source is not loaded: compaction
  // replaces ALL entries of the cid, so a missing source would silently
  // drop its data.
  var cache_count: Int = 0;
  var cc: Int = 0;
  while cc < eng.sealed_cache.len() {
    if eng.sealed_cache[cc].cid == eng.active_cid { cache_count = cache_count + 1; }
    cc = cc + 1;
  }
  if cache_count != eng.sealed.len() {
    return Err(CoreError.InvalidState("a sealed source is not loaded (refusing to compact)"));
  }
  var seg_id: Int = eng.sealed_next_id;
  var head: Int = wal_writer_current_lsn(&eng.wal);
  var ss = sealed_segment_new(seg_id, eng.active_cid, eng.dimension, eng.metric, eng.index_kind, eng.ann);
  if !sealed_segment_seal(&mut ss) {
    return Err(CoreError.InvalidState("segment lifecycle transition failed"));
  }
  // Merge: active first (current truth), then each cached sealed source with
  // the union rules (skip active/resurrected dupes and tombstones).
  var merged = index_new(eng.dimension);
  var merged_pl = payload_store_new();
  var a: Int = 0;
  while a < eng.store.ids.len() {
    var aid = eng.store.ids[a];
    index_add(&mut merged, aid, eng.store.vectors[a]);
    a = a + 1;
  }
  var pi: Int = 0;
  while pi < eng.payloads.entries.len() {
    payload_store_put(&mut merged_pl, eng.payloads.entries[pi].id, eng.payloads.entries[pi].payload);
    pi = pi + 1;
  }
  var cj: Int = 0;
  while cj < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[cj];
    if sc.cid == eng.active_cid {
      var j: Int = 0;
      while j < sc.ss.store.ids.len() {
        var id = sc.ss.store.ids[j];
        var skip: Bool = false;
        match index_get(&merged, id) {
          Some(_) => { skip = true; }
          None => {}
        }
        if !skip && tombs_contain(&eng.tombstones, id) { skip = true; }
        if !skip {
          index_add(&mut merged, id, sc.ss.store.vectors[j]);
          match payload_store_get(&sc.ss.payloads, id) {
            Some(pl) => { payload_store_put(&mut merged_pl, id, pl); }
            None => {}
          }
        }
        j = j + 1;
      }
    }
    cj = cj + 1;
  }
  ss.store = merged;
  ss.payloads = merged_pl;
  if eng.index_kind == AnnIndexKind.Hnsw {
    var g = hnsw_new(eng.ann.m, 4.0);
    hnsw_set_ef_construction(&mut g, eng.ann.ef_construction);
    var gi: Int = 0;
    while gi < ss.store.ids.len() {
      var gid = ss.store.ids[gi];
      hnsw_insert_ref(&mut g, gid, &ss.store.vectors[gi], eng.metric);
      gi = gi + 1;
    }
    ss.graph = g;
    ss.has_graph = true;
  }
  let _sq = sealed_segment_enable_sq(&mut ss);
  if !segment_file_persist(&ss, path) {
    return Err(CoreError.IOFailure("segment persist failed"));
  }
  var points: Int = ss.store.ids.len();
  var has_sq: Bool = ss.has_sq;
  // Registry swap: one entry, tombstones applied and cleared.
  var fresh = Vec[SealedEntry].new();
  fresh.push(SealedEntry{ seg_id: seg_id, points: points, head_lsn: head, has_sq: has_sq, path: path });
  eng.sealed = fresh;
  eng.sealed_cache = sealed_cache_replaced(&eng.sealed_cache, eng.active_cid, seg_id, ss);
  // Clear the active remainder; every tombstone has been applied.
  eng.store = index_new(eng.dimension);
  eng.graph = hnsw_new(eng.ann.m, 4.0);
  hnsw_set_ef_construction(&mut eng.graph, eng.ann.ef_construction);
  eng.payloads = payload_store_new();
  eng.tombstones = Vec[Int].new();
  eng.sealed_next_id = eng.sealed_next_id + 1;
  var words = sealed_words(2, seg_id, points, head, has_sq, path);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.SnapshotMarker, 0, eng.active_cid, words);
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(seg_id);
}

// Apply an index configuration to the (already created) collection: Hnsw
// builds the graph from the flat store; anything else resets the graph.
// Build into a local then assign once (XVC-C-09: repeated cross-module
// access to eng.graph inside the loop crashed the WSL build).
fn apply_index(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) {
  if kind == AnnIndexKind.Hnsw {
    var g = hnsw_new(params.m, 4.0);
    hnsw_set_ef_construction(&mut g, params.ef_construction);
    var i: Int = 0;
    while i < eng.store.ids.len() {
      var pid = eng.store.ids[i];
      var pv = eng.store.vectors[i];
      hnsw_insert_ref(&mut g, pid, &pv, eng.metric);
      i = i + 1;
    }
    eng.graph = g;
  } else {
    eng.graph = hnsw_new(16, 4.0);
  }
  eng.index_kind = kind;
  eng.ann = params;
}

// The registry-entry form of the same operation (used for parked
// collections during recovery).
fn entry_apply_index(e: &mut CollectionEntry, kind: AnnIndexKind, params: AnnParams) {
  if kind == AnnIndexKind.Hnsw {
    var g = hnsw_new(params.m, 4.0);
    hnsw_set_ef_construction(&mut g, params.ef_construction);
    var i: Int = 0;
    while i < e.store.ids.len() {
      var pid = e.store.ids[i];
      var pv = e.store.vectors[i];
      hnsw_insert_ref(&mut g, pid, &pv, e.metric);
      i = i + 1;
    }
    e.graph = g;
  } else {
    e.graph = hnsw_new(16, 4.0);
  }
  e.index_kind = kind;
  e.ann = params;
}

// Legacy single-collection entry point: (re)creates the canonical "default"
// collection through the registry path. Multi-collection callers use
// engine_create_named.
pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  if collection_find(eng, "default") >= 0 {
    match engine_drop(eng, "default") {
      Ok(_) => {}
      Err(_) => {}
    }
  }
  return engine_create_named(eng, "default", dim, metric);
}

// Select the ANN index for the active collection. Hnsw validates its params
// and (re)builds the graph from the flat store; Flat resets the graph to
// empty. The choice is in-memory only (collection metadata persistence is
// future work), so callers re-apply it after engine_recover.
pub fn engine_set_index(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) -> Result[Bool, CoreError]
  requires: eng.created
{
  if kind == AnnIndexKind.Hnsw {
    if !ann_params_valid(&params) {
      return Err(CoreError.InvalidInput("invalid ann params"));
    }
  }
  apply_index(eng, kind, params);
  log_manifest(eng, kind, params);
  return Ok(true);
}

// Per-request HNSW beam override (a query parameter in spirit): validates
// and updates the ACTIVE collection's `ef_search` WITHOUT rebuilding the
// graph and WITHOUT a manifest write -- the configured beam stays what is
// on disk; the next `select_collection` restores it. Service use: the
// optional `ef_search` field on /search (benchmark sweeps).
pub fn engine_set_ef_search(eng: &mut VectorEngine, ef: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  if ef < 1 || ef > 4096 {
    return Err(CoreError.InvalidInput("ef_search out of range"));
  }
  eng.ann.ef_search = ef;
  return Ok(true);
}

// Compact the ANN graph: rebuild it from the live nodes, reclaiming
// tombstoned slots (no-op returning 0 for a Flat collection). The flat
// store is untouched. Returns the number of reclaimed graph nodes.
pub fn engine_compact_index(eng: &mut VectorEngine) -> Result[Int, CoreError]
  requires: eng.created
{
  if eng.index_kind != AnnIndexKind.Hnsw {
    return Ok(0);
  }
  var before: Int = hnsw_size(&eng.graph);
  var fresh = hnsw_compact(&eng.graph, eng.metric);
  eng.graph = fresh;
  var after: Int = hnsw_size(&eng.graph);
  return Ok(before - after);
}

// ---- Index admin (M-Q5) ----

// A collection's live statistics: config + point/payload counts + graph
// occupancy (Hnsw: nodes = size incl. tombstones, tombstones = nodes -
// live). `wal_lsn` is the shared WAL's current lsn (one log per engine).
pub type CollectionStats = {
  name: Str;
  cid: Int;
  dimension: Int;
  metric: DistanceMetric;
  index_kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
  points: Int;
  payloads: Int;
  nodes: Int;
  tombstones: Int;
  wal_lsn: Int;
}

// Statistics of the index an admin rebuild produced.
pub type IndexStats = {
  kind: AnnIndexKind;
  points: Int;
  nodes_before: Int;
  nodes_after: Int;
  reclaimed: Int;
}

fn stats_from_live(eng: &VectorEngine) -> CollectionStats {
  var nodes: Int = 0;
  var tombstones: Int = 0;
  if eng.index_kind == AnnIndexKind.Hnsw {
    nodes = hnsw_size(&eng.graph);
    tombstones = nodes - hnsw_live_count(&eng.graph);
  }
  return CollectionStats{
    name: eng.active_name,
    cid: eng.active_cid,
    dimension: eng.dimension,
    metric: eng.metric,
    index_kind: eng.index_kind,
    m: eng.ann.m,
    ef_construction: eng.ann.ef_construction,
    ef_search: eng.ann.ef_search,
    points: engine_size(eng),
    payloads: payload_store_len(&eng.payloads),
    nodes: nodes,
    tombstones: tombstones,
    wal_lsn: engine_durable_lsn(eng),
  };
}

fn stats_from_entry(eng: &VectorEngine, e: &CollectionEntry) -> CollectionStats {
  var nodes: Int = 0;
  var tombstones: Int = 0;
  if e.index_kind == AnnIndexKind.Hnsw {
    nodes = hnsw_size(&e.graph);
    tombstones = nodes - hnsw_live_count(&e.graph);
  }
  return CollectionStats{
    name: e.name,
    cid: e.cid,
    dimension: e.dimension,
    metric: e.metric,
    index_kind: e.index_kind,
    m: e.ann.m,
    ef_construction: e.ann.ef_construction,
    ef_search: e.ann.ef_search,
    points: e.store.ids.len(),
    payloads: payload_store_len(&e.payloads),
    nodes: nodes,
    tombstones: tombstones,
    wal_lsn: engine_durable_lsn(eng),
  };
}

// ---- Memory accounting estimate (M-P P2) ----
//
// A per-collection accounting estimate for capacity planning; the model
// constants and per-structure formulas live in `hnsw_memory_estimate`
// (graph), `index_memory_estimate` (flat store),
// `payload_store_memory_estimate` and `wal_memory_estimate` (both
// documented there). `wal_bytes` is engine-wide (one shared log) and
// reported separately from `total_bytes` (store + graph + payloads for
// this collection).
pub type MemoryEstimate = {
  name: Str;
  dim: Int;
  points: Int;
  index_kind: AnnIndexKind;
  store_bytes: Int;
  graph_bytes: Int;
  payload_bytes: Int;
  total_bytes: Int;
  wal_bytes: Int;
}

pub fn engine_memory_estimate(eng: &VectorEngine, name: Str) -> Result[MemoryEstimate, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.NotFound);
  }
  var dim: Int = 0;
  var kind = AnnIndexKind.Flat;
  var points: Int = 0;
  var store_b: Int = 0;
  var graph_b: Int = 0;
  var payload_b: Int = 0;
  if idx == eng.active_idx {
    dim = eng.dimension;
    kind = eng.index_kind;
    points = engine_size(eng);
    store_b = index_memory_estimate(&eng.store);
    payload_b = payload_store_memory_estimate(&eng.payloads);
    if eng.index_kind == AnnIndexKind.Hnsw {
      var hm = hnsw_memory_estimate(&eng.graph);
      graph_b = hm.bytes;
    }
  } else {
    var e = eng.collections[idx];
    dim = e.dimension;
    kind = e.index_kind;
    points = e.store.ids.len();
    store_b = index_memory_estimate(&e.store);
    payload_b = payload_store_memory_estimate(&e.payloads);
    if e.index_kind == AnnIndexKind.Hnsw {
      var hm2 = hnsw_memory_estimate(&e.graph);
      graph_b = hm2.bytes;
    }
  }
  return Ok(MemoryEstimate{
    name: name,
    dim: dim,
    points: points,
    index_kind: kind,
    store_bytes: store_b,
    graph_bytes: graph_b,
    payload_bytes: payload_b,
    total_bytes: store_b + graph_b + payload_b,
    wal_bytes: wal_memory_estimate(&eng.wal),
  });
}

// Per-collection statistics (active collection from the live fields; any
// parked collection from its registry entry, which is synced at park time).
pub fn engine_collection_stats(eng: &VectorEngine, name: Str) -> Result[CollectionStats, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.NotFound);
  }
  if idx == eng.active_idx {
    return Ok(stats_from_live(eng));
  }
  var e = eng.collections[idx];
  return Ok(stats_from_entry(eng, &e));
}

// Rebuild the active collection's index from the flat store (the admin
// path; compact_index remains the Int-returning compatibility wrapper).
// Hnsw: fresh graph from the live nodes only -- tombstones reclaimed.
// Flat: no-op with zeroed graph stats. Returns before/after/reclaimed.
pub fn engine_rebuild_index(eng: &mut VectorEngine) -> Result[IndexStats, CoreError]
  requires: eng.created
{
  var points = engine_size(eng);
  if eng.index_kind != AnnIndexKind.Hnsw {
    eng.graph = hnsw_new(16, 4.0);
    return Ok(IndexStats{ kind: eng.index_kind, points: points, nodes_before: 0, nodes_after: 0, reclaimed: 0 });
  }
  var before: Int = hnsw_size(&eng.graph);
  var fresh = hnsw_compact(&eng.graph, eng.metric);
  eng.graph = fresh;
  var after: Int = hnsw_size(&eng.graph);
  return Ok(IndexStats{ kind: AnnIndexKind.Hnsw, points: points, nodes_before: before, nodes_after: after, reclaimed: before - after });
}

pub fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  var ok: Bool = false;
  match engine_upsert_apply(eng, point, vec) {
    Ok(b) => { ok = b; }
    Err(e) => { return Err(e); }
  }
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(ok);
}

// In-memory apply half of upsert (no durability commit): the batch path
// loops this and commits ONCE per API call.
fn engine_upsert_apply(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  if vec.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  var payload = vector_encode(&vec);
  log_upsert(&mut eng.wal, eng.active_cid, point, payload);
  if tombs_contain(&eng.tombstones, point) {
    eng.tombstones = tombs_without(&eng.tombstones, point);
  }
  if eng.index_kind == AnnIndexKind.Hnsw {
    hnsw_insert_ref(&mut eng.graph, point, &vec, eng.metric);
  }
  var ok = index_add(&mut eng.store, point, vec);
  metric_counter_inc(&mut eng.upserts);
  return Ok(ok);
}

// HNSW results are Neighbor(id: UInt64, distance); the engine surface uses
// SearchResult(id: Int, distance).
fn neighbors_to_results(items: &Vec[Neighbor]) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var i: Int = 0;
  while i < items.len() {
    out.push(SearchResult{ id: items[i].id as Int, distance: items[i].distance });
    i = i + 1;
  }
  return out;
}

// ---- M-D7 union search helpers ----
// Per-source candidate budget: k + tombstones guarantees >= k live candidates
// per Flat source (at most `tombstones.len()` prefix entries can be shadowed),
// so the merged top-k is exact. Distance ties resolve by source order (active
// first, then sealed-cache order) -- deterministic.

fn union_per_limit(k: Int, tombs: Int) -> Int {
  return k + tombs;
}

fn union_sealed_knn(eng: &VectorEngine, q: &Vector, per: Int) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[ci];
    if sc.cid == eng.active_cid {
      var src = Vec[SearchResult].new();
      if sc.ss.kind == AnnIndexKind.Hnsw && sc.ss.has_graph {
        var nb = hnsw_search(&sc.ss.graph, q, per, sc.ss.ef_search, sc.ss.metric);
        src = neighbors_to_results(&nb);
      } else {
        src = search_knn(&sc.ss.store, q, per, sc.ss.metric);
      }
      var j: Int = 0;
      while j < src.len() {
        var id = src[j].id;
        var skip: Bool = false;
        match index_get(&eng.store, id) {
          Some(_) => { skip = true; }
          None => {}
        }
        if !skip && tombs_contain(&eng.tombstones, id) { skip = true; }
        if !skip {
          results_push_bounded(&mut out, SearchResult{ id: id, distance: src[j].distance }, per);
        }
        j = j + 1;
      }
    }
    ci = ci + 1;
  }
  return out;
}

fn union_sealed_knn_filtered(eng: &VectorEngine, q: &Vector, per: Int, filter: &FilterExpr) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[ci];
    if sc.cid == eng.active_cid {
      var src = Vec[SearchResult].new();
      if sc.ss.kind == AnnIndexKind.Hnsw && sc.ss.has_graph {
        var nb = hnsw_search(&sc.ss.graph, q, per, sc.ss.ef_search, sc.ss.metric);
        src = filter_results_by_payload(&neighbors_to_results(&nb), &sc.ss.payloads, filter);
      } else {
        src = search_knn_filtered(&sc.ss.store, &sc.ss.payloads, q, per, sc.ss.metric, filter);
      }
      var j: Int = 0;
      while j < src.len() {
        var id = src[j].id;
        var skip: Bool = false;
        match index_get(&eng.store, id) {
          Some(_) => { skip = true; }
          None => {}
        }
        if !skip && tombs_contain(&eng.tombstones, id) { skip = true; }
        if !skip {
          results_push_bounded(&mut out, SearchResult{ id: id, distance: src[j].distance }, per);
        }
        j = j + 1;
      }
    }
    ci = ci + 1;
  }
  return out;
}

fn union_knn(eng: &VectorEngine, q: &Vector, k: Int) -> Vec[SearchResult] {
  if eng.sealed.len() == 0 {
    // No registered sealed segments: the historical behavior, bit-exact.
    if eng.index_kind == AnnIndexKind.Hnsw {
      return neighbors_to_results(&hnsw_search(&eng.graph, q, k, eng.ann.ef_search, eng.metric));
    }
    return search_knn(&eng.store, q, k, eng.metric);
  }
  var per = union_per_limit(k, eng.tombstones.len());
  var results = Vec[SearchResult].new();
  if eng.index_kind == AnnIndexKind.Hnsw {
    var nb = hnsw_search(&eng.graph, q, per, eng.ann.ef_search, eng.metric);
    var ar = neighbors_to_results(&nb);
    var i: Int = 0;
    while i < ar.len() {
      results_push_bounded(&mut results, ar[i], k);
      i = i + 1;
    }
  } else {
    var ar2 = search_knn(&eng.store, q, per, eng.metric);
    var i: Int = 0;
    while i < ar2.len() {
      results_push_bounded(&mut results, ar2[i], k);
      i = i + 1;
    }
  }
  var sealed = union_sealed_knn(eng, q, per);
  var j: Int = 0;
  while j < sealed.len() {
    results_push_bounded(&mut results, sealed[j], k);
    j = j + 1;
  }
  return results;
}

fn union_knn_filtered(eng: &VectorEngine, q: &Vector, k: Int, filter: &FilterExpr) -> Vec[SearchResult] {
  if eng.sealed.len() == 0 {
    if eng.index_kind == AnnIndexKind.Hnsw {
      return hnsw_search_filtered(eng, q, k, filter);
    }
    return search_knn_filtered(&eng.store, &eng.payloads, q, k, eng.metric, filter);
  }
  var per = union_per_limit(k, eng.tombstones.len());
  var results = Vec[SearchResult].new();
  if eng.index_kind == AnnIndexKind.Hnsw {
    var ar = hnsw_search_filtered(eng, q, per, filter);
    var i: Int = 0;
    while i < ar.len() {
      results_push_bounded(&mut results, ar[i], k);
      i = i + 1;
    }
  } else {
    var ar2 = search_knn_filtered(&eng.store, &eng.payloads, q, per, eng.metric, filter);
    var i: Int = 0;
    while i < ar2.len() {
      results_push_bounded(&mut results, ar2[i], k);
      i = i + 1;
    }
  }
  var sealed = union_sealed_knn_filtered(eng, q, per, filter);
  var j: Int = 0;
  while j < sealed.len() {
    results_push_bounded(&mut results, sealed[j], k);
    j = j + 1;
  }
  return results;
}

// Collect EVERY live union candidate (active store + sealed sources, union
// rules applied) into a bound-limited sorted list. `use_radius` adds the
// inclusive range predicate. O(active + sealed) per call, the scan class.
fn union_scan(eng: &VectorEngine, q: &Vector, bound: Int, radius: Float32, use_radius: Bool) -> Vec[SearchResult] {
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  while i < eng.store.ids.len() {
    var d = vector_distance(&eng.store.vectors[i], q, eng.metric);
    if !use_radius || d <= radius {
      results_push_bounded(&mut results, SearchResult{ id: eng.store.ids[i], distance: d }, bound);
    }
    i = i + 1;
  }
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[ci];
    if sc.cid == eng.active_cid {
      var j: Int = 0;
      while j < sc.ss.store.ids.len() {
        var id = sc.ss.store.ids[j];
        var skip: Bool = false;
        match index_get(&eng.store, id) {
          Some(_) => { skip = true; }
          None => {}
        }
        if !skip && tombs_contain(&eng.tombstones, id) { skip = true; }
        if !skip {
          var d2 = vector_distance(&sc.ss.store.vectors[j], q, sc.ss.metric);
          if !use_radius || d2 <= radius {
            results_push_bounded(&mut results, SearchResult{ id: id, distance: d2 }, bound);
          }
        }
        j = j + 1;
      }
    }
    ci = ci + 1;
  }
  return results;
}

fn union_range(eng: &VectorEngine, q: &Vector, radius: Float32, limit: Int) -> Vec[SearchResult] {
  return union_scan(eng, q, limit, radius, true);
}

fn union_page(eng: &VectorEngine, q: &Vector, k: Int, offset: Int) -> Vec[SearchResult] {
  if eng.sealed.len() == 0 {
    var sh = search_page_scan(&eng.store, q, k, offset, eng.metric);
    return sh.items;
  }
  var all = union_scan(eng, q, offset + k, 0.0, false);
  var out = Vec[SearchResult].new();
  var i: Int = offset;
  while i < all.len() && out.len() < k {
    out.push(all[i]);
    i = i + 1;
  }
  return out;
}

fn union_after(eng: &VectorEngine, q: &Vector, k: Int, after_id: Int) -> Option[SearchHits] {
  if eng.sealed.len() == 0 {
    return search_after_scan(&eng.store, q, k, after_id, eng.metric);
  }
  var bound: Int = eng.store.ids.len();
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    if eng.sealed_cache[ci].cid == eng.active_cid {
      bound = bound + eng.sealed_cache[ci].ss.store.ids.len();
    }
    ci = ci + 1;
  }
  var all = union_scan(eng, q, bound, 0.0, false);
  var pos: Int = -1;
  var i: Int = 0;
  while i < all.len() {
    if all[i].id == after_id {
      pos = i;
      i = all.len();
    } else {
      i = i + 1;
    }
  }
  if pos < 0 { return None; }
  var out = Vec[SearchResult].new();
  var j: Int = pos + 1;
  while j < all.len() && out.len() < k {
    out.push(all[j]);
    j = j + 1;
  }
  return Some(SearchHits{ items: out });
}

pub fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
  requires: k > 0
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  // M-D7: union over active + sealed (single-source fast path inside).
  return Ok(SearchHits{ items: union_knn(eng, query, k) });
}

pub fn engine_delete(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  var ok: Bool = false;
  match engine_delete_apply(eng, point) {
    Ok(b) => { ok = b; }
    Err(e) => { return Err(e); }
  }
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(ok);
}

// M-D7: does the id exist in any cached sealed source of the active
// collection? (Deletes must report sealed-only points as deleted -- they are
// visible through the union until shadowed.)
fn point_in_sealed(eng: &VectorEngine, id: Int) -> Bool {
  var ci: Int = 0;
  while ci < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[ci];
    if sc.cid == eng.active_cid {
      match index_get(&sc.ss.store, id) {
        Some(_) => { return true; }
        None => {}
      }
    }
    ci = ci + 1;
  }
  return false;
}

// In-memory apply half of delete (no durability commit); the batch path
// loops this and commits ONCE per API call.
fn engine_delete_apply(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  log_delete(&mut eng.wal, eng.active_cid, point);
  var ok = index_remove(&mut eng.store, point);
  if eng.index_kind == AnnIndexKind.Hnsw {
    hnsw_delete(&mut eng.graph, point);
  }
  payload_store_remove(&mut eng.payloads, point);   // no orphan metadata
  // M-D7: a sealed-only point is a real deletion (it leaves the union);
  // keep the id shadowed. The shadow is unconditional here (a deleted id
  // that also has a sealed copy must not resurface); a re-upsert clears it,
  // so tombstones and the active store stay disjoint at checkpoint time.
  if !ok && point_in_sealed(eng, point) { ok = true; }
  if !tombs_contain(&eng.tombstones, point) {
    eng.tombstones.push(point);
  }
  metric_counter_inc(&mut eng.deletes);
  return Ok(ok);
}

// Batch upsert (M-Q2): all-or-nothing per call. The whole batch is validated
// BEFORE anything is applied (non-empty, equal lengths, every vector matches
// the collection dimension), then each point goes through the same
// WAL-before-ack path as engine_upsert. Returns the number of records
// applied (duplicate ids collapse in the store, like single upserts).
pub fn engine_upsert_many(eng: &mut VectorEngine, ids: &Vec[Int], vecs: &Vec[Vector]) -> Result[Int, CoreError]
  requires: eng.created
{
  if ids.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  if ids.len() != vecs.len() {
    return Err(CoreError.InvalidInput("batch length mismatch"));
  }
  var i: Int = 0;
  while i < vecs.len() {
    if vecs[i].dimension != eng.dimension {
      return Err(CoreError.InvalidInput("dimension mismatch"));
    }
    i = i + 1;
  }
  i = 0;
  while i < ids.len() {
    match engine_upsert_apply(eng, ids[i], vecs[i]) {
      Ok(_) => {}
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(ids.len());
}

// Batch delete (M-Q2): idempotent per id (missing ids are skipped, not an
// error); returns the number of points actually removed. Empty batches are
// rejected loudly.
pub fn engine_delete_many(eng: &mut VectorEngine, ids: &Vec[Int]) -> Result[Int, CoreError]
  requires: eng.created
{
  if ids.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  var removed: Int = 0;
  var i: Int = 0;
  while i < ids.len() {
    match engine_delete_apply(eng, ids[i]) {
      Ok(ok) => { if ok { removed = removed + 1; } }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  match engine_wal_commit(eng) {
    Ok(_) => {}
    Err(e) => { return Err(e); }
  }
  return Ok(removed);
}

// Selective delete (M-Q4): remove every live point whose payload matches
// `filter`, WAL-durable per point (graph tombstones + payload/index cleanup
// through the gated batch path). Planner-driven: index-answerable shapes
// (Eq/Range/Exists/And-of-those) resolve candidates from the sorted payload
// index (each verified before deletion); every other shape scans the live
// store. Ids are applied in ascending order (plan-independent WAL order).
// Returns the number of points actually removed; a filter matching nothing
// is Ok(0), never an error.
pub fn engine_delete_filter(eng: &mut VectorEngine, filter: &FilterExpr) -> Result[Int, CoreError]
  requires: eng.created
{
  var ids = Vec[Int].new();
  if filter_index_answerable(filter) {
    var cands = filter_plan_candidates(&eng.payloads, filter);
    var i: Int = 0;
    while i < cands.len() {
      if payload_store_matches(&eng.payloads, cands[i], filter) {
        ids.push(cands[i]);
      }
      i = i + 1;
    }
  } else {
    var i2: Int = 0;
    while i2 < eng.store.ids.len() {
      if payload_store_matches(&eng.payloads, eng.store.ids[i2], filter) {
        ids.push(eng.store.ids[i2]);
      }
      i2 = i2 + 1;
    }
  }
  // M-D7: sealed-only matches. The sealed payload store is the truth for
  // ids that live only in sealed files (active ids were covered above; an
  // id present in active is deleted through its active entry).
  var cs: Int = 0;
  while cs < eng.sealed_cache.len() {
    var sc = eng.sealed_cache[cs];
    if sc.cid == eng.active_cid {
      var si: Int = 0;
      while si < sc.ss.payloads.entries.len() {
        var sid = sc.ss.payloads.entries[si].id;
        var in_active: Bool = false;
        match index_get(&eng.store, sid) {
          Some(_) => { in_active = true; }
          None => {}
        }
        if !in_active && !tombs_contain(&eng.tombstones, sid) {
          if payload_store_matches(&sc.ss.payloads, sid, filter) {
            ids.push(sid);
          }
        }
        si = si + 1;
      }
    }
    cs = cs + 1;
  }
  if ids.len() == 0 {
    return Ok(0);
  }
  var a: Int = 1;
  while a < ids.len() {
    var v = ids[a];
    var b: Int = a - 1;
    while b >= 0 && ids[b] > v {
      ids[b + 1] = ids[b];
      b = b - 1;
    }
    ids[b + 1] = v;
    a = a + 1;
  }
  return engine_delete_many(eng, &ids);
}

// Batch search (M-Q2): one result set per query, order preserved.
// All-or-nothing validation (non-empty, k in range, every query dimension
// matches) happens before any search runs. Returns `BatchHits` (struct
// wrapper; a Result whose payload is a Vec of Vec-bearing structs is the
// XVC-C-04/C-08 shape family).
pub fn engine_search_many(eng: &VectorEngine, queries: &Vec[Vector], k: Int) -> Result[BatchHits, CoreError]
  requires: eng.created
{
  if queries.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var i: Int = 0;
  while i < queries.len() {
    if queries[i].dimension != eng.dimension {
      return Err(CoreError.InvalidInput("dimension mismatch"));
    }
    i = i + 1;
  }
  var sets = Vec[SearchHits].new();
  i = 0;
  while i < queries.len() {
    match engine_search(eng, &queries[i], k) {
      Ok(h) => { sets.push(h); }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(BatchHits{ sets: sets });
}

// Attach/replace metadata for an existing point (WAL-before-ack: the encoded
// payload record is appended before the in-memory store is touched).
// Returns Ok(false) when the point does not exist (payloads never outlive
// their point).
pub fn engine_set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError]
  requires: eng.created
{
  match index_get(&eng.store, point) {
    Some(_) => {
      var words = payload_encode(&payload);
      log_payload_set(&mut eng.wal, eng.active_cid, point, words);
      payload_store_put(&mut eng.payloads, point, payload);
      match engine_wal_commit(eng) {
        Ok(_) => {}
        Err(e) => { return Err(e); }
      }
      return Ok(true);
    }
    None => { return Ok(false); }
  }
}

pub fn engine_get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return payload_store_get(&eng.payloads, point);
}

// M-D7 union hydration: the active payload store is the truth for active
// ids; sealed-only ids hydrate from their sealed source (first match wins;
// ids are unique across sources by the union rules).
fn hydrate_hits_union(eng: &VectorEngine, items: &Vec[SearchResult], with_payload: Bool) -> Vec[SearchHit] {
  var out = Vec[SearchHit].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = payload_new();
    var have: Bool = false;
    if with_payload {
      match payload_store_get(&eng.payloads, items[i].id) {
        Some(f) => { pl = f; have = true; }
        None => {}
      }
      if !have {
        var ci: Int = 0;
        while ci < eng.sealed_cache.len() {
          var sc = eng.sealed_cache[ci];
          if sc.cid == eng.active_cid {
            match payload_store_get(&sc.ss.payloads, items[i].id) {
              Some(f2) => { pl = f2; have = true; }
              None => {}
            }
          }
          ci = ci + 1;
        }
      }
    }
    out.push(SearchHit{ id: items[i].id, distance: items[i].distance, payload: pl, has_payload: have });
    i = i + 1;
  }
  return out;
}

// Filtered search on an Hnsw collection: ANN fetch (ef_search wide), keep
// the matching subset (order preserved), and fall back to the exact flat
// filtered scan when the ANN pass under-fills -- selective filters stay
// exact and k-filled at the cost of one scan. Approximation semantics match
// the unfiltered ANN path.
fn hnsw_search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Vec[SearchResult] {
  var fetch: Int = eng.ann.ef_search;
  if fetch < k { fetch = k; }
  var neighbors = hnsw_search(&eng.graph, query, fetch, fetch, eng.metric);
  var raw = neighbors_to_results(&neighbors);
  var matched = filter_results_by_payload(&raw, &eng.payloads, filter);
  if matched.len() >= k {
    var out = Vec[SearchResult].new();
    var i: Int = 0;
    while i < k {
      out.push(SearchResult{ id: matched[i].id, distance: matched[i].distance });
      i = i + 1;
    }
    return out;
  }
  return search_knn_filtered(&eng.store, &eng.payloads, query, k, eng.metric, filter);
}

// Filtered exact top-k: dimension/top_k validation, then the exact flat
// filtered scan (the planner picks the pre/post plan). ANN + filter is
// future work, so this path is always exact even on an Hnsw collection.
pub fn engine_search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError]
  requires: eng.created
  requires: k > 0
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  // M-D7: union over active + sealed (single-source fast path inside).
  return Ok(SearchHits{ items: union_knn_filtered(eng, query, k, filter) });
}

// Exact range search: points within `radius` (inclusive) on the active
// collection, distance-sorted ascending, at most `limit` items (the closest
// ones). Exact for both index kinds (raw-store scan); ANN widening is M-P
// tuning. Negative radius and out-of-range limit are rejected loudly.
pub fn engine_search_range(eng: &VectorEngine, query: &Vector, radius: Float32, limit: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(limit) {
    return Err(CoreError.InvalidInput("limit out of range"));
  }
  if radius < 0.0 {
    return Err(CoreError.InvalidInput("radius out of range"));
  }
  // M-D7: union over active + sealed (single-source fast path inside).
  return Ok(SearchHits{ items: union_range(eng, query, radius, limit) });
}

// Offset pagination (M-Q3): ranks [offset, offset+k) of the exact total
// order (distance ascending, id ascending). Exact for both index kinds
// (raw-store scan; ANN widening is M-P tuning). Negative offset and
// out-of-range k are rejected loudly.
pub fn engine_search_page(eng: &VectorEngine, query: &Vector, k: Int, offset: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  if offset < 0 {
    return Err(CoreError.InvalidInput("offset must be >= 0"));
  }
  // M-D7: union over active + sealed (single-source fast path inside).
  return Ok(SearchHits{ items: union_page(eng, query, k, offset) });
}

// Cursor pagination (M-Q3): the next k ranks strictly after the current
// position of `after_id` in the same total order. Err(NotFound) when the
// cursor id does not exist (e.g. deleted between pages) -- restarting is
// the caller's policy.
pub fn engine_search_after(eng: &VectorEngine, query: &Vector, k: Int, after_id: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  // M-D7: union over active + sealed (single-source fast path inside).
  var page = union_after(eng, query, k, after_id);
  match page {
    Some(h) => { return Ok(h); }
    None => { return Err(CoreError.NotFound); }
  }
}

// Request-driven search: honors the request's top_k, filter, and
// with_payload hydration flag. The active collection's metric governs; a
// request whose metric differs from the collection is rejected. Returns
// HydratedHits (SearchHit carries id/distance + optional payload) so the
// same call serves both plain and hydrated searches.
pub fn engine_search_request(eng: &VectorEngine, req: &SearchRequest) -> Result[HydratedHits, CoreError]
  requires: eng.created
  requires: req.top_k > 0
{
  if req.query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(req.top_k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  if req.metric != eng.metric {
    return Err(CoreError.InvalidInput("metric mismatch"));
  }
  // M-Q6 mode dispatch: Range uses top_k as the inclusive-radius limit;
  // filters and pagination are Knn-only.
  if req.mode == SearchMode.Range {
    if search_request_has_filter(req) {
      return Err(CoreError.InvalidInput("range mode does not support filters"));
    }
    if req.offset > 0 || req.after_id >= 0 {
      return Err(CoreError.InvalidInput("range mode does not support pagination"));
    }
    if req.radius < 0.0 {
      return Err(CoreError.InvalidInput("radius out of range"));
    }
    var rres = engine_search_range(eng, &req.query, req.radius, req.top_k);
    match rres {
      Ok(h) => { return Ok(HydratedHits{ items: hydrate_hits_union(eng, &h.items, req.with_payload) }); }
      Err(e) => { return Err(e); }
    }
  }
  // M-Q6 pagination dispatch (Knn): after-id cursor or offset ranks.
  if req.after_id >= 0 {
    if req.offset > 0 {
      return Err(CoreError.InvalidInput("offset and after_id are mutually exclusive"));
    }
    if search_request_has_filter(req) {
      return Err(CoreError.InvalidInput("pagination does not support filters"));
    }
    var cres = engine_search_after(eng, &req.query, req.top_k, req.after_id);
    match cres {
      Ok(h) => { return Ok(HydratedHits{ items: hydrate_hits_union(eng, &h.items, req.with_payload) }); }
      Err(e) => { return Err(e); }
    }
  }
  if req.offset > 0 {
    if search_request_has_filter(req) {
      return Err(CoreError.InvalidInput("pagination does not support filters"));
    }
    var pres = engine_search_page(eng, &req.query, req.top_k, req.offset);
    match pres {
      Ok(h) => { return Ok(HydratedHits{ items: hydrate_hits_union(eng, &h.items, req.with_payload) }); }
      Err(e) => { return Err(e); }
    }
  }
  if search_request_has_filter(req) {
    // M-D7: union over active + sealed for every Knn shape.
    var hits0 = union_knn_filtered(eng, &req.query, req.top_k, &req.filter[0]);
    return Ok(HydratedHits{ items: hydrate_hits_union(eng, &hits0, req.with_payload) });
  }
  var hh = union_knn(eng, &req.query, req.top_k);
  return Ok(HydratedHits{ items: hydrate_hits_union(eng, &hh, req.with_payload) });
}

// Batch request search (M-Q6): validate non-empty, then one dispatch per
// request (all-or-nothing: the first failing request aborts the batch).
pub fn engine_search_batch_request(eng: &VectorEngine, batch: &SearchBatchRequest) -> Result[HydratedBatch, CoreError]
  requires: eng.created
{
  if batch.requests.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  var sets = Vec[HydratedHits].new();
  var i: Int = 0;
  while i < batch.requests.len() {
    match engine_search_request(eng, &batch.requests[i]) {
      Ok(h) => { sets.push(h); }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(HydratedBatch{ sets: sets });
}

// Point getter used by the facade's `get_point` -- keeps the facade from
// reaching into the store directly.
pub fn engine_get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return index_get(&eng.store, point);
}

pub fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

pub fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}

// Fsync'd frontier (M-D5): the highest LSN committed to the durable delta
// segment and fsynced. 0 when durability is not enabled -- the in-memory log
// carries no durability claim. Advanced only after segment_append_sync Ok.
pub fn engine_synced_lsn(eng: &VectorEngine) -> Int {
  return eng.wal_seg_frontier;
}

// Enable durable mode (M-D5): heal (or create) the delta segment at
// `seg_path` and adopt the SEGMENT FILE as the durable frontier. The
// file is the durable truth: in-memory records beyond it (e.g. the
// renumbered block `engine_recover` emits when a home is reopened) are
// re-sent by the first commit, keeping the segment gap-free across
// reopen-then-write cycles. The old rule took max(file, in-memory
// current), which marked that renumbered block "durable" although it
// was never in the segment: the next commit appended past it and the
// reopen merge stopped at the gap -- post-restart writes were lost
// (found+fixed by probe_reopen_write during L-4; the kill matrix never
// reloaded a home before writing, so it missed the shape). Commit every
// subsequent mutation before its ack. Idempotent. Framing is xiom.wal
// codec v1 (durability.wal_segment).
pub fn engine_enable_durable(eng: &mut VectorEngine, seg_path: Str) -> Result[Bool, CoreError] {
  if seg_path.len() == 0 { return Err(CoreError.InvalidInput("empty segment path")); }
  if !segment_heal(seg_path) { return Err(CoreError.IOFailure("segment heal failed")); }
  var file_last = segment_last_lsn(seg_path);
  eng.wal_seg_path = seg_path;
  eng.wal_seg_frontier = file_last;
  eng.wal_seg_needs_heal = false;
  return Ok(true);
}

// Commit pending records (LSN > frontier) to the segment and fsync BEFORE
// the caller acknowledges. No-op (Ok(true)) when durability is not enabled.
// On failure the frontier does NOT advance: the next commit retries every
// pending record, and the segment is marked for heal (a failed write may
// have left a torn tail).
// M-D7 policy hooks, shared by the durable and non-durable commit paths:
// count the commit, then run the opt-in seal policy (roll at threshold) and
// the checkpoint policy. A policy failure never fails the ack (the write is
// already durable when it matters; roll/persist failures retry at the next
// commit).
fn engine_policy_hooks(eng: &mut VectorEngine) {
  eng.commits_since_ckpt = eng.commits_since_ckpt + 1;
  if eng.seal_every > 0 && eng.seal_dir.len() > 0 && eng.store.ids.len() >= eng.seal_every {
    var sid = eng.sealed_next_id;
    var ap = eng.seal_dir + "/sealed-" + convert.int_to_string(eng.active_cid) + "-" + convert.int_to_string(sid) + ".seg";
    match engine_roll_segment(eng, ap) {
      Ok(_) => {}
      Err(_) => {}
    }
  }
  if eng.ckpt_every > 0 && eng.commits_since_ckpt >= eng.ckpt_every {
    match engine_checkpoint_swap(eng) {
      Ok(_) => {}
      Err(_) => {}
    }
  }
}

pub fn engine_wal_commit(eng: &mut VectorEngine) -> Result[Bool, CoreError] {
  if eng.wal_seg_path.len() == 0 {
    // No durable segment: still honor the opt-in roll/checkpoint policies
    // (a roll writes its own files; a checkpoint swap Err is a no-op here).
    engine_policy_hooks(eng);
    return Ok(true);
  }
  if eng.wal_seg_needs_heal {
    if !segment_heal(eng.wal_seg_path) {
      return Err(CoreError.IOFailure("segment heal failed"));
    }
    eng.wal_seg_needs_heal = false;
  }
  var cur = wal_writer_current_lsn(&eng.wal);
  if cur <= eng.wal_seg_frontier { return Ok(true); }
  let r = segment_append_sync(eng.wal_seg_path, &eng.wal, eng.wal_seg_frontier);
  match r {
    Ok(_n) => {
      eng.wal_seg_frontier = cur;
      let _f = wal_writer_flush(&mut eng.wal);
      engine_policy_hooks(eng);
      return Ok(true);
    }
    Err(e) => {
      eng.wal_seg_needs_heal = true;
      return Err(CoreError.IOFailure(e));
    }
  }
}

// Set the checkpoint path used by engine_checkpoint_swap (embedders with a
// durable segment but no engine_open_durable came path).
pub fn engine_set_checkpoint_path(eng: &mut VectorEngine, path: Str) -> Result[Bool, CoreError] {
  if path.len() == 0 { return Err(CoreError.InvalidInput("empty checkpoint path")); }
  eng.wal_ckpt_path = path;
  return Ok(true);
}

// Auto-checkpoint policy: run a checkpoint swap every `every` successful
// commits (0 disables). Requires durable mode + a checkpoint path.
pub fn engine_set_checkpoint_policy(eng: &mut VectorEngine, every: Int) -> Result[Bool, CoreError] {
  if every < 0 { return Err(CoreError.InvalidInput("negative checkpoint interval")); }
  eng.ckpt_every = every;
  return Ok(true);
}

pub fn engine_checkpoint_countdown(eng: &VectorEngine) -> Int {
  return eng.commits_since_ckpt;
}

// Compact the in-memory log to the live state (no persistence): used by
// snapshots on non-durable engines and by callers that manage persistence
// themselves. Rebases LSNs to the current next_lsn; returns the rebased
// current LSN.
pub fn engine_compact_log(eng: &mut VectorEngine) -> Int {
  engine_checkpoint_from(eng, eng.wal.next_lsn);
  return wal_writer_current_lsn(&eng.wal);
}

// Compact + durable swap (M-D6): rebase the in-memory log to the live state
// (engine_checkpoint_from), swap a crash-safe checkpoint
// (wal_persist_sync: write tmp -> fsync tmp -> rename -> dir fsync), and
// ONLY THEN reset the delta segment and advance the durable frontier. On any
// failure the segment keeps every acknowledged record (its merge dedupes
// against the checkpoint, so retries are safe). Returns the new durable
// frontier (LSN).
pub fn engine_checkpoint_swap(eng: &mut VectorEngine) -> Result[Int, CoreError] {
  if eng.wal_seg_path.len() == 0 || eng.wal_ckpt_path.len() == 0 {
    return Err(CoreError.InvalidInput("durable mode is not enabled"));
  }
  engine_checkpoint_from(eng, eng.wal.next_lsn);
  var cur = wal_writer_current_lsn(&eng.wal);
  if !wal_persist_sync(&eng.wal, eng.wal_ckpt_path) {
    return Err(CoreError.IOFailure("checkpoint persist failed"));
  }
  if !segment_reset(eng.wal_seg_path) {
    return Err(CoreError.IOFailure("segment reset failed"));
  }
  eng.wal_seg_frontier = cur;
  eng.wal_seg_needs_heal = false;
  eng.commits_since_ckpt = 0;
  let _f = wal_writer_flush(&mut eng.wal);
  return Ok(cur);
}

// ---- Multi-collection recovery (D3) ----

// Recovery-time registry entry (ManifestInfo + cid + liveness).
pub type MetaEntry = {
  cid: Int;
  name: Str;
  alive: Bool;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

fn meta_find_cid(metas: &Vec[MetaEntry], cid: Int) -> Int {
  var i: Int = 0;
  while i < metas.len() {
    if metas[i].cid == cid { return i; }
    i = i + 1;
  }
  return -1;
}

fn meta_find_name(metas: &Vec[MetaEntry], name: Str) -> Int {
  var i: Int = 0;
  while i < metas.len() {
    if metas[i].name == name { return i; }
    i = i + 1;
  }
  return -1;
}

fn meta_upsert(metas: &mut Vec[MetaEntry], m: MetaEntry) {
  var idx = meta_find_cid(metas, m.cid);
  if idx < 0 {
    metas.push(m);
  } else {
    metas[idx] = m;
  }
}

fn meta_from_info(mi: &ManifestInfo, cid: Int) -> MetaEntry {
  return MetaEntry{
    cid: cid,
    name: mi.name,
    alive: true,
    dim: mi.dim,
    metric: mi.metric,
    kind: mi.kind,
    m: mi.m,
    ef_construction: mi.ef_construction,
    ef_search: mi.ef_search,
  };
}

// Replay a WAL across the collection registry: manifest records build the
// set (v1 legacy -> "default"/cid 1; v2 upsert; v3 drop), data records route
// by collection id when the log carries v2/v3 records (D3 strict mode) and
// land in the single collection otherwise (legacy logs, where the value
// field is not meaningful). A valid manifest file (`file_reg`) overrides
// configs by collection name -- with the D2 first-entry migration rule for
// single-collection logs. Returns an engine with the first alive collection
// active and a fresh checkpoint WAL carrying every alive collection.
fn engine_recover_registry(w: &WalWriter, dim: Int, metric: DistanceMetric, file_reg: &CollectionRegistry) -> VectorEngine {
  // 1. Metas from manifest records.
  var metas = Vec[MetaEntry].new();
  var strict: Bool = false;
  var i: Int = 0;
  while i < w.records.len() {
    if w.records[i].op == WalOpKind.ManifestUpdate {
      var mi = parse_manifest_info(&w.records[i].payload);
      if mi.valid {
        if mi.version == 1 {
          meta_upsert(&mut metas, meta_from_info(&mi, 1));
        } elif mi.version == 2 {
          strict = true;
          var cid2: Int = w.records[i].value;
          if cid2 < 1 { cid2 = 1; }
          meta_upsert(&mut metas, meta_from_info(&mi, cid2));
        } elif mi.version == 3 {
          strict = true;
          var di = meta_find_cid(&metas, w.records[i].value);
          if di >= 0 {
            var md = metas[di];
            md.alive = false;
            metas[di] = md;
          }
        }
      }
    }
    i = i + 1;
  }
  if metas.len() == 0 {
    var lm = MetaEntry{
      cid: 1,
      name: "default",
      alive: true,
      dim: dim,
      metric: metric,
      kind: AnnIndexKind.Flat,
      m: 16,
      ef_construction: 200,
      ef_search: 64,
    };
    metas.push(lm);
  }
  // 2. Manifest-file overrides (by name; D2 migration for single logs).
  if file_reg.valid && file_reg.entries.len() >= 1 {
    var fi: Int = 0;
    while fi < file_reg.entries.len() {
      var fe = file_reg.entries[fi];
      var oi = meta_find_name(&metas, fe.name);
      if oi < 0 && metas.len() == 1 { oi = 0; }
      if oi >= 0 {
        var mm = metas[oi];
        mm.name = fe.name;
        mm.dim = fe.dim;
        mm.metric = fe.metric;
        mm.kind = fe.kind;
        mm.m = fe.m;
        mm.ef_construction = fe.ef_construction;
        mm.ef_search = fe.ef_search;
        metas[oi] = mm;
      }
      fi = fi + 1;
    }
  }
  // 3. Per-collection stores + routed replay.
  var stores = Vec[VectorIndex].new();
  var pls = Vec[PayloadStore].new();
  var mi3: Int = 0;
  while mi3 < metas.len() {
    stores.push(index_new(metas[mi3].dim));
    pls.push(payload_store_new());
    mi3 = mi3 + 1;
  }
  var sealed_acc = Vec[SealedReg].new();
  var tomb_acc = Vec[TombReg].new();
  var ri: Int = 0;
  while ri < w.records.len() {
    var op = w.records[ri].op;
    var si: Int = -1;
    if strict {
      si = meta_find_cid(&metas, w.records[ri].value);
      if si >= 0 && !metas[si].alive { si = -1; }
    } else {
      si = 0;
    }
    if si >= 0 {
      if op == WalOpKind.Insert {
        match vector_decode(&w.records[ri].payload) {
          Some(v) => {
            if v.dimension == metas[si].dim {
              index_add(&mut stores[si], w.records[ri].key, v);
              // M-D7 replay symmetry: a live upsert clears the id's
              // tombstone shadow, so replay must too (a delete-miss then
              // upsert must not leave the id live AND tombstoned).
              if tombs_acc_has(&tomb_acc, metas[si].cid, w.records[ri].key) {
                tomb_acc = tombs_acc_without(&tomb_acc, metas[si].cid, w.records[ri].key);
              }
            }
          }
          None => {}
        }
      } elif op == WalOpKind.Delete {
        var dkey = w.records[ri].key;
        var found = index_get(&stores[si], dkey);
        var was_there: Bool = false;
        match found {
          Some(_) => { was_there = true; }
          None => {}
        }
        index_remove(&mut stores[si], dkey);
        payload_store_remove(&mut pls[si], dkey);
        if !was_there {
          // M-D7: missed the active store -- the id may live in a sealed
          // segment; the tombstone shadows it in the union.
          tomb_add(&mut tomb_acc, metas[si].cid, dkey);
        }
      } elif op == WalOpKind.Update {
        match payload_decode(&w.records[ri].payload) {
          Some(p) => { payload_store_put(&mut pls[si], w.records[ri].key, p); }
          None => {}
        }
      } elif op == WalOpKind.SegmentSeal {
        // M-D7 roll: register the sealed entry AND clear the cid's active
        // state (the roll moved everything active at that LSN into the file;
        // replay-order reproduction).
        if strict {
          var ps = parse_sealed_words(&w.records[ri].payload);
          if ps.valid {
            sealed_acc_add(&mut sealed_acc, metas[si].cid, ps.entry);
            stores[si] = index_new(metas[si].dim);
            pls[si] = payload_store_new();
          }
        }
      } elif op == WalOpKind.SnapshotMarker {
        // M-D7 checkpoint attach (kind 1) / compaction replace (kind 2):
        // registry-only -- the active state already reflects the roll.
        if strict {
          var ps2 = parse_sealed_words(&w.records[ri].payload);
          if ps2.valid {
            if ps2.kind == 2 {
              sealed_acc = sealed_acc_replaced(&sealed_acc, metas[si].cid, ps2.entry);
            } else {
              sealed_acc_add(&mut sealed_acc, metas[si].cid, ps2.entry);
            }
          }
        }
      }
    }
    ri = ri + 1;
  }
  // 4. Entries for every alive meta; the first alive becomes active.
  var eng = engine_new();
  var entries = Vec[CollectionEntry].new();
  var ai: Int = -1;
  var k: Int = 0;
  while k < metas.len() {
    var mk = metas[k];
    if mk.alive {
      var e = CollectionEntry{
        cid: mk.cid,
        name: mk.name,
        store: stores[k],
        payloads: pls[k],
        graph: hnsw_new(16, 4.0),
        index_kind: mk.kind,
        ann: AnnParams{ m: mk.m, ef_construction: mk.ef_construction, ef_search: mk.ef_search },
        dimension: mk.dim,
        metric: mk.metric,
        sealed: sealed_for_cid(&sealed_acc, mk.cid),
        tombstones: tombstones_for_cid(&tomb_acc, mk.cid),
      };
      var params = AnnParams{ m: mk.m, ef_construction: mk.ef_construction, ef_search: mk.ef_search };
      entry_apply_index(&mut e, mk.kind, params);
      if ai < 0 { ai = entries.len(); }
      entries.push(e);
    }
    k = k + 1;
  }
  eng.collections = entries;
  if ai >= 0 {
    load_active(&mut eng, ai);
  }
  // 5. Restore the cid counter (gate-caught fix, 2026-10-16): creating a
  // collection after a reopen must not reuse a recovered cid -- colliding
  // cids make the next recovery's last-wins manifest merge drop the
  // earlier collection (found by probe_mote_embedded: reopen -> create
  // "other" -> persist -> reopen lost "docs").
  var max_cid: Int = 0;
  var mci: Int = 0;
  while mci < eng.collections.len() {
    if eng.collections[mci].cid > max_cid { max_cid = eng.collections[mci].cid; }
    mci = mci + 1;
  }
  eng.next_collection = max_cid + 1;
  // 6. Checkpoint: every alive collection's data + its v2 manifest.
  engine_checkpoint_from(&mut eng, w.next_lsn);
  return eng;
}

// Rewrite the WAL as a compacted checkpoint of the whole registry, resuming
// LSNs from `base_lsn`: every collection's live points + payloads (record
// value = cid) followed by one v2 manifest each. sync_active first, so the
// active collection's entry matches the live fields.
fn engine_checkpoint_from(eng: &mut VectorEngine, base_lsn: Int) {
  sync_active(eng);
  var out = wal_writer_resume(base_lsn);
  var c: Int = 0;
  while c < eng.collections.len() {
    var ce = eng.collections[c];
    var di2: Int = 0;
    while di2 < ce.store.ids.len() {
      wal_writer_append_payload(&mut out, WalOpKind.Insert, ce.store.ids[di2], ce.cid, vector_encode(&ce.store.vectors[di2]));
      di2 = di2 + 1;
    }
    var pi: Int = 0;
    while pi < ce.payloads.entries.len() {
      wal_writer_append_payload(&mut out, WalOpKind.Update, ce.payloads.entries[pi].id, ce.cid, payload_encode(&ce.payloads.entries[pi].payload));
      pi = pi + 1;
    }
    // M-D7 tombstones: re-emitted as Delete records so they survive a
    // checkpoint compaction (replay re-derives them via the miss rule).
    var ti: Int = 0;
    while ti < ce.tombstones.len() {
      wal_writer_append(&mut out, WalOpKind.Delete, ce.tombstones[ti], ce.cid);
      ti = ti + 1;
    }
    c = c + 1;
  }
  var c2: Int = 0;
  while c2 < eng.collections.len() {
    var ce2 = eng.collections[c2];
    var words2 = manifest_words(ce2.name, ce2.dimension, ce2.metric, ce2.index_kind, ce2.ann);
    wal_writer_append_payload(&mut out, WalOpKind.ManifestUpdate, 0, ce2.cid, words2);
    c2 = c2 + 1;
  }
  // M-D7 sealed entries: registry attach markers (replay attaches only --
  // no active clear; the checkpoint's data phase already excludes sealed
  // content).
  var c3: Int = 0;
  while c3 < eng.collections.len() {
    var ce3 = eng.collections[c3];
    var sj: Int = 0;
    while sj < ce3.sealed.len() {
      var se3 = ce3.sealed[sj];
      var sw = sealed_words(1, se3.seg_id, se3.points, se3.head_lsn, se3.has_sq, se3.path);
      wal_writer_append_payload(&mut out, WalOpKind.SnapshotMarker, 0, ce3.cid, sw);
      sj = sj + 1;
    }
    c3 = c3 + 1;
  }
  eng.wal = out;
}

// Rebuild an engine from its WAL: manifest records define the collection
// registry (legacy v1 -> "default"; no manifest -> caller config), data
// records replay into their collection, and a fresh checkpoint carries every
// alive collection. LSNs stay monotonic.
pub fn engine_recover(w: &WalWriter, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var empty_reg = CollectionRegistry{ valid: false, version: 0, entries: Vec[RegistryEntry].new() };
  return engine_recover_registry(w, dim, metric, &empty_reg);
}

// Open from disk (M-D2/D3): the manifest file's registry overrides per-
// collection configs by name (registry of record); without it (or when a
// name is absent) the in-WAL manifests govern, and the caller's dim/metric
// are the last resort for logs with no manifest at all.
pub fn engine_recover_file(w: &WalWriter, path: Str, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var reg = manifest_load(path);
  return engine_recover_registry(w, dim, metric, &reg);
}

// Open a DURABLE engine (M-D5) from its whole-file checkpoint + delta
// segment: load the checkpoint, merge the segment delta (checkpoint-deduped,
// prefix-exact), recover, then enable durable mode on the same segment so
// every later mutation commits + fsyncs before its ack. `manifest_path` may
// be "" (the in-WAL manifests govern). Missing files degrade to an empty
// engine exactly like engine_recover_file.
pub fn engine_open_durable(ckpt_path: Str, seg_path: Str, manifest_path: Str, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var w = wal_load(ckpt_path);
  let _added = segment_merge_into(seg_path, &mut w);
  var eng = engine_recover_file(&w, manifest_path, dim, metric);
  match engine_enable_durable(&mut eng, seg_path) {
    Ok(_) => {}
    Err(_) => {}
  }
  eng.wal_ckpt_path = ckpt_path;
  return eng;
}
