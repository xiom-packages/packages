// XIOM -- xiom.dns package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder from it; the tests use xiom.test, xiom.io,
// xiom.string, xiom.string.builder and xiom.encoding.hex.

package xiom_dns {
  name: "xiom.dns";
  version: "0.1.0";
  description: "DNS message wire codec (RFC 1035 subset): header, names, questions and A/AAAA/CNAME/MX/TXT records";
  categories: ["network"];
  keywords: ["dns", "wire", "codec", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dns"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
