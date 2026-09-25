// XIOM -- xiom.irc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement the xiom.irc package as a real, tested, pure-XIOM
// IRC message codec (RFC 1459/2812 subset plus IRCv3 message tags).
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test, xiom.io and xiom.string.compare.

package xiom_irc {
  name: "xiom.irc";
  version: "0.1.0";
  description: "IRC message codec: RFC 1459/2812 subset plus IRCv3 tags, parse and build with round-trips";
  categories: ["protocol"];
  keywords: ["irc", "chat", "protocol", "message"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.irc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
