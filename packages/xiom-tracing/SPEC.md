# xiom.tracing -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.tracing` (`src/tracing.xi`). Manifest: `package.xi` (name
`xiom.tracing`, version `0.1.0`). Depends on `xiom.std` (no library imports;
tests use `xiom.test`, `xiom.io` and `xiom.string.compare`).

## Scope

An in-memory span tree for tracing:

- spans created with an explicit parent id, name, and start time;
- closes with an explicit end time, any order, open spans tracked as `-1`;
- durations, direct children in creation order, depth, and self time;
- the longest closed root duration.

Everything is caller-owned values and explicit inputs; the module performs no
I/O, no clock access, and no FFI.

## Non-goals

- Clock access: timestamps are always passed in by the caller.
- Persistence, streaming, flushing, or an export format (JSON, OTLP, ...).
- Sampling, trace/span context propagation, or correlation ids.
- Span attributes, events, links, status codes, or resource metadata.
- Thread safety, locking, or cross-thread sharing.
- Nanosecond or fractional durations; only integer milliseconds.
- Automatic instrumentation (wrapping closures, RAII guards); the caller
  records start and end explicitly.

## Data model

`SpanTree` is four parallel vectors kept in lockstep:

```xi
pub type SpanTree = {
  names: Vec[Str];
  parents: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
}
```

| Vector | Meaning | Default |
|---|---|---|
| `names` | span name, verbatim | caller string |
| `parents` | parent id: -1 root, else an existing id | resolved at start |
| `starts` | start time in ms | clamped to >= 0 |
| `ends` | end time in ms, -1 while open | -1 |

A span id is its 0-based index; ids are never reused and all four vectors have
`trace_span_count` entries. Because `trace_start_span` only accepts an already
existing parent id and returns the pre-push count, `parents[i] < i` always
holds for every span, so ancestor walks terminate.

## API signatures

All functions are free functions in module `xiom.tracing`:

```xi
pub fn trace_new() -> SpanTree
pub fn trace_start_span(t: &mut SpanTree, parent: Int, name: Str, start_ms: Int) -> Int
pub fn trace_end_span(t: &mut SpanTree, id: Int, end_ms: Int) -> Bool
pub fn trace_span_count(t: &SpanTree) -> Int
pub fn trace_span_name(t: &SpanTree, id: Int) -> Str
pub fn trace_span_parent(t: &SpanTree, id: Int) -> Int
pub fn trace_is_open(t: &SpanTree, id: Int) -> Bool
pub fn trace_duration_ms(t: &SpanTree, id: Int) -> Int
pub fn trace_children(t: &SpanTree, id: Int) -> Vec[Int]
pub fn trace_depth(t: &SpanTree, id: Int) -> Int
pub fn trace_self_time_ms(t: &SpanTree, id: Int) -> Int
pub fn trace_root_duration_ms(t: &SpanTree) -> Int
```

The type's fields are internal implementation details; callers construct
through `trace_new` and operate through the functions above.

## Semantics

### Creation

`trace_start_span(t, parent, name, start_ms)`:

1. resolves `parent`: an `Int` in `[0, count)` selects that span; every other
   value (including `-1`, negative values other than -1, and ids >= count) is
   treated as -1, making the span a root;
2. clamps `start_ms < 0` to 0;
3. pushes `name`, the resolved parent, the clamped start, and `-1` (open);
4. returns the new span id (the previous count).

### Closing

`trace_end_span(t, id, end_ms)` returns true and stores `end_ms` exactly when
all of the following hold:

- `0 <= id < trace_span_count`;
- the span is open (`ends[id] == -1`);
- `end_ms >= starts[id]` (end equal to start is allowed; duration 0).

Otherwise it returns false and leaves the tree unchanged: unknown id, already
closed, or `end_ms < starts[id]`. Spans may be closed in any order, including
a parent before its children.

### Queries

| Query | Result |
|---|---|
| `trace_span_count` | length of the parallel vectors |
| `trace_span_name(t, id)` | stored name; `""` when `id` is unknown |
| `trace_span_parent(t, id)` | `parents[id]` (-1 for roots); -2 when unknown |
| `trace_is_open(t, id)` | `ends[id] == -1`; false when unknown |
| `trace_duration_ms(t, id)` | `ends[id] - starts[id]`; -1 when unknown or open |
| `trace_children(t, id)` | ids `i` with `parents[i] == id`, ascending (creation order); empty Vec when unknown |
| `trace_depth(t, id)` | number of parent steps to reach a -1 parent (roots 0); -1 when unknown |
| `trace_self_time_ms(t, id)` | duration minus the durations of all closed direct children, clamped to >= 0; -1 when unknown or open |
| `trace_root_duration_ms(t)` | max over closed spans with `parents[i] == -1` of `ends[i] - starts[i]`; 0 when there is none |

`trace_children` lists only direct children (a grandchild's `parents[i]` is its
own parent, not `id`). The returned Vec is freshly allocated and owned by the
caller; nothing in the module aliases it.

### Self time

`trace_self_time_ms` is `duration(id) - sum(duration(child))` over direct
children whose `ends[child] != -1`; open children are unknown and contribute
nothing. The subtraction is clamped at 0, so a child interval that overlaps a
sibling or extends beyond the parent (both representable, since close order
and interval bounds are unconstrained) can only push the result to 0, never
negative. Children closed after their parent still count once closed, because
the computation reads the current `ends` vector.

### Root duration

`trace_root_duration_ms` ignores open roots and non-root spans; with only open
roots it returns 0, which is indistinguishable from an empty tree.

## Edge rules

| Case | Behaviour |
|---|---|
| `parent == -1` | root |
| `parent` out of range or < -1 | treated as -1 (root), documented fallback |
| `start_ms < 0` | clamped to 0 |
| `end_ms < start_ms` | `false`, span stays open |
| `end_ms == start_ms` | `true`, duration 0 |
| second `trace_end_span` | `false`, first duration kept |
| unknown id in any query | name `""`, parent -2, open `false`, duration -1, depth -1, self -1, children empty, end `false` |
| `trace_children(t, -1)` | empty Vec (no span has id -1) |
| closing a parent before children | allowed; children keep their own lifecycle |
| child outside parent's interval | still subtracted from self time (clamped at 0) |
| empty tree | count 0, root duration 0, every per-id query default |

Error paths: none. Every function is total over `Int` arguments; there is no
panic path and no `Result`.

## Complexity

| Operation | Complexity |
|---|---|
| `trace_new`, `trace_start_span`, `trace_end_span` | O(1) amortized |
| `trace_span_count`, `trace_span_name`, `trace_span_parent`, `trace_is_open`, `trace_duration_ms` | O(1) |
| `trace_children`, `trace_self_time_ms`, `trace_root_duration_ms` | O(n) in the span count |
| `trace_depth` | O(depth) |

## Test plan

`tests/test_conformance.xi` (`module tracing_tests`, 20 named checks, hello-
style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line, and
returns the failure count):

1. empty tree reports zeroed defaults for every lookup;
2. `start_span` appends and returns sequential ids;
3. `end_span` closes the span and duration is `end - start`;
4. end before start is rejected; end == start gives duration 0;
5. second `end_span` returns false and keeps the duration;
6. unknown ids report defaults and `end_span` returns false;
7. children link to their parent id;
8. children are listed in creation order;
9. children only include direct children;
10. depth counts the ancestor chain (40-deep);
11. self time subtracts sequential closed children;
12. overlapping children are subtracted and the result clamps at 0;
13. open children are ignored; an open span has no self time;
14. root duration is the max closed root duration;
15. negative `start_ms` is clamped to 0;
16. unknown parents fall back to root (-1);
17. self time only subtracts direct children (chain);
18. 50-span tree: links, counts and self time stay consistent;
19. a child closed after its parent still subtracts its duration;
20. trees are independent; children of a non-span id are empty.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.tracing
```

Last verified: compiler 0.61.3, `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Explicit clock only: the module has no clock, no I/O, no environment access.
- Integer milliseconds; no sub-millisecond or Float durations.
- In-memory and non-threaded: no persistence, no sharing, no locking.
- No export/serialization format and no sampling/propagation.
- Overlapping sibling intervals are summed without merging before the clamp at
  0, so overlap can only collapse self time to 0 (not a merged-interval
  measure).
- Extensions (attributes, events, status, resource) are out of scope for
  this version.
- Times and counts are caller-supplied `Int`s; extreme values wrap with the
  platform's 64-bit signed arithmetic rather than trapping.

## Compiler / stdlib notes for v0.61.3

- `Str` values read from `Vec[Str]` must be compared with
  `xiom.string.compare.str_compare` (BUG 17: `==` on such values lowers to a
  pointer comparison). The tests route every name check through a `streq`
  helper; the library module performs no string comparison at all.
- Advisory E001 ("cannot borrow as mutable while immutably borrowed") fires
  when a `&local` call is followed by a `&mut local` call on the same local in
  one function. The tests route read-only checks through tiny helpers that
  take `&mut` and call the real `&`-based API internally; the harness run is
  warning-free.
- `Vec[SpanTree]` is not used (struct-typed vector elements are avoided);
  children are returned as `Vec[Int]` ids instead.
- The compiler bug where constructing `Ok(x)`/`Err(x)` inside a function whose
  return type is a struct miscompiles is avoided entirely: the module uses no
  `Result`, and the tests use plain `assert`.
