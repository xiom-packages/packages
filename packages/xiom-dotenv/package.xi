// XIOM -- xiom.dotenv package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// dotenv (.env) parsing and emitting with quoting and comment rules.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_dotenv {
  name: "xiom.dotenv";
  version: "0.1.0";
  description: "dotenv (.env) parsing and emitting with quoting and comment rules";
  categories: ["data", "tooling"];
  keywords: ["dotenv", "config", "env", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dotenv"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
