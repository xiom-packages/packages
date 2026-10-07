// XIOM -- xiom.static package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.convert, xiom.convert.percent, xiom.io, xiom.io.fs, xiom.net.mime and
// xiom.time from it; the tests additionally use xiom.test, xiom.io,
// xiom.io.fs and xiom.string.compare.

package xiom_static {
  name: "xiom.static";
  version: "0.1.0";
  description: "Static-file response planning: MIME typing, stat/sha256 ETags, RFC 1123 dates, Cache-Control, single byte ranges, lexical traversal guard";
  categories: ["web", "network"];
  keywords: ["static", "mime", "etag", "range", "cache-control"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.static"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
