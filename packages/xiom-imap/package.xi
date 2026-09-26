// XIOM -- xiom.imap package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement the xiom.imap package as a real, tested, pure-XIOM
// IMAP4rev1 (RFC 3501) protocol parser: command lines (tags, atoms, quoted
// strings, literals, nested parenthesized lists, NIL), server responses
// (tagged completions, untagged responses, continuations, response text
// codes), and a buffer-consuming parse entry point that reports the bytes
// consumed. No sockets, no TLS, no session state machine.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_imap {
  name: "xiom.imap";
  version: "0.1.0";
  description: "IMAP4rev1 protocol parser (RFC 3501): commands, responses, literals, nested lists, response codes";
  categories: ["network"];
  keywords: ["imap", "email", "protocol", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.imap"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
