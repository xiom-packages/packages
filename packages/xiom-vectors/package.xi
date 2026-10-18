// XIOM -- xiom.vectors package manifest (MOTE artifact)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Source pin: xvector c858ec1 (frozen). The carved src/ tree is the embedded
// (mote) tier: in-process engine and HTTP handler, no lattice transport.
// api/router.xi, api/replica.xi and api/httpd.xi are LATTICE-ONLY and are
// intentionally absent (standing order).

package xiom_vectors {
  name: "xiom.vectors";
  version: "0.2.0";
  stage: "incubating";
  description: "XVECTOR MOTE -- embedded vector database engine: dense vectors, distance metrics, flat + HNSW ANN, collections, segments, payload filtering, WAL-backed durability and recovery; in-process only (no socket, no daemon)";
  categories: ["database", "systems"];
  keywords: ["vector", "embedding", "ann", "database", "engine"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.vectors", "xiom.vector.primitives", 
    "xiom.vector.engine",
    "xiom.vector.error",
    "xiom.vector.hnsw",
    "xiom.vector.ids",
    "xiom.vector.index",
    "xiom.vector.search",
    "xiom.vector.types",
    "xiom.vector.api.http_service",
    "xiom.vector.api.json_fast",
    "xiom.vector.api.vector_api",
    "xiom.vector.collection.collection",
    "xiom.vector.collection.schema",
    "xiom.vector.collection.validator",
    "xiom.vector.core.shim",
    "xiom.vector.distance.cosine",
    "xiom.vector.distance.dot",
    "xiom.vector.distance.l2",
    "xiom.vector.durability.manifest_file",
    "xiom.vector.durability.recovery",
    "xiom.vector.durability.snapshot",
    "xiom.vector.durability.wal",
    "xiom.vector.durability.wal_file",
    "xiom.vector.durability.wal_segment",
    "xiom.vector.durability.write_ahead_events",
    "xiom.vector.engine.core",
    "xiom.vector.index.ann_index",
    "xiom.vector.index.flat_index",
    "xiom.vector.index.hnsw",
    "xiom.vector.index.quantize",
    "xiom.vector.observability.metrics",
    "xiom.vector.payload.filter_ast",
    "xiom.vector.payload.filter_eval",
    "xiom.vector.payload.payload",
    "xiom.vector.query.filter_plan",
    "xiom.vector.query.pagination",
    "xiom.vector.query.search_request",
    "xiom.vector.query.search_service",
    "xiom.vector.segment.manifest",
    "xiom.vector.segment.segment",
    "xiom.vector.segment.segment_file",
    "xiom.vector.segment.segment_state",
    "xiom.vector.storage.id_map",
    "xiom.vector.storage.vector_store"
  ];
  deps: {
    "xiom.wal": "0.1.0",
    "xiom.metrics": "0.2.0",
    "xiom.rate": "0.2.0", "xiom.http": "0.1.9",
    "xiom.std": ">=0.60.0 <1.0.0"
  };
}
