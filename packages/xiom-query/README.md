# xiom.query

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Simple filter expressions over flat key/value records with AND/OR
> connectors.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_compare`,
> `xiom.string.byte_at`, `xiom.string.str_slice`, `xiom.string.str_contains`,
> `xiom.string.str_starts_with` and `xiom.string.str_ends_with`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.query` turns a small filter language into a `Query` value and evaluates
it against flat records: a list of keys and a parallel list of values (a CSV
row with its header, a config's key/value pairs, ...). Expressions look like:

```
age >= 30 AND city = "New York" OR nick = it's
```

- **Terms** are `field op value` with whitespace-separated tokens.
- **Operators:** `=`, `!=`, `<`, `<=`, `>`, `>=`, `contains`, `startswith`,
  `endswith`. The symbolic comparisons are numeric when both sides parse as
  integers, byte-wise otherwise; the word operators are always byte-wise
  substring tests.
- **Connectors:** `AND` / `OR`, case-insensitive, between terms.
- **Values** may be quoted with `"` or `'` to contain spaces; a quote byte is
  only special at the start of a token (`nick = it's` works bare).
- There are **no parentheses** and **no precedence**: `query_matches` folds
  the terms strictly left to right with the connectors the expression wrote.

## API

| Function | Returns | Description |
|---|---|---|
| `query_parse(expr)` | `Result[Query, Str]` | Parse a filter expression into `Query` (parallel `fields`/`ops`/`values`/`joins` vectors; `joins[i]` is `"and"`/`"or"` before term `i`, `joins[0]` is `""`). `Err("query: ...")` on malformed input. |
| `query_term_count(q)` | `Int` | Number of terms (`q.fields.len()`); 0 for a hand-built empty query. |
| `query_to_string(q)` | `Str` | Canonical text `field op value [AND field op value]`; connectors uppercase, values quoted only when needed. |
| `query_match_one(op, left, right)` | `Bool` | Evaluate one term; integers compare numerically when both sides parse within `Int64`, else byte-wise via `str_compare`; substring ops on bytes; unknown operator is false. |
| `query_matches(q, keys, values)` | `Bool` | Evaluate a whole query against one flat record, strictly left to right; a missing field is false except for `!=` (true). |
| `query_select(headers, rows, q)` | `Vec[Vec[Str]]` | The rows whose cell map matches, in original order; ragged rows lack their trailing fields; cells beyond `headers` are preserved but not matched. |

## Grammar

```
expr      := term (connector term)*
term      := field op value              (whitespace-separated tokens)
connector := "AND" | "OR"                (any case mix)
op        := "=" | "!=" | "<" | "<=" | ">" | ">="
           | "contains" | "startswith" | "endswith"   (case-sensitive)
token     := quoted | bare
quoted    := '"' bytes* '"' | "'" bytes* "'"          (no escapes)
bare      := any run of bytes that contains no ASCII whitespace
             (space, tab, CR, LF); quote bytes are allowed inside
```

The expression must start with a term (a leading connector is an error) and
every connector must be followed by a term. Empty input parses to
`Err("query: empty expression")`.

## Usage

```xi
use xiom.query;
use xiom.io;

fn main() -> Int {
  let r = query_parse("age >= 30 AND city = \"New York\"");
  match r {
    Ok(q) => {
      io.println(query_to_string(&q));   // age >= 30 AND city = "New York"
      var keys = Vec[Str].new();
      keys.push("age"); keys.push("city");
      var vals = Vec[Str].new();
      vals.push("30"); vals.push("New York");
      if query_matches(&q, &keys, &vals) { io.println("match"); }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.query
```

Expected tail: 22 `[PASS]` lines, `xiom.query: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No parentheses and no precedence:** evaluation is strictly left to right;
  `a = 1 OR b = 2 AND c = 3` means `((a = 1 OR b = 2) AND c = 3)`, which
  differs from the usual AND-over-OR reading. Add terms in the intended order.
- **Flat records only:** evaluation is a linear scan over `(key, value)`
  pairs; there are no nested fields (`address.city`), arrays, nulls or joins.
  The first key equal to the field wins; duplicate keys are not merged.
- **Missing fields:** a term whose field is absent is false for every
  operator except `!=` (which is true). A key without a parallel value counts
  as missing.
- **Integer model:** `Int64` only; a side "is an integer" when it is an
  optional `+`/`-` sign followed by digits, with magnitude `<= 2^63 - 1`
  (so `-9223372036854775808` is *not* numeric and compares byte-wise). Leading
  zeros fold (`010` = `10`); comparisons never wrap.
- **Byte-wise text:** substring and non-numeric comparisons are byte-wise
  (case-sensitive, no Unicode collation); `contains`/`startswith`/`endswith`
  with an empty needle match everything.
- **Canonical text:** `query_to_string` quotes values containing whitespace or
  starting with a quote, preferring single quotes for values with embedded
  `"`. A value containing *both* quote bytes is emitted in double quotes and
  may not re-parse (the language has no escape sequences).
- Compiler note: `Ok`/`Err` are constructed only in the leaf helpers
  `_ok_*`/`_err_*` (v0.61.3 miscompiles inline `Result` construction in
  struct-returning functions); `Str` equality always goes through
  `xiom.string.str_compare` (BUG 17 family); reference arguments are
  re-referenced explicitly (`&param`) -- a bare reference-typed local passed
  to a `&`-parameter miscompiles.

See `SPEC.md` for the exact grammar, evaluation rules, error catalog and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
