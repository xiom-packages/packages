// XIOM -- xiom.eml package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// RFC 5322/MIME message structure: unfolded headers, body split, and
// multipart boundaries. xiom.std is the standard library: a platform
// dependency, excluded from the registry install closure. The module itself
// imports xiom.string, xiom.string.builder and xiom.string.compare from it;
// the tests additionally use xiom.test and xiom.io.

package xiom_eml {
  name: "xiom.eml";
  version: "0.1.0";
  description: "RFC 5322/MIME message structure: unfolded headers, body split, and multipart boundaries";
  categories: ["data", "text"];
  keywords: ["email", "mime", "rfc5322", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.eml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
