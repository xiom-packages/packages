// XIOM -- xiom.formatter-fw package manifest
// Port task: promote the xiom.formatter-fw placeholder to a real, tested,
// pure-XIOM package (a Wadler/Leijen-style pretty-printing framework over an
// explicit document model: text/line/softline/hardline/concat/nest/group/
// align nodes, greedy group fitting against an integer width, indentation
// tracking and a deterministic renderer).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte_at) from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_formatter_fw {
  name: "xiom.formatter-fw";
  version: "0.1.1";
  description: "Wadler/Leijen-style pretty-printing framework: explicit document model (text/line/softline/hardline/concat/nest/group/align), greedy width fitting, deterministic renderer";
  categories: ["text-nlp", "tooling"];
  keywords: ["formatter", "pretty-printer", "layout", "document", "wadler"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.formatter_fw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
