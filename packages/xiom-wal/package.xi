// XIOM -- xiom.wal package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.io,
// xiom.convert, xiom.convert.parse, xiom.string, xiom.string.split and
// xiom.string.trim only; the tests additionally use xiom.test and xiom.io.fs.

package xiom_wal {
  name: "xiom.wal";
  version: "0.1.0";
  description: "Standalone write-ahead log: durable record shape + crash-proven disk segment (lsn|op|key|value|timestamp[|payload]) with torn-tail healing, replay, temp+rename truncate and in-memory LSN/checkpoint/recovery vocabulary";
  categories: ["database", "systems"];
  keywords: ["wal", "durability", "storage", "crash-recovery"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.wal"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
