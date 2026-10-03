// XIOM -- xiom.legacy-proto package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement xiom.legacy-proto as a real, tested, pure-XIOM codec
// for legacy internet text protocols: Finger queries/responses (RFC 1288),
// Gopher menu documents (RFC 1436) and WHOIS response records (RFC 3912).
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_legacy_proto {
  name: "xiom.legacy-proto";
  version: "0.1.1";
  description: "Finger, Gopher and WHOIS text-protocol codecs: parse, canonical render and deterministic error catalogs";
  categories: ["network"];
  keywords: ["finger", "gopher", "whois", "legacy", "text-protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.legacy_proto"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
