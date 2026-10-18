#!/usr/bin/env bash
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Pre-release verification battery (WSL/Linux): conformance suite x2 plus
# every probe x2, using the standard scripts. Exit 0 only when all gates are
# green. Windows twin: scripts/ci.ps1.

set -u
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/dev-env.sh

probes=(
  probe_hello
  probe_bind_semantics
  probe_engine_import
  probe_vector_store
  probe_filtered_search
  probe_payload_recovery
  probe_floatval_roundtrip
  probe_search_request
  probe_payload_index
  probe_filter_plan
  probe_hnsw_recall
  probe_engine_hnsw
  probe_hnsw_codec
  probe_result_shapes
  probe_fuzz_codecs
  probe_soak_mixed
  probe_kill_recovery
  probe_wal_file
  probe_manifest_file
  probe_collections
  probe_segment_file
  probe_range_search
  probe_pagination
  probe_delete_filter
  probe_index_admin
  probe_memory_estimate
  probe_reference_oracle
  probe_http_service
  probe_service_limits
  probe_service_auth
  probe_http_fuzz
probe_metrics
probe_package_wal
probe_package_metrics
probe_package_rate
probe_package_http
probe_package_vectors
probe_package_orbitdb
probe_package_pulse
probe_http_server
probe_json_fast
probe_quantization
probe_wal_segment
probe_snapshot
probe_multisegment
probe_batch_ops
probe_thread_sync
probe_mote_embedded
probe_collection_move
probe_router_2shards
probe_move_under_load
probe_replica
probe_reopen_write
)

failures=0

echo "ci: suite x2"
if ! bash scripts/run-suite.sh 2 240; then
  failures=$((failures + 1))
  echo "ci: SUITE FAILED"
fi

echo "ci: sbom + unsafe gate"
if ! bash scripts/sbom.sh; then
  failures=$((failures + 1))
  echo "ci: SBOM FAILED"
fi

for p in "${probes[@]}"; do
  echo "ci: $p x2"
  if ! bash scripts/run-probe.sh "tests/probes/$p.xi" 2 > "out/ci_$p.log" 2>&1; then
    failures=$((failures + 1))
    echo "ci: PROBE FAILED: $p (see out/ci_$p.log)"
  fi
done

echo "ci: bench smoke (quick)"
if ! bash scripts/bench.sh quick > "out/ci_bench_smoke.log" 2>&1; then
  failures=$((failures + 1))
  echo "ci: BENCH FAILED (see out/ci_bench_smoke.log)"
fi

echo "ci: kill matrix (durability delta, 4 iterations)"
if ! bash scripts/kill_matrix.sh 4 > "out/ci_kill_matrix.log" 2>&1; then
  failures=$((failures + 1))
  echo "ci: KILL MATRIX FAILED (see out/ci_kill_matrix.log)"
fi

if [ "$failures" -ne 0 ]; then
  echo "ci: FAILED ($failures gate(s) red)"
  exit 1
fi
echo "ci: ALL GATES GREEN (suite x2 + sbom + ${#probes[@]} probes x2 + bench smoke + kill matrix)"
exit 0
