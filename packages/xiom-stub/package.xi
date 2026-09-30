// XIOM -- xiom.stub package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string.compare and
// xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_stub {
  name: "xiom.stub";
  version: "0.1.0";
  description: "Ordered programmable test stubs: canned returns, failure actions, cardinality and structured violation reports";
  categories: ["testing"];
  keywords: ["stub", "test", "double", "test-double", "ordered", "verification"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stub"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
