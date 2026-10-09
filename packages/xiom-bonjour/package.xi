// XIOM -- xiom.bonjour package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.string.split from it;
// the tests use xiom.test, xiom.io, xiom.string.builder, xiom.string.compare
// and xiom.encoding.hex.

package xiom_bonjour {
  name: "xiom.bonjour";
  version: "0.1.2";
  description: "Bonjour (mDNS/DNS-SD) message codec: DNS framing, name compression, PTR/SRV/TXT/A/AAAA records and DNS-SD builders";
  categories: ["network"];
  keywords: ["bonjour", "mdns", "dns-sd", "zeroconf", "multicast-dns"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bonjour"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
