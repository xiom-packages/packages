// XIOM -- xiom.mime package manifest
// Port task: create the xiom.mime package as a real, tested, pure-XIOM module
// (no FFI, no IANA registry at runtime).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte_at,
// str_slice and the string builder); the tests additionally use xiom.test,
// xiom.io and xiom.string.compare.

package xiom_mime {
  name: "xiom.mime";
  version: "0.1.0";
  description: "Media type helpers: extension mapping, normalization, and class checks";
  categories: ["data", "networking"];
  keywords: ["mime", "media-type", "extension", "http"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mime"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
