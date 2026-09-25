// XIOM -- xiom.nbt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_nbt {
  name: "xiom.nbt";
  version: "0.1.0";
  description: "Minecraft NBT (Named Binary Tag) encoding and decoding for the XIOM ecosystem";
  categories: ["data"];
  keywords: ["nbt", "minecraft", "binary", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nbt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
