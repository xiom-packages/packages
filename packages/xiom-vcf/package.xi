// XIOM -- xiom.vcf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// RFC 6350-subset vCard text codec: content lines with optional groups and
// parameters, CRLF folding/unfolding, value escaping, BEGIN/END card
// envelopes (VERSION 3.0 or 4.0), multi-card streams, and card building.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_vcf {
  name: "xiom.vcf";
  version: "0.1.0";
  description: "RFC 6350-subset vCard text codec: content lines, folding, escaping, cards and streams";
  categories: ["data"];
  keywords: ["vcf", "vcard", "contacts", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.vcf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
