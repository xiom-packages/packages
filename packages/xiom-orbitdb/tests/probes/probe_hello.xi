// XIOM ORBITDB -- bootstrap hello probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Purpose: prove the toolchain resolves, compiles, links, and runs this
// repo's modules under the tracked compiler/stdlib with XIOM_RUNTIME_DIR
// retired. Run twice (suite x2 rule): .\scripts\run.ps1 tests\probes\probe_hello.xi

module orbitdb_probe_hello

use xiom.io;
use xiom.db.engine;

fn main() -> Int {
  io.println("orbitdb: hello probe");
  io.println("orbitdb: engine module linked");

  // Touch the critical primitive so the probe fails if linking broke:
  // WAL is written before data (ARCHITECTURE.md golden rule).
  var db = db_open(4);
  let ok = db_insert(&mut db, 1, 100);
  if !ok { io.println("orbitdb: insert FAILED"); return 1; }
  let v = db_get(&db, 1);
  match v {
    None => { io.println("orbitdb: get FAILED"); return 1; }
    Some(x) => {
      if x != 100 { io.println("orbitdb: get wrong value"); return 1; }
    }
  }
  if db_size(&db) != 1 { io.println("orbitdb: size FAILED"); return 1; }
  db_close(&mut db);
  io.println("orbitdb: hello probe OK");
  return 0;
}
