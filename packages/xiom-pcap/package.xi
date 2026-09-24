// XIOM -- xiom.pcap package manifest
// Port task: greenfield pure-XIOM port (no FFI) of a classic PCAP reader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_pcap {
  name: "xiom.pcap";
  version: "0.1.0";
  description: "Classic PCAP capture file structure: magic/endianness, global header, and packet records";
  categories: ["data","networking"];
  keywords: ["pcap","capture","packets","binary"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pcap"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
