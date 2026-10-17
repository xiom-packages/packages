// XIOM ORBITDB <-> XVECTOR hybrid retrieval probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Consumer conformance for the documented hybrid contract
// (docs/XVECTOR-INTEGRATION.md + xiom-xvector/docs/ORBITDB-INTEGRATION.md):
// rows live in ORBITDB, embeddings live in XVECTOR, one external int join
// key. Source-level composition: tests/hybrid/xiom.toml lists both src trees
// as source roots (see the header there).
//
// Modes (env ORBITDB_HYBRID_MODE):
//   full   (default) -- in-process acceptance: ingest, crash-between state,
//           delete pipeline, repair, join integrity, top-k edges, dim
//           mismatch, duplicate ids, reopen integrity, payloads, WAL prefix
//           and torn-tail recovery.
//   writer -- ingest N rows + embeddings, persist the vector WAL, then hang
//           (scripts/hybrid_crash_test.* hard-kills the process).
//   verify -- reopen both stores after the kill, run the repair pass, check
//           100% join integrity (the headline gate); idempotent re-runs.
//
// Env:
//   ORBITDB_HYBRID_ROWS  row store path                (required)
//   ORBITDB_HYBRID_VEC   vector WAL path               (required)
//   ORBITDB_HYBRID_N     row count                     (default 1000)
//   ORBITDB_HYBRID_DIM   vector dimension              (default 8)
//   ORBITDB_HYBRID_SKIP  trailing rows committed but NOT embedded (default 10)
//   ORBITDB_HYBRID_LAG   rows bumped to version 2 without re-embed (default 3)
//   ORBITDB_HYBRID_CHUNK upsert_many chunk size        (default 200)
//   ORBITDB_HYBRID_Q     query count                   (default 8)
//   ORBITDB_HYBRID_K     top-k                         (default 20)
//
// Exit: 0 = all checks passed, 1 = check failed, 2 = bad env.

module orbitdb_probe_hybrid

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.num.float;
use xiom.string.slice;
use xiom.db.engine;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.payload.payload;
use xiom.vector.query.search_service;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

// Row-store key layout (documented in docs/XVECTOR-INTEGRATION.md section 2):
//   key id            row payload (value = the join id itself today)
//   ROWVER_BASE + id  row version        (bumped when the row changes)
//   EMBVER_BASE + id  embedding version  (last row version embedded)
const ROWVER_BASE: Int = 100000000;
const EMBVER_BASE: Int = 200000000;

// ===========================================================================
// Shared helpers
// ===========================================================================

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

// Deterministic embedding for (id, row version): both stores regenerate it
// independently (repair pass, brute-force model).
fn embed_vec(id: Int, rv: Int, dim: Int) -> Vector {
  var v = Vector.new(dim);
  var s = id * 7919 + rv * 104729;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    let c = ((s % 2001) as Float32) / 1000.0 - 1.0;
    v.set(i, c);
    i = i + 1;
  }
  return v;
}

fn query_vec(q: Int, dim: Int) -> Vector {
  return embed_vec(1000000 + q, 7, dim);
}

fn payload_for(id: Int) -> Payload {
  var p = payload_new();
  payload_set(&mut p, "bucket", FieldValue.IntVal(id % 3));
  return p;
}

fn rowver_key(id: Int) -> Int { return ROWVER_BASE + id; }

fn embver_key(id: Int) -> Int { return EMBVER_BASE + id; }

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn ints_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn seq_vec(from: Int, to: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i: Int = from;
  while i <= to {
    v.push(i);
    i = i + 1;
  }
  return v;
}

fn get_or(db: &DBFile, key: Int, dflt: Int) -> Int {
  match db_file_get(db, key) {
    Some(v) => { return v; }
    None => { return dflt; }
  }
}

fn env_int(name: Str, dflt: Int) -> Int {
  match parse.parse_int(env.var_or(name, "")) {
    Ok(v) => { return v; }
    Err(_) => { return dflt; }
  }
}

// ===========================================================================
// Store operations
// ===========================================================================

// Ingest rows 1..n transactionally (100/row txn), writing the row, its row
// version (1) and its embedding-version slot (0 = not embedded yet). A
// checkpoint at `ckpt_at` rows exercises snapshot+tail recovery.
fn ingest_rows(db: &mut DBFile, n: Int, ckpt_at: Int) -> Int {
  var start: Int = 1;
  while start <= n {
    var end: Int = start + 99;
    if end > n { end = n; }
    if !db_file_txn_begin(db) { return 1; }
    var k: Int = start;
    while k <= end {
      if !db_file_txn_put(db, k, k) { return 1; }
      if !db_file_txn_put(db, rowver_key(k), 1) { return 1; }
      if !db_file_txn_put(db, embver_key(k), 0) { return 1; }
      k = k + 1;
    }
    if !db_file_txn_commit(db) { return 1; }
    if ckpt_at > 0 && end == ckpt_at {
      let anchor = db_file_checkpoint(db);
      if anchor < 0 { return 2; }
    }
    start = end + 1;
  }
  return 0;
}

// Embed rows lo..hi in upsert_many chunks at row version `rv`; after each
// chunk the embedding-version slots are advanced in one transaction.
fn embed_range(eng: &mut VectorEngine, db: &mut DBFile, lo: Int, hi: Int,
               rv: Int, dim: Int, chunk: Int) -> Int {
  var start: Int = lo;
  while start <= hi {
    var end: Int = start + chunk - 1;
    if end > hi { end = hi; }
    var ids = Vec[Int].new();
    var vecs = Vec[Vector].new();
    var i: Int = start;
    while i <= end {
      ids.push(i);
      vecs.push(embed_vec(i, rv, dim));
      i = i + 1;
    }
    match upsert_many(eng, &ids, &vecs) {
      Ok(_) => {}
      Err(_) => { return 1; }
    }
    if !db_file_txn_begin(db) { return 1; }
    var j: Int = start;
    while j <= end {
      if !db_file_txn_put(db, embver_key(j), rv) { return 1; }
      j = j + 1;
    }
    if !db_file_txn_commit(db) { return 1; }
    start = end + 1;
  }
  return 0;
}

// The repair pass (consumer-side, documented pattern): re-embed every live
// row whose embedding version lags its row version; the slot advances last,
// so a crash mid-repair just re-embeds again (idempotent). Tombstoned rows
// are skipped (their vectors are GC-swept separately).
fn repair_rows(db: &mut DBFile, eng: &mut VectorEngine, n: Int, dim: Int) -> Int {
  var repaired: Int = 0;
  var i: Int = 1;
  while i <= n {
    match db_file_get(db, i) {
      Some(_) => {
        let rv = get_or(db, rowver_key(i), -1);
        let ev = get_or(db, embver_key(i), -1);
        if rv < 0 || ev < 0 { return -1; }
        if ev < rv {
          let v = embed_vec(i, rv, dim);
          match upsert(eng, i, v) {
            Ok(_) => {}
            Err(_) => { return -1; }
          }
          if !db_file_put(db, embver_key(i), rv) { return -1; }
          repaired = repaired + 1;
        }
      }
      None => {}
    }
    i = i + 1;
  }
  return repaired;
}

fn search_ids(eng: &VectorEngine, q: &Vector, k: Int, out: &mut Vec[Int]) -> Bool {
  match search(eng, q, k) {
    Ok(hits) => {
      var i: Int = 0;
      while i < hits.items.len() {
        out.push(hits.items[i].id);
        i = i + 1;
      }
      return true;
    }
    Err(_) => { return false; }
  }
}

fn search_contains(eng: &VectorEngine, q: &Vector, k: Int, id: Int) -> Bool {
  match search(eng, q, k) {
    Ok(hits) => {
      var i: Int = 0;
      while i < hits.items.len() {
        if hits.items[i].id == id { return true; }
        i = i + 1;
      }
      return false;
    }
    Err(_) => { return false; }
  }
}

// Does the JOINED result (hits whose row still exists) contain `id`? A
// tombstoned id must never surface through the join even while its orphan
// vector is still searchable.
fn joined_contains(db: &DBFile, eng: &VectorEngine, q: &Vector, k: Int, id: Int) -> Bool {
  match search(eng, q, k) {
    Ok(hits) => {
      var i: Int = 0;
      while i < hits.items.len() {
        if hits.items[i].id == id && get_or(db, id, -1) >= 0 { return true; }
        i = i + 1;
      }
      return false;
    }
    Err(_) => { return false; }
  }
}

// Join integrity over Q queries: every hit maps to a live row, no duplicate
// ids inside a result set, results sorted by score (distance, ascending).
fn join_check(db: &DBFile, eng: &VectorEngine, qn: Int, dim: Int, k: Int,
              fails: Int, label: Str) -> Int {
  var checked: Int = 0;
  var dangling: Int = 0;
  var dup: Int = 0;
  var unsorted: Int = 0;
  var q: Int = 1;
  while q <= qn {
    let qv = query_vec(q, dim);
    match search(eng, &qv, k) {
      Ok(hits) => {
        var i: Int = 0;
        while i < hits.items.len() {
          checked = checked + 1;
          if get_or(db, hits.items[i].id, -1) < 0 { dangling = dangling + 1; }
          var j: Int = i + 1;
          while j < hits.items.len() {
            if hits.items[j].id == hits.items[i].id { dup = dup + 1; }
            j = j + 1;
          }
          if i > 0 {
            if hits.items[i - 1].distance > hits.items[i].distance { unsorted = unsorted + 1; }
          }
          i = i + 1;
        }
      }
      Err(_) => { return fails + 1; }
    }
    q = q + 1;
  }
  return check(checked > 0 && dangling == 0 && dup == 0 && unsorted == 0, label, fails);
}

// Brute-force exact top-k over candidate ids (Flat search is exact, so the
// engine must agree with this model bit-for-bit on ids and order).
fn brute_topk(db: &DBFile, cands: &Vec[Int], q: &Vector, dim: Int, k: Int) -> Vec[Int] {
  var ids = Vec[Int].new();
  var dists = Vec[Float32].new();
  var c: Int = 0;
  while c < cands.len() {
    var rv: Int = 1;
    match db_file_get(db, rowver_key(cands[c])) {
      Some(v) => { rv = v; }
      None => { rv = 1; }
    }
    let v = embed_vec(cands[c], rv, dim);
    let d = cosine_distance(q, &v);
    ids.push(cands[c]);
    dists.push(d);
    var pos: Int = ids.len() - 1;
    while pos > 0 && dists[pos - 1] > dists[pos] {
      let ti = ids[pos];
      ids[pos] = ids[pos - 1];
      ids[pos - 1] = ti;
      let td = dists[pos];
      dists[pos] = dists[pos - 1];
      dists[pos - 1] = td;
      pos = pos - 1;
    }
    if ids.len() > k {
      ids.pop();
      dists.pop();
    }
    c = c + 1;
  }
  return ids;
}

fn brute_equals_search(db: &DBFile, eng: &VectorEngine, cands: &Vec[Int],
                       qn: Int, dim: Int, k: Int) -> Bool {
  var q: Int = 1;
  while q <= qn {
    let qv = query_vec(q, dim);
    let expect = brute_topk(db, cands, &qv, dim, k);
    var got = Vec[Int].new();
    if !search_ids(eng, &qv, k, &mut got) { return false; }
    if !ints_eq(&got, &expect) { return false; }
    q = q + 1;
  }
  return true;
}

// Live candidates: row present and embedding version >= row version.
fn live_candidates(db: &DBFile, n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i: Int = 1;
  while i <= n {
    match db_file_get(db, i) {
      Some(_) => {
        let rv = get_or(db, rowver_key(i), -1);
        let ev = get_or(db, embver_key(i), -1);
        if rv > 0 && ev >= rv { out.push(i); }
      }
      None => {}
    }
    i = i + 1;
  }
  return out;
}

fn count_slots_ok(db: &DBFile, n: Int) -> Int {
  var bad: Int = 0;
  var i: Int = 1;
  while i <= n {
    match db_file_get(db, i) {
      Some(_) => {
        if get_or(db, rowver_key(i), -1) != get_or(db, embver_key(i), -2) { bad = bad + 1; }
      }
      None => {}
    }
    i = i + 1;
  }
  return bad;
}

// Live rows whose embedding version lags the row version (repair backlog).
fn gap_count(db: &DBFile, n: Int) -> Int {
  var gaps: Int = 0;
  var i: Int = 1;
  while i <= n {
    match db_file_get(db, i) {
      Some(_) => {
        if get_or(db, embver_key(i), -1) < get_or(db, rowver_key(i), -2) { gaps = gaps + 1; }
      }
      None => {}
    }
    i = i + 1;
  }
  return gaps;
}

// Recovered results bit-match the live engine (ids and Float32 distances).
fn results_bits_match(a: &VectorEngine, b: &VectorEngine, q: &Vector, k: Int) -> Bool {
  var aid = Vec[Int].new();
  var ad = Vec[Float32].new();
  var bid = Vec[Int].new();
  var bd = Vec[Float32].new();
  match search(a, q, k) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        aid.push(h.items[i].id);
        ad.push(h.items[i].distance);
        i = i + 1;
      }
    }
    Err(_) => { return false; }
  }
  match search(b, q, k) {
    Ok(h) => {
      var i: Int = 0;
      while i < h.items.len() {
        bid.push(h.items[i].id);
        bd.push(h.items[i].distance);
        i = i + 1;
      }
    }
    Err(_) => { return false; }
  }
  if aid.len() != bid.len() { return false; }
  var j: Int = 0;
  while j < aid.len() {
    if aid[j] != bid[j] { return false; }
    if float.float_bits(ad[j] as Float64) != float.float_bits(bd[j] as Float64) { return false; }
    j = j + 1;
  }
  return true;
}

fn payload_bucket(eng: &VectorEngine, id: Int) -> Int {
  match get_payload(eng, id) {
    Some(p) => {
      match payload_get(&p, "bucket") {
        Some(fv) => {
          match fv {
            FieldValue.IntVal(v) => { return v; }
            _ => { return -1; }
          }
        }
        None => { return -1; }
      }
    }
    None => { return -1; }
  }
}

// ===========================================================================
// full mode -- in-process acceptance
// ===========================================================================

fn run_full(rows_path: Str, vec_path: Str, n: Int, dim: Int, skip: Int, lag: Int,
            chunk: Int, qn: Int, k: Int) -> Int {
  var fails: Int = 0;
  if n < 200 || skip < 1 || lag < 1 {
    io.println("hybrid: full mode needs N>=200, SKIP>=1, LAG>=1");
    return 2;
  }
  io.println("hybrid: full n=" + convert.int_to_string(n) + " dim=" + convert.int_to_string(dim)
    + " skip=" + convert.int_to_string(skip) + " lag=" + convert.int_to_string(lag));

  // --- ingest + initial embeddings ---------------------------------------
  var db = db_file_open(rows_path, 4);
  let rc = ingest_rows(&mut db, n, n / 2);
  if rc != 0 { io.println("hybrid: ingest failed rc=" + convert.int_to_string(rc)); return 1; }
  fails = check(get_or(&db, 1, -1) == 1 && get_or(&db, n, -1) == n,
    "ingest: rows 1..N present (snapshot at N/2 + tail)", fails);
  fails = check(get_or(&db, embver_key(n), -1) == 0 && get_or(&db, rowver_key(n), -1) == 1,
    "ingest: version slots written in the same transaction", fails);
  fails = check(ints_eq(&db_file_range(&db, 1, 3), &seq_vec(1, 3)),
    "ingest: key range [1,3] = [1,2,3]", fails);

  var eng = engine_new();
  match create_collection(&mut eng, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("hybrid: create_collection failed"); return 1; }
  }
  let erc = embed_range(&mut eng, &mut db, 1, n - skip, 1, dim, chunk);
  if erc != 0 { io.println("hybrid: embed failed rc=" + convert.int_to_string(erc)); return 1; }
  fails = check(engine_size(&eng) == n - skip, "embed: engine size = N-SKIP", fails);

  // Crash-between state: rows n-skip+1..n were committed but never embedded.
  fails = check(!search_contains(&eng, &embed_vec(n, 1, dim), 3, n),
    "crash-between: skipped row unsearchable (no dangling hit)", fails);
  fails = join_check(&db, &eng, qn, dim, k, fails,
    "pre-repair: every hit joins a live row (sorted, unique)");

  // --- lag: bump LAG rows to version 2 without re-embedding --------------
  if !db_file_txn_begin(&mut db) { return 1; }
  var l: Int = 1;
  while l <= lag {
    if !db_file_txn_put(&mut db, rowver_key(l), 2) { return 1; }
    l = l + 1;
  }
  if !db_file_txn_commit(&mut db) { return 1; }

  // --- delete pipeline ----------------------------------------------------
  let d1a = n - 99;
  let d2a = n - 96;
  var d: Int = 0;
  while d < 3 {
    if !db_file_delete(&mut db, d1a + d) { return 1; }             // row tombstone first
    match delete_point(&mut eng, d1a + d) {                        // then vector delete
      Ok(_) => {}
      Err(_) => { return 1; }
    }
    d = d + 1;
  }
  var d2_alive: Int = 0;
  d = 0;
  while d < 3 {
    if !db_file_delete(&mut db, d2a + d) { return 1; }             // tombstone only (simulated crash)
    if search_contains(&eng, &embed_vec(d2a + d, 1, dim), 1, d2a + d) { d2_alive = d2_alive + 1; }
    d = d + 1;
  }
  fails = check(d2_alive == 3, "delete pipeline: orphan vectors remain searchable (pre-GC)", fails);
  fails = check(!joined_contains(&db, &eng, &embed_vec(d2a, 1, dim), 3, d2a),
    "delete pipeline: tombstoned hit is skipped by the join", fails);
  d = 0;
  while d < 3 {
    match delete_point(&mut eng, d2a + d) {                        // GC sweep (blind, safe)
      Ok(_) => {}
      Err(_) => { return 1; }
    }
    d = d + 1;
  }

  // --- repair -------------------------------------------------------------
  let repaired = repair_rows(&mut db, &mut eng, n, dim);
  fails = check(repaired == skip + lag,
    "repair: re-embedded SKIP+LAG rows (repaired=" + convert.int_to_string(repaired) + ")", fails);
  fails = check(count_slots_ok(&db, n) == 0, "repair: every live row ev == rv", fails);
  let cands = live_candidates(&db, n);
  fails = check(cands.len() == n - 6, "repair: live rows = N-6 (3+3 tombstoned)", fails);
  fails = check(engine_size(&eng) == cands.len(), "repair: exactly one vector per live row", fails);
  fails = join_check(&db, &eng, qn, dim, k, fails,
    "post-repair: every hit joins a live row (sorted, unique)");
  fails = check(brute_equals_search(&db, &eng, &cands, qn, dim, k),
    "post-repair: engine == brute-force exact top-k (ids + order)", fails);

  // Every live row searchable again (repair closed the version gap).
  var all_searchable: Bool = true;
  var vi: Int = 0;
  while vi < cands.len() {
    let rvi = get_or(&db, rowver_key(cands[vi]), -1);
    if !search_contains(&eng, &embed_vec(cands[vi], rvi, dim), 5, cands[vi]) { all_searchable = false; }
    vi = vi + 1;
  }
  fails = check(all_searchable, "post-repair: every live row searchable", fails);

  // --- top-k edges + duplicate ids + readd --------------------------------
  let one = query_vec(1, dim);
  var k1 = Vec[Int].new();
  fails = check(search_ids(&eng, &one, 1, &mut k1) && k1.len() == 1, "edges: k=1 returns one hit", fails);
  var kbig = Vec[Int].new();
  fails = check(search_ids(&eng, &one, n + 50, &mut kbig) && kbig.len() == cands.len(),
    "edges: k > live size returns all live hits", fails);
  // k=0: per-call search traps on its `requires: k > 0` contract, so the
  // rejection path is the batch/range API (validated Err, no trap).
  var zero_qs = Vec[Vector].new();
  zero_qs.push(query_vec(1, dim));
  var kzero_ok: Bool = false;
  match search_many(&eng, &zero_qs, 0) {
    Ok(_) => { kzero_ok = false; }
    Err(_) => { kzero_ok = true; }
  }
  fails = check(kzero_ok, "edges: k=0 rejected by the batch API (Err)", fails);
  var rzero_ok: Bool = false;
  match search_range(&eng, &one, 0.5, 0) {
    Ok(_) => { rzero_ok = false; }
    Err(_) => { rzero_ok = true; }
  }
  fails = check(rzero_ok, "edges: range limit=0 rejected (Err)", fails);
  var kmax = Vec[Int].new();
  fails = check(search_ids(&eng, &one, 10000, &mut kmax) && kmax.len() == cands.len(),
    "edges: k=10000 accepted", fails);

  var dup_id: Int = 7;
  let dup_rv = get_or(&db, rowver_key(dup_id), -1);
  let size_before = engine_size(&eng);
  match upsert(&mut eng, dup_id, embed_vec(dup_id, dup_rv, dim)) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(engine_size(&eng) == size_before, "duplicate ids: repeated upsert overwrites (no dup)", fails);
  match delete_point(&mut eng, dup_id) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var gone: Bool = false;
  match get_point(&eng, dup_id) {
    Some(_) => { gone = false; }
    None => { gone = true; }
  }
  fails = check(gone, "duplicate ids: delete removes the point", fails);
  match upsert(&mut eng, dup_id, embed_vec(dup_id, dup_rv, dim)) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var revived: Bool = false;
  match get_point(&eng, dup_id) {
    Some(_) => { revived = true; }
    None => { revived = false; }
  }
  fails = check(revived, "duplicate ids: delete then re-add revives", fails);

  // --- dimension mismatch + new collection --------------------------------
  var badv = Vector.new(dim + 1);
  match upsert(&mut eng, n + 10, badv) {
    Ok(_) => { fails = fails + 1; }
    Err(_) => {}
  }
  let badq = query_vec(1, dim + 1);
  var badhits = Vec[Int].new();
  fails = check(!search_ids(&eng, &badq, 3, &mut badhits),
    "dim mismatch: wrong-dim query and vector rejected", fails);

  var eng2 = engine_new();
  match create_collection(&mut eng2, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { return 1; }
  }
  var v2 = Vector.new(dim);
  v2.set(0, 1.0);
  match upsert(&mut eng2, 1, v2) {
    Ok(_) => {}
    Err(_) => { return 1; }
  }
  match create_collection(&mut eng2, dim + 3, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(engine_size(&eng2) == 0, "dim: re-embed at a new dim resets to a new collection", fails);
  var v3 = Vector.new(dim + 3);
  v3.set(0, 1.0);
  match upsert(&mut eng2, 1, v3) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var nk = Vec[Int].new();
  fails = check(search_ids(&eng2, &v3, 1, &mut nk) && nk.len() == 1 && nk[0] == 1,
    "dim: new-dim collection upsert + search", fails);

  // --- payloads + persist + reopen integrity ------------------------------
  var pi: Int = 1;
  while pi <= 5 {
    match set_payload(&mut eng, pi, payload_for(pi)) {
      Ok(_) => {}
      Err(_) => { fails = fails + 1; }
    }
    pi = pi + 1;
  }
  let anchor = db_file_checkpoint(&mut db);
  fails = check(anchor >= 0, "persist: row checkpoint committed (anchor=" + convert.int_to_string(anchor) + ")", fails);

  // Three marker upserts make the last 3 WAL records deterministic for the
  // prefix test (ids n+1..n+3 have no row: join-skipped markers).
  var mk: Int = n + 1;
  while mk <= n + 3 {
    match upsert(&mut eng, mk, embed_vec(mk, 1, dim)) {
      Ok(_) => {}
      Err(_) => { fails = fails + 1; }
    }
    mk = mk + 1;
  }
  fails = check(wal_persist(&eng.wal, vec_path), "persist: vector WAL persisted", fails);
  let eng_size = engine_size(&eng);

  var db2 = db_file_open(rows_path, 4);
  fails = check(get_or(&db2, 1, -1) == 1 && get_or(&db2, d1a, -1) == -1,
    "reopen: rows recovered (tombstones stay deleted)", fails);
  fails = check(ints_eq(&db_file_range(&db2, 200, 204), &seq_vec(200, 204)),
    "reopen: range [200,204] = [200..204]", fails);
  fails = check(get_or(&db2, rowver_key(1), -1) == 2 && get_or(&db2, embver_key(1), -1) == 2,
    "reopen: repaired version slots persisted", fails);

  var wr2 = wal_load(vec_path);
  var eng_r = engine_recover(&wr2, dim, DistanceMetric.Cosine);
  fails = check(engine_size(&eng_r) == eng_size, "reopen: vector size matches", fails);
  var bits_ok: Bool = true;
  var qq: Int = 1;
  while qq <= qn {
    let qv = query_vec(qq, dim);
    if !results_bits_match(&eng, &eng_r, &qv, k) { bits_ok = false; }
    qq = qq + 1;
  }
  fails = check(bits_ok, "reopen: search results bit-identical (ids + distances)", fails);
  var pl_ok: Bool = true;
  var pj: Int = 1;
  while pj <= 5 {
    if payload_bucket(&eng_r, pj) != pj % 3 { pl_ok = false; }
    pj = pj + 1;
  }
  fails = check(pl_ok, "reopen: payloads intact (ids 1..5)", fails);

  // --- WAL prefix (record boundary) + torn tail ---------------------------
  var prefix = wal_writer_new();
  var pr: Int = 0;
  while pr < wr2.records.len() - 3 {
    let rec = wr2.records[pr];
    wal_writer_append_payload(&mut prefix, rec.op, rec.key, rec.value, rec.payload);
    pr = pr + 1;
  }
  let ppref = wal_persist(&prefix, vec_path + ".prefix");
  var eng_p = engine_recover(&wal_load(vec_path + ".prefix"), dim, DistanceMetric.Cosine);
  var pref_ok: Bool = ppref && engine_size(&eng_p) == eng_size - 3;
  var mj: Int = n + 1;
  while mj <= n + 3 {
    var have: Bool = false;
    match get_point(&eng_p, mj) {
      Some(_) => { have = true; }
      None => { have = false; }
    }
    if have { pref_ok = false; }
    mj = mj + 1;
  }
  fails = check(pref_ok, "WAL prefix: recovery = full minus last 3 records", fails);

  match io.read_file_bytes(vec_path) {
    Ok(b) => {
      var torn = Vec[UInt8].new();
      var bi: Int = 0;
      while bi < b.len() {
        torn.push(b[bi]);
        bi = bi + 1;
      }
      let tail = slice.str_bytes("torn");
      var ti: Int = 0;
      while ti < tail.len() {
        torn.push(tail[ti]);
        ti = ti + 1;
      }
      match io.write_file_bytes(vec_path + ".torn", &torn) {
        Ok(_) => {
          var wr_t = wal_load(vec_path + ".torn");
          var eng_t = engine_recover(&wr_t, dim, DistanceMetric.Cosine);
          fails = check(engine_size(&eng_t) == eng_size,
            "torn tail: longest valid prefix recovered (full state)", fails);
        }
        Err(_) => { fails = check(false, "torn tail: write failed", fails); }
      }
    }
    Err(_) => { fails = check(false, "torn tail: read failed", fails); }
  }

  if fails == 0 { io.println("hybrid: FULL GREEN"); return 0; }
  io.println("hybrid: FULL RED fails=" + convert.int_to_string(fails));
  return 1;
}

// ===========================================================================
// writer mode -- ingest, persist, hang (harness kills the process)
// ===========================================================================

fn run_writer(rows_path: Str, vec_path: Str, n: Int, dim: Int, skip: Int, lag: Int,
              chunk: Int) -> Int {
  var db = db_file_open(rows_path, 4);
  let rc = ingest_rows(&mut db, n, n / 2);
  if rc != 0 { io.println("writer: ingest failed rc=" + convert.int_to_string(rc)); return 1; }
  var eng = engine_new();
  match create_collection(&mut eng, dim, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("writer: create_collection failed"); return 1; }
  }
  let erc = embed_range(&mut eng, &mut db, 1, n - skip, 1, dim, chunk);
  if erc != 0 { io.println("writer: embed failed rc=" + convert.int_to_string(erc)); return 1; }
  if lag > 0 {
    if !db_file_txn_begin(&mut db) { return 1; }
    var l: Int = 1;
    while l <= lag {
      if !db_file_txn_put(&mut db, rowver_key(l), 2) { return 1; }
      l = l + 1;
    }
    if !db_file_txn_commit(&mut db) { return 1; }
  }
  if !wal_persist(&eng.wal, vec_path) { io.println("writer: persist failed"); return 1; }
  io.println("writer: ready rows=" + convert.int_to_string(n)
    + " embedded=" + convert.int_to_string(n - skip) + " rv2=" + convert.int_to_string(lag));
  // Hang until the harness hard-kills us (crash simulation).
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

// ===========================================================================
// verify mode -- reopen after the kill, repair, 100% join integrity
// ===========================================================================

fn run_verify(rows_path: Str, vec_path: Str, n: Int, dim: Int, skip: Int, lag: Int,
              qn: Int, k: Int) -> Int {
  var fails: Int = 0;
  var db = db_file_open(rows_path, 4);
  fails = check(get_or(&db, 1, -1) == 1 && get_or(&db, n, -1) == n,
    "verify: all N rows recovered (snapshot + tail replay)", fails);

  var wr = wal_load(vec_path);
  var eng = engine_recover(&wr, dim, DistanceMetric.Cosine);
  // The first verify finds the crash state (gaps: SKIP unembedded + LAG
  // stale); later verifies find the persisted post-repair state. Both are
  // fully checked: the mode only picks the expectations.
  let gaps = gap_count(&db, n);
  fails = check(gaps == skip + lag || gaps == 0,
    "verify: gap count is crash-state (SKIP+LAG) or repaired (0), got=" + convert.int_to_string(gaps), fails);
  fails = check((gaps > 0 && engine_size(&eng) == n - skip) || (gaps == 0 && engine_size(&eng) == n),
    "verify: vector count matches state (crash=N-SKIP / repaired=N)", fails);
  if gaps > 0 {
    fails = check(!search_contains(&eng, &embed_vec(n, 1, dim), 3, n),
      "verify: skipped rows unsearchable before repair (no dangling hit)", fails);
  }
  fails = join_check(&db, &eng, qn, dim, k, fails,
    "verify: every hit joins before repair (sorted, unique)");

  let repaired = repair_rows(&mut db, &mut eng, n, dim);
  if gaps > 0 {
    fails = check(repaired == skip + lag,
      "verify: repair pass re-embedded SKIP+LAG rows (repaired=" + convert.int_to_string(repaired) + ")", fails);
  } else {
    fails = check(repaired == 0,
      "verify: repaired state is idempotent (repaired=0)", fails);
  }
  fails = check(engine_size(&eng) == n, "verify: all N rows have vectors after repair", fails);
  var all_searchable: Bool = true;
  var i: Int = 1;
  while i <= n {
    let rvi = get_or(&db, rowver_key(i), -1);
    if !search_contains(&eng, &embed_vec(i, rvi, dim), 5, i) { all_searchable = false; }
    i = i + 1;
  }
  fails = check(all_searchable, "verify: every live row searchable after repair", fails);
  fails = join_check(&db, &eng, qn, dim, k, fails,
    "verify: 100% join integrity after repair (headline gate)");
  fails = check(count_slots_ok(&db, n) == 0, "verify: every live row ev == rv after repair", fails);

  if !wal_persist(&eng.wal, vec_path) { fails = fails + 1; }
  io.println("verify: repaired=" + convert.int_to_string(repaired)
    + " rows=" + convert.int_to_string(n)
    + " vectors=" + convert.int_to_string(engine_size(&eng)));
  if fails == 0 { io.println("verify: GREEN"); return 0; }
  io.println("verify: RED fails=" + convert.int_to_string(fails));
  return 1;
}

// ===========================================================================
// main
// ===========================================================================

fn main() -> Int {
  let rows_path = env.var_or("ORBITDB_HYBRID_ROWS", "");
  let vec_path = env.var_or("ORBITDB_HYBRID_VEC", "");
  if rows_path == "" || vec_path == "" {
    io.println("hybrid: ORBITDB_HYBRID_ROWS and ORBITDB_HYBRID_VEC are required");
    return 2;
  }
  let n = env_int("ORBITDB_HYBRID_N", 1000);
  let dim = env_int("ORBITDB_HYBRID_DIM", 8);
  let skip = env_int("ORBITDB_HYBRID_SKIP", 10);
  let lag = env_int("ORBITDB_HYBRID_LAG", 3);
  let chunk = env_int("ORBITDB_HYBRID_CHUNK", 200);
  let qn = env_int("ORBITDB_HYBRID_Q", 8);
  let k = env_int("ORBITDB_HYBRID_K", 20);
  let mode = env.var_or("ORBITDB_HYBRID_MODE", "full");
  if mode == "writer" {
    return run_writer(rows_path, vec_path, n, dim, skip, lag, chunk);
  }
  if mode == "verify" {
    return run_verify(rows_path, vec_path, n, dim, skip, lag, qn, k);
  }
  return run_full(rows_path, vec_path, n, dim, skip, lag, chunk, qn, k);
}
