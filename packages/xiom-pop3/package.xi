// XIOM -- xiom.pop3 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// POP3 protocol codec (RFC 1939): command and response parsing/building,
// byte-stuffed multi-line payloads, and flat LIST/UIDL pair columns.
// xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_pop3 {
  name: "xiom.pop3";
  version: "0.1.0";
  description: "POP3 protocol codec (RFC 1939): commands, responses, dot-stuffing, flat listing pairs";
  categories: ["network"];
  keywords: ["pop3", "email", "protocol", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pop3"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
