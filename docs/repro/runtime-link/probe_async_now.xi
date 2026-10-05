// AOT runtime-link probe: async_runtime.c must be linked (v0.63.1).
//
// `find_runtime_c_files()` (crates/xiom/src/lib.rs:2111) does not scan the
// production install layout `<install>\lib\runtime`, so it returns an empty
// list and the link falls back to the single `xiom_runtime.c`. Any program
// whose closure references `xiom_async_now_ms` then fails:
//
//   lld-link: error: undefined symbol: xiom_async_now_ms
//   >>> referenced by ...:(__unsafe_block_N)
//
// With the supported override `XIOM_RUNTIME_DIR=<stdlib>\runtime` the whole
// runtime dir is linked and this probe exits 0.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module runtime_link_probe

use xiom.time;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let ms = time.monotonic_ms();
  io.println("now_ms=" + int_to_string(ms));
  if ms < 0 {
    io.println("bad=1");
    return 1;
  }
  io.println("bad=0");
  return 0;
}
