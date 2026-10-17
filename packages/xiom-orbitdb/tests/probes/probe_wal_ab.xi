// scratch A/B: per-op durable append, OLD shape (append_line + byteio_sync)
// vs NEW shape (wal_file_append_sync single held handle). Same process,
// interleaved rounds -- load-noise-immune ratio.
module orbitdb_probe_wal_ab

use xiom.io;
use xiom.os.env;
use xiom.convert.parse;
use xiom.convert;
use xiom.time.time;
use xiom.db.wal_file;
use xiom.db.storage.byte_io;

fn run_old(path: Str, n: Int) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  let t0 = time.monotonic_ms();
  var i = 0;
  while i < n {
    let lsn = wal_file_append(&mut w, WALOpKind.Insert, i, i * 7 + 1);
    if lsn < 0 { return -1; }
    if !byteio_sync(path) { return -2; }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  return t1 - t0;
}

fn run_new(path: Str, n: Int) -> Int {
  let _ = io.remove_file(path);
  var w = wal_file_open(path);
  let t0 = time.monotonic_ms();
  var i = 0;
  while i < n {
    let lsn = wal_file_append_sync(&mut w, WALOpKind.Insert, i, i * 7 + 1, true);
    if lsn < 0 { return -1; }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  return t1 - t0;
}

fn main() -> Int {
  // env: ORBITDB_AB_N (default 5000), ORBITDB_AB_ROUNDS (default 3)
  var n = 5000;
  match parse.parse_int(env.var_or("ORBITDB_AB_N", "5000")) {
    Err(_) => {}
    Ok(v) => { n = v; }
  }
  var rounds = 3;
  match parse.parse_int(env.var_or("ORBITDB_AB_ROUNDS", "3")) {
    Err(_) => {}
    Ok(v) => { rounds = v; }
  }
  let old_p = "probe-logs/ab-old.wal";
  let new_p = "probe-logs/ab-new.wal";
  var r = 1;
  while r <= rounds {
    let o = run_old(old_p, n);
    let w = run_new(new_p, n);
    io.println("round" + convert.int_to_string(r)
      + ": old_ms=" + convert.int_to_string(o)
      + " new_ms=" + convert.int_to_string(w));
    r = r + 1;
  }
  return 0;
}
