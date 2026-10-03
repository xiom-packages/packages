// XIOM -- xiom.rocksdb package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports xiom.string.compare from it; the
// tests add xiom.test, xiom.io, xiom.string and xiom.convert.

package xiom_rocksdb {
  name: "xiom.rocksdb";
  version: "0.1.0";
  description: "Pure-XIOM LSM storage-engine model: memtable, WAL, SST blocks/index/Bloom shape, level structure, compaction scheduling, snapshots, column families and statistics (no FFI, no disk I/O)";
  categories: ["database"];
  keywords: ["rocksdb", "lsm", "memtable", "wal", "sstable", "compaction", "bloom", "snapshot", "column-family"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rocksdb"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
