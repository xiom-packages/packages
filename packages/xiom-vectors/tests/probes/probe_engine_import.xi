// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: can a probe module import the project's engine module through the
// xiom.toml source-roots catalog? (Bootstrap gate for the layered build.)
// Exit 0 = the consolidated engine is importable cross-file.

module probe_engine_import

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.io;

fn main() -> Int {
  var eng = engine_new();
  if engine_size(&eng) != 0 { io.println("import: FAIL size"); return 1; }
  io.println("import: xiom.vector.engine resolves cross-file");
  return 0;
}
