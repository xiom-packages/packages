// XIOM -- xiom.punycode package manifest
// Port task: add a real, tested, pure-XIOM RFC 3492 Punycode package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare. No external tables, no FFI.

package xiom_punycode {
  name: "xiom.punycode";
  version: "0.1.0";
  description: "RFC 3492 Punycode for IDN labels: xn-- encode/decode without external tables";
  categories: ["text","networking"];
  keywords: ["punycode","idn","unicode","domain"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.punycode"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
