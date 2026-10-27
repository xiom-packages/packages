// XIOM -- xiom.jev.batch: caller-side batch aggregation
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SPEC.md section 19.5 pins batch as CALLER-SIDE SCHEDULING ONLY: the v0.2.0
// API has no batch endpoint, so this package never performs I/O and owns no
// async runtime. A caller schedules its own requests (sequentially, or with
// whatever concurrency its host provides) and hands the collected Result
// values to batch_collect, which produces a deterministic partial-failure
// view.
//
// Shape note: SPEC.md writes the two payload vectors as Vec[(Int, Str)] and
// Vec[(Int, JevError)]. Tuples inside Vec have a known element-read defect in
// released compilers, so the package uses the established struct-per-row
// convention instead: BatchSuccess { index, value } and
// BatchFailure { index, error }. The shape is equivalent and documented in
// README.md and SPEC.md section 19.7.
//
// Stability: batch_collect makes ONE linear pass over the input, in input
// order, so successes and failures each carry ascending indices. Items never
// move between vectors; a failure preserves its exact typed JevError payload.
//
// Compiler note: batch_collect assumes the caller's input Vec already holds
// items in caller order. Compiler v0.64.8 lost the Err Str payload (and could
// perturb order) when a directly-constructed Err was passed straight to
// Vec.push (probe: docs/repro/batch_result_vec_push.xi); fixed in v0.65.2, so
// callers may push Results directly -- the local-bind workaround is retired.

module xiom.jev.batch

use xiom.jev.errors;

/// BatchSuccess is one Ok item: its zero-based input index and the Str
/// payload exactly as supplied by the caller. Complexity: O(1).
pub type BatchSuccess = {
  index: Int;
  value: Str;
}

/// BatchFailure is one Err item: its zero-based input index and the exact
/// typed JevError payload returned by the caller's request. Complexity: O(1).
pub type BatchFailure = {
  index: Int;
  error: JevError;
}

/// BatchOutcome is the deterministic aggregation of a caller-scheduled batch.
/// successes and failures are each in ascending input-index order; ok is true
/// exactly when failures is empty. Complexity: O(1).
pub type BatchOutcome = {
  successes: Vec[BatchSuccess];
  failures: Vec[BatchFailure];
  ok: Bool;
}

/// batch_collect partitions caller-collected results without reordering:
/// every Ok becomes BatchSuccess{ index, value } and every Err becomes
/// BatchFailure{ index, error }, each preserving its input position, and
/// ok = failures.len() == 0. An empty input yields an ok outcome with both
/// vectors empty. Performs no I/O and no scheduling. Complexity: O(n). Pure.
pub fn batch_collect(results: &Vec[Result[Str, JevError]]) -> BatchOutcome {
  var successes: Vec[BatchSuccess] = Vec[BatchSuccess].new();
  var failures: Vec[BatchFailure] = Vec[BatchFailure].new();
  let n: Int = results.len();
  var i: Int = 0;
  while i < n {
    let item: Result[Str, JevError] = results[i];
    if item.is_ok {
      let value: Str = item.value;
      successes.push(BatchSuccess{ index: i, value: value });
    } else {
      let e: JevError = item.error;
      failures.push(BatchFailure{ index: i, error: e });
    }
    i = i + 1;
  }
  return BatchOutcome{
    successes: successes,
    failures: failures,
    ok: failures.len() == 0
  };
}
