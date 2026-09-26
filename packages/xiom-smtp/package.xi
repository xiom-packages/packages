// XIOM -- xiom.smtp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement the xiom.smtp package as a real, tested, pure-XIOM
// SMTP protocol codec (RFC 5321 grammar subset). xiom.std is the standard
// library: a platform dependency, excluded from the registry install closure.
// The library module imports xiom.string, xiom.string.builder and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_smtp {
  name: "xiom.smtp";
  version: "0.1.0";
  description: "SMTP protocol codec: RFC 5321 command lines and reply blocks, parse, build and canonical CRLF emit";
  categories: ["network"];
  keywords: ["smtp", "email", "protocol", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.smtp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
