// XIOM XVECTOR -- thread-primitive gate probe (G-phase groundwork).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Question: can this lane start REAL OS threads on the installed toolchain
// via xiom.thread's extern-backed `spawn[T]`? The `xiom.thread.spawn`
// module documents a simulation (inline execution: "the current toolchain
// cannot start real OS threads -- fn-to-pointer casts are rejected and the
// runtime thread entrypoint AVs"), so this probe is the acceptance for the
// real path:
//   - 3 workers must return exact distinct sums through JoinHandle.join;
//   - a worker's thread id must differ from the main thread's id (proves
//     real concurrency, not inline simulation);
//   - available_parallelism >= 1.
// Exit = failed checks. On a compile reject / runtime AV, the bundle README
// records the gate; re-run at the next compiler release (the fn-value ABI
// batch m263-m265 / fde5548e is the expected unblocker).

module probe_thread_abi

use xiom.io;
use xiom.convert;
use xiom.thread;

fn sum_upto(n: Int) -> Int {
  var acc: Int = 0;
  var i: Int = 1;
  while i <= n {
    acc = acc + i;
    i = i + 1;
  }
  return acc;
}

fn work_a() -> Int {
  return sum_upto(1000);
}

fn work_b() -> Int {
  return sum_upto(2000);
}

fn work_c() -> Int {
  return sum_upto(4000);
}

fn id_worker() -> Int {
  return current_thread_id();
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.thread real-spawn gate (G phase) ===");
  var fails: Int = 0;

  let main_id = current_thread_id();

  let ha = spawn(work_a);
  let hb = spawn(work_b);
  let hc = spawn(work_c);
  var ra: Int = -1;
  var rb: Int = -1;
  var rc: Int = -1;
  match ha.join() {
    Ok(v) => { ra = v; }
    Err(e) => { io.println("  join err: " + e); }
  }
  match hb.join() {
    Ok(v) => { rb = v; }
    Err(e) => { io.println("  join err: " + e); }
  }
  match hc.join() {
    Ok(v) => { rc = v; }
    Err(e) => { io.println("  join err: " + e); }
  }
  fails = check(ra == sum_upto(1000) && rb == sum_upto(2000) && rc == sum_upto(4000),
    "spawn[T]+join: 3 workers return exact sums", fails);

  let hid = spawn(id_worker);
  var wid: Int = -1;
  match hid.join() {
    Ok(v) => { wid = v; }
    Err(e) => { io.println("  join err: " + e); }
  }
  fails = check(wid != main_id && wid != -1,
    "worker thread id differs from main (real OS thread, not inline)", fails);

  fails = check(available_parallelism() >= 1, "available_parallelism >= 1", fails);

  io.println("");
  io.println("probe_thread_abi: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
