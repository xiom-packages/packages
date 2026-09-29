// XIOM -- xiom.stm package manifest
// Port task: replace the xiom.stm placeholder with a real, tested, pure-XIOM
// package (deterministic software-transactional-memory primitives: versioned
// cells, transaction read/write sets, optimistic commit with version
// validation, conflict aborts with reason codes and retry bookkeeping).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert (and
// xiom.convert.int for int_to_base); the tests additionally use xiom.test,
// xiom.io, xiom.string and xiom.string.compare.

package xiom_stm {
  name: "xiom.stm";
  version: "0.1.0";
  description: "Deterministic single-threaded software-transactional-memory primitives: versioned cells, optimistic transactions with read/write sets, commit validation, conflict aborts and retry bookkeeping";
  categories: ["concurrency", "data"];
  keywords: ["stm", "transactional-memory", "transaction", "tvar", "optimistic", "conflict", "versioning", "atomicity"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
