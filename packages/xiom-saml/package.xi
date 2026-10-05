// XIOM -- xiom.saml package manifest
// Port task: greenfield pure-XIOM port (no FFI, no networking) of a SAML 2.0
// assertion/response structure toolkit: minimal XML subset reader, base64,
// AuthnRequest builder, IdP metadata and XML-DSig structural parsing.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests use
// xiom.test and xiom.io in addition.

package xiom_saml {
  name: "xiom.saml";
  version: "0.1.1";
  description: "SAML 2.0 structure toolkit: XML subset reader, assertion/response parsing, AuthnRequest builder, IdP metadata, base64 and XML-DSig structural parsing (no networking, no public-key verification)";
  categories: ["crypto-security"];
  keywords: ["saml", "sso", "assertion", "xml", "signature", "metadata"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.saml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
