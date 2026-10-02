# xiom.cloudlog -- normative specification

Package: `xiom.cloudlog` 0.1.0 (category `data`, deps stdlib).
Module: `xiom.cloudlog`. Tests: `cloudlog_tests` (27 checks).

This document pins every rule the implementation and its conformance suite
enforce. Where text and tests disagree, the tests win and this file is a bug.

## 1. Scope and non-goals

In scope: a pure model of ingest batching (size/time flush policies,
sequence watermarks), structured format encoding/decoding (key=value and a
flat JSON-ish subset with level/time/severity fields and escaping), a stream
tail consumer model (cursors, checkpoints, at-least-once replay window), a
retention store model (segments, retention/compaction policies, per-segment
stats), and search (predicate tree, time ranges, deterministic pagination).

Non-goals: network or disk I/O, collectors/agents, threads and scheduling,
compression, encryption, wall-clock or timezone logic, Unicode
normalization, persistence formats, and concurrency. No function reads or
writes global state; every input is a value and every output is a value.

## 2. Conventions

* `Int` is a signed 64-bit integer. `time_ms` is an epoch-millisecond
  integer; it may be negative; there is no calendar arithmetic in this
  module. `nbytes`, `max` and lengths are non-negative in valid use.
* `Str` is a byte string. All string equality in the implementation goes
  through `str_compare`; callers comparing decoded fields must do the same
  (BUG-17 makes `==` on `Vec[Str]` elements a pointer comparison).
* Errors are deterministic strings of the exact form
  `"cloudlog: <reason> at <byte offset>"`. Offsets are absolute byte
  positions in the text passed to the function. `0` means the first byte;
  `<len>` means one past the end. The full catalogs are in sections 4 and 5.
* All results are `Result[T, Str]`; struct payloads are built only through
  the module's leaf helpers. `Option[Str]` is used for lookups.
* Parallel vectors are always pushed in lockstep; every accessor bounds
  checks each vector it reads, and out-of-range reads return `0`, `-1` or
  `""` as documented per function.

## 3. Tables

Levels (and severity codes) 0..5:

| code | name |
|---|---|
| 0 | trace |
| 1 | debug |
| 2 | info |
| 3 | warn |
| 4 | error |
| 5 | fatal |

Attribute keys: 1..64 bytes of `[A-Za-z0-9_.-]`; anything else is invalid
(`cl_key_ok` false, `cl_event_set` false, encoders never see invalid keys
because `cl_event_set` gates them).

Ingest accept codes (`cl_ingest_accept`):

| code | meaning |
|---|---|
| 0 | accepted, in order (watermark advanced to at least `seq`) |
| 1 | accepted, but a gap remains above the watermark |
| 2 | rejected duplicate/old (`seq <= watermark`) |
| 3 | rejected empty line |

Flush reasons (`CloudFlush.reason`):

| code | meaning |
|---|---|
| 0 | no flush |
| 1 | event count reached `max_events` |
| 2 | byte total reached `max_bytes` |
| 3 | oldest event age reached `max_age_ms` |
| 4 | explicit `cl_ingest_flush` (no policy triggered) |

Store segment states (`seg_state`):

| code | meaning |
|---|---|
| 0 | dead (dropped by retention or absorbed by compaction) |
| 1 | open: newest live segment, receives appends; at most one exists |
| 2 | sealed: live but no longer appended to |

Retention reasons (`CloudRetention.reason`): `0` none, `1` bytes, `2` age,
`3` segment count, `4` event count.

Predicate opcodes (`CloudPred.op`): `0` FALSE, `1` TRUE, `2` AND, `3` OR,
`4` NOT, `5` level equals, `6` severity >=, `7` message contains, `8`
attribute key=value, `9` time in inclusive range.

## 4. key=value format

### 4.1 Grammar

```
line    := field *( SP field ) [ SP ]
field   := key "=" value
key     := 1*64 of [A-Za-z0-9_.-]
value   := bare | quoted
bare    := 1*( %x01-21 / %x23-5B / %x5D-FF )   ; no SP, '"', backslash, NUL-raw
quoted  := '"' *( qchar / escape ) '"'
qchar   := %x20-21 / %x23-5B / %x5D-FF        ; raw, no control, no quote/backslash
escape  := "\" ( '"' / "\" / "n" / "r" / "t" / "x" HEX HEX )
```

`\xNN` is case-insensitive hex; `\x00` is rejected (a `Str` cannot safely
carry NUL). Raw bytes `< 0x20` and `0x7F` are rejected inside quoted values
and must be escaped; bytes `>= 0x80` pass through byte-exact. Leading and
trailing spaces are ignored; a line with no field is `empty line at 0`.
Fields are separated by exactly one or more spaces.

### 4.2 Encode

`cl_kv_encode` emits, in this fixed order:

```
time=<decimal> level=<name> severity=<decimal> msg="<escaped>"
  [ SP <key>="<escaped>" ]...        (attributes in insertion order)
```

Escaping: `\` -> `\\`, `"` -> `\"`, LF -> `\n`, CR -> `\r`, TAB -> `\t`;
other bytes `< 0x20` and `0x7F` -> `\xNN` (uppercase hex). All other bytes
are emitted raw. Attributes beyond a parallel-vector mismatch are dropped
(the encoder stops at `min(keys.len(), vals.len())`).

### 4.3 Decode

`cl_kv_decode` returns a `CloudEvent` where:

* `time` (required) is a bare decimal integer (optional `-`, 1..18 digits,
  leading zeros allowed, `integer overflow` beyond 18 digits);
* `level` (required) is a bare or quoted name from section 3;
* `severity` (optional, bare integer 0..5) defaults to the level code;
* `msg` (optional, bare or quoted string) defaults to `""`;
* every other key becomes an attribute in first-seen order and duplicates
  (header or attribute) are errors.

Error catalog (reason, then the position used):

| reason | position |
|---|---|
| `empty line` | 0 |
| `bad key` | first byte not a key char |
| `expected =` | byte where `=` was required |
| `missing value` | byte after `=`, or first byte of an empty bare value |
| `bad value` | stray `"`/`\` in a bare value, or junk after a closing quote |
| `unterminated string` | end of text |
| `bad escape` | the backslash |
| `unsupported escape` | backslash of `\x00` |
| `bad character` | raw control/DEL byte in a quoted value |
| `missing integer` | first byte scanned for an integer |
| `integer overflow` | 19th digit |
| `bad integer` | quoted `time`/`severity`, or trailing bytes after an integer |
| `bad severity` | integer outside 0..5 |
| `duplicate key: <k>` | start of the repeated key |
| `missing time` | end of text |
| `missing level` | end of text |

## 5. JSON-ish format

### 5.1 Grammar

A flat object only: string keys, values limited to strings, integers and
`true`/`false`. No arrays, no nested objects, no `null`, no floats, no
exponents. Whitespace is SP, TAB, LF or CR between tokens. Raw control
bytes `< 0x20` inside strings are rejected.

String escapes: `\" \\ \/ \b \f \n \r \t` and `\uXXXX` for code points
1..127 (0 or values > 127 are `unsupported unicode escape`; malformed
4-digit runs are `bad unicode escape`). Integers: optional `-`, 1..18
digits (same overflow rule as section 4).

### 5.2 Encode

`cl_json_encode` emits, in fixed order, no extra whitespace:

```
{"time":<decimal>,"level":"<name>","severity":<decimal>,"msg":"<escaped>"
  [ ,"<key>":"<escaped>" ]... }
```

Escaping: quote, backslash, LF, CR, TAB, BS (0x08), FF (0x0C) use the short
escapes; every other byte `< 0x20` uses `\u00NN` (uppercase hex); all other
bytes are emitted raw. Attribute values are always encoded as strings, so
an integer or bool decoded as an attribute re-encodes as a string (documented
type loss; `time`/`severity` keep integer types).

### 5.3 Decode

Field mapping: `time` must be an integer; `level` must be a string name;
`severity` optional integer 0..5 (defaults to the level); `msg` optional
string (defaults `""`); any other key takes a string, integer (stored as its
decimal text) or bool (stored `"true"`/`"false"`). Duplicate keys are
errors. Events are validated after the whole object is scanned: a missing
`time` or `level` is reported at the end offset.

Error catalog:

| reason | position |
|---|---|
| `empty document` | 0 |
| `expected object` | first non-space byte |
| `expected key` | byte where a key string was required |
| `unterminated object` | end of text, or the byte where `,`/`}` was required |
| `expected colon` | byte where `:` was required |
| `expected value` | end of text after a colon |
| `unsupported value` | start of a nested/non-scalar value or bad `true`/`false` |
| `unterminated string` | end of text |
| `bad escape` | the backslash |
| `bad unicode escape` | the backslash of a malformed `\uXXXX` |
| `unsupported unicode escape` | the backslash when the code point is 0 or > 127 |
| `bad character` | raw control byte inside a string |
| `trailing data` | first non-space byte after the root object |
| `missing integer` / `integer overflow` | as section 4 |
| `bad integer` | `time` not an integer |
| `bad level` | `level` not a string |
| `unknown level: <v>` | start of the `level` value |
| `bad severity` | `severity` not an integer in 0..5 |
| `bad string` | `msg` not a string |
| `duplicate key: <k>` | start of the repeated key string |
| `missing time` / `missing level` | end of text |

## 6. Ingest batching

State (`CloudIngest`): content parallel vectors `lines`, `seqs`, `times`,
`sizes`; `base_seq`; producer counter `next_seq`; consumer `watermark`;
`seen_max`; lifetime counters `accepted`, `duplicates`, `gap_events`; and
`total_bytes` for the current buffer.

* `cl_ingest_new(base_seq)` sets `next_seq = base_seq`,
  `watermark = seen_max = base_seq - 1`, and zero counters.
* `cl_ingest_accept` first rejects empty lines (code 3, never stored), then
  rejects `seq <= watermark` as duplicates (code 2, `duplicates` + 1).
  Otherwise the line/seq/time/size are appended in lockstep, `accepted` and
  `total_bytes` grow, `seen_max` rises, and the watermark advances through
  every contiguous sequence now present, not only the accepted one. Code 0
  when `seq` is at or below the advanced watermark, else 1 (`gap_events`
  + 1). Out-of-order arrival is fully supported; a later fill closes the gap.
* `cl_ingest_assign` takes `next_seq`, increments it, then accepts; so the
  producer path is always contiguous.
* `cl_ingest_pending = max(0, seen_max - watermark)`.
* Flush: `cl_ingest_plan_flush` checks, in order, `max_events > 0 &&
  count >= max_events` (1), `max_bytes > 0 && total_bytes >= max_bytes` (2),
  `max_age_ms > 0 && now_ms - first_time >= max_age_ms` (3). An empty buffer
  never flushes (should false, reason 0). `CloudFlush` carries count, bytes,
  age, and `seq_first`/`seq_last` (-1 when the seq vector does not match the
  line count).
* `cl_ingest_flush` returns that plan (reason 4 when no policy triggered) and
  clears lines/seqs/times/sizes and `total_bytes`; `watermark`, `next_seq`,
  `base_seq` and the lifetime counters survive.

## 7. Stream and tail

### 7.1 Stream

`CloudStream` stores records in one `Str` blob separated by LF plus parallel
`off`/`len`/`ts` vectors. `cl_stream_append` rejects empty records and
records containing CR or LF (returns -1) so record framing cannot be broken;
otherwise it appends `line + "\n"`, records the start offset, byte length
and timestamp, and returns the index. `cl_stream_byte_len` includes the LF
separators. `cl_stream_line/ts` are bounds-checked ("" / 0). `span_ms` is
`ts[last] - ts[first]` for two or more records, else 0.

### 7.2 Tail consumer

`CloudTail` holds `cursor` (next index to deliver), `acked` (checkpoint: all
records before it are processed) and `retained_from` (earliest index still
retained). Invariant (`cl_tail_ok`): `0 <= retained_from <= acked <= cursor
<= stream count`.

* `cl_tail_new(f)` clamps `f` to `>= 0` and starts cursor = acked =
  retained_from = f.
* `cl_tail_seek` sets the cursor but never below `retained_from`.
* `cl_tail_set_retained` only raises the floor, modelling retention.
* `cl_tail_read(st, t, max)` reads up to `max` records starting at the
  cursor. It is pure: it does not move the cursor. When the cursor is below
  the floor the read starts at the floor and `truncated` is true (data was
  lost). `from`, `count`, the record `lines`/`idx`, and `next_cursor`
  (`from + count`) are returned; `max <= 0` or a cursor past the end yields
  an empty read whose `next_cursor` is the clamped `from`.
* `cl_tail_replay(st, t, max)` reads from `acked` instead of `cursor` with
  `replayed` true: the at-least-once redelivery after a crash. It is also
  pure.
* `cl_tail_commit(t, through)` refuses a `through` below the checkpoint,
  then sets `acked = through` and raises `cursor` to `acked` if needed.
  Committing only after processing the delivered records is what makes the
  model at-least-once: an uncommitted delivery is replayed.
* `cl_tail_lag = max(0, cursor - acked)` is the replay window.

## 8. Retention store

`CloudStore` keeps parallel per-segment vectors (`from_off`, `to_off`,
`from_time`, `to_time`, `bytes`, `events`, `state`), the roll threshold
`seg_max_events`, the monotonic byte cursor `next_off`, and counters
`live_count`, `total_bytes`, `total_events`, `dropped_segments`,
`dropped_bytes`, `dropped_events`, `compacted_segments`.

* `cl_store_new(m)` clamps `m >= 1`. `cl_store_append(st, time_ms, nbytes)`
  rejects `nbytes <= 0` (-1). The newest live segment is the unique state-1
  (open) segment; if none exists or its `events >= seg_max_events`, it is
  sealed and a new open segment is pushed. The event updates `to_off =
  next_off + nbytes`, `to_time`, `bytes`, `events`, then advances `next_off`
  and the totals; a segment that reaches `seg_max_events` is sealed
  immediately. Offsets are monotonic and never reused.
* `cl_store_seal` seals the open segment and returns its index (-1 when
  none). Segment accessors return raw per-slot stats regardless of state,
  with documented zero/-1 defaults for out-of-range indices.
* Retention (`cl_store_apply_retention`) applies policies in the fixed order
  bytes (1), age (2), segments (3), events (4); each stage is skipped when
  its policy value is `<= 0` and loops while the condition holds:
  `total_bytes > max_bytes`; `now_ms - oldest_live_to_time > max_age_ms`
  (a whole segment must be older than the window); `live_count >
  max_segments`; `total_events > max_events`. The newest live segment is
  never dropped (`live_count > 1` guard). Returns the per-call drop counts
  (segment/byte/event deltas), the first stage that dropped something as
  `reason` (0 none), and the oldest surviving `from_off`/`from_time`.
  Dropped segments become state 0 and their bytes/events leave the totals
  into the dropped counters.
* Compaction (`cl_store_compact`) merges the two oldest live segments
  repeatedly until at most `target` (clamped `>= 1`) remain: the older
  absorbs the newer's `to_off`/`to_time` and sums bytes/events, the newer
  becomes dead, `compacted_segments` increments, and `live_count` drops.
  Totals are unchanged. If the newer was open, the merged survivor becomes
  open. Returns the number of merges. `cl_store_compact_due` is true when
  `compact_at > 0 && live_count > compact_at`.

## 9. Search

`CloudLog` is a parallel-vector table: record `i` has `time[i]`, `level[i]`,
`sev[i]`, `msg[i]`; attributes are flattened into `kname`/`kval`/`krec`
where entry `e` belongs to record `krec[e]`. `cl_log_add` appends a record
and returns its index; `cl_log_add_kv` refuses invalid record indices and
invalid keys.

`CloudPred` is a flat node table: `op` holds the opcode, `left`/`right` the
child slots for AND/OR/NOT, and `num`/`num2`/`text`/`text2` the leaf
operands. Builders append a node and return its slot; AND/OR/NOT return -1
when a child index is out of range. The root is the most recently pushed
node (search/count use `op.len() - 1`).

`cl_pred_eval(p, l, rec, node)` evaluates explicitly by opcode:

* TRUE/FALSE constants; AND/OR short-circuit over child slots (recursive);
  NOT negates its child.
* level equals (`num`), severity >= (`num`), time in inclusive
  `[num, num2]`.
* message contains: byte-wise substring; an empty needle matches every
  record; a UTF-8 needle matches byte-exact.
* attribute key=value: first exact-key entry on the record compared with
  `str_compare` on both name and value.

Out-of-range nodes, records and mismatched parallel vectors evaluate false
rather than crashing.

`cl_search(l, p, from_time, to_time, start, limit)` scans records in index
order and considers a record only when its time is in the inclusive range
(`from_time > to_time` yields an empty page). `start` is clamped to `>= 0`
and is the 0-based ordinal of the first wanted match; `limit` is the page
size. The result carries:

* `hits`: matching record indices for ordinals `[start, start + limit)`;
* `count`: page size (0 when `limit <= 0`);
* `matched_total`: all matches in the time range (independent of
  `start`/`limit`);
* `next_start`: `start + count` when further matches exist, `start` while
  `limit <= 0` and matches remain, else -1 (pagination is exhausted);
* `scanned`: the record count.

`cl_search_count` returns `matched_total` without building a page.

## 10. Determinism and complexity

* No hidden state, clock, RNG or I/O: identical inputs give identical
  outputs, and repeated whole-pipeline runs are byte-identical (test 27).
* Scans are index-ordered; policies and precedence orders are fixed; the
  newest store segment is never dropped; tail checkpoints are monotonic.
* The sequence-watermark advance is O(n) per accept in the worst case
  (bounded by the buffered count); store compaction is O(segments^2) in the
  worst case; search is O(records) per predicate leaf with a naive O(n*m)
  substring test. All loops are bounded by input sizes.

## 11. Conformance mapping

| test | covers |
|---|---|
| t1 | level/severity names, codes, bounds |
| t2 | event construction, attributes, lookups |
| t3-t6 | key=value encode/round-trip/errors/bare values |
| t7-t10 | JSON encode/escapes/errors/types |
| t11-t12 | ingest in-order accept, gaps, duplicates, empty rejects |
| t13-t14 | flush policies and precedence, explicit flush reset |
| t15 | stream append, slicing, framing rejects |
| t16-t18 | tail read/commit, retention floor/truncation, replay |
| t19-t20 | store rolling, states, per-segment stats, sealing |
| t21-t23 | retention bytes/age/segments/events, compaction |
| t24 | predicate tree evaluation |
| t25 | search pagination, totals, time boundaries |
| t26 | end-to-end pipeline |
| t27 | determinism replay |
