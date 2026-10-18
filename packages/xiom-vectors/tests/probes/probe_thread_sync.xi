// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// G-1 thread + sync smoke (upgraded on v0.64.7 -- XVC-C-17 verified fixed):
//   1) spawn/join: 3 workers return exact values; a worker's OS thread id
//      differs from main; available_parallelism() >= 1.
//   2) mutex-guarded shared counter: 4 workers x 500 increments through a
//      REAL module-level imported-type SyncMutex global (the natural
//      pattern; the Int-handle workaround is RETIRED -- C-17 fixed).
//   3) atomic counter: 4 workers x 500 atomic_fetch_add on a module-level
//      AtomicInt global -> exact total.
//   4) channel contract (same-thread): bounded capacity, FIFO order, close.
//   5) CROSS-THREAD producer/consumer: 2 real producer threads x 200
//      handoffs through a scalar single-slot mailbox guarded by the shared
//      module-level spinlock (natural imported-type global). Scalars only:
//      a module-level container initializer (channel_new / Vec::new at load
//      time) hangs the v0.64.7 compiler and would also allocate before
//      runtime init, so the cross-thread CHANNEL leg stays blocked on a
//      stdlib channel handle form; the scalar mailbox proves the same
//      contract (exact totals + per-producer FIFO + cross-thread lock).
// Exit = failed checks (0 = green).

module probe_thread_sync

use xiom.thread;
use xiom.sync.mutex;
use xiom.sync.atomics;
use xiom.sync.channel;
use xiom.io;
use xiom.convert;

// Shared state: NATURAL imported-type globals (C-17 fix under test).
// Scalars / null-only literals: global initializers must not allocate.
var G_M: mutex.SyncMutex = mutex.SyncMutex{ locked: null };
var G_ATOM: atomics.AtomicInt = atomics.AtomicInt{ ptr: null };
var G_SLOT: Int = 0;
var G_FULL: Bool = false;
var G_COUNT: Int = 0;
var G_ITERS: Int = 500;
var G_SENT_PER: Int = 200;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// ---- part 1: spawn/join acceptance ----------------------------------------

fn work_ten() -> Int { return 10; }
fn work_twenty() -> Int { return 20; }
fn work_thirty() -> Int { return 30; }
fn work_whoami() -> Int { return current_thread_id(); }

// ---- part 2: mutex-guarded counter (natural global handle) ----------------

fn bump_locked() -> Int {
  var i: Int = 0;
  while i < G_ITERS {
    mutex.mutex_lock(&mut G_M);
    G_COUNT = G_COUNT + 1;
    mutex.mutex_unlock(&mut G_M);
    i = i + 1;
  }
  return 0;
}

// ---- part 3: atomic counter ------------------------------------------------

fn bump_atomic() -> Int {
  var i: Int = 0;
  while i < G_ITERS {
    atomics.atomic_fetch_add(&mut G_ATOM, 1);
    i = i + 1;
  }
  return 0;
}

// ---- part 5: cross-thread single-slot mailbox producers --------------------

fn produce_worker(worker: Int) -> Int {
  var n: Int = 0;
  while n < G_SENT_PER {
    var v = worker * 1000 + n;
    var placed: Bool = false;
    while !placed {
      mutex.mutex_lock(&mut G_M);
      if !G_FULL {
        G_SLOT = v;
        G_FULL = true;
        placed = true;
      }
      mutex.mutex_unlock(&mut G_M);
    }
    n = n + 1;
  }
  return 0;
}

fn produce_a() -> Int { return produce_worker(1); }
fn produce_b() -> Int { return produce_worker(2); }

fn main() -> Int {
  io.println("=== xvector probe: thread + sync smoke (G-1) ===");
  var fails: Int = 0;

  // Part 1: real spawn/join.
  var h1 = spawn(work_ten);
  var h2 = spawn(work_twenty);
  var h3 = spawn(work_thirty);
  var r1: Int = -1;
  var r2: Int = -1;
  var r3: Int = -1;
  match h1.join() {
    Ok(v) => { r1 = v; }
    Err(e) => { io.println("  join1 Err " + e); }
  }
  match h2.join() {
    Ok(v) => { r2 = v; }
    Err(e) => { io.println("  join2 Err " + e); }
  }
  match h3.join() {
    Ok(v) => { r3 = v; }
    Err(e) => { io.println("  join3 Err " + e); }
  }
  io.println("  sums: " + convert.int_to_string(r1) + "+" + convert.int_to_string(r2)
    + "+" + convert.int_to_string(r3));
  fails = check(r1 == 10 && r2 == 20 && r3 == 30, "spawn/join: 3 workers return exact values", fails);

  var main_id = current_thread_id();
  var hw = spawn(work_whoami);
  var wid: Int = -1;
  match hw.join() {
    Ok(v) => { wid = v; }
    Err(e) => { io.println("  joinw Err " + e); }
  }
  fails = check(wid != main_id && wid > 0,
    "spawn: worker OS thread id != main (" + convert.int_to_string(wid) + " vs "
    + convert.int_to_string(main_id) + ")", fails);
  fails = check(available_parallelism() >= 1, "available_parallelism >= 1", fails);

  // Part 2: mutex-guarded counter (4 x 500 = 2000) through the GLOBAL handle.
  G_M = mutex.mutex_new();
  G_COUNT = 0;
  fails = check(!mutex.mutex_is_locked(&G_M), "sync setup: module-level SyncMutex global (unlocked)", fails);
  var a = spawn(bump_locked);
  var b = spawn(bump_locked);
  var c = spawn(bump_locked);
  var d = spawn(bump_locked);
  var ja: Int = -1;
  var jb: Int = -1;
  var jc: Int = -1;
  var jd: Int = -1;
  match a.join() { Ok(v) => { ja = v; } Err(_) => {} }
  match b.join() { Ok(v) => { jb = v; } Err(_) => {} }
  match c.join() { Ok(v) => { jc = v; } Err(_) => {} }
  match d.join() { Ok(v) => { jd = v; } Err(_) => {} }
  var expected = G_ITERS * 4;
  io.println("  mutex counter: " + convert.int_to_string(G_COUNT) + " (expect "
    + convert.int_to_string(expected) + "), joins " + convert.int_to_string(ja + jb + jc + jd));
  fails = check(G_COUNT == expected, "mutex: 4 workers x 500 on the global handle -> exact total", fails);

  // Part 3: atomic counter (4 x 500 = 2000) through the GLOBAL cell.
  G_ATOM = atomics.atomic_int_new(0);
  fails = check(atomics.atomic_load(&G_ATOM) == 0, "sync setup: module-level AtomicInt global installed", fails);
  var e = spawn(bump_atomic);
  var f = spawn(bump_atomic);
  var g = spawn(bump_atomic);
  var h = spawn(bump_atomic);
  match e.join() { Ok(_) => {} Err(_) => {} }
  match f.join() { Ok(_) => {} Err(_) => {} }
  match g.join() { Ok(_) => {} Err(_) => {} }
  match h.join() { Ok(_) => {} Err(_) => {} }
  var aval = atomics.atomic_load(&G_ATOM);
  var aexpected = G_ITERS * 4;
  io.println("  atomic counter: " + convert.int_to_string(aval) + " (expect "
    + convert.int_to_string(aexpected) + ")");
  fails = check(aval == aexpected, "atomics: 4 workers x 500 fetch_add -> exact total", fails);

  // Part 4: channel contract (same-thread).
  var ch = channel.channel_new[Int](4);
  fails = check(channel.channel_capacity(&ch) == 4 && channel.channel_len(&ch) == 0,
    "channel: new(cap=4) -> cap 4, empty", fails);
  var s1ok = true;
  var sr1 = channel.channel_send(&mut ch, 11);
  var sr2 = channel.channel_send(&mut ch, 22);
  var sr3 = channel.channel_send(&mut ch, 33);
  var sr4 = channel.channel_send(&mut ch, 44);
  match sr1 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr2 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr3 { Ok(_) => {} Err(_) => { s1ok = false; } }
  match sr4 { Ok(_) => {} Err(_) => { s1ok = false; } }
  var full = channel.channel_try_send(&mut ch, 55);
  fails = check(s1ok && channel.channel_len(&ch) == 4 && !full,
    "channel: 4 sends fill cap 4; try_send when full -> false", fails);
  var got: Int = 0;
  var fifo_ok = true;
  var want: Int = 11;
  var recvs: Int = 0;
  while recvs < 4 {
    match channel.channel_recv(&mut ch) {
      Some(v) => { got = got + 1; if v != want { fifo_ok = false; } want = want + 11; }
      None => { recvs = 4; }
    }
    recvs = recvs + 1;
  }
  fails = check(fifo_ok && got == 4, "channel: FIFO 11,22,33,44 for 4 recvs", fails);
  channel.channel_close(&mut ch);
  var none_ok = true;
  match channel.channel_recv(&mut ch) {
    Some(_) => { none_ok = false; }
    None => {}
  }
  var send_after_close = channel.channel_send(&mut ch, 66);
  var err_ok = false;
  match send_after_close { Ok(_) => {} Err(_) => { err_ok = true; } }
  fails = check(none_ok && err_ok && channel.channel_is_closed(&ch),
    "channel: close -> recv None, send Err", fails);

  // Part 5: CROSS-THREAD producer/consumer (2 x 200 scalar mailbox handoffs,
  // coarse lock; the channel's cross-thread leg awaits a handle form).
  G_SLOT = 0;
  G_FULL = false;
  var pa = spawn(produce_a);
  var pb = spawn(produce_b);
  var total: Int = 0;
  var seen_a: Int = 0;
  var seen_b: Int = 0;
  var order_ok: Bool = true;
  while total < G_SENT_PER * 2 {
    var recv_v: Int = -1;
    var have = false;
    mutex.mutex_lock(&mut G_M);
    if G_FULL {
      recv_v = G_SLOT;
      G_FULL = false;
      have = true;
    }
    mutex.mutex_unlock(&mut G_M);
    if have {
      total = total + 1;
      var worker = recv_v / 1000;
      var seq = recv_v - worker * 1000;
      if worker == 1 {
        if seq != seen_a { order_ok = false; }
        seen_a = seen_a + 1;
      } else if worker == 2 {
        if seq != seen_b { order_ok = false; }
        seen_b = seen_b + 1;
      } else {
        order_ok = false;
      }
    }
  }
  match pa.join() { Ok(_) => {} Err(_) => {} }
  match pb.join() { Ok(_) => {} Err(_) => {} }
  fails = check(total == G_SENT_PER * 2 && seen_a == G_SENT_PER && seen_b == G_SENT_PER && order_ok,
    "mailbox: cross-thread 2x200 handoffs under one global lock (exact + per-producer FIFO)", fails);
  fails = check(!G_FULL, "mailbox: fully drained (no slot held after 400 handoffs)", fails);

  io.println("");
  io.println("probe_thread_sync: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
