// XIOM -- xiom.gps package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure. The module imports xiom.net.socket,
// xiom.serialize.json, xiom.string, xiom.string.compare,
// xiom.string.split, xiom.string.builder and xiom.convert.parse from it.

package xiom_gps {
  name: "xiom.gps";
  version: "0.1.0";
  description: "Pure-XIOM GPS/GNSS data path: gpsd JSON-protocol client (VERSION/WATCH/DEVICES/TPV/SKY/ERROR) and NMEA 0183 parsers (GGA/RMC/GSA/GSV)";
  categories: ["network"];
  keywords: ["gps", "gnss", "gpsd", "nmea", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gps"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
