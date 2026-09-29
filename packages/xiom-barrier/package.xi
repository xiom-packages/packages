// XIOM -- xiom.barrier package manifest
// Port task: promote the xiom.barrier placeholder to a real, tested,
// pure-XIOM package (reusable multiparty barrier as a deterministic state
// machine).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and xiom.string.

package xiom_barrier {
  name: "xiom.barrier";
  version: "0.1.0";
  description: "Reusable multiparty barrier as a deterministic state machine (generations, sense reversal, trip metadata)";
  categories: ["concurrency", "core"];
  keywords: ["barrier", "concurrency", "rendezvous", "generation", "sense-reversal"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.barrier"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
