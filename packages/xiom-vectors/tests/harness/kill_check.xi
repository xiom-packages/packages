// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// D5 kill-matrix CHECKER: recover from <ckpt> + <seg> (segment-only in the
// crash runs) and prove every ACKNOWLEDGED id in the ack ledger is present.
// Usage: kill_check <seg_path> <ckpt_path> <ack_path>
// Exit: 0 = all acked present; 1 = acked records missing; 2 = no acks.
// A torn last ack line is safe to count: the ack is written only AFTER the
// engine's fsync, so any prefix of it names an already-durable id.

module kill_check

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.os.env;
use xiom.vector.durability.wal_file;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let args = env.args();
  let n = args.len();
  if n < 4 {
    io.println("kill_check: need <seg> <ckpt> <ack>");
    return 2;
  }
  let seg = args[n - 3];
  let ckpt = args[n - 2];
  let ack = args[n - 1];

  var acked = Vec[Int].new();
  if io.file_exists(ack) {
    match io.read_file_bytes(ack) {
      Ok(b) => {
        var pos: Int = 0;
        while pos < b.len() {
          var r = parse_int_at(b, pos);
          if !r.ok {
            pos = pos + 1;
          } else {
            acked.push(r.value);
            pos = r.pos;
          }
        }
      }
      Err(_) => {}
    }
  }
  if acked.len() == 0 {
    io.println("kill_check: NO ACKS");
    return 2;
  }

  var eng = engine_open_durable(ckpt, seg, "", 4, DistanceMetric.Cosine);
  var missing: Int = 0;
  var i: Int = 0;
  while i < acked.len() {
    match index_get(&eng.store, acked[i]) {
      Some(_) => {}
      None => { missing = missing + 1; }
    }
    i = i + 1;
  }
  var recovered = engine_size(&eng);
  io.println("kill_check: acked=" + convert.int_to_string(acked.len())
    + " recovered=" + convert.int_to_string(recovered)
    + " missing=" + convert.int_to_string(missing));
  if missing == 0 && recovered >= acked.len() {
    return 0;
  }
  return 1;
}
