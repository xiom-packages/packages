// XIOM -- xiom.gif package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.convert for
// offset-carrying error messages; the conformance suite also uses
// xiom.test/xiom.io/xiom.string from it.

package xiom_gif {
  name: "xiom.gif";
  version: "0.1.0";
  description: "GIF87a/GIF89a structure parser: canvas, color tables, frame metadata, extensions, byte offsets";
  categories: ["graphics"];
  keywords: ["gif", "image", "animation", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gif"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
