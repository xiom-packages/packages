// XIOM -- xiom.llm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.compare from it and consumes xiom.gguf (GGUF header codec) as
// its container dependency; the tests additionally use xiom.test, xiom.io and
// xiom.gguf's builder to construct a synthetic deterministic fixture.
//
// This manifest is the lane manifest (packaging, namespace checks, registry).
// The companion xiom.toml carries the same dependency list for the v0.64.x
// dependency-root resolver (path deps): the legacy package.xi `deps:` block
// is not consumed for catalog source roots. Keep the two in sync.

package xiom_llm {
  name: "xiom.llm";
  version: "0.1.0";
  description: "llama.cpp-family runner tier: GGUF payload/vocab loading, byte-level BPE tokenizer and (planned) deterministic float-free dequant, matmul, forward pass and generation loop";
  categories: ["ai-ml"];
  keywords: ["llm", "gguf", "inference", "bpe", "tokenizer", "llama", "quantization"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.llm"];
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0";
    "xiom.gguf": "0.1.4";
    "xiom.tensor": "0.1.0";
  };
}
