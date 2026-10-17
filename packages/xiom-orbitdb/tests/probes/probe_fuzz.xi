// XIOM ORBITDB -- deterministic seeded fuzz/property harness.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// No wall-clock, no OS entropy: every run over a fixed seed matrix is
// reproducible. Sections:
//   (a) tuple codec -- roundtrip + byte-flip mutations (decode must reject or
//       re-encode to the exact mutated buffer) + truncation rejection;
//   (b) WAL segment parser -- valid records interleaved with garbage lines and
//       an optional torn tail; replay must return exactly the valid records
//       with strictly increasing LSNs, and open() must heal before appending;
//   (c) page log parser -- latest-wins across CRC-valid versions; corrupted
//       checksums are skipped; garbage/torn lines never count;
//   (d) B-tree vs model -- random insert/update/delete/search/range/min/max
//       against a flat model, several orders and seeds;
//   (e) block codec v2 -- random page/header roundtrips + single-byte
//       mutations (decode must reject or reflect the mutation; it must never
//       decode back to the original view);
//   (f) block store vs model -- random put generations with probabilistic
//       commits, an open/compare after every commit and at the end (visible
//       set + latest payload per id must match the committed history);
//   (g) query + secondary index vs model -- random put/delete + random
//       conditions/order/limit/offset on a DBFile with an index installed;
//       results must equal a brute-force model and usable conditions must
//       plan as IndexValue;
//   (h) tuple codec v2 -- typed-value rows (null/int/float/text/blob):
//       encode -> decode -> per-kind model assertions -> single-byte
//       mutations (reject or visibly change the row);
//   (i) schema rows -- random schemas (1..6 cols, random types/nullability,
//       int pk) + valid rows: validate/key/encode/decode must agree and
//       roundtrip byte-identically; every single-column violation (null on
//       non-nullable, kind mismatch, pk non-int) must be rejected;
//   (j) db_file typed rows -- random put/put_typed/delete mixes with
//       periodic checkpoints/reopens vs a model (size/get/get_typed/range
//       checked after every op, incl. after recovery);
//   (k) typed queries -- random typed rows + conditions/order/limit/offset vs
//       an independent model;
//   (l) snapshot pins + savepoints (M3) -- random put/delete/pin/end-pin/
//       checkpoint/reopen/txn-savepoint streams; the live tree and EVERY live
//       pin must match their models after every op; a final reopen must match
//       the live model.
//
// Env:
//   ORBITDB_FUZZ_DIR          scratch dir                     (default probe-logs)
//   ORBITDB_FUZZ_SEEDS        seed count                     (default 4)
//   ORBITDB_FUZZ_OPS          btree ops per seed             (default 4000)
//   ORBITDB_FUZZ_N            btree key space                (default 512)
//   ORBITDB_FUZZ_TUPLE_ITERS  tuple iterations per seed      (default 300)
//   ORBITDB_FUZZ_WAL_ITERS    WAL files per seed             (default 30)
//   ORBITDB_FUZZ_PAGE_ITERS   page logs per seed             (default 30)
//   ORBITDB_FUZZ_BLOCK_ITERS  block-codec iterations per seed (default 200)
//   ORBITDB_FUZZ_BLOCKSTORE_GENS  block-store generations per seed (default 12)
//   ORBITDB_FUZZ_QUERY_ITERS    query/index iterations per seed (default 150)
//   ORBITDB_FUZZ_TUPLE2_ITERS   tuple-v2 iterations per seed    (default 200)
//   ORBITDB_FUZZ_SCHEMA_ITERS   schema-row iterations per seed  (default 150)
//   ORBITDB_FUZZ_TYPED_ITERS    db typed-row iterations per seed (default 200)
//   ORBITDB_FUZZ_TQUERY_ITERS   typed-query iterations per seed  (default 150)
//   ORBITDB_FUZZ_PINS_ITERS     pin/savepoint iterations per seed (default 150)
//
// Exit: 0 = green; non-zero = failing section + first violation (printed).

module orbitdb_probe_fuzz

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.engine;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.secondary_index;
use xiom.db.storage.tuple;
use xiom.db.wal_file;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;

fn rand_next(state: &mut Int) -> Int {
  *state = (*state * 1103515245 + 12345) % 2147483648;
  return *state;
}

// High-bit modulus: the LCG's low bits cycle with small periods, so a plain
// `% m` for non-power-of-two m can starve whole branches (e.g. action = 11
// never being selected) -- the fuzz must exercise every branch.
fn rand_mod(state: &mut Int, m: Int) -> Int {
  if m <= 1 { return 0; }
  return (rand_next(state) / 65536) % m;
}

fn value_of(key: Int) -> Int {
  return key * 7 + 1;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn parse_env_int(name: Str, fallback: Int) -> Int {
  var out = fallback;
  match parse.parse_int(env.var_or(name, convert.int_to_string(fallback))) {
    Ok(v) => { if v > 0 { out = v; } }
    Err(_) => {}
  }
  return out;
}

// (a) tuple codec fuzz -------------------------------------------------------
fn fuzz_tuple(seed: Int, iters: Int) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    var row_id = rand_next(&mut state) % 2000003 - 1000000;
    var cols = rand_mod(&mut state, 6);
    var data = Vec[Int].new();
    var c = 0;
    while c < cols {
      data.push(rand_next(&mut state) % 4096 - 2048);
      c = c + 1;
    }
    var row = Row.new(row_id, data);

    let enc_r = tuple_encode_checked(&row);
    var enc = Vec[Int].new();
    match enc_r {
      Ok(p) => {
        let v: Vec[Int] = p;
        enc = v;
      }
      Err(_) => {
        io.println("fuzz tuple: encode rejected a valid row it=" + convert.int_to_string(it));
        return 1;
      }
    }

    let dec_r = tuple_decode(&enc);
    match dec_r {
      Ok(p) => {
        let back: Row = p;
        if back.id != row_id { io.println("fuzz tuple: id mismatch"); return 2; }
        if back.data.len() != cols { io.println("fuzz tuple: column count"); return 3; }
        var ci = 0;
        while ci < cols {
          if back.data[ci] != row.data[ci] { io.println("fuzz tuple: column value"); return 4; }
          ci = ci + 1;
        }
      }
      Err(_) => {
        io.println("fuzz tuple: decode rejected a valid encoding it=" + convert.int_to_string(it));
        return 5;
      }
    }

    // Byte-flip mutation: decode must reject, or produce a row whose
    // re-encoding reproduces the mutated buffer byte-for-byte (canonical v1).
    var mbuf = Vec[Int].new();
    var mi = 0;
    while mi < enc.len() {
      mbuf.push(enc[mi]);
      mi = mi + 1;
    }
    let pos = rand_mod(&mut state, mbuf.len());
    let delta = rand_mod(&mut state, 255) + 1;
    mbuf[pos] = (mbuf[pos] + delta) & 0xFF;
    let mr = tuple_decode(&mbuf);
    match mr {
      Ok(p) => {
        let mrow: Row = p;
        let re = tuple_encode(&mrow);
        if !vec_eq(&re, &mbuf) {
          io.println("fuzz tuple: mutated decode not canonical it=" + convert.int_to_string(it));
          return 6;
        }
      }
      Err(_) => {}
    }

    // Strict-prefix truncation must be rejected by the length gate.
    let cut = rand_next(&mut state) % enc.len();
    var trunc = Vec[Int].new();
    var ti = 0;
    while ti < cut {
      trunc.push(enc[ti]);
      ti = ti + 1;
    }
    let tr = tuple_decode(&trunc);
    match tr {
      Ok(_) => {
        io.println("fuzz tuple: truncated buffer accepted it=" + convert.int_to_string(it));
        return 7;
      }
      Err(_) => {}
    }

    it = it + 1;
  }
  return 0;
}

// (b) WAL segment parser fuzz -------------------------------------------------
fn fuzz_wal(seed: Int, iters: Int, recs: Int, dir: Str) -> Int {
  var state = seed;
  var garbage = Vec[Str].new();
  garbage.push("garbage");
  garbage.push("1|2|3");
  garbage.push("|||");
  garbage.push("1|2|x|4|5");
  garbage.push("a|b|c|d|e");

  var it = 0;
  while it < iters {
    let path = dir + "/fuzz-wal-" + convert.int_to_string(seed) + "-"
      + convert.int_to_string(it) + ".wal";
    let _ = io.remove_file(path);
    var w = wal_file_open(path);
    var expected = 0;
    var j = 0;
    while j < recs {
      let action = rand_mod(&mut state, 7);
      if action == 0 {
        let lsn = wal_file_append(&mut w, WALOpKind.Insert, rand_next(&mut state) % 1000, 7);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 1 {
        let lsn = wal_file_append(&mut w, WALOpKind.Update, rand_next(&mut state) % 1000, 8);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 2 {
        let lsn = wal_file_append(&mut w, WALOpKind.Delete, rand_next(&mut state) % 1000, 9);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 3 {
        var payload = Vec[Int].new();
        payload.push(rand_next(&mut state) % 100);
        payload.push(rand_next(&mut state) % 100);
        let lsn = wal_file_append_tagged(&mut w, WALOpKind.Checkpoint, 0, 0, payload, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } elif action == 4 {
        let g = garbage[rand_mod(&mut state, garbage.len())];
        let app = io.append_line(path, g);
        match app { Ok(_) => {}, Err(_) => { io.println("fuzz wal: garbage append failed"); return 2; } }
      } elif action == 5 {
        // A valid begin/commit pair (no index effect) keeps the op mix broad.
        let lsn = wal_file_append(&mut w, WALOpKind.BeginTxn, 0, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      } else {
        let lsn = wal_file_append(&mut w, WALOpKind.CommitTxn, 0, 0);
        if lsn < 0 { io.println("fuzz wal: append failed"); return 1; }
        expected = expected + 1;
      }
      j = j + 1;
    }

    // Optional torn tail AFTER the last valid record: replay must skip it and
    // open() must heal it before the next append.
    if (rand_next(&mut state) % 2) == 0 {
      let app = io.append_file(path, "88|2|3|");
      match app { Ok(_) => {}, Err(_) => { io.println("fuzz wal: torn append failed"); return 2; } }
    }

    let got = wal_file_replay(path);
    if got.len() != expected {
      io.println("fuzz wal: replay count got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(expected) + " it=" + convert.int_to_string(it));
      return 3;
    }
    var prev = 0;
    var ri = 0;
    while ri < got.len() {
      let rec = got[ri];
      if rec.lsn <= prev { io.println("fuzz wal: lsn not increasing"); return 4; }
      prev = rec.lsn;
      let code = wal_op_code(rec.op);
      if code < 1 || code > 10 { io.println("fuzz wal: op code out of range"); return 5; }
      ri = ri + 1;
    }

    var w2 = wal_file_open(path);
    let lsn2 = wal_file_append(&mut w2, WALOpKind.Insert, 42, 420);
    if lsn2 < 0 { io.println("fuzz wal: heal append failed"); return 6; }
    let got2 = wal_file_replay(path);
    if got2.len() != expected + 1 { io.println("fuzz wal: post-heal count"); return 7; }
    let last = got2[got2.len() - 1];
    if last.lsn != lsn2 { io.println("fuzz wal: post-heal last lsn"); return 8; }

    let _ = io.remove_file(path);
    it = it + 1;
  }
  return 0;
}

// (c) page log parser fuzz ----------------------------------------------------
fn fuzz_page(seed: Int, iters: Int, pages_per: Int, dir: Str) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    let path = dir + "/fuzz-page-" + convert.int_to_string(seed) + "-"
      + convert.int_to_string(it) + ".tmp";
    let _ = io.remove_file(path);
    let pf = page_file_open(path);
    var ids = Vec[Int].new();
    var vers = Vec[Int].new();

    var j = 0;
    while j < pages_per {
      let id = rand_next(&mut state) % 8;
      let ver = rand_next(&mut state) % 64;
      var d = Vec[Int].new();
      d.push(id);
      d.push(ver);
      var cs = page_compute_checksum(&d);
      let corrupt = rand_mod(&mut state, 5) == 0;
      if corrupt { cs = cs + 1; }
      if !page_log_append(&pf, Page.new(id, d, cs)) {
        io.println("fuzz page: append failed");
        return 1;
      }
      // Model: only CRC-valid writes count, latest version per id wins.
      if !corrupt {
        var found = -1;
        var k = 0;
        while k < ids.len() {
          if ids[k] == id { found = k; }
          k = k + 1;
        }
        if found >= 0 {
          vers[found] = ver;
        } else {
          ids.push(id);
          vers.push(ver);
        }
      }
      j = j + 1;
    }

    let _ = io.append_line(path, "garbage");
    let _ = io.append_line(path, "1|2|3");
    if (rand_next(&mut state) % 2) == 0 {
      let _ = io.append_file(path, "7|2|");
    }

    let got = page_log_read_all(&pf);
    if got.len() != ids.len() {
      io.println("fuzz page: read_all count got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(ids.len()) + " it=" + convert.int_to_string(it));
      return 2;
    }
    var q = 0;
    while q < ids.len() {
      var ok = false;
      var r = 0;
      while r < got.len() {
        let pg = got[r];
        if pg.id == ids[q] {
          if pg.data.len() == 2 {
            if pg.data[1] == vers[q] { ok = true; }
          }
        }
        r = r + 1;
      }
      if !ok {
        io.println("fuzz page: latest version mismatch id=" + convert.int_to_string(ids[q]));
        return 3;
      }
      q = q + 1;
    }

    if ids.len() > 0 {
      let single = page_file_read(&pf, ids[0]);
      match single {
        None => { io.println("fuzz page: point read missing"); return 4; }
        Some(p) => {
          let pg2: Page = p;
          if pg2.data.len() != 2 { io.println("fuzz page: point read shape"); return 5; }
        }
      }
    }

    let _ = io.remove_file(path);
    it = it + 1;
  }
  return 0;
}

// (d) B-tree vs model fuzz ----------------------------------------------------
fn fuzz_btree(seed: Int, ops: Int, n: Int, order: Int) -> Int {
  var tree = btree_new(order);
  var present = Vec[Int].new();
  var values = Vec[Int].new();
  var i = 0;
  while i < n {
    present.push(0);
    values.push(0);
    i = i + 1;
  }

  var state = seed;
  var step = 0;
  while step < ops {
    let key = rand_next(&mut state) % n;
    let action = rand_mod(&mut state, 12);

    if action < 4 {
      let should = present[key] == 0;
      let got = btree_insert(&mut tree, key, value_of(key));
      if got != should { io.println("fuzz btree: insert mismatch step=" + convert.int_to_string(step)); return 1; }
      if should {
        present[key] = 1;
        values[key] = value_of(key);
      }
    } elif action < 7 {
      let should = present[key] == 1;
      let got = btree_delete(&mut tree, key);
      if got != should { io.println("fuzz btree: delete mismatch step=" + convert.int_to_string(step)); return 2; }
      if should { present[key] = 0; }
    } elif action < 9 {
      let got = btree_search(&tree, key);
      if present[key] == 1 {
        match got {
          None => { io.println("fuzz btree: search missing step=" + convert.int_to_string(step)); return 3; }
          Some(v) => {
            if v != values[key] { io.println("fuzz btree: search value step=" + convert.int_to_string(step)); return 4; }
          }
        }
      } else {
        match got {
          Some(_) => { io.println("fuzz btree: ghost step=" + convert.int_to_string(step)); return 5; }
          None => {}
        }
      }
    } elif action < 11 {
      var lo = rand_mod(&mut state, n);
      var hi = lo + rand_mod(&mut state, 40);
      if hi >= n { hi = n - 1; }
      let got = btree_range_query(&tree, lo, hi);
      var want = Vec[Int].new();
      var k = lo;
      while k <= hi {
        if present[k] == 1 { want.push(values[k]); }
        k = k + 1;
      }
      if got.len() != want.len() { io.println("fuzz btree: range len step=" + convert.int_to_string(step)); return 6; }
      var gi = 0;
      while gi < got.len() {
        if got[gi] != want[gi] { io.println("fuzz btree: range value step=" + convert.int_to_string(step)); return 7; }
        gi = gi + 1;
      }
    } else {
      let got_min = btree_min(&tree);
      let got_max = btree_max(&tree);
      var want_min = -1;
      var want_max = -1;
      var k2 = 0;
      while k2 < n {
        if present[k2] == 1 {
          if want_min < 0 { want_min = k2; }
          want_max = k2;
        }
        k2 = k2 + 1;
      }
      if want_min < 0 {
        match got_min { Some(_) => { io.println("fuzz btree: min on empty"); return 8; }, None => {} }
        match got_max { Some(_) => { io.println("fuzz btree: max on empty"); return 9; }, None => {} }
      } else {
        // btree_min/max return the VALUE at the extreme key.
        match got_min {
          None => { io.println("fuzz btree: min missing"); return 10; }
          Some(v) => { if v != value_of(want_min) { io.println("fuzz btree: min value"); return 11; } }
        }
        match got_max {
          None => { io.println("fuzz btree: max missing"); return 12; }
          Some(v) => { if v != value_of(want_max) { io.println("fuzz btree: max value"); return 13; } }
        }
      }
    }
    step = step + 1;
  }

  // Final: size, in-order content, min/max against the model.
  var expected = 0;
  var k3 = 0;
  while k3 < n {
    if present[k3] == 1 { expected = expected + 1; }
    k3 = k3 + 1;
  }
  if btree_size(&tree) != expected { io.println("fuzz btree: final size"); return 14; }
  let vals = btree_to_vec(&tree);
  if vals.len() != expected { io.println("fuzz btree: final vec len"); return 15; }
  var vi = 0;
  var k4 = 0;
  while k4 < n {
    if present[k4] == 1 {
      if vals[vi] != values[k4] { io.println("fuzz btree: final order key=" + convert.int_to_string(k4)); return 16; }
      vi = vi + 1;
    }
    k4 = k4 + 1;
  }
  if expected == 0 {
    match btree_min(&tree) { Some(_) => { io.println("fuzz btree: final min on empty"); return 17; }, None => {} }
  } else {
    var want_min2 = -1;
    var want_max2 = -1;
    var k5 = 0;
    while k5 < n {
      if present[k5] == 1 {
        if want_min2 < 0 { want_min2 = k5; }
        want_max2 = k5;
      }
      k5 = k5 + 1;
    }
    match btree_min(&tree) {
      None => { io.println("fuzz btree: final min missing"); return 18; }
      Some(v) => { if v != value_of(want_min2) { io.println("fuzz btree: final min"); return 19; } }
    }
    match btree_max(&tree) {
      None => { io.println("fuzz btree: final max missing"); return 20; }
      Some(v) => { if v != value_of(want_max2) { io.println("fuzz btree: final max"); return 21; } }
    }
  }
  return 0;
}

// (e) block codec v2 fuzz ----------------------------------------------------
// Round-trips random page blocks and header slots against a model, then
// applies single-byte mutations: decode must reject, or reflect the mutation
// (the kind byte lives outside the payload CRC, so a flip to another valid
// kind may decode -- it must never decode to the ORIGINAL view).
fn fuzz_block(seed: Int, iters: Int) -> Int {
  var state = seed + 555;
  var it = 0;
  while it < iters {
    let gen = rand_next(&mut state) % 1000000;
    let pid = rand_next(&mut state) % 100000;
    let len = rand_mod(&mut state, block_payload_capacity() + 1);
    var payload = Vec[Int].new();
    var i = 0;
    while i < len {
      payload.push(rand_next(&mut state) % 256);
      i = i + 1;
    }
    let b = block_encode_page(gen, pid, &payload);
    if b.len() != block_size() { return 1; }
    match block_decode_page(&b) {
      Some(p) => {
        if p.generation != gen || p.page_id != pid || !vec_eq(&p.payload, &payload) { return 2; }
      }
      None => { return 3; }
    }
    let h = BlockHeader{
      root: rand_next(&mut state) % 100000,
      order: 3 + rand_mod(&mut state, 8),
      node_count: rand_next(&mut state) % 100000,
      checkpoint_lsn: rand_next(&mut state) % 1000000,
      committed_generation: rand_next(&mut state) % 100000,
      block_count: rand_next(&mut state) % 100000,
      next_page_id: rand_next(&mut state) % 100000,
    };
    let hb = block_encode_header(&h);
    match block_decode_header(&hb) {
      Some(h2) => {
        if h2.root != h.root || h2.order != h.order || h2.node_count != h.node_count { return 4; }
        if h2.checkpoint_lsn != h.checkpoint_lsn { return 4; }
        if h2.committed_generation != h.committed_generation { return 4; }
        if h2.block_count != h.block_count || h2.next_page_id != h.next_page_id { return 4; }
      }
      None => { return 5; }
    }
    var m = 0;
    while m < 6 {
      let idx = rand_next(&mut state) % block_size();
      var t = Vec[Int].new();
      var j = 0;
      while j < block_size() {
        t.push(b[j]);
        j = j + 1;
      }
      t[idx] = (t[idx] + 1 + rand_mod(&mut state, 255)) % 256;
      match block_decode(&t) {
        Some(v) => {
          if v.kind == 0x50 && v.generation == gen && v.page_id == pid && v.payload.len() == len {
            if idx != 5 { return 6; }
          }
        }
        None => {}
      }
      m = m + 1;
    }
    it = it + 1;
  }
  return 0;
}

// (f) block store vs model ---------------------------------------------------
// Model: append history of (id, payload, generation); the reopened view must
// show exactly the distinct ids whose latest history entry has gen <= the
// committed generation, with that entry's payload.
fn bs_compare(path: Str, hid: &Vec[Int], hpay: &Vec[Int], hgen: &Vec[Int], committed: Int) -> Bool {
  var mitems = Vec[Int].new();
  var mvals = Vec[Int].new();
  var i = 0;
  while i < hid.len() {
    if hgen[i] <= committed {
      var at = -1;
      var j = 0;
      while j < mitems.len() {
        if mitems[j] == hid[i] { at = j; }
        j = j + 1;
      }
      if at < 0 {
        mitems.push(hid[i]);
        mvals.push(hpay[i]);
      } else {
        mvals[at] = hpay[i];
      }
    }
    i = i + 1;
  }
  var bs = block_store_open(path);
  if block_store_count(&bs) != mitems.len() { return false; }
  var k = 0;
  while k < mitems.len() {
    match block_store_read(&bs, mitems[k]) {
      Some(pg) => {
        if pg.payload.len() != 1 || pg.payload[0] != mvals[k] { return false; }
      }
      None => { return false; }
    }
    k = k + 1;
  }
  return true;
}

fn fuzz_blockstore(seed: Int, gens: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-block-store.bv2";
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".tmp") { Ok(_) => {} Err(_) => {} }
  var state = seed + 999;
  var hid = Vec[Int].new();
  var hpay = Vec[Int].new();
  var hgen = Vec[Int].new();
  var committed: Int = 0;
  var bs = block_store_open(path);
  var g: Int = 1;
  while g <= gens {
    let puts = 1 + rand_mod(&mut state, 5);
    var p: Int = 0;
    while p < puts {
      let id = rand_mod(&mut state, 12);
      let pay = 10 + rand_mod(&mut state, 200);
      var pv = Vec[Int].new();
      pv.push(pay);
      if block_store_put(&mut bs, g, id, &pv) < 0 { return 1; }
      hid.push(id);
      hpay.push(pay);
      hgen.push(g);
      p = p + 1;
    }
    if rand_mod(&mut state, 10) < 8 {
      var h = BlockHeader{
        root: 1,
        order: 4,
        node_count: 0,
        checkpoint_lsn: g,
        committed_generation: g,
        block_count: 0,
        next_page_id: 64,
      };
      if !block_store_commit(&mut bs, &h) { return 1; }
      committed = g;
      if !bs_compare(path, &hid, &hpay, &hgen, committed) { return 2; }
    }
    g = g + 1;
  }
  if !bs_compare(path, &hid, &hpay, &hgen, committed) { return 3; }
  return 0;
}

// (g) query + secondary index vs model ---------------------------------------
fn model_insert(keys: &mut Vec[Int], vals: &mut Vec[Int], key: Int, val: Int) {
  var pos = 0;
  while pos < keys.len() && keys[pos] < key {
    pos = pos + 1;
  }
  if pos < keys.len() && keys[pos] == key {
    vals[pos] = val;
    return;
  }
  keys.push(0);
  vals.push(0);
  var i = keys.len() - 1;
  while i > pos {
    keys[i] = keys[i - 1];
    vals[i] = vals[i - 1];
    i = i - 1;
  }
  keys[pos] = key;
  vals[pos] = val;
}

fn model_delete(keys: &mut Vec[Int], vals: &mut Vec[Int], key: Int) -> Bool {
  var pos = 0;
  while pos < keys.len() && keys[pos] < key {
    pos = pos + 1;
  }
  if pos >= keys.len() || keys[pos] != key { return false; }
  var i = pos;
  while i < keys.len() - 1 {
    keys[i] = keys[i + 1];
    vals[i] = vals[i + 1];
    i = i + 1;
  }
  keys.pop();
  vals.pop();
  return true;
}

fn model_match(v: Int, op: Int, target: Int) -> Bool {
  if op == 0 { return v == target; }
  if op == 1 { return v != target; }
  if op == 2 { return v < target; }
  if op == 3 { return v <= target; }
  if op == 4 { return v > target; }
  return v >= target;
}

fn model_query(keys: &Vec[Int], vals: &Vec[Int], ops: &Vec[Int], cvals: &Vec[Int],
               order: Int, offset: Int, limit: Int) -> Vec[Int] {
  var mvals = Vec[Int].new();
  var mpos = Vec[Int].new();
  var i = 0;
  while i < vals.len() {
    var ok = true;
    var c = 0;
    while c < ops.len() {
      if !model_match(vals[i], ops[c], cvals[c]) { ok = false; }
      c = c + 1;
    }
    if ok {
      mvals.push(vals[i]);
      mpos.push(i);
    }
    i = i + 1;
  }
  if order == 1 || order == 2 {
    secidx_sort_pairs(&mut mvals, &mut mpos, order == 2);
  }
  var out = Vec[Int].new();
  var start = offset;
  var end = mvals.len();
  if limit > 0 && start + limit < end {
    end = start + limit;
  }
  var k = start;
  while k < end {
    out.push(mvals[k]);
    k = k + 1;
  }
  return out;
}

fn query_where_int(q: &mut Query, op: Int, v: Int) {
  if op == 0 {
    query_where(q, QueryOp.Eq, v);
  } elif op == 1 {
    query_where(q, QueryOp.Neq, v);
  } elif op == 2 {
    query_where(q, QueryOp.Lt, v);
  } elif op == 3 {
    query_where(q, QueryOp.Lte, v);
  } elif op == 4 {
    query_where(q, QueryOp.Gt, v);
  } else {
    query_where(q, QueryOp.Gte, v);
  }
}

fn fuzz_query(seed: Int, iters: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-query.wal";
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".snap") { Ok(_) => {} Err(_) => {} }
  var state = seed + 7777;
  var db = db_file_open(path, 4);
  var keys = Vec[Int].new();
  var vals = Vec[Int].new();

  var s = 0;
  while s < 30 {
    let k = rand_mod(&mut state, 50);
    let v = rand_mod(&mut state, 40);
    if !db_file_put(&mut db, k, v) { return 1; }
    model_insert(&mut keys, &mut vals, k, v);
    s = s + 1;
  }
  if !db_file_create_index(&mut db, "by_value") { return 1; }

  var it = 0;
  while it < iters {
    let action = rand_mod(&mut state, 10);
    if action < 5 {
      let k = rand_mod(&mut state, 50);
      let v = rand_mod(&mut state, 40);
      if !db_file_put(&mut db, k, v) { return 1; }
      model_insert(&mut keys, &mut vals, k, v);
    } elif action < 7 {
      let k = rand_mod(&mut state, 50);
      let ok = db_file_delete(&mut db, k);
      let mok = model_delete(&mut keys, &mut vals, k);
      if ok != mok { return 2; }
    } else {
      let ncond = rand_mod(&mut state, 3);
      var ops = Vec[Int].new();
      var cvals = Vec[Int].new();
      var q = query_new();
      var c = 0;
      while c < ncond {
        let op = rand_mod(&mut state, 6);
        let v = rand_mod(&mut state, 40);
        ops.push(op);
        cvals.push(v);
        query_where_int(&mut q, op, v);
        c = c + 1;
      }
      let order = rand_mod(&mut state, 3);
      if order != 0 { query_order(&mut q, order); }
      let offs = rand_mod(&mut state, 4);
      if offs > 0 { query_offset(&mut q, offs); }
      let lim = rand_mod(&mut state, 5);
      if lim > 0 { query_limit(&mut q, lim); }

      let got = db_file_query(&db, &q);
      let want = model_query(&keys, &vals, &ops, &cvals, order, offs, lim);
      if !vec_eq(&got, &want) { return 3; }

      var usable = false;
      var ci = 0;
      while ci < ops.len() {
        if ops[ci] != 1 { usable = true; }
        ci = ci + 1;
      }
      if usable {
        let plan = plan_query_with_index(&q, &db.tree, true);
        if plan.kind != PlanKind.IndexValue { return 4; }
      }
    }
    it = it + 1;
  }
  return 0;
}

// (h) tuple codec v2 -- typed-value rows (M5.1) ------------------------------
// Random rows over every kind (null/int/float/text/blob): encode -> decode
// -> per-kind model assertions -> single-byte mutation (decode must reject,
// or the mutated row must re-encode to something OTHER than the original
// buffer -- a mutation can never be silently invisible).
fn fuzz_tuple2(seed: Int, iters: Int) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    let row_id = rand_next(&mut state) % 2000003 - 1000000;
    let nvals = rand_mod(&mut state, 8);
    var vals = Vec[TValue].new();
    var specs = Vec[Int].new();
    var j = 0;
    while j < nvals {
      let kind = rand_mod(&mut state, 5);
      if kind == 0 {
        vals.push(TValue.VNull);
        specs.push(0);
      } elif kind == 1 {
        let x = rand_next(&mut state) % 2000003 - 1000000;
        vals.push(TValue.VInt(x));
        specs.push(1);
      } elif kind == 2 {
        let a = rand_next(&mut state) % 2000003 - 1000000;
        var f = convert.int_to_float(a) / 16.0;
        if rand_mod(&mut state, 7) == 0 { f = 0.0; }
        vals.push(TValue.VFloat(f));
        specs.push(2);
      } elif kind == 3 {
        let l = rand_mod(&mut state, 12);
        var s = "";
        var k = 0;
        while k < l {
          s = s + "xyz";
          k = k + 1;
        }
        vals.push(TValue.VText(s));
        specs.push(3);
      } else {
        let l = rand_mod(&mut state, 10);
        var b = Vec[Int].new();
        var k = 0;
        while k < l {
          b.push(rand_next(&mut state) % 256);
          k = k + 1;
        }
        vals.push(TValue.VBlob(b));
        specs.push(4);
      }
      j = j + 1;
    }

    match tuple2_encode_row_checked(row_id, &vals) {
      Err(_) => { return 1; }
      Ok(buf) => {
        let x: Vec[Int] = buf;
        if x.len() != tuple2_encoded_len(&vals) { return 2; }
        match tuple2_decode_row(&x) {
          Err(_) => { return 3; }
          Ok(row) => {
            let r: TypedRow = row;
            if r.id != row_id { return 4; }
            if r.values.len() != vals.len() { return 5; }
            var k = 0;
            while k < r.values.len() {
              let spec = specs[k];
              let v = r.values[k];
              if tuple2_kind(v) != spec { return 6; }
              let ov = vals[k];
              if spec == 0 {
                if !tuple2_is_null(v) { return 7; }
              }
              if spec == 1 {
                match tuple2_int_value(v) {
                  None => { return 8; }
                  Some(iv) => {
                    match tuple2_int_value(ov) {
                      None => { return 9; }
                      Some(orig) => { if iv != orig { return 10; } }
                    }
                  }
                }
              }
              if spec == 2 {
                match tuple2_float_value(v) {
                  None => { return 11; }
                  Some(fv) => {
                    match tuple2_float_value(ov) {
                      None => { return 12; }
                      Some(origf) => { if fv != origf { return 13; } }
                    }
                  }
                }
              }
              if spec == 3 {
                match tuple2_text_value(v) {
                  None => { return 14; }
                  Some(sv) => {
                    match tuple2_text_value(ov) {
                      None => { return 15; }
                      Some(origs) => { if sv != origs { return 16; } }
                    }
                  }
                }
              }
              if spec == 4 {
                match tuple2_blob_value(v) {
                  None => { return 17; }
                  Some(bv) => {
                    match tuple2_blob_value(ov) {
                      None => { return 18; }
                      Some(origb) => { if !vec_eq(&bv, &origb) { return 19; } }
                    }
                  }
                }
              }
              k = k + 1;
            }
          }
        }

        // Single-byte mutation: reject, or the mutation must be visible.
        let at = rand_mod(&mut state, x.len());
        var mutb = Vec[Int].new();
        var m = 0;
        while m < x.len() {
          mutb.push(x[m]);
          m = m + 1;
        }
        mutb[at] = (mutb[at] + 1 + rand_mod(&mut state, 255)) & 0xFF;
        match tuple2_decode_row(&mutb) {
          Err(_) => {}
          Ok(mrow) => {
            let r2: TypedRow = mrow;
            match tuple2_encode_row_checked(r2.id, &r2.values) {
              Err(_) => { return 20; }
              Ok(buf2) => {
                let x2: Vec[Int] = buf2;
                if vec_eq(&x2, &x) { return 21; }
              }
            }
          }
        }
      }
    }
    it = it + 1;
  }
  return 0;
}

// (i) schema rows -- schema-driven typed rows (M5.2) -------------------------
fn fuzz_schema_col_type(code: Int) -> ColumnType {
  if code == 1 { return ColumnType.IntType; }
  if code == 2 { return ColumnType.FloatType; }
  if code == 3 { return ColumnType.BoolType; }
  if code == 4 { return ColumnType.StringType; }
  return ColumnType.BytesType;
}

fn fuzz_schema_expected_kind(code: Int) -> Int {
  if code == 2 { return 0x02; } // float
  if code == 4 { return 0x03; } // text
  if code == 5 { return 0x04; } // blob
  return 0x01;                  // int + bool
}

fn fuzz_schema_value(state: &mut Int, code: Int) -> TValue {
  if code == 1 { return TValue.VInt(rand_next(state) % 2000003 - 1000000); }
  if code == 2 {
    let a = rand_next(state) % 2000003 - 1000000;
    return TValue.VFloat(convert.int_to_float(a) / 16.0);
  }
  if code == 3 { return TValue.VInt(rand_next(state) % 2); }
  if code == 4 {
    let l = rand_mod(state, 8);
    var s = "";
    var k = 0;
    while k < l {
      s = s + "ab";
      k = k + 1;
    }
    return TValue.VText(s);
  }
  let l = rand_mod(state, 8);
  var b = Vec[Int].new();
  var k = 0;
  while k < l {
    b.push(rand_next(state) % 256);
    k = k + 1;
  }
  return TValue.VBlob(b);
}

// A value that must violate the column: null when the column is
// non-nullable, otherwise a kind that can never match (per type code).
fn fuzz_schema_bad_value(code: Int, nullable: Bool) -> TValue {
  if !nullable { return TValue.VNull; }
  if code == 1 { return TValue.VText("x"); }
  if code == 2 { return TValue.VInt(1); }
  if code == 3 { return TValue.VText("1"); }
  if code == 4 { return TValue.VBlob(fuzz_byte_vec()); }
  return TValue.VInt(1);
}

fn fuzz_byte_vec() -> Vec[Int] {
  var b = Vec[Int].new();
  b.push(1);
  return b;
}

fn fuzz_schema_row(seed: Int, iters: Int) -> Int {
  var state = seed;
  var it = 0;
  while it < iters {
    let ncols = 1 + rand_mod(&mut state, 6);
    let pk = rand_mod(&mut state, ncols);
    var cols = Vec[ColumnDef].new();
    var types = Vec[Int].new();
    var nullables = Vec[Int].new();
    var j = 0;
    while j < ncols {
      var tc = 1 + rand_mod(&mut state, 5);
      if j == pk { tc = 1; } // the int-keyed storage path needs an int pk
      let nullable = rand_mod(&mut state, 4) == 0;
      let name = "c" + convert.int_to_string(j);
      if nullable {
        cols.push(ColumnDef.optional(name, fuzz_schema_col_type(tc), None));
        nullables.push(1);
      } else {
        cols.push(ColumnDef.new(name, fuzz_schema_col_type(tc)));
        nullables.push(0);
      }
      types.push(tc);
      j = j + 1;
    }
    let schema = Schema.new("f", cols, pk);

    // Valid row by construction: pk always carries VInt.
    var vals = Vec[TValue].new();
    var pkval = 0;
    j = 0;
    while j < ncols {
      let tc = types[j];
      let nullable = nullables[j] == 1;
      if j == pk {
        pkval = rand_next(&mut state) % 2000003 - 1000000;
        vals.push(TValue.VInt(pkval));
      } elif nullable && rand_mod(&mut state, 3) == 0 {
        vals.push(TValue.VNull);
      } else {
        vals.push(fuzz_schema_value(&mut state, tc));
      }
      j = j + 1;
    }

    match schema_row_validate(&schema, &vals) {
      Err(_) => { return 1; }
      Ok(_) => {}
    }
    match schema_row_key(&schema, &vals) {
      Err(_) => { return 2; }
      Ok(k) => { if k != pkval { return 3; } }
    }
    match schema_row_encode(&schema, &vals) {
      Err(_) => { return 4; }
      Ok(buf) => {
        let x: Vec[Int] = buf;
        if x.len() != tuple2_encoded_len(&vals) { return 5; }
        match schema_row_decode(&schema, &x) {
          Err(_) => { return 6; }
          Ok(row) => {
            let r: TypedRow = row;
            if r.id != pkval { return 7; }
            if r.values.len() != vals.len() { return 8; }
            var k = 0;
            while k < r.values.len() {
              let orig = vals[k];
              let got = r.values[k];
              if tuple2_is_null(orig) {
                if !tuple2_is_null(got) { return 9; }
              } else {
                if tuple2_kind(got) != fuzz_schema_expected_kind(types[k]) { return 10; }
                // Value equality per kind (accessor-based).
                if types[k] == 1 || types[k] == 3 {
                  match tuple2_int_value(got) {
                    None => { return 11; }
                    Some(gv) => {
                      match tuple2_int_value(orig) {
                        None => { return 12; }
                        Some(ov) => { if gv != ov { return 13; } }
                      }
                    }
                  }
                }
                if types[k] == 2 {
                  match tuple2_float_value(got) {
                    None => { return 14; }
                    Some(gv) => {
                      match tuple2_float_value(orig) {
                        None => { return 15; }
                        Some(ov) => { if gv != ov { return 16; } }
                      }
                    }
                  }
                }
                if types[k] == 4 {
                  match tuple2_text_value(got) {
                    None => { return 17; }
                    Some(gv) => {
                      match tuple2_text_value(orig) {
                        None => { return 18; }
                        Some(ov) => { if gv != ov { return 19; } }
                      }
                    }
                  }
                }
                if types[k] == 5 {
                  match tuple2_blob_value(got) {
                    None => { return 20; }
                    Some(gv) => {
                      match tuple2_blob_value(orig) {
                        None => { return 21; }
                        Some(ov) => { if !vec_eq(&gv, &ov) { return 22; } }
                      }
                    }
                  }
                }
              }
              k = k + 1;
            }
          }
        }
        // Re-encode the decoded row: byte-identical.
        match schema_row_decode(&schema, &x) {
          Err(_) => { return 23; }
          Ok(row2) => {
            let r2: TypedRow = row2;
            match schema_row_encode(&schema, &r2.values) {
              Err(_) => { return 24; }
              Ok(buf2) => {
                let x2: Vec[Int] = buf2;
                if !vec_eq(&x2, &x) { return 25; }
              }
            }
          }
        }
      }
    }

    // Every single-column violation must be rejected.
    j = 0;
    while j < ncols {
      var bad = Vec[TValue].new();
      var k2 = 0;
      while k2 < vals.len() {
        if k2 == j {
          bad.push(fuzz_schema_bad_value(types[j], nullables[j] == 1));
        } else {
          bad.push(vals[k2]);
        }
        k2 = k2 + 1;
      }
      match schema_row_validate(&schema, &bad) {
        Ok(_) => { return 26; }
        Err(_) => {}
      }
      match schema_row_encode(&schema, &bad) {
        Ok(_) => { return 27; }
        Err(_) => {}
      }
      j = j + 1;
    }
    it = it + 1;
  }
  return 0;
}

// (j) db_file typed rows (M5.3) ----------------------------------------------
// Random put/put_typed/delete mixes against a model, with periodic
// checkpoints and reopens: size, get (typed rows mirror the pk as the int
// value), get_typed, and range values must match the model after EVERY op,
// including after recovery. Model payloads are append-only (offsets into a
// flat byte vec) so no nested-vec element writes are involved.
fn fuzz_db_typed(seed: Int, iters: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-typed.wal";
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  var state = seed;
  var db = db_file_open(path, 4);

  let nkeys = 40;
  var kind = Vec[Int].new();   // 0 absent, 1 int, 2 typed
  var val = Vec[Int].new();
  var payoff = Vec[Int].new();
  var paylen = Vec[Int].new();
  var payflat = Vec[Int].new();
  var k0 = 0;
  while k0 <= nkeys {
    kind.push(0);
    val.push(0);
    payoff.push(0);
    paylen.push(0);
    k0 = k0 + 1;
  }

  var it = 0;
  while it < iters {
    let roll = rand_mod(&mut state, 100);
    if roll < 45 {
      let k = 1 + rand_mod(&mut state, nkeys);
      let plen = rand_mod(&mut state, 21);
      var p = Vec[Int].new();
      var i = 0;
      while i < plen {
        p.push(rand_next(&mut state) % 256);
        i = i + 1;
      }
      if !db_file_put_typed(&mut db, k, p) { return 1; }
      kind[k] = 2;
      val[k] = k;
      payoff[k] = payflat.len();
      paylen[k] = plen;
      i = 0;
      while i < plen {
        payflat.push(p[i]);
        i = i + 1;
      }
    } elif roll < 70 {
      let k = 1 + rand_mod(&mut state, nkeys);
      let v = rand_next(&mut state) % 2000003 - 1000000;
      if !db_file_put(&mut db, k, v) { return 2; }
      kind[k] = 1;
      val[k] = v;
      paylen[k] = 0;
    } elif roll < 85 {
      let k = 1 + rand_mod(&mut state, nkeys);
      if kind[k] > 0 {
        if !db_file_delete(&mut db, k) { return 3; }
        kind[k] = 0;
      }
    } elif roll < 92 {
      if db_file_checkpoint(&mut db) < 0 { return 4; }
    } else {
      db = db_file_open(path, 4);
    }

    // Full verification after every op.
    var live = 0;
    var k = 1;
    while k <= nkeys {
      if kind[k] > 0 { live = live + 1; }
      let g = db_file_get(&db, k);
      if kind[k] == 0 {
        match g { Some(_) => { return 5; } None => {} }
      } else {
        match g {
          None => { return 6; }
          Some(v) => { if v != val[k] { return 7; } }
        }
      }
      let gt = db_file_get_typed(&db, k);
      if kind[k] == 2 && paylen[k] > 0 {
        match gt {
          None => { return 8; }
          Some(p2) => {
            if p2.len() != paylen[k] { return 9; }
            var i2 = 0;
            while i2 < p2.len() {
              if p2[i2] != payflat[payoff[k] + i2] { return 10; }
              i2 = i2 + 1;
            }
          }
        }
      } else {
        match gt { Some(_) => { return 11; } None => {} }
      }
      k = k + 1;
    }
    if db_file_size(&db) != live { return 12; }

    // Sampled range check (key order, values).
    if rand_mod(&mut state, 5) == 0 {
      let lo = 1 + rand_mod(&mut state, nkeys);
      let hi = lo + rand_mod(&mut state, nkeys - lo + 1);
      var expect = Vec[Int].new();
      var k2 = lo;
      while k2 <= hi {
        if kind[k2] > 0 { expect.push(val[k2]); }
        k2 = k2 + 1;
      }
      let got = db_file_range(&db, lo, hi);
      if !vec_eq(&got, &expect) { return 13; }
    }
    it = it + 1;
  }
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  return 0;
}

// (k) typed queries (M5-S4) --------------------------------------------------
// Random typed rows (col0 int|null, col1 text|null, col2 float|null) + random
// conditions vs an INDEPENDENT model: model values live in their natural
// domains (ints, half-scaled ints for floats, bytewise-ordered table indexes
// for text), the comparator and op logic are re-implemented here, and the
// engine's db_file_query_typed must match after every op (incl. checkpoints
// and reopens).
fn tq_model_text(i: Int) -> Str {
  if i == 0 { return ""; }
  if i == 1 { return " z"; }
  if i == 2 { return "a"; }
  if i == 3 { return "apple"; }
  if i == 4 { return "b"; }
  return "banana";
}

// Domain compare: kind 0 = null, kind 1 = natural-domain value (ints; text
// table indexes in bytewise order; floats as exact halves).
fn tq_model_cmp(ak: Int, av: Int, bk: Int, bv: Int) -> Int {
  if ak == 0 && bk == 0 { return 0; }
  if ak == 0 { return -1; }
  if bk == 0 { return 1; }
  if av < bv { return -1; }
  if av > bv { return 1; }
  return 0;
}

fn tq_model_op_ok(cmp: Int, op: Int) -> Bool {
  if op == 0 { return cmp == 0; }
  if op == 1 { return cmp != 0; }
  if op == 2 { return cmp < 0; }
  if op == 3 { return cmp <= 0; }
  if op == 4 { return cmp > 0; }
  return cmp >= 0;
}

fn tq_model_literal(kind: Int, v: Int) -> TValue {
  if kind == 0 { return TValue.VNull; }
  if kind == 1 { return TValue.VInt(v); }
  if kind == 2 { return TValue.VText(tq_model_text(v)); }
  return TValue.VFloat(convert.int_to_float(v) / 2.0);
}

fn tq_engine_op(op: Int) -> QueryOp {
  if op == 0 { return QueryOp.Eq; }
  if op == 1 { return QueryOp.Neq; }
  if op == 2 { return QueryOp.Lt; }
  if op == 3 { return QueryOp.Lte; }
  if op == 4 { return QueryOp.Gt; }
  return QueryOp.Gte;
}

fn fuzz_typed_query(seed: Int, iters: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-tquery.wal";
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  var state = seed;
  var db = db_file_open(path, 4);

  let nkeys = 30;
  var mk = Vec[Int].new();    // 0 absent, 1 typed row, 2 int row
  var m0k = Vec[Int].new();   // col0: 0 null, 1 int
  var m0v = Vec[Int].new();
  var m1k = Vec[Int].new();   // col1: 0 null, 2 text (table index in m1v)
  var m1v = Vec[Int].new();
  var m2k = Vec[Int].new();   // col2: 0 null, 3 float (half-units in m2v)
  var m2v = Vec[Int].new();
  var k0 = 0;
  while k0 <= nkeys {
    mk.push(0);
    m0k.push(0);
    m0v.push(0);
    m1k.push(0);
    m1v.push(0);
    m2k.push(0);
    m2v.push(0);
    k0 = k0 + 1;
  }

  var it = 0;
  while it < iters {
    let roll = rand_mod(&mut state, 100);
    if roll < 40 {
      let k = 1 + rand_mod(&mut state, nkeys);
      var c0k = rand_mod(&mut state, 4);
      var c1k = rand_mod(&mut state, 4);
      var c2k = rand_mod(&mut state, 4);
      var v0 = 0;
      if c0k > 0 {
        c0k = 1;
        v0 = rand_mod(&mut state, 7) - 3;
      }
      var v1 = 0;
      if c1k > 0 {
        c1k = 2;
        v1 = rand_mod(&mut state, 6);
      }
      var v2 = 0;
      if c2k > 0 {
        c2k = 3;
        v2 = rand_mod(&mut state, 13) - 6;
      }
      var vals = Vec[TValue].new();
      vals.push(tq_model_literal(c0k, v0));
      vals.push(tq_model_literal(c1k, v1));
      vals.push(tq_model_literal(c2k, v2));
      match tuple2_encode_row_checked(k, &vals) {
        Err(_) => { return 1; }
        Ok(buf) => {
          if !db_file_put_typed(&mut db, k, buf) { return 2; }
        }
      }
      mk[k] = 1;
      m0k[k] = c0k;
      m0v[k] = v0;
      m1k[k] = c1k;
      m1v[k] = v1;
      m2k[k] = c2k;
      m2v[k] = v2;
    } elif roll < 60 {
      let k = 1 + rand_mod(&mut state, nkeys);
      if mk[k] > 0 {
        if !db_file_delete(&mut db, k) { return 3; }
        mk[k] = 0;
      }
    } elif roll < 70 {
      let k = 1 + rand_mod(&mut state, nkeys);
      let v = rand_next(&mut state) % 2000 - 1000;
      if !db_file_put(&mut db, k, v) { return 4; }
      mk[k] = 2;
    } elif roll < 90 {
      // Build 1..3 conditions and compare query result vs the model.
      let nconds = 1 + rand_mod(&mut state, 3);
      var cols = Vec[Int].new();
      var ops = Vec[Int].new();
      var cks = Vec[Int].new();
      var cvs = Vec[Int].new();
      var q = typed_query_new();
      var ci = 0;
      while ci < nconds {
        let col = rand_mod(&mut state, 3);
        let op = rand_mod(&mut state, 6);
        var ck = 0;
        var cv = 0;
        if col == 0 {
          if rand_mod(&mut state, 3) == 0 {
            ck = 0;
          } else {
            ck = 1;
            cv = rand_mod(&mut state, 7) - 3;
          }
        }
        if col == 1 {
          if rand_mod(&mut state, 3) == 0 {
            ck = 0;
          } else {
            ck = 2;
            cv = rand_mod(&mut state, 6);
          }
        }
        if col == 2 {
          if rand_mod(&mut state, 3) == 0 {
            ck = 0;
          } else {
            ck = 3;
            cv = rand_mod(&mut state, 13) - 6;
          }
        }
        typed_query_where(&mut q, col, tq_engine_op(op), tq_model_literal(ck, cv));
        cols.push(col);
        ops.push(op);
        cks.push(ck);
        cvs.push(cv);
        ci = ci + 1;
      }
      let lim = rand_mod(&mut state, 4);   // 0..3, 0 = no limit
      let off = rand_mod(&mut state, 3);
      if lim > 0 { typed_query_limit(&mut q, lim); }
      if off > 0 { typed_query_offset(&mut q, off); }

      // Model evaluation.
      var hits = Vec[Int].new();
      var k = 1;
      while k <= nkeys {
        if mk[k] == 1 {
          var ok = true;
          var cj = 0;
          while cj < nconds {
            let col = cols[cj];
            var rk = 0;
            var rv = 0;
            if col == 0 { rk = m0k[k]; rv = m0v[k]; }
            if col == 1 { rk = m1k[k]; rv = m1v[k]; }
            if col == 2 { rk = m2k[k]; rv = m2v[k]; }
            if !tq_model_op_ok(tq_model_cmp(rk, rv, cks[cj], cvs[cj]), ops[cj]) { ok = false; }
            cj = cj + 1;
          }
          if ok { hits.push(k); }
        }
        k = k + 1;
      }
      var out = Vec[Int].new();
      var start = off;
      var end = hits.len();
      if lim > 0 && start + lim < end { end = start + lim; }
      var m2 = start;
      while m2 < end {
        out.push(hits[m2]);
        m2 = m2 + 1;
      }
      let got = db_file_query_typed(&db, &q);
      if !vec_eq(&got, &out) { return 5; }
    } elif roll < 95 {
      if db_file_checkpoint(&mut db) < 0 { return 6; }
    } else {
      db = db_file_open(path, 4);
    }
    it = it + 1;
  }
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  return 0;
}

// (l) snapshot pins + savepoints (M3) ----------------------------------------

fn fuzz_pins_copy(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn fuzz_pins_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
}

fn fuzz_db_pins(seed: Int, iters: Int, dir: Str) -> Int {
  let path = dir + "/fuzz-mvcc.wal";
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  let n = 48;
  var db = db_file_open(path, 3);
  var model = Vec[Int].new();
  var i0 = 0;
  while i0 <= n {
    model.push(-1);
    i0 = i0 + 1;
  }
  var pin_ids = Vec[Int].new();
  var pin_models = Vec[Vec[Int]].new();
  var state = seed;
  var it = 0;
  while it < iters {
    let roll = rand_mod(&mut state, 100);
    let key = 1 + rand_mod(&mut state, n);
    let val = rand_mod(&mut state, 1000);
    if roll < 55 {
      if !db_file_put(&mut db, key, val) { return 1; }
      model[key] = val;
    } elif roll < 70 {
      let _ = db_file_delete(&mut db, key);
      model[key] = -1;
    } elif roll < 80 {
      let s = db_file_snapshot_begin(&mut db);
      pin_ids.push(s.id);
      pin_models.push(fuzz_pins_copy(&model));
    } elif roll < 88 {
      if pin_ids.len() > 0 {
        let at = rand_mod(&mut state, pin_ids.len());
        if !db_file_snapshot_end(&mut db, pin_ids[at]) { return 2; }
        var j = at;
        while j < pin_ids.len() - 1 {
          pin_ids[j] = pin_ids[j + 1];
          pin_models[j] = pin_models[j + 1];
          j = j + 1;
        }
        pin_ids.pop();
        pin_models.pop();
      }
    } elif roll < 93 {
      if db_file_checkpoint(&mut db) < 0 { return 3; }
    } elif roll < 97 {
      db = db_file_open(path, 3);
      pin_ids = Vec[Int].new();
      pin_models = Vec[Vec[Int]].new();
    } else {
      // Txn dance with a savepoint: buffer w1, marker, w2, maybe restore, w3;
      // commit applies the surviving set (or abort drops everything).
      if !db_file_txn_begin(&mut db) { return 4; }
      let k1 = 1 + rand_mod(&mut state, n);
      let v1 = rand_mod(&mut state, 700);
      if !db_file_txn_put(&mut db, k1, v1) { return 5; }
      if !db_file_txn_savepoint(&mut db) { return 6; }
      let k2 = 1 + rand_mod(&mut state, n);
      let v2 = rand_mod(&mut state, 700);
      if !db_file_txn_put(&mut db, k2, v2) { return 7; }
      var restored = false;
      if rand_mod(&mut state, 2) == 0 {
        if !db_file_txn_savepoint_restore(&mut db) { return 8; }
        restored = true;
      }
      let k3 = 1 + rand_mod(&mut state, n);
      let v3 = rand_mod(&mut state, 700);
      if !db_file_txn_put(&mut db, k3, v3) { return 9; }
      if rand_mod(&mut state, 5) == 0 {
        if !db_file_txn_abort(&mut db) { return 10; }
      } else {
        if !db_file_txn_commit(&mut db) { return 11; }
        model[k1] = v1;
        if !restored { model[k2] = v2; }
        model[k3] = v3;
      }
    }
    // After every op: the live tree and EVERY live pin must match the model.
    let want_live = fuzz_pins_expected(&model);
    let got_live = db_file_range(&db, 1, n);
    if !vec_eq(&got_live, &want_live) { return 20; }
    var p = 0;
    while p < pin_ids.len() {
      let want_p = fuzz_pins_expected(&pin_models[p]);
      let got_p = db_file_snapshot_range(&db, pin_ids[p], 1, n);
      if !vec_eq(&got_p, &want_p) { return 21; }
      if db_file_snapshot_count(&db, pin_ids[p]) != want_p.len() { return 22; }
      p = p + 1;
    }
    it = it + 1;
  }
  var q = 0;
  while q < pin_ids.len() {
    if !db_file_snapshot_end(&mut db, pin_ids[q]) { return 30; }
    q = q + 1;
  }
  if db_file_checkpoint(&mut db) < 0 { return 31; }
  var db2 = db_file_open(path, 3);
  let want_final = fuzz_pins_expected(&model);
  let got_final = db_file_range(&db2, 1, n);
  if !vec_eq(&got_final, &want_final) { return 32; }
  let _ = io.remove_file(path);
  let _ = io.remove_file(path + ".snap");
  return 0;
}


fn main() -> Int {
  let dir = env.var_or("ORBITDB_FUZZ_DIR", "probe-logs");
  let seeds = parse_env_int("ORBITDB_FUZZ_SEEDS", 4);
  let ops = parse_env_int("ORBITDB_FUZZ_OPS", 4000);
  let n = parse_env_int("ORBITDB_FUZZ_N", 512);
  let tuple_iters = parse_env_int("ORBITDB_FUZZ_TUPLE_ITERS", 300);
  let wal_iters = parse_env_int("ORBITDB_FUZZ_WAL_ITERS", 30);
  let page_iters = parse_env_int("ORBITDB_FUZZ_PAGE_ITERS", 30);
  let block_iters = parse_env_int("ORBITDB_FUZZ_BLOCK_ITERS", 200);
  let blockstore_gens = parse_env_int("ORBITDB_FUZZ_BLOCKSTORE_GENS", 12);
  let query_iters = parse_env_int("ORBITDB_FUZZ_QUERY_ITERS", 150);
  let tuple2_iters = parse_env_int("ORBITDB_FUZZ_TUPLE2_ITERS", 200);
  let schema_iters = parse_env_int("ORBITDB_FUZZ_SCHEMA_ITERS", 150);
  let typed_iters = parse_env_int("ORBITDB_FUZZ_TYPED_ITERS", 200);
  let tquery_iters = parse_env_int("ORBITDB_FUZZ_TQUERY_ITERS", 150);
  let pins_iters = parse_env_int("ORBITDB_FUZZ_PINS_ITERS", 150);

  var s = 0;
  while s < seeds {
    let seed = 1000 + s * 97;

    let rc_t = fuzz_tuple(seed, tuple_iters);
    if rc_t != 0 {
      io.println("fuzz: tuple FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_t));
      return 10 + rc_t;
    }
    let rc_w = fuzz_wal(seed, wal_iters, 40, dir);
    if rc_w != 0 {
      io.println("fuzz: wal FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_w));
      return 30 + rc_w;
    }
    let rc_p = fuzz_page(seed, page_iters, 30, dir);
    if rc_p != 0 {
      io.println("fuzz: page FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_p));
      return 50 + rc_p;
    }
    let rc_blk = fuzz_block(seed, block_iters);
    if rc_blk != 0 {
      io.println("fuzz: block FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_blk));
      return 90 + rc_blk;
    }
    let rc_bs = fuzz_blockstore(seed, blockstore_gens, dir);
    if rc_bs != 0 {
      io.println("fuzz: blockstore FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_bs));
      return 110 + rc_bs;
    }
    let rc_q = fuzz_query(seed, query_iters, dir);
    if rc_q != 0 {
      io.println("fuzz: query FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_q));
      return 130 + rc_q;
    }
    let rc_t2 = fuzz_tuple2(seed, tuple2_iters);
    if rc_t2 != 0 {
      io.println("fuzz: tuple2 FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_t2));
      return 150 + rc_t2;
    }
    let rc_sr = fuzz_schema_row(seed, schema_iters);
    if rc_sr != 0 {
      io.println("fuzz: schema_row FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_sr));
      return 170 + rc_sr;
    }
    let rc_td = fuzz_db_typed(seed, typed_iters, dir);
    if rc_td != 0 {
      io.println("fuzz: db_typed FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_td));
      return 190 + rc_td;
    }
    let rc_tq = fuzz_typed_query(seed, tquery_iters, dir);
    if rc_tq != 0 {
      io.println("fuzz: typed_query FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_tq));
      return 210 + rc_tq;
    }
    let rc_pins = fuzz_db_pins(seed, pins_iters, dir);
    if rc_pins != 0 {
      io.println("fuzz: pins FAILED seed=" + convert.int_to_string(seed) + " rc=" + convert.int_to_string(rc_pins));
      return 230 + rc_pins;
    }
    let order = 3 + (s % 3);
    let rc_b = fuzz_btree(seed, ops, n, order);
    if rc_b != 0 {
      io.println("fuzz: btree FAILED seed=" + convert.int_to_string(seed) + " order=" + convert.int_to_string(order) + " rc=" + convert.int_to_string(rc_b));
      return 70 + rc_b;
    }
    io.println("fuzz: seed=" + convert.int_to_string(seed) + " order=" + convert.int_to_string(order) + " OK");
    s = s + 1;
  }
  io.println("fuzz: OK seeds=" + convert.int_to_string(seeds) + " ops/seed=" + convert.int_to_string(ops)
    + " n=" + convert.int_to_string(n));
  return 0;
}


