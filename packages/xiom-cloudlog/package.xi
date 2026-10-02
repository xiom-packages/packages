// XIOM -- xiom.cloudlog package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_cloudlog {
  name: "xiom.cloudlog";
  version: "0.1.0";
  description: "Cloud log pipeline model: ingest batching, structured formats, tail consumers, retention store, search";
  categories: ["data"];
  keywords: ["cloud", "logs", "ingest", "batching", "retention", "search", "tail", "observability"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cloudlog"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
