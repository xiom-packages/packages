// XIOM -- xiom.option package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_option {
  name: "xiom.option";
  version: "0.1.0";
  description: "Combinators for Option and Result values: map, flat_map, filter, unwrap, conversions";
  categories: ["core"];
  keywords: ["option", "result", "combinators", "functional"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.option"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
