// XIOM -- xiom.parquet package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_parquet {
  name: "xiom.parquet";
  version: "0.1.2";
  description: "Apache Parquet file metadata codec: thrift compact-protocol footer, schema tree, row groups, statistics and page headers";
  categories: ["data"];
  keywords: ["parquet", "apache", "format", "metadata", "columnar", "thrift"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.parquet"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
