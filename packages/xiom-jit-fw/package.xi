// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.jit-fw package manifest
// Port task: promote the xiom-jit-fw placeholder to a real, tested,
// pure-XIOM package (a deterministic JIT-framework model: source hashing and
// artifact keys, symbolic IR lowering, a bounded dispatch interpreter with
// call frames, a bounded LRU artifact cache, closure/trampoline adapters and
// a per-site monitor with a deterministic tiering policy).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte_at) and
// xiom.convert (int_to_string); the tests additionally use xiom.test and
// xiom.io.

package xiom_jit_fw {
  name: "xiom.jit-fw";
  version: "0.1.0";
  description: "JIT-framework model: source hashing and artifact keys, IR lowering to an instruction stream, bounded dispatch interpreter with call frames, bounded LRU artifact cache, closure/trampoline adapters, per-site monitor and deterministic tiering policy";
  categories: ["compiler"];
  keywords: ["jit", "compiler", "interpreter", "cache", "tiering", "trampoline", "framework"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.jit_fw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
