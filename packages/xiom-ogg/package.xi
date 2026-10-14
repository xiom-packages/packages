// XIOM -- xiom.ogg package manifest
// 0.2.0: adds the vendored libogg v1.3.6 packet-reassembly/write layer
// (sync/stream pageout/packetin + paging write) next to the unchanged
// pure-XIOM page layer.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The pure library module imports nothing from it;
// xiom.ogg.ffi / xiom.ogg.mux use only package modules; the tests use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_ogg {
  name: "xiom.ogg";
  version: "0.2.0";
  description: "Ogg container: pure-XIOM page walk + CRC-32, and the vendored libogg v1.3.6 packet-reassembly/write layer (sync/stream pageout/packetin, mux/demux)";
  categories: ["data","media"];
  keywords: ["ogg","page","crc32","container","packet","mux","demux","binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ogg", "xiom.ogg.abi", "xiom.ogg.ffi", "xiom.ogg.mux", "xiom.ogg.types"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
