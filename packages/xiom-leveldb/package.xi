// XIOM -- xiom.leveldb package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports xiom.string.builder and xiom.convert
// from it; the tests add xiom.test, xiom.io and xiom.string.compare.

package xiom_leveldb {
  name: "xiom.leveldb";
  version: "0.1.1";
  description: "LevelDB storage-format parser: log records, block/index/footer structure and LEB128 varints (no filesystem, no compression)";
  categories: ["data"];
  keywords: ["leveldb", "log", "sstable", "block", "crc32c", "varint", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.leveldb"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
