// XIOM -- xiom.pcapng package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_pcapng {
  name: "xiom.pcapng";
  version: "0.1.0";
  description: "PCAP Next Generation (pcapng) capture-file block index, options and packet spans";
  categories: ["network"];
  keywords: ["pcapng", "capture", "network", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pcapng"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
