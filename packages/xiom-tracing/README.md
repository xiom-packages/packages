# xiom.tracing

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** in-memory span trees: explicit-clock spans, durations, parent/
> child links, direct-children queries, depth, and self time.
> **Deps:** `xiom.std` only (the library imports nothing; tests use
> `xiom.test`, `xiom.io` and `xiom.string.compare`).

## What it is

`xiom.tracing` records a tree of timed spans -- the data model behind a trace
viewer -- without owning a clock, a thread, or a storage backend. A tree is
four parallel vectors kept in lockstep by `trace_start_span`; a span id is its
0-based index and ids are never reused. The caller passes `start_ms` and
`end_ms` explicitly, so the same call sequence always builds the same tree and
the harness can assert exact millisecond values.

Every function is a free function; the module performs no I/O, no allocation
beyond the span vectors, and no FFI.

## API

| Function | Returns | Description |
|---|---|---|
| `trace_new()` | `SpanTree` | Empty tree (0 spans). |
| `trace_start_span(&mut t, parent, name, start_ms)` | `Int` | Appends a span and returns its id. `parent` is -1 (root) or an existing id; anything else is treated as -1. Negative `start_ms` is clamped to 0. The span starts open. |
| `trace_end_span(&mut t, id, end_ms)` | `Bool` | Closes span `id`. `false` for an unknown id, an already-closed span, or `end_ms < start_ms`; the tree is unchanged on `false`. |
| `trace_span_count(t)` | `Int` | Number of spans. |
| `trace_span_name(t, id)` | `Str` | Stored name; `""` for an unknown id. |
| `trace_span_parent(t, id)` | `Int` | Parent id (-1 for roots); -2 for an unknown id. |
| `trace_is_open(t, id)` | `Bool` | True while the span exists and has not been closed. |
| `trace_duration_ms(t, id)` | `Int` | `end - start`; -1 for an unknown id or an open span. |
| `trace_children(t, id)` | `Vec[Int]` | Direct children in creation order; empty Vec for an unknown id. |
| `trace_depth(t, id)` | `Int` | 0 for roots, +1 per ancestor; -1 for an unknown id. |
| `trace_self_time_ms(t, id)` | `Int` | Duration minus the durations of closed direct children, clamped to >= 0; -1 for an unknown id or an open span. |
| `trace_root_duration_ms(t)` | `Int` | Longest duration among closed root spans; 0 when there is none. |

## Usage

```xi
use xiom.tracing;

var t = trace_new();
let root = trace_start_span(&mut t, -1, "request", 1000);   // root span
let db = trace_start_span(&mut t, root, "db.query", 1010); // child of root
let cache = trace_start_span(&mut t, root, "cache.put", 1050);

trace_end_span(&mut t, db, 1040);      // true; duration 30 ms
trace_end_span(&mut t, cache, 1060);   // true; duration 10 ms
trace_end_span(&mut t, root, 1100);    // true; duration 100 ms

trace_span_count(&t);                  // 3
trace_duration_ms(&t, root);           // 100
trace_self_time_ms(&t, root);          // 100 - 30 - 10 = 60
trace_children(&t, root)[0];           // db's id
trace_depth(&t, cache);                // 1
trace_root_duration_ms(&t);            // 100
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tracing
```

Expected: the module passes the section-4 namespace rule, 20 `[PASS]` lines,
and a final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- Explicit clocks only: the module never reads a clock; `start_ms` / `end_ms`
  are caller-supplied `Int` milliseconds, so timestamps are only as good as the
  caller's source.
- In-memory only: no persistence, no flushing, no thread safety, and no
  sharing across threads.
- No export format: no JSON/OTLP/console serializer and no sampling or
  propagation; the tree is plain data the caller can walk.
- Self time subtracts each closed child's full duration; overlapping siblings
  are not merged, so the clamp at 0 absorbs double-counted overlap (by design,
  documented in SPEC.md).
- A parent may be closed before its children; children closed afterwards still
  subtract from the parent's self time.
- No span attributes, events, links, status, or resource metadata; names are
  single `Str` labels.
- Value semantics only: fields are public but are implementation details; use
  the `trace_*` functions.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
