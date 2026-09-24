// XIOM -- xiom.rpc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// JSON-RPC 2.0 envelope codec: builds compact request/notification/response/
// error envelopes from raw JSON text and scans those envelopes back with a
// minimal byte-wise scanner. No JSON parser, no validation of caller-supplied
// params/result/data text, no transports, no batch arrays.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module imports
// xiom.string and xiom.convert from it; the tests add xiom.io, xiom.test and
// xiom.string.compare.

package xiom_rpc {
  name: "xiom.rpc";
  version: "0.1.0";
  description: "JSON-RPC 2.0 envelope codec with a minimal response scanner (no JSON parser)";
  categories: ["networking", "data"];
  keywords: ["jsonrpc", "rpc", "envelope", "remote"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rpc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
