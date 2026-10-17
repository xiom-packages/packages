// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// XV-ORBITDB-01 regression probe: chained persist -> load -> recover ->
// persist -> load. Fixed in xiom-xvector commit 3c36f34 ("wal_load accepts
// any starting LSN"), verified 2026-10-10 against the xvector source tree
// (load2 records=3, recovered2 == recovered; previously load2 records=0).
// Expects a GREEN line on the fixed tree; RED if the loader regresses.

module repro_chain

use xiom.io;
use xiom.convert;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal;
use xiom.vector.durability.wal_file;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

fn main() -> Int {
  let f1 = "probe-logs/repro-chain-1.wal";
  let f2 = "probe-logs/repro-chain-2.wal";
  var eng = engine_new();
  create_collection(&mut eng, 4, DistanceMetric.Cosine);
  var v = Vector.new(4);
  v.set(0, 1.0);
  upsert(&mut eng, 1, v);
  var v2 = Vector.new(4);
  v2.set(1, 1.0);
  upsert(&mut eng, 2, v2);
  let p1 = wal_persist(&eng.wal, f1);
  var p1n: Int = 0;
  if p1 { p1n = 1; }
  io.println("persist1=" + convert.int_to_string(p1n));
  var w1 = wal_load(f1);
  io.println("load1 records=" + convert.int_to_string(w1.records.len()));
  var eng2 = engine_recover(&w1, 4, DistanceMetric.Cosine);
  let size1 = engine_size(&eng2);
  io.println("recovered size=" + convert.int_to_string(size1));
  io.println("checkpointed log records=" + convert.int_to_string(eng2.wal.records.len()));
  io.println("checkpointed first lsn=" + convert.int_to_string(eng2.wal.records[0].lsn));
  let p2 = wal_persist(&eng2.wal, f2);
  var p2n: Int = 0;
  if p2 { p2n = 1; }
  io.println("persist2=" + convert.int_to_string(p2n));
  var w2 = wal_load(f2);
  io.println("load2 records=" + convert.int_to_string(w2.records.len()));
  var eng3 = engine_recover(&w2, 4, DistanceMetric.Cosine);
  let size2 = engine_size(&eng3);
  io.println("recovered2 size=" + convert.int_to_string(size2));
  // Regression assert (was XV-ORBITDB-01; fixed in xiom-xvector 3c36f34):
  // the chained reload must carry the full state, not an empty writer.
  if w2.records.len() > 0 && size2 == size1 {
    io.println("repro: GREEN");
    return 0;
  }
  io.println("repro: RED");
  return 1;
}
