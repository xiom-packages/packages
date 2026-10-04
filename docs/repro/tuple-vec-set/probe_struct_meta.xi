// Struct-wrapped metadata mutation probe (v0.62.3).
//
// `probe_tuple_vec_set.xi` (plain Vec[(Str, Str)]) passes; this variant
// mirrors `xiom.grpc`'s `GrpcRequest` wrapper, `grpc_request_new`
// (`.clone()` on Str args) and `grpc_metadata_set` exactly, including the
// `requires` contracts.
//
// Expected after the fix: `len=1`, `bad=0`, exit 0.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module struct_meta_probe

use xiom.io;
use xiom.convert;

pub type Req = {
  service: Str;
  method: Str;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
}

pub fn req_new(service: Str, method: Str, payload: Vec[Int], metadata: Vec[(Str, Str)]) -> Req
  requires: service.len() > 0
  requires: method.len() > 0
{
  Req {
    service: service.clone();
    method: method.clone();
    payload: payload;
    metadata: metadata;
  }
}

pub fn metadata_set(req: &mut Req, key: Str, value: Str)
  requires: key.len() > 0
{
  var found = false;
  var i = 0;
  while i < req.metadata.len() {
    let (k, v) = &req.metadata[i];
    if k == &key {
      req.metadata[i] = (key.clone(), value.clone());
      found = true;
    };
    i = i + 1;
  };
  if !found {
    req.metadata.push((key.clone(), value.clone()));
  };
}

fn main() -> Int {
  var bad = 0;
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = req_new("svc", "m", payload, meta);
  metadata_set(&mut req, "grpc-timeout", "5s");
  io.println("len=" + int_to_string(req.metadata.len()));
  io.flush_stdout();
  if req.metadata.len() != 1 { bad = bad + 1; }
  io.println("bad=" + int_to_string(bad));
  io.flush_stdout();
  return bad;
}
