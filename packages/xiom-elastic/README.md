# xiom.elastic

A **pure** Elasticsearch client *model* for XIOM: it builds query-DSL clauses,
request envelopes and bulk NDJSON, parses the response envelope subset, and
models mappings, index settings and bounded scroll state. It contains **no
HTTP and no transport** -- callers own the network layer.

## What is in scope

| Area | API |
| --- | --- |
| Query DSL | `elastic_match`, `elastic_term`, `elastic_terms` + `elastic_terms_add`, `elastic_range`, `elastic_bool` + `elastic_bool_must/filter/must_not/should`, `elastic_exists`, `elastic_nested` |
| Query serialization | `elastic_query_to_json`, `elastic_search_body`, `elastic_query_kind`, `elastic_query_field`, `elastic_query_value`, `elastic_query_kind_name` |
| Requests | `elastic_search_request`, `elastic_index_request`, `elastic_scroll_request`, `elastic_bulk_index_action`, `elastic_bulk_frame`, `elastic_ndjson_line_count`, `elastic_ndjson_wellformed` |
| Response subset | `elastic_parse_response` -> `EResponse` (`took`, `timed_out`, `hits.total`, hit count, raw `_source` spans, aggregations subset) |
| Mapping | `elastic_mapping_new`, `elastic_mapping_add`, `elastic_mapping_field_type`, `elastic_mapping_type_name`, `elastic_mapping_to_json` |
| Settings | `elastic_settings_new`, setters, `elastic_settings_to_json` |
| Paging | `elastic_scroll_new`, `elastic_scroll_advance`, `elastic_scroll_done`, `elastic_scroll_next_request`, `elastic_page_count` |

## Model shape

The query DSL is a flat arena of parallel `Vec` fields (this compiler has no
`Vec[StructType]`): a node index identifies one clause, bool and terms child
lists are `(owner, child)` pairs. All builders go through a single push site,
so rows cannot drift; `elastic_query_consistent` asserts the invariant.
Serialization is deterministic (fixed key order).

`elastic_parse_response` scans the JSON linearly with a hand-rolled flat
scanner (no DOM). It reads only the envelope fields and records each hit's
`_source` as a byte span into the original text; `elastic_response_source`
slices it on demand. Aggregations are read as first-seen `name -> numeric
value` pairs. Input that is not a JSON object is rejected with `Err`.

## Dependency

`xiom.std` only (`xiom.string`, `xiom.string.compare`, `xiom.convert`).

## Example

```xiom
use xiom.elastic;

fn build() -> Str {
  var q = elastic_query_new();
  let title = elastic_match(&mut q, "title", "rust");
  let year = elastic_range(&mut q, "year", "2020", "", 1, 0);
  let b = elastic_bool(&mut q);
  elastic_bool_must(&mut q, b, title);
  elastic_bool_filter(&mut q, b, year);
  return elastic_search_request("books", &q, b);
}
```

## Tests

```
.\scripts\port.ps1 -Package xiom-elastic -TimeoutSec 60
```

28 inline checks (no external fixtures), deterministic.

## License

MIT OR Apache-2.0.
