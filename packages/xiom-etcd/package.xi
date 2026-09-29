// XIOM -- xiom.etcd package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_etcd {
  name: "xiom.etcd";
  version: "0.1.2";
  description: "Pure-XIOM etcd v3 gRPC message-structure codec: protobuf-wire subset and the decoded rpc.proto message subset over gRPC frames (no network, no server)";
  categories: ["protocol"];
  keywords: ["etcd", "grpc", "protobuf", "wire", "codec", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.etcd"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
