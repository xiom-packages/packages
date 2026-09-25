// XIOM -- xiom.ulid package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string and xiom.string.builder from it;
// the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_ulid {
  name: "xiom.ulid";
  version: "0.1.0";
  description: "ULID codec: Crockford base32 encode/decode with caller-supplied timestamp and randomness";
  categories: ["data"];
  keywords: ["ulid", "identifier", "crockford", "sortable"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ulid"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
