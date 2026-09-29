// XIOM -- xiom.pki package manifest
// Port task: greenfield pure-XIOM port (no FFI) of an X.509/PKIX certificate
// structure parser (DER X.690 TLV walker + ASN.1 primitives + PEM unwrap).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests use
// xiom.test and xiom.io in addition.

package xiom_pki {
  name: "xiom.pki";
  version: "0.1.2";
  description: "X.509/PKIX certificate structure parser: DER TLV walker, ASN.1 primitives, TBS/extension decoding and PEM unwrap (no crypto verification)";
  categories: ["security"];
  keywords: ["x509", "pki", "asn1", "der", "certificate", "pem"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pki"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
