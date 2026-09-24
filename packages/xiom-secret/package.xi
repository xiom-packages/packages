// XIOM -- xiom.secret package manifest
// Port task: promote the xiom.secret placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_secret {
  name: "xiom.secret";
  version: "0.1.0";
  description: "Secret redaction for logs and text: emails, tokens, keys, and card-like digits";
  categories: ["text", "safety"];
  keywords: ["redact", "secrets", "security", "masking"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.secret"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
