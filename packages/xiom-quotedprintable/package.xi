// XIOM -- xiom.quotedprintable package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test,
// xiom.io and xiom.string.compare.

package xiom_quotedprintable {
  name: "xiom.quotedprintable";
  version: "0.1.0";
  description: "RFC 2045 quoted-printable codec for bytes and text";
  categories: ["data"];
  keywords: ["quoted-printable", "mime", "encoding", "email"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.quotedprintable"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
