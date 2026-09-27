// XIOM -- xiom.tor package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder
// from it; the tests additionally use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex.

package xiom_tor {
  name: "xiom.tor";
  version: "0.1.0";
  description: "Pure-XIOM Tor link-layer cell structure codec: fixed/variable cell framing, link and relay command tables, VERSIONS/NETINFO handshake bodies and typed RELAY payload decode (BEGIN, CONNECTED, END, SENDME, RESOLVE, RESOLVED) with byte-offset errors";
  categories: ["protocol"];
  keywords: ["tor", "onion", "anonymity", "cell", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tor"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
