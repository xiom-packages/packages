// XIOM -- xiom.proxy package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.encoding.hex.

package xiom_proxy {
  name: "xiom.proxy";
  version: "0.1.0";
  description: "Pure-XIOM HAProxy PROXY protocol structure codec: v1 text lines and v2 binary headers with TLV parsing (ALPN, authority, CRC32C, NOOP, SSL, unique id, AWS VPC), address parse/render and byte-offset errors -- no sockets";
  categories: ["protocol"];
  keywords: ["proxy-protocol", "haproxy", "load-balancer", "codec", "tlv"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.proxy"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
