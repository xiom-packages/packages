// XIOM -- xiom.badger package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert.int (for
// decimal offsets in error messages), xiom.string (literal scanning and hex
// text) and xiom.hash.siphash (upstream bbloom membership); the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_badger {
  name: "xiom.badger";
  version: "0.1.1";
  description: "Pure-XIOM BadgerDB v1.6.2 file-format structure parser: value-log entries, key versions, SST blocks/index/bloom and manifest records (parse-only)";
  categories: ["data"];
  keywords: ["badger", "vlog", "sstable", "manifest", "crc32c", "bloom", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.badger"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
