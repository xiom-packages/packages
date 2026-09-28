// XIOM -- xiom.mssql package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test,
// xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_mssql {
  name: "xiom.mssql";
  version: "0.1.1";
  description: "Microsoft SQL Server TDS (Tabular Data Stream) structure codec: packet headers, PRELOGIN option table, LOGIN7 fixed layout, and RESPONSE token streams (LOGINACK/ERROR/ENVCHANGE/DONE/COLMETADATA/ROW/NBCROW/RETURNVALUE); no sockets, no login crypto";
  categories: ["network"];
  keywords: ["mssql", "sqlserver", "tds", "wire", "binary", "codec", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mssql"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
