# xiom.elastic -- Specification

Version 0.1.0. Pure, deterministic Elasticsearch client **model** (no HTTP).

## 1. Scope

This module models Elasticsearch request/response *data* and framing:

1. the query DSL subset and its JSON serializer;
2. request envelopes (search, index, scroll) and bulk NDJSON framing;
3. the response envelope subset parser;
4. mapping, index settings and bounded scroll/pagination state.

Non-goals: sockets/HTTP, retries, auth, TLS, connection pools, a full JSON
parser or DOM, index-cluster administration, and validating a query against a
live cluster.

## 2. Query DSL subset

Kinds (`QE_KIND_*`): `MATCH`, `TERM`, `TERMS`, `RANGE`, `BOOL`, `EXISTS`,
`NESTED`. Bool categories (`QE_BOOL_*`): `MUST`, `FILTER`, `MUST_NOT`,
`SHOULD`.

Arena `QEQuery` holds parallel rows (`kinds`, `fields`, `values`, `froms`,
`tos`, `inc_lo`, `inc_hi`, `children`); bool and terms children are
`(owner, child)` pairs in their own parallel vectors. Every base row is pushed
together by the single `_q_push`; `elastic_query_consistent` returns false if
any pair drifts.

Serialization is deterministic and pretty-print-free:

| Node | Output |
| --- | --- |
| match | `{"match":{"<field>":{"query":"<value>"}}}` |
| term | `{"term":{"<field>":{"value":"<value>"}}}` |
| terms | `{"terms":{"<field>":["v1","v2"]}}` |
| range | `{"range":{"<field>":{"gte":"10","lte":"20"}}}` |
| bool | `{"bool":{"must":[...],"filter":[...],"must_not":[...],"should":[...]}}` |
| exists | `{"exists":{"field":"<field>"}}` |
| nested | `{"nested":{"path":"<path>","query":<child>}}` |

Range uses `gte`/`lte` when `inc_lo`/`inc_hi` is 1 and `gt`/`lt` otherwise;
an empty `from`/`to` is omitted and both empty yields `{}`. Bool emits only
non-empty categories, in the fixed order must, filter, must_not, should. An
out-of-range or unknown node serializes as `{}`.

String fields and values are JSON-escaped (`"`, `\`, LF, CR, TAB, and control
bytes below 0x20 as `\u00xx`).

## 3. Request builders and bulk framing

* `elastic_search_body(q, node)` -> `{"query":<node>}`.
* `elastic_search_request(index, q, node)` ->
  `{"method":"POST","path":"/<index>/_search","body":<body>}`.
* `elastic_index_request(index, id, doc)` -> `PUT /<index>/_doc/<id>` when
  `id` is non-empty, else `POST /<index>/_doc`; `doc` is embedded verbatim.
* `elastic_scroll_request(id, size)` ->
  `{"method":"POST","path":"/_search/scroll","body":{"scroll":"30s","scroll_id":"<id>","size":N}}`.
* `elastic_bulk_index_action(index, id)` -> one bulk action line.
* `elastic_bulk_frame(action, source)` -> `action + "\n" + source + "\n"`
  (two NDJSON lines). `elastic_ndjson_line_count` counts `\n`;
  `elastic_ndjson_wellformed` requires a trailing `\n`.

## 4. Response envelope subset

`elastic_parse_response(text) -> Result[EResponse, Str]`.

* **Ok**: `text` begins (after ASCII whitespace) with `{`. The parser reads,
  when present: top-level `took` (Int), `timed_out` (Bool), then inside
  `hits`: `total` (either the legacy numeric form or the object
  `{"value":N,"relation":"..."}`) and the `hits` array, recording each hit's
  `_source` value span. It then reads `aggregations` as first-seen
  `name -> value` numeric pairs (the `value` sub-field of each aggregation
  object).
* **Err**: input is empty or does not begin with `{`. Error:
  `elastic: response must be a JSON object`.

Accessors: `elastic_response_took`, `elastic_response_timed_out`,
`elastic_response_total`, `elastic_response_total_relation`,
`elastic_response_hit_count`, `elastic_response_source_count`,
`elastic_response_source(text, r, i)` (raw `_source` slice),
`elastic_response_agg_count/name/value`.

### Error cases and limits

The parser is a **subset** scanner, not a validator: it does not verify the
full JSON grammar, duplicate keys, or numeric syntax beyond leading digits.
It never aborts: malformed internals degrade to 0 / "" / no spans. Only the
top-level non-object case is an explicit `Err`.

## 5. Mapping model

`EMapping` is parallel `names: Vec[Str]` / `types: Vec[Int]`. Type codes
(`QE_MT_*`): `TEXT`, `KEYWORD`, `LONG`, `INTEGER`, `DOUBLE`, `BOOLEAN`,
`DATE`, `OBJECT`, `NESTED`; `elastic_mapping_type_name` returns their
Elasticsearch names. `elastic_mapping_add` overwrites an existing field and
appends otherwise (no duplicates). `elastic_mapping_to_json` emits
`{"properties":{"<name>":{"type":"<type>"},...}}` in insertion order.

## 6. Index settings model

`EIndexSettings { shards; replicas; refresh }`, default `1 / 1 / "1s"`.
`elastic_settings_to_json` emits
`{"index":{"number_of_shards":N,"number_of_replicas":N,"refresh_interval":"..."}}`.

## 7. Scroll and bounded pagination

`EScroll` tracks `scroll_id`, `size`, `page`, `seen`, `max_pages`, `done`
and a diagnostic `ids` list. `max_pages <= 0` is clamped to 1.
`elastic_scroll_advance(s, hits)` increments the page and seen count; it
latches `done` when the page cap is reached or `hits <= 0`, returning true
only while a further page remains. `elastic_page_count(total, size)` uses the
truncation-safe ceil form and returns 0 for non-positive inputs.

## 8. Determinism

All functions are pure and IO-free. The same inputs always produce identical
output strings and state transitions.

## 9. Compiler notes

Written for XIOM 0.62.2: free functions only; no `Vec[StructType]`
(parallel vectors instead); bytes widened with `(byte_at(..) as Int) & 0xFF`;
Str comparisons via `str_compare`; `Ok`/`Err` only in the leaf helpers
`_resp_ok`/`_resp_err`; scan loops are bounded by the input length; the
serializer uses Str concatenation rather than a `&mut Vec[UInt8]` builder.
