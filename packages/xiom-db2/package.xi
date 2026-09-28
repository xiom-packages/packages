// XIOM -- xiom.db2 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_db2 {
  name: "xiom.db2";
  version: "0.1.1";
  description: "IBM Db2 DRDA/DSS wire structure codec (DSS frames, DDM codepoints and parameters, SQLCARD, SQLDTA; no network, no EBCDIC conversion)";
  categories: ["database"];
  keywords: ["db2", "drda", "dss", "ddm", "wire", "codec", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.db2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
