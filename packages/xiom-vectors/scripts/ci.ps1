# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Pre-release verification battery (Windows): conformance suite x2 plus
# every probe x2, using the standard scripts. Exit 0 only when all gates
# are green. WSL twin: scripts/ci.sh.

param(
  [int]$SuiteRuns = 2,
  [int]$ProbeRuns = 2
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
. "$PSScriptRoot/dev-env.ps1"

$probes = @(
  "probe_hello",
  "probe_bind_semantics",
  "probe_engine_import",
  "probe_vector_store",
  "probe_filtered_search",
  "probe_payload_recovery",
  "probe_floatval_roundtrip",
  "probe_search_request",
  "probe_payload_index",
  "probe_filter_plan",
  "probe_hnsw_recall",
  "probe_engine_hnsw",
  "probe_hnsw_codec",
  "probe_result_shapes",
  "probe_fuzz_codecs",
  "probe_soak_mixed",
  "probe_kill_recovery",
  "probe_wal_file",
  "probe_manifest_file",
  "probe_collections",
  "probe_segment_file",
  "probe_range_search",
  "probe_pagination",
  "probe_delete_filter",
  "probe_index_admin",
  "probe_memory_estimate",
  "probe_reference_oracle",
  "probe_http_service",
  "probe_service_limits",
  "probe_service_auth",
  "probe_http_fuzz",
  "probe_metrics",
  "probe_package_wal",
  "probe_package_metrics",
  "probe_package_rate",
  "probe_package_http",
  "probe_package_vectors",
  "probe_package_orbitdb",
  "probe_package_pulse",
  "probe_http_server",
  "probe_json_fast",
  "probe_quantization",
  "probe_wal_segment",
  "probe_snapshot",
  "probe_multisegment",
  "probe_batch_ops",
  "probe_thread_sync",
  "probe_mote_embedded",
  "probe_collection_move",
  "probe_router_2shards",
  "probe_move_under_load",
  "probe_replica",
  "probe_reopen_write"
)

$failures = 0

Write-Host "ci: suite x$SuiteRuns"
& "$PSScriptRoot/run-suite.ps1" -Runs $SuiteRuns
if ($LASTEXITCODE -ne 0) { $failures = $failures + 1; Write-Host "ci: SUITE FAILED" }

Write-Host "ci: sbom + unsafe gate"
& "$PSScriptRoot/sbom.ps1"
if ($LASTEXITCODE -ne 0) { $failures = $failures + 1; Write-Host "ci: SBOM FAILED" }

foreach ($p in $probes) {
  Write-Host "ci: $p x$ProbeRuns"
  & "$PSScriptRoot/run-probe.ps1" "tests/probes/$p.xi" -Runs $ProbeRuns *> "out/ci_$p.log"
  if ($LASTEXITCODE -ne 0) {
    $failures = $failures + 1
    Write-Host "ci: PROBE FAILED: $p (see out/ci_$p.log)"
  }
}

Write-Host "ci: bench smoke (quick)"
& "$PSScriptRoot/bench.ps1" -Mode quick *> "out/ci_bench_smoke.log"
if ($LASTEXITCODE -ne 0) {
  $failures = $failures + 1
  Write-Host "ci: BENCH FAILED (see out/ci_bench_smoke.log)"
}

Write-Host "ci: kill matrix (durability delta, 4 iterations)"
& "$PSScriptRoot/kill_matrix.ps1" -Iters 4 *> "out/ci_kill_matrix.log"
if ($LASTEXITCODE -ne 0) {
  $failures = $failures + 1
  Write-Host "ci: KILL MATRIX FAILED (see out/ci_kill_matrix.log)"
}

if ($failures -ne 0) {
  Write-Host "ci: FAILED ($failures gate(s) red)"
  exit 1
}
Write-Host "ci: ALL GATES GREEN (suite x$SuiteRuns + sbom + $($probes.Count) probes x$ProbeRuns + bench smoke + kill matrix)"
exit 0
