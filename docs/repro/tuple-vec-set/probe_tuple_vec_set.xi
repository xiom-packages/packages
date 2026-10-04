// Tuple-vector mutation probe (v0.62.3).
//
// Found while restoring `xiom.grpc`: `test_grpc_metadata_set_new_key` alone
// crashes the suite binary with 0xC0000005 before any output, on both the
// pinned v0.62.3 and a local main build (m184..m188). The test exercises
// `grpc_metadata_set` on a `Vec[(Str, Str)]`:
//
//   let (k, v) = &req.metadata[i];
//   if k == &key { req.metadata[i] = (key.clone(), value.clone()); found = true; };
//   ... if !found { req.metadata.push((key.clone(), value.clone())); }
//
// This probe mirrors those operations standalone.
//
// Expected after the fix: `len=1`, `bad=0`, exit 0.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tuple_vec_set_probe

use xiom.io;
use xiom.convert;

fn set_meta(meta: &mut Vec[(Str, Str)], key: Str, value: Str) {
  var found = false;
  var i = 0;
  while i < meta.len() {
    let (k, v) = &meta[i];
    if k == &key {
      meta[i] = (key.clone(), value.clone());
      found = true;
    };
    i = i + 1;
  };
  if !found {
    meta.push((key.clone(), value.clone()));
  };
}

fn main() -> Int {
  var bad = 0;
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  set_meta(&mut meta, "grpc-timeout", "5s");
  io.println("len=" + int_to_string(meta.len()));
  io.flush_stdout();
  if meta.len() != 1 { bad = bad + 1; }
  io.println("bad=" + int_to_string(bad));
  io.flush_stdout();
  return bad;
}
