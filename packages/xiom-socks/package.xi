// XIOM -- xiom.socks package manifest
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.socks placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string only for
// the socks5_domain_bytes convenience; the tests use xiom.test, xiom.io and
// xiom.string.compare from it.

package xiom_socks {
  name: "xiom.socks";
  version: "0.1.0";
  description: "SOCKS5 wire codec (RFC 1928 greeting/method/CONNECT request/reply and RFC 1929 username-password auth)";
  categories: ["network"];
  keywords: ["socks", "proxy", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.socks"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
