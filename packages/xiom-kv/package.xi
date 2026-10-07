// XIOM -- xiom.kv package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.io, xiom.io.fs,
// xiom.hash.crc, xiom.serialize.endian, xiom.collect.stringmap, xiom.string
// and xiom.convert.int only; the tests additionally use xiom.test.

package xiom_kv {
  name: "xiom.kv";
  version: "0.1.0";
  description: "Pure-XIOM embedded log-structured key-value store: 28-byte segment headers, CRC32C-framed records, tombstones, crash-safe reopen with torn-tail repair, atomic-rename compaction and optional snapshots";
  categories: ["data", "storage"];
  keywords: ["kv", "storage", "log-structured", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.kv"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
