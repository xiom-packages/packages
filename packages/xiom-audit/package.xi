// XIOM -- xiom.audit package manifest
// Port task: promote the xiom.audit placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_audit {
  name: "xiom.audit";
  version: "0.1.0";
  description: "Hash-chained append-only audit log with verification and export";
  categories: ["data","safety"];
  keywords: ["audit","hash-chain","tamper-evident","log"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.audit"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
