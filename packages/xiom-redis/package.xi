// XIOM -- xiom.redis package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM Redis RESP2 client. No FFI, no bridge C, no hiredis: the
// transport is the stdlib TCP socket (xiom.net.socket) and the wire codec
// is implemented from the RESP2 specification. xiom.std is the standard
// library: a platform dependency, excluded from the registry install
// closure. Modules: xiom.redis (public surface), xiom.redis.client
// (transport/session), xiom.redis.verbs (typed verb wrappers),
// xiom.redis.resp (codec) and xiom.redis.value (value model/accessors).

package xiom_redis {
  name: "xiom.redis";
  version: "0.1.0";
  description: "Pure-XIOM Redis RESP2 client and protocol codec (TCP socket transport; no FFI, no hiredis)";
  categories: ["database"];
  keywords: ["redis", "resp", "cache", "key-value", "protocol", "client"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.redis", "xiom.redis.value", "xiom.redis.resp", "xiom.redis.client", "xiom.redis.verbs"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
