// XIOM -- xiom.rtc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert and
// xiom.string.compare from it; the tests use xiom.test, xiom.io,
// xiom.string.compare, xiom.convert and xiom.encoding.hex.

package xiom_rtc {
  name: "xiom.rtc";
  version: "0.1.2";
  description: "Real-time clock register codecs: BCD fields, DS1307 and PCF8563 layouts, civil-date arithmetic";
  categories: ["systems"];
  keywords: ["rtc", "ds1307", "pcf8563", "i2c", "bcd", "clock", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rtc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
