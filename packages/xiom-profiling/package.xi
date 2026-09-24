// XIOM -- xiom.profiling package manifest
// Port task: promote the xiom.profiling placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io. No FFI: folded text in, aggregation out.

package xiom_profiling {
  name: "xiom.profiling";
  version: "0.1.0";
  description: "Folded-stack sampling profile analysis: parse, aggregate leaves, top stacks";
  categories: ["tooling"];
  keywords: ["profiling","flamegraph","sampling","stacks"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.profiling"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
