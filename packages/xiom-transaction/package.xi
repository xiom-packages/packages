// XIOM -- xiom.transaction package manifest
// Port task: replace the xiom.transaction placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports only the stdlib Str
// comparison helper; the tests use xiom.test and xiom.io from it.

package xiom_transaction {
  name: "xiom.transaction";
  version: "0.1.0";
  description: "Transaction lifecycle state machine with named savepoints";
  categories: ["core","data"];
  keywords: ["transaction","savepoint","state","database"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.transaction"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
