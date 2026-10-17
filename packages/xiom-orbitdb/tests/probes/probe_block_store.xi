// XIOM ORBITDB -- byte-page block store probe (M1.2 S2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Functional + crash-shape acceptance for src/storage/block_store.xi over
// the byte-IO shim (docs/BYTE-PAGE-FORMAT-V2.md):
//   - append + committed visibility, uncommitted hidden on reopen
//   - latest-wins per page id across generations
//   - torn tail (garbage block) skipped by the scan
//   - torn ACTIVE header slot -> fallback to the previous slot
//   - a later commit re-commits surviving pages of a lost generation
//   - both slots corrupt -> store reads empty; next commit restores
//   - compaction (temp+rename) keeps exactly one block per live page
//   - capacity: payload > 4056 rejected
//
// Env: ORBITDB_BLOCK_DB -- store path (default probe-logs/block-store.bv2).
// Exit: 0 = all checks passed, 1 = check failed.

module orbitdb_probe_block_store

use xiom.io;
use xiom.os.env;
use xiom.convert;
use xiom.convert.parse;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
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

// 4096 garbled bytes (bad magic) for corrupting slots / tails.
fn garblock() -> Vec[Int] {
  var g = Vec[Int].new();
  var i = 0;
  while i < block_size() {
    g.push(0x5A);
    i = i + 1;
  }
  return g;
}

fn header_for(generation: Int, block_count: Int, node_count: Int, lsn: Int) -> BlockHeader {
  return BlockHeader{
    root: 1,
    order: 4,
    node_count: node_count,
    checkpoint_lsn: lsn,
    committed_generation: generation,
    block_count: block_count,
    next_page_id: 64,
  };
}

fn env_int(name: Str, dflt: Int) -> Int {
  match parse.parse_int(env.var_or(name, "")) {
    Ok(v) => { return v; }
    Err(_) => { return dflt; }
  }
}

fn page_payload(i: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(i & 0xFF);
  v.push((i >> 8) & 0xFF);
  return v;
}

// ===========================================================================
// writer mode -- deterministic crash states, then hang for the harness kill
// ===========================================================================
//
// Gens 1..G (G = n / batch) each put `batch` pages and commit, so the
// committed view is exactly G*batch pages. The extra generation G+1 then
// stops at the state named by ORBITDB_BLOCK_KILL_AT:
//   pages2   -- half of the pages appended, no commit (hidden after reopen)
//   full2    -- all pages appended, no commit (hidden after reopen)
//   midheader-- pages committed normally, then the INACTIVE header slot is
//               torn (second half garbled), simulating a crash mid-slot-write
//   compacted-- full compaction ran (temp + atomic rename) before the hang
// The writer then writes a `.ready` marker and spins; the harness kills it.
// Kill at a quiescent state (no write in flight) -- the O(file) shim writes
// are not atomic, so mid-write kills are out of scope until S4.

fn run_writer(path: Str, n: Int, batch: Int, kill_at: Str) -> Int {
  var bs = block_store_open(path);
  let gens = n / batch;
  var g: Int = 1;
  while g <= gens {
    var i: Int = (g - 1) * batch + 1;
    while i <= g * batch {
      let pay = page_payload(i);
      if block_store_put(&mut bs, g, i, &pay) < 0 { return 1; }
      i = i + 1;
    }
    let h = header_for(g, 0, 0, 0);
    if !block_store_commit(&mut bs, &h) { return 1; }
    g = g + 1;
  }
  var i2: Int = gens * batch + 1;
  if kill_at == "pages2" {
    var half: Int = batch / 2;
    var c: Int = 0;
    while c < half {
      let pay = page_payload(i2 + c);
      if block_store_put(&mut bs, gens + 1, i2 + c, &pay) < 0 { return 1; }
      c = c + 1;
    }
  } elif kill_at == "full2" {
    var c: Int = 0;
    while c < batch {
      let pay = page_payload(i2 + c);
      if block_store_put(&mut bs, gens + 1, i2 + c, &pay) < 0 { return 1; }
      c = c + 1;
    }
  } elif kill_at == "compacted" {
    if !block_store_compact(&mut bs, gens + 1) { return 1; }
  } else {
    var c: Int = 0;
    while c < batch {
      let pay = page_payload(i2 + c);
      if block_store_put(&mut bs, gens + 1, i2 + c, &pay) < 0 { return 1; }
      c = c + 1;
    }
    let h2 = header_for(gens + 1, 0, 0, 0);
    if !block_store_commit(&mut bs, &h2) { return 1; }
    let slot = 1 - bs.active_slot;
    var half: Int = block_size() / 2;
    var t = Vec[Int].new();
    var k: Int = 0;
    while k < half {
      t.push(0x5A);
      k = k + 1;
    }
    if !byteio_write_at(path, slot * block_size() + half, &t) { return 1; }
  }
  match io.write_file(path + ".ready", "ready") {
    Ok(_) => {}
    Err(_) => { return 1; }
  }
  io.println("writer: ready kill_at=" + kill_at);
  var alive = true;
  while alive {
    io.sleep(1000);
  }
  return 0;
}

// ===========================================================================
// verify mode -- reopen after the kill, check the committed view, recover
// ===========================================================================

fn run_verify(path: Str, n: Int, batch: Int, kill_at: Str) -> Int {
  var fails: Int = 0;
  let gens = n / batch;
  var expected_gen = gens;
  var expected_count = gens * batch;
  var hidden = 0;
  if kill_at == "midheader" {
    expected_gen = gens + 1;
    expected_count = (gens + 1) * batch;
  } elif kill_at == "pages2" {
    hidden = batch / 2;
  } elif kill_at == "full2" {
    hidden = batch;
  } else {
    // compacted: the writer rewrote the store at gen+1 before hanging
    expected_gen = gens + 1;
    expected_count = gens * batch;
  }

  var bs = block_store_open(path);
  fails = check(bs.committed, "verify: store committed after the kill", fails);
  fails = check(bs.header.committed_generation == expected_gen,
    "verify: committed generation is the last complete one", fails);
  fails = check(block_store_count(&bs) == expected_count,
    "verify: visible pages = committed generation * batch (uncommitted hidden)", fails);

  var ok = true;
  var i: Int = 1;
  while i <= expected_count {
    let want = page_payload(i);
    match block_store_read(&bs, i) {
      Some(p) => { if !vec_eq(&p.payload, &want) { ok = false; } }
      None => { ok = false; }
    }
    i = i + 1;
  }
  fails = check(ok, "verify: every visible page payload intact (torn tail skipped)", fails);

  // Recovery append: one new page + commit, then reopen. The id sits past
  // the whole generation range (n pages + one extra batch) so it can never
  // collide with a re-committed hidden page.
  let new_id = n + batch + 1;
  let pay = page_payload(new_id);
  let nb = block_store_put(&mut bs, expected_gen + 1, new_id, &pay);
  let h = header_for(expected_gen + 1, 0, 0, 0);
  fails = check(nb >= 0 && block_store_commit(&mut bs, &h), "verify: append + commit after the kill", fails);
  var bs2 = block_store_open(path);
  var ok2 = bs2.committed && block_store_count(&bs2) == expected_count + hidden + 1;
  ok2 = ok2 && block_store_has(&bs2, new_id);
  fails = check(ok2, "verify: reopen shows prev hidden pages re-committed + the new page", fails);

  if fails == 0 {
    io.println("verify: GREEN gen=" + convert.int_to_string(expected_gen)
      + " pages=" + convert.int_to_string(expected_count));
    return 0;
  }
  io.println("verify: RED fails=" + convert.int_to_string(fails));
  return 1;
}

fn main() -> Int {
  let path = env.var_or("ORBITDB_BLOCK_DB", "probe-logs/block-store.bv2");
  let mode = env.var_or("ORBITDB_BLOCK_MODE", "full");
  let kill_at = env.var_or("ORBITDB_BLOCK_KILL_AT", "pages2");
  let n = env_int("ORBITDB_BLOCK_N", 60);
  let batch = env_int("ORBITDB_BLOCK_BATCH", 10);
  if mode == "writer" { return run_writer(path, n, batch, kill_at); }
  if mode == "verify" { return run_verify(path, n, batch, kill_at); }
  return run_full(path);
}

fn run_full(path: Str) -> Int {
  match io.remove_file(path) { Ok(_) => {} Err(_) => {} }
  match io.remove_file(path + ".tmp") { Ok(_) => {} Err(_) => {} }
  var fails: Int = 0;

  var empty = Vec[Int].new();
  var pa = Vec[Int].new();
  pa.push(1);
  pa.push(2);
  pa.push(3);
  var pc = Vec[Int].new();
  pc.push(9);
  var pd = Vec[Int].new();
  pd.push(4);
  var pe = Vec[Int].new();
  pe.push(5);
  var pf = Vec[Int].new();
  pf.push(6);
  var pg = Vec[Int].new();
  pg.push(7);
  pg.push(7);

  // --- fresh store ---------------------------------------------------------
  var bs = block_store_open(path);
  fails = check(!bs.committed && block_store_count(&bs) == 0, "fresh: open is empty and uncommitted", fails);

  // --- appends + committed visibility --------------------------------------
  let b1 = block_store_put(&mut bs, 1, 1, &pa);
  let b2 = block_store_put(&mut bs, 1, 2, &empty);
  let b3 = block_store_put(&mut bs, 1, 3, &pc);
  fails = check(b1 == 2 && b2 == 3 && b3 == 4, "put: first pages land after the two header slots", fails);
  match block_store_read(&bs, 1) {
    Some(p) => { fails = check(vec_eq(&p.payload, &pa) && p.generation == 1, "put: in-process read (own writes visible)", fails); }
    None => { fails = check(false, "put: in-process read", fails); }
  }
  var h1 = header_for(1, 5, 3, 10);
  fails = check(block_store_commit(&mut bs, &h1), "commit: first commit accepted", fails);
  fails = check(!block_store_commit(&mut bs, &h1), "commit: non-increasing generation rejected", fails);

  var bs1 = block_store_open(path);
  fails = check(bs1.committed && bs1.header.committed_generation == 1, "reopen: committed header gen 1", fails);
  fails = check(block_store_count(&bs1) == 3, "reopen: three pages visible", fails);
  var ok_payloads = true;
  match block_store_read(&bs1, 2) {
    Some(p) => { if !vec_eq(&p.payload, &empty) { ok_payloads = false; } }
    None => { ok_payloads = false; }
  }
  match block_store_read(&bs1, 3) {
    Some(p) => { if !vec_eq(&p.payload, &pc) { ok_payloads = false; } }
    None => { ok_payloads = false; }
  }
  fails = check(ok_payloads, "reopen: payloads round-trip (empty page included)", fails);

  // --- uncommitted pages are hidden on reopen -------------------------------
  let b4 = block_store_put(&mut bs, 2, 4, &pd);
  fails = check(b4 == 5 && block_store_has(&bs, 4), "put: uncommitted page visible in-process", fails);
  var bs2 = block_store_open(path);
  fails = check(!block_store_has(&bs2, 4) && block_store_count(&bs2) == 3, "reopen: uncommitted page hidden", fails);

  // --- latest-wins at commit time (both gen-2 pages become visible) --------
  let b5 = block_store_put(&mut bs, 2, 1, &pg);
  var h2 = header_for(2, 7, 4, 20);
  fails = check(b5 == 6 && block_store_commit(&mut bs, &h2), "commit: gen 2 (update + new page)", fails);
  var bs3 = block_store_open(path);
  var ok_lw = block_store_count(&bs3) == 4;
  match block_store_read(&bs3, 1) {
    Some(p) => { if p.generation != 2 || !vec_eq(&p.payload, &pg) { ok_lw = false; } }
    None => { ok_lw = false; }
  }
  match block_store_read(&bs3, 4) {
    Some(p) => { if p.generation != 2 { ok_lw = false; } }
    None => { ok_lw = false; }
  }
  fails = check(ok_lw, "reopen: latest-wins per id (updated page + previously uncommitted page)", fails);

  // --- torn tail: a garbage block is skipped, appends continue after it ----
  let gar = garblock();
  if !byteio_append(path, &gar) { fails = fails + 1; }
  var bs4 = block_store_open(path);
  fails = check(block_store_blocks(&bs4) == 8 && block_store_count(&bs4) == 4,
    "torn tail: garbage block skipped (blocks=8, pages=4)", fails);
  let b6 = block_store_put(&mut bs4, 3, 5, &pe);
  var h3 = header_for(3, 9, 5, 30);
  fails = check(b6 == 8 && block_store_commit(&mut bs4, &h3), "commit: gen 3 lands after the torn block", fails);
  var bs5 = block_store_open(path);
  fails = check(block_store_count(&bs5) == 5 && block_store_has(&bs5, 5), "reopen: gen 3 visible (5 pages)", fails);

  // --- torn ACTIVE header slot -> fallback to the previous slot ------------
  let active = bs5.active_slot;
  if !byteio_write_at(path, active * block_size(), &gar) { fails = fails + 1; }
  var bs6 = block_store_open(path);
  fails = check(bs6.committed && bs6.header.committed_generation == 2,
    "torn active slot: falls back to the previous header (gen 2)", fails);
  fails = check(block_store_count(&bs6) == 4 && !block_store_has(&bs6, 5),
    "torn active slot: gen-3 pages hidden again", fails);

  // --- a later commit re-commits the surviving gen-3 page ------------------
  var bs7 = block_store_open(path);
  let b7 = block_store_put(&mut bs7, 4, 6, &pf);
  var h4 = header_for(4, 10, 6, 40);
  fails = check(b7 == 9 && block_store_commit(&mut bs7, &h4), "commit: gen 4 repairs the corrupt slot", fails);
  var bs8 = block_store_open(path);
  var ok_rec = block_store_count(&bs8) == 6 && block_store_has(&bs8, 5) && block_store_has(&bs8, 6);
  match block_store_read(&bs8, 1) {
    Some(p) => { if p.generation != 2 { ok_rec = false; } }
    None => { ok_rec = false; }
  }
  fails = check(ok_rec, "reopen: gen 4 re-commits the surviving gen-3 page (6 pages)", fails);

  // --- both slots corrupt -> empty; next commit restores everything --------
  if !byteio_write_at(path, 0, &gar) { fails = fails + 1; }
  if !byteio_write_at(path, block_size(), &gar) { fails = fails + 1; }
  var bs9 = block_store_open(path);
  fails = check(!bs9.committed && block_store_count(&bs9) == 0, "both slots corrupt: store reads empty", fails);
  var h5 = header_for(5, 10, 6, 50);
  fails = check(block_store_commit(&mut bs9, &h5), "commit: gen 5 rewrites both slots", fails);
  var bs10 = block_store_open(path);
  fails = check(block_store_count(&bs10) == 6, "reopen: all six pages visible again under gen 5", fails);

  // --- compaction -----------------------------------------------------------
  var bs11 = block_store_open(path);
  fails = check(block_store_compact(&mut bs11, 6), "compact: gen 6 accepted", fails);
  fails = check(block_store_blocks(&bs11) == 8 && block_store_count(&bs11) == 6,
    "compact: file is 2 slots + 6 pages", fails);
  var bs12 = block_store_open(path);
  var ok_comp = bs12.committed && bs12.header.committed_generation == 6 && block_store_count(&bs12) == 6;
  match block_store_read(&bs12, 1) {
    Some(p) => { if !vec_eq(&p.payload, &pg) || p.generation != 6 { ok_comp = false; } }
    None => { ok_comp = false; }
  }
  match block_store_read(&bs12, 6) {
    Some(p) => { if !vec_eq(&p.payload, &pf) { ok_comp = false; } }
    None => { ok_comp = false; }
  }
  fails = check(ok_comp, "compact: reopen reads the compacted store (gen 6, payloads kept)", fails);

  // --- capacity -------------------------------------------------------------
  var big = Vec[Int].new();
  var i: Int = 0;
  while i <= block_payload_capacity() {
    big.push(0);
    i = i + 1;
  }
  fails = check(block_store_put(&mut bs12, 7, 99, &big) == -1, "capacity: payload > 4056 rejected", fails);

  if fails == 0 { io.println("block-store: GREEN"); return 0; }
  io.println("block-store: RED fails=" + convert.int_to_string(fails));
  return 1;
}
