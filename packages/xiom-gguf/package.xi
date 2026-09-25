// XIOM -- xiom.gguf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_gguf {
  name: "xiom.gguf";
  version: "0.1.0";
  description: "GGUF container header codec: metadata KV, tensor infos, alignment and builder";
  categories: ["ai-ml"];
  keywords: ["gguf", "llm", "format", "container"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gguf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
