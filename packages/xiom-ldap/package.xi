// XIOM -- xiom.ldap package manifest
// Port task: greenfield pure-XIOM port (no FFI) of an LDAP (RFC 4511) BER codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder
// from it; the tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare, xiom.string.builder and xiom.encoding.hex.

package xiom_ldap {
  name: "xiom.ldap";
  version: "0.1.1";
  description: "LDAP (RFC 4511) BER message decoder plus a minimal BindRequest/SearchRequest encoder";
  categories: ["network"];
  keywords: ["ldap", "ber", "asn1", "wire", "codec", "directory"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ldap"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
