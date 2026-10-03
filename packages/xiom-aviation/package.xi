// XIOM -- xiom.aviation package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_aviation {
  name: "xiom.aviation";
  version: "0.1.2";
  description: "Mode S / ADS-B extended squitter frame codec: bit-oriented frame intake, ME type-code decoding and CPR position helpers";
  categories: ["network", "science"];
  keywords: ["ads-b", "mode-s", "aviation", "transponder", "cpr"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.aviation"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
