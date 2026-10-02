# xiom.cloudlog

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.0` on the XIOM registry.
> **Scope:** a pure, deterministic MODEL of a cloud log pipeline, in five
> cooperating parts: ingest batching with sequence watermarks, structured
> format encoding/decoding (key=value and a flat JSON-ish subset), an
> append-only stream with a tail consumer (cursor, checkpoint, at-least-once
> replay window), a retention store with per-segment stats, retention and
> compaction policies, and predicate-tree search with deterministic
> pagination. No network, no disk, no clock, no global state.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`, and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.convert.int`.

## What it is

`xiom.cloudlog` is the model layer behind an observability pipeline. Every
stage is a flat value that the caller owns and drives:

```
raw lines --> ingest buffer --(flush policy)--> format encode --> stream blob
                                                                    |
                              search <-- log table <-- decode <-- tail read/commit
                                                                    |
                                                              retention store
```

Nothing here talks to a socket, a file or a system clock: `now_ms`,
sequence numbers and timestamps are caller-supplied integers, so every
decision is reproducible and lockable by tests. Two runs over the same
inputs produce byte-identical output (pinned by the determinism check).

Non-goals: no transports (agents, collectors, sockets, files), no
background threads, no serialization to disk, no compression, no
authentication, no Unicode normalization, no wall-clock or timezone logic.

## API

All functions are free functions prefixed `cl_`; the module is
`xiom.cloudlog`.

### Events and levels

| Function | Returns | Description |
|---|---|---|
| `cl_level_name(level)` | `Str` | `trace`..`fatal` for 0..5, `""` outside. |
| `cl_level_code(name)` | `Result[Int, Str]` | Name -> 0..5; `Err("cloudlog: unknown level: <name>")`. |
| `cl_level_valid(level)` | `Bool` | True for 0..5. |
| `cl_event_new(time_ms, level, msg)` | `CloudEvent` | Severity defaults to the level. |
| `cl_event_new_full(time_ms, level, severity, msg)` | `CloudEvent` | Explicit severity. |
| `cl_event_set(ev, key, val)` | `Bool` | Append attribute; false for an invalid key. |
| `cl_event_get(ev, key)` / `cl_event_has_key(ev, key)` | `Option[Str]` / `Bool` | First exact-key lookup. |
| `cl_event_key_count(ev)`, `cl_event_key(ev, i)`, `cl_event_val(ev, i)` | `Int` / `Str` / `Str` | Parallel attribute view. |
| `cl_key_ok(key)`, `cl_text_contains(hay, needle)` | `Bool` | Attribute-key validation, substring test. |

### Formats

| Function | Returns | Description |
|---|---|---|
| `cl_kv_encode(ev)` | `Str` | Canonical `time= level= severity= msg="..." [k="..."]...` line. |
| `cl_kv_decode(line)` | `Result[CloudEvent, Str]` | Parse a key=value line; bare or quoted values; exact errors with byte offsets. |
| `cl_json_encode(ev)` | `Str` | Canonical flat JSON object `{"time":...,"level":...,"severity":...,"msg":...}`. |
| `cl_json_decode(text)` | `Result[CloudEvent, Str]` | Flat JSON subset: string/int/bool values; exact errors with byte offsets. |

### Ingest batching

| Function | Returns | Description |
|---|---|---|
| `cl_ingest_new(base_seq)` | `CloudIngest` | Empty buffer; watermark starts at `base_seq - 1`. |
| `cl_ingest_accept(ing, seq, time_ms, line)` | `Int` | 0 in order, 1 accepted with a gap, 2 duplicate/old, 3 empty reject. |
| `cl_ingest_assign(ing, time_ms, line)` | `Int` | Assign `next_seq`, then accept. |
| `cl_ingest_watermark/seen_max/pending/count/accepted/duplicates/gap_events/total_bytes/first_time/last_time/age_ms` | `Int` | Buffer and watermark statistics. |
| `cl_ingest_plan_flush(ing, pol, now_ms)` | `CloudFlush` | Non-mutating decision; reason order count > bytes > age. |
| `cl_ingest_flush(ing, pol, now_ms)` | `CloudFlush` | Return the plan and clear content; reason 4 when explicit. |

### Stream and tail

| Function | Returns | Description |
|---|---|---|
| `cl_stream_new()` | `CloudStream` | Empty stream (one `Str` blob + parallel offsets). |
| `cl_stream_append(st, ts, line)` | `Int` | Index, or -1 for empty/CR/LF records. |
| `cl_stream_count/line/ts/byte_len/span_ms` | `Int` / `Str` | Record view and stats. |
| `cl_tail_new(retained_from)` | `CloudTail` | Cursor = checkpoint = retention floor. |
| `cl_tail_seek(t, idx)` | `Int` | Move cursor, clamped to the retention floor. |
| `cl_tail_read(st, t, max)` | `CloudRead` | Pull at the cursor (no commit); `truncated` when retention passed it. |
| `cl_tail_replay(st, t, max)` | `CloudRead` | Redeliver from the checkpoint (`replayed` true). |
| `cl_tail_commit(t, through)` | `Bool` | Monotonic checkpoint; the at-least-once commit. |
| `cl_tail_set_retained(t, idx)`, `cl_tail_lag(t)`, `cl_tail_ok(st, t)` | `Int` / `Int` / `Bool` | Retention floor, replay window, invariant check. |

### Retention store

| Function | Returns | Description |
|---|---|---|
| `cl_store_new(seg_max_events)` | `CloudStore` | Empty store; roll threshold clamped to >= 1. |
| `cl_store_append(st, time_ms, nbytes)` | `Int` | Segment index; rolls/seals automatically; -1 for `nbytes <= 0`. |
| `cl_store_seal(st)` | `Int` | Seal the open segment. |
| `cl_store_apply_retention(st, pol, now_ms)` | `CloudRetention` | Policy order bytes, age, segments, events; never drops the newest segment. |
| `cl_store_compact(st, target)` | `Int` | Merges oldest live segments; stats preserved; merge count. |
| `cl_store_compact_due(st, pol)` | `Bool` | `live_count > compact_at`. |
| `cl_store_live_count/segment_count/total_bytes/total_events/next_off/dropped_segments/dropped_bytes/dropped_events/compacted_segments/oldest_time/newest_time` | `Int` | Store-wide stats. |
| `cl_store_segment_state/bytes/events/from_off/to_off/from_time/to_time/span_ms` | `Int` | Per-segment stats. |

### Search

| Function | Returns | Description |
|---|---|---|
| `cl_log_new()`, `cl_log_add(l, ...)`, `cl_log_add_kv(l, rec, k, v)` | `CloudLog` / `Int` / `Bool` | Parallel-vector log table. |
| `cl_log_count/time/level/severity/msg/key_get` | `Int` / `Str` / `Option[Str]` | Record accessors. |
| `cl_pred_new()` plus `cl_pred_const/and/or/not/level/sev_ge/msg_contains/key_eq/time_range` | `CloudPred` / `Int` | Build a flat predicate tree; builders return the node index. |
| `cl_pred_node_count(p)`, `cl_pred_op(p, i)` | `Int` | Tree introspection. |
| `cl_pred_eval(p, l, rec, node)` | `Bool` | Evaluate a node against one record. |
| `cl_search(l, p, from, to, start, limit)` | `CloudPage` | Deterministic page: hits, `matched_total`, `next_start`. |
| `cl_search_count(l, p, from, to)` | `Int` | Match count only. |

## Example

```xiom
use xiom.cloudlog;

var ev = cl_event_new(1712345678000, 4, "db timeout");
cl_event_set(&mut ev, "host", "node-a");
let line = cl_kv_encode(&ev);

var st = cl_stream_new();
cl_stream_append(&mut st, ev.time_ms, line);

var tail = cl_tail_new(0);
let page = cl_tail_read(&st, &tail, 10);
cl_tail_commit(&mut tail, page.next_cursor);   // at-least-once: after processing
```

## Tests

```
.\scripts\port.ps1 -Package xiom-cloudlog -TimeoutSec 60
```

27 conformance checks cover the level tables, event attributes, both format
codecs (canonical output, escaping round-trips, the exact error catalog with
byte offsets), ingest watermarks/gaps/duplicates and flush precedence, the
stream blob and tail commit/replay/truncation semantics, store rolling,
retention reasons and compaction, predicate evaluation, pagination and an
end-to-end pipeline plus a determinism replay. See `SPEC.md` for the
normative rules.

## License

MIT OR Apache-2.0.
