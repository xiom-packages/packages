// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.hnsw

// DEPRECATED / SUPERSEDED -- safe to delete.
//
// The full HNSW implementation (HNSWGraph, HNSWLayer, HNSWNode, hnsw_new,
// hnsw_insert, hnsw_search, hnsw_layer_count, hnsw_node_count) was migrated to
// src/index/hnsw.xi (module xiom.vector.index.hnsw), with results expressed as
// `Neighbor` instead of `SearchResult`. Remove this file once no build target
// references `module xiom.vector.hnsw`.
