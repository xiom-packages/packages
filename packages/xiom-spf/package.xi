// XIOM -- xiom.spf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_spf {
  name: "xiom.spf";
  version: "0.1.0";
  description: "SPF record parser (RFC 7208 syntax subset) with flat term storage and canonical emitter";
  categories: ["network"];
  keywords: ["spf", "email", "dns", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.spf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
