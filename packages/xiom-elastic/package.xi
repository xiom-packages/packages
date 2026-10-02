// XIOM -- xiom.elastic package manifest
// Port task: promote the xiom.elastic placeholder to a real, tested,
// pure-XIOM Elasticsearch client MODEL. Scope: the query DSL (match/term/
// terms/range/bool/exists/nested) with builder + deterministic serializer,
// request builders (search/index/scroll/bulk NDJSON framing), a response
// envelope parser over hand-rolled flat JSON scanning, a mapping model,
// index settings, and a bounded scroll/pagination state model. PURE -- no
// sockets, no HTTP, no transports (see SPEC.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_elastic {
  name: "xiom.elastic";
  version: "0.1.0";
  description: "Elasticsearch client model: query DSL, request builders, response envelope parsing, mapping/settings and scroll state (pure, no HTTP)";
  categories: ["data"];
  keywords: ["elasticsearch", "search", "query-dsl", "json", "rest"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.elastic"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
