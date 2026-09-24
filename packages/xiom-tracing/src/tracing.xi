// XIOM -- xiom.tracing: in-memory span trees with explicit-clock durations
// Port task: replace the xiom.tracing placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic value type: no clock access, no I/O, no export format, no
// FFI. A span tree is four parallel vectors kept in lockstep by trace_start_span
// (names, parents, starts, ends); a span id is its 0-based index and ids are
// never reused. The caller owns the clock and passes start_ms/end_ms explicitly,
// so the same call sequence always builds the same tree. Spans may be closed in
// any order; an open span has ends[id] == -1. Roots have parents[id] == -1.
// Free functions only -- XIOM v0.61.x has no methods.

module xiom.tracing

/// In-memory span tree stored as parallel vectors.
///
/// Fields are internal implementation details; construct through trace_new and
/// operate through the trace_* functions below. Invariants: the four vectors
/// have equal length (the span count); span id `i` is valid when
/// `0 <= i < trace_span_count`; `parents[i]` is -1 for a root or the id of an
/// existing span that was created earlier (so a parent id is always smaller
/// than its children's ids and the parent walk terminates); `starts[i] >= 0`;
/// `ends[i]` is -1 while the span is open, otherwise `ends[i] >= starts[i]`.
pub type SpanTree = {
  names: Vec[Str];
  parents: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
}

/// Create an empty span tree.
/// Returns: a tree with zero spans, no roots, and no open spans.
/// Error case: none. Complexity: O(1).
pub fn trace_new() -> SpanTree {
  var names_vec = Vec[Str].new();
  var parents_vec = Vec[Int].new();
  var starts_vec = Vec[Int].new();
  var ends_vec = Vec[Int].new();
  return SpanTree{ names: names_vec; parents: parents_vec; starts: starts_vec; ends: ends_vec; };
}

/// Start a span and return its id.
/// Params: t - the mutable tree; parent - -1 for a root, or the id of an
///         existing span; anything else (out of range, negative other than -1)
///         is treated as -1, so the span becomes a root;
///         name - the span name, stored verbatim;
///         start_ms - start time; negative values are clamped to 0.
/// Returns: the new span id (the previous span count). The span starts open
/// (its end is -1). No error path.
/// Complexity: O(1) amortized (four vector pushes).
pub fn trace_start_span(t: &mut SpanTree, parent: Int, name: Str, start_ms: Int) -> Int {
  var actual_parent = -1;
  if parent >= 0 && parent < t.names.len() {
    actual_parent = parent;
  }
  var clamped_start = start_ms;
  if clamped_start < 0 {
    clamped_start = 0;
  }
  let id = t.names.len();
  t.names.push(name);
  t.parents.push(actual_parent);
  t.starts.push(clamped_start);
  t.ends.push(-1);
  return id;
}

/// Close an open span.
/// Params: t - the mutable tree; id - the span to close; end_ms - end time.
/// Returns: true when the span existed, was still open, and
/// `end_ms >= starts[id]`; false for an unknown id, an already-closed span, or
/// an end before the start. A false result leaves the tree unchanged.
/// Complexity: O(1).
pub fn trace_end_span(t: &mut SpanTree, id: Int, end_ms: Int) -> Bool {
  if id < 0 || id >= t.names.len() {
    return false;
  }
  let current: Int = t.ends[id];
  if current != -1 {
    return false;
  }
  let started: Int = t.starts[id];
  if end_ms < started {
    return false;
  }
  t.ends[id] = end_ms;
  return true;
}

/// Number of spans in the tree (all four vectors have this length).
/// Complexity: O(1).
pub fn trace_span_count(t: &SpanTree) -> Int {
  return t.names.len();
}

/// Name of span `id`, stored verbatim at start; "" for an unknown id.
/// Complexity: O(1).
pub fn trace_span_name(t: &SpanTree, id: Int) -> Str {
  if id < 0 || id >= t.names.len() {
    return "";
  }
  let name: Str = t.names[id];
  return name;
}

/// Parent id of span `id`: -1 for a root; -2 for an unknown id.
/// Complexity: O(1).
pub fn trace_span_parent(t: &SpanTree, id: Int) -> Int {
  if id < 0 || id >= t.parents.len() {
    return -2;
  }
  let parent: Int = t.parents[id];
  return parent;
}

/// True while span `id` exists and has not been closed; false for an unknown
/// id. Complexity: O(1).
pub fn trace_is_open(t: &SpanTree, id: Int) -> Bool {
  if id < 0 || id >= t.ends.len() {
    return false;
  }
  let end: Int = t.ends[id];
  return end == -1;
}

/// Duration of span `id` in milliseconds: `ends[id] - starts[id]`.
/// Returns -1 for an unknown id or a span that is still open.
/// Complexity: O(1).
pub fn trace_duration_ms(t: &SpanTree, id: Int) -> Int {
  if id < 0 || id >= t.ends.len() {
    return -1;
  }
  let end: Int = t.ends[id];
  if end == -1 {
    return -1;
  }
  let start: Int = t.starts[id];
  return end - start;
}

/// Ids of span `id`'s direct children, in creation order (ascending id).
/// Only spans whose parent is exactly `id` are listed; grandchildren are not.
/// Returns an empty Vec for an unknown id. The caller owns the returned Vec.
/// Complexity: O(n) in the span count.
pub fn trace_children(t: &SpanTree, id: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if id < 0 || id >= t.parents.len() {
    return out;
  }
  var i = 0;
  while i < t.parents.len() {
    let parent: Int = t.parents[i];
    if parent == id {
      out.push(i);
    }
    i = i + 1;
  }
  return out;
}

/// Depth of span `id`: 0 for a root, 1 for its child, and so on; -1 for an
/// unknown id. Ids are created after their parent, so the walk cannot cycle.
/// Complexity: O(depth).
pub fn trace_depth(t: &SpanTree, id: Int) -> Int {
  if id < 0 || id >= t.parents.len() {
    return -1;
  }
  var depth = 0;
  var current = id;
  while current >= 0 {
    if current >= t.parents.len() {
      return -1;
    }
    let parent: Int = t.parents[current];
    if parent < 0 {
      return depth;
    }
    depth = depth + 1;
    current = parent;
  }
  return -1;
}

/// Self time of span `id` in milliseconds: its duration minus the durations of
/// every closed direct child, clamped to >= 0. Open children are not
/// subtracted (their duration is unknown), so an open parent or an open child
/// contributes nothing. Returns -1 for an unknown id or an open span.
/// Child intervals may overlap each other or exceed the parent; the clamp
/// keeps the result at 0 in those cases (no underflow).
/// Complexity: O(n) in the span count.
pub fn trace_self_time_ms(t: &SpanTree, id: Int) -> Int {
  if id < 0 || id >= t.ends.len() {
    return -1;
  }
  let end: Int = t.ends[id];
  if end == -1 {
    return -1;
  }
  let start: Int = t.starts[id];
  var total = end - start;
  var i = 0;
  while i < t.parents.len() {
    let parent: Int = t.parents[i];
    if parent == id {
      let child_end: Int = t.ends[i];
      if child_end != -1 {
        let child_start: Int = t.starts[i];
        total = total - (child_end - child_start);
      }
    }
    i = i + 1;
  }
  if total < 0 {
    total = 0;
  }
  return total;
}

/// Longest duration among closed root spans; 0 when there is no closed root
/// (empty tree or only open roots). Only spans with parent -1 are considered.
/// Complexity: O(n) in the span count.
pub fn trace_root_duration_ms(t: &SpanTree) -> Int {
  var best = 0;
  var i = 0;
  while i < t.parents.len() {
    let parent: Int = t.parents[i];
    if parent == -1 {
      let end: Int = t.ends[i];
      if end != -1 {
        let start: Int = t.starts[i];
        let duration = end - start;
        if duration > best {
          best = duration;
        }
      }
    }
    i = i + 1;
  }
  return best;
}
