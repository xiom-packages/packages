// Hang variant of the grpc tuple-vec bug (v0.62.3, compiler-lane handoff).
//
// Same operations as `probe_suite_min.xi` but inline in main:
//   - WITHOUT the `req.metadata[0].0 == "grpc-timeout"` read: runs
//     (`start`, `len=1`, exit 0);
//   - WITH that read (the code below): HANGS (watchdog-killed at 30s).
//
// Together with `probe_suite_min.xi` (crash 0xC0000005 when the wrapper
// function is called) this isolates the fault to reading a tuple-`Str`
// element after mutating the `Vec[(Str, Str)]` through the library path.
// See `docs/repro/tuple-vec-set/README.md` for the full matrix.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tuple_direct_probe

use xiom.grpc;
use xiom.grpc.types;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  io.println("start");
  io.flush_stdout();
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("svc", "m", payload, meta);
  grpc_metadata_set(&mut req, "grpc-timeout", "5s");
  io.println("len=" + int_to_string(req.metadata.len()));
  io.flush_stdout();
  if req.metadata.len() == 1 && req.metadata[0].0 == "grpc-timeout" {
    io.println("match=ok");
  } else {
    io.println("match=no");
  };
  io.flush_stdout();
  return 0;
}
