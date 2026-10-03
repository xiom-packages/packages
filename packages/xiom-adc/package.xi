// XIOM -- xiom.adc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert
// (int_to_string); the tests use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_adc {
  name: "xiom.adc";
  version: "0.1.1";
  description: "ADC codecs: integer conversion scaling, channel/gain/reference selection, sample-rate tables and ADS1x15 config registers";
  categories: ["science", "systems"];
  keywords: ["adc", "analog", "conversion", "ads1115", "ads1015", "mux", "pga", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.adc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
