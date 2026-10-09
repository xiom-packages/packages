// XIOM -- xiom.upnp package manifest
// Port task: greenfield pure-XIOM port (no FFI) of an SSDP/UPnP discovery codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert.int; the tests use xiom.test and
// xiom.io from it as well.

package xiom_upnp {
  name: "xiom.upnp";
  version: "0.1.2";
  description: "SSDP/UPnP discovery message codec: M-SEARCH, NOTIFY and search responses";
  categories: ["network"];
  keywords: ["upnp", "ssdp", "discovery", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.upnp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
