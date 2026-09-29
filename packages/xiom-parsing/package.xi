// XIOM -- xiom.parsing package manifest
// Port task: promote the xiom.parsing placeholder to a real, tested,
// pure-XIOM package: a spanned parser-combinator framework over a Str input
// (arena-defined literal/class/seq/alt/many/many1/optional/capture/EOF
// combinators, index-range results, structured line/column errors with
// expected sets, documented backtracking).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_parsing {
  name: "xiom.parsing";
  version: "0.1.0";
  description: "Spanned parser-combinator framework: literal/class/seq/alt/many/optional/capture combinators, index ranges, structured errors";
  categories: ["text", "tooling"];
  keywords: ["parser", "combinator", "grammar", "parsing", "peg"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.parsing"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
