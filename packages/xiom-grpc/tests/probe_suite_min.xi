// Minimal extraction of `test_grpc_metadata_set_new_key` (v0.62.3).
//
// The suite file crashes 0xC0000005 pre-output when main calls this test;
// the same operations replicated standalone (plain and struct-wrapped) pass.
// This probe keeps the suite's exact body but calls the *library*
// implementations (`grpc_request_new`, `grpc_metadata_set`) in a minimal file.
//
// Expected after the fix: `rc=0`, exit 0.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tuple_vec_min_probe

use xiom.grpc;
use xiom.grpc.types;
use xiom.io;
use xiom.convert;

fn test_set_new_key() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("svc", "m", payload, meta);
  grpc_metadata_set(&mut req, "grpc-timeout", "5s");
  if req.metadata.len() == 1 && req.metadata[0].0 == "grpc-timeout" { return 0; }
  return 1;
}

fn main() -> Int {
  io.println("start");
  io.flush_stdout();
  let rc = test_set_new_key();
  io.println("rc=" + int_to_string(rc));
  io.flush_stdout();
  return rc;
}

