# Metadata Filtering

`src/payload/` — attaching metadata to points and filtering search results by
it. SCAFFOLD (Phase 3): the data model and AST are complete and the boolean
combinators evaluate; typed value comparisons are the remaining work.

## Payload model (`payload.xi`)

```
enum FieldValue { IntVal(v), FloatVal(v), TextVal(v), BoolVal(v) }
PayloadField    { key: Str; value: FieldValue }
Payload         { fields: Vec[PayloadField] }
```

A payload is a small set of typed `(key, value)` fields attached to a point.
`FieldValue` is a tagged union so each field carries its own type; `field_value_kind`
reports it as a string. API:

- `payload_new()`, `payload_set(p, key, value)`, `payload_has(p, key)`, `payload_len(p)`.
- TODO(Phase 3): `payload_set` should overwrite an existing key rather than
  append duplicates, and a sorted key index should replace the linear scan.

## Filter AST (`filter_ast.xi`)

```
enum FilterExpr {
  Eq(field, value),
  Range(field, lo, hi),
  Exists(field),
  In(field, values),
  And(clauses),
  Or(clauses),
  Not(clauses),
}
```

`And`/`Or`/`Not` carry their operands in a `Vec[FilterExpr]`. XIOM has no direct
self-referential enum field, so the `Vec` provides the indirection needed for a
recursive tree. `Not` uses a one-element `Vec` (via the `filter_not` constructor).

Constructors: `filter_eq`, `filter_range`, `filter_exists`, `filter_in`,
`filter_and`, `filter_or`, `filter_not`.

Example — `color = "red" AND price ∈ [10, 100]`:

```xiom
var clauses = Vec[FilterExpr].new();
clauses.push(filter_eq("color", FieldValue.TextVal("red")));
clauses.push(filter_range("price", 10.0, 100.0));
var expr = filter_and(clauses);
```

## Evaluation (`filter_eval.xi`)

```
filter_matches(expr: &FilterExpr, p: &Payload) -> Bool
```

| Variant | Status | Behaviour |
|---------|--------|-----------|
| `Exists` | ✅ implemented | true iff the field is present |
| `And` | ✅ implemented | all clauses match (short-circuits false) |
| `Or` | ✅ implemented | any clause matches (short-circuits true) |
| `Not` | ✅ implemented | negation of the single clause |
| `Eq` | 🟠 fail-open | currently only checks field presence |
| `Range` | 🟠 fail-open | currently only checks field presence |
| `In` | 🟠 fail-open | currently only checks field presence |

"Fail-open" means the value predicates don't yet reject on value mismatch — they
pass if the field exists. This lets the search path be wired end-to-end before
typed comparison lands. Each stub carries a `// TODO(Phase 3):` marker.

## Where filtering plugs into search

The query planner (see [`query-execution.md`](query-execution.md)) will apply
`filter_matches` to each candidate's payload. Two strategies, chosen by
selectivity:

- **Pre-filter**: evaluate the filter first, then ANN over the surviving set.
  Best for highly selective filters.
- **Post-filter**: ANN first, then drop non-matching hits (may need a larger
  candidate pool to still return `k`). Best for permissive filters.

`SearchRequest.filter` (in `query/search_request.xi`) carries the expression;
`with_payload` controls whether matched payloads are hydrated onto the returned
hits.
