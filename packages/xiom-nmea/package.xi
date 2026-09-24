// XIOM -- xiom.nmea package manifest
// Port task: populate the xiom.nmea package with a real, tested, pure-XIOM
// NMEA 0183 sentence parser (checksum, fields, coordinates, GGA/RMC).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.math from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_nmea {
  name: "xiom.nmea";
  version: "0.1.0";
  description: "NMEA 0183 sentence parsing: checksum, fields, coordinates, and GGA/RMC accessors";
  categories: ["networking", "science"];
  keywords: ["nmea", "gps", "serial", "sentences"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nmea"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
