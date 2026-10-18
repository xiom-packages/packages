// XIOM XVECTOR -- crash-forensics marks variant of probe.xi (thread gate).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Rewrites out/thread_abi_mark.txt at each stage (survives an abnormal
// exit). The last surviving mark localizes the access violation in the
// xiom.thread.spawn[T]/JoinHandle.join path on a toolchain where the
// runtime thread entrypoint is known to AV (see probe.xi header).

module probe_thread_marks

use xiom.io;
use xiom.slice;
use xiom.thread;

fn mark(tag: Str) {
  var b = slice.str_bytes(tag);
  var res = io.write_file_bytes("out/thread_abi_mark.txt", &b);
  match res {
    Ok(_) => {}
    Err(_) => {}
  }
}

fn trivial() -> Int {
  mark("W0: worker entered");
  return 42;
}

fn main() -> Int {
  mark("M0: main entered");
  let mid = current_thread_id();
  let ap = available_parallelism();
  if ap < 1 { mark("M1b: no parallelism"); return 3; }
  mark("M1: main ids ok");
  let h = spawn(trivial);
  mark("M2: spawn returned");
  match h.join() {
    Ok(v) => {
      if v == 42 { mark("M3: join ok 42"); return 0; }
      mark("M3b: join wrong value");
      return 1;
    }
    Err(e) => {
      mark("M3c: join err");
      return 2;
    }
  }
}
