// XIOM -- xiom.ssh2 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert.int
// (error offset formatting), xiom.string (byte literals) and
// xiom.string.compare (Str equality); the tests additionally use xiom.test,
// xiom.io and xiom.encoding.hex.

package xiom_ssh2 {
  name: "xiom.ssh2";
  version: "0.1.1";
  description: "Pure-XIOM SSH-2 transport, authentication and connection-layer message structure codec (RFC 4251/4253/4252/4254; no crypto)";
  categories: ["protocol"];
  keywords: ["ssh", "ssh2", "transport", "auth", "channel", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ssh2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
