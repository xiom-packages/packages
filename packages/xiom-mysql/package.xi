// XIOM -- xiom.mysql package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_mysql {
  name: "xiom.mysql";
  version: "0.1.2";
  description: "MySQL client/server wire protocol structure codec (packet framing, handshake v10, handshake response 41, length-encoded values, OK/ERR/EOF, result sets; no sockets, no auth crypto)";
  categories: ["network"];
  keywords: ["mysql", "mariadb", "wire", "binary", "codec", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mysql"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
