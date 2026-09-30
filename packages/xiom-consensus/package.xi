// XIOM -- xiom.consensus package manifest
// Port task: promote the xiom.consensus placeholder to a real, tested,
// pure-XIOM package (deterministic caller-driven Raft-style consensus model).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert.int from it (for
// int_to_base); the tests additionally use xiom.test, xiom.io, xiom.string
// and xiom.string.compare.

package xiom_consensus {
  name: "xiom.consensus";
  version: "0.1.0";
  description: "Deterministic caller-driven Raft-style consensus model: terms, explicit-vote elections with quorum math, log replication with match/next/commit indices, role transitions, message records, invariants and traces";
  categories: ["systems"];
  keywords: ["consensus", "raft", "election", "quorum", "replication", "commit", "invariants"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.consensus"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
