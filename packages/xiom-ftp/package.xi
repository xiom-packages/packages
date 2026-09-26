// XIOM -- xiom.ftp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_ftp {
  name: "xiom.ftp";
  version: "0.1.0";
  description: "Pure-XIOM FTP control-protocol codec (RFC 959): command parsing/emission and reply parsing/emission";
  categories: ["network"];
  keywords: ["ftp", "protocol", "parser", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ftp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
