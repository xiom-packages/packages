// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// D5 kill-matrix WRITER: durable upserts forever, with an ack ledger.
// Usage: kill_writer <seg_path> <ack_path> <max_points>
// The parent kills this process mid-stream; every id written to the ack
// ledger was acknowledged AFTER its fsync (WAL-before-ack), so recovery
// must contain all of them. No checkpoint is ever persisted here: the
// delta segment alone is the crash contract under test.

module kill_writer

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.storage.vector_store;
use xiom.vectors;
use xiom.os.env;
use xiom.os.sync_io;
use xiom.os.fs_ffi;
use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.convert.parse;

fn main() -> Int {
  let args = env.args();
  let n = args.len();
  if n < 4 {
    io.println("kill_writer: need <seg> <ack> <max>");
    return 2;
  }
  let seg = args[n - 3];
  let ack = args[n - 2];
  var max_points: Int = 1000000;
  match parse.parse_int(args[n - 1]) {
    Ok(v) => { max_points = v; }
    Err(_) => {}
  }

  var eng = engine_new();
  match engine_enable_durable(&mut eng, seg) {
    Ok(_) => {}
    Err(_) => { io.println("kill_writer: enable failed"); return 3; }
  }
  match engine_create_collection(&mut eng, 4, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(_) => { io.println("kill_writer: create failed"); return 4; }
  }

  var afr = sync_io.open_append(ack);
  var afd: Int = -1;
  match afr {
    Ok(f) => { afd = f; }
    Err(_) => { io.println("kill_writer: ack open failed"); return 5; }
  }

  var s: Int = 12345;
  var i: Int = 1;
  while i <= max_points {
    s = (s * 1103515245 + 12345) % 2147483648;
    var c0 = (s % 2001) as Float32;
    s = (s * 1103515245 + 12345) % 2147483648;
    var c1 = (s % 2001) as Float32;
    s = (s * 1103515245 + 12345) % 2147483648;
    var c2 = (s % 2001) as Float32;
    s = (s * 1103515245 + 12345) % 2147483648;
    var c3 = (s % 2001) as Float32;
    var v = Vector.new(4);
    v.set(0, c0 / 1000.0 - 1.0);
    v.set(1, c1 / 1000.0 - 1.0);
    v.set(2, c2 / 1000.0 - 1.0);
    v.set(3, c3 / 1000.0 - 1.0);

    match engine_upsert(&mut eng, i, v) {
      Ok(_) => {}
      Err(_) => { return 8; }
    }
    var line = convert.int_to_string(i) + "\n";
    var lb = slice.str_bytes(line);
    match sync_io.write_all(afd, &lb) {
      Ok(_) => {}
      Err(_) => { return 6; }
    }
    match fs_ffi.fsync(afd) {
      Ok(_) => {}
      Err(_) => { return 7; }
    }
    i = i + 1;
  }
  return 0;
}
