# xiom.query -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI. All functions are free
functions; the module depends on `xiom.string` from `xiom.std` only.

## 1. Model

A **record** is a flat pair of parallel vectors: `keys[i]` names the cell
`values[i]`. A **query** is a conjunction/disjunction chain of **terms**, each
`field op value`. `query_parse` turns expression text into `Query`:

```
Query = {
  fields: Vec[Str];   // term i's field name
  ops:    Vec[Str];   // term i's operator
  values: Vec[Str];   // term i's right-hand value
  joins:  Vec[Str];   // connector BEFORE term i: "and"/"or"; joins[0] == ""
}
```

All four vectors have the same length and stay parallel; `query_parse` is the
only producer in this package and maintains that invariant. `joins[i]` is
stored lowercased; `query_to_string` renders the canonical uppercase form.

Text is byte-oriented throughout: `xiom.string.byte_at` reads raw bytes and
all comparisons are byte-wise.

## 2. Grammar and tokenization

```
expr      := term (connector term)*
term      := field op value
connector := "AND" | "OR"                (ASCII case-insensitive)
op        := "=" | "!=" | "<" | "<=" | ">" | ">="
           | "contains" | "startswith" | "endswith"   (case-sensitive)
value     := token
field     := token
token     := quoted | bare
quoted    := '"' bytes* '"' | "'" bytes* "'"
bare      := any run of bytes containing no ASCII whitespace
```

Rules:

1. Tokens are separated by one or more ASCII whitespace bytes: space (32),
   tab (9), LF (10) and CR (13). Newlines therefore act as separators.
2. A token starting with `"` or `'` is **quoted**: it runs to the next
   matching quote byte and may contain whitespace; there are no escape
   sequences, and the quotes are stripped. A quoted token with no closing
   quote is `Err("query: unterminated quote")`.
3. Any other token is **bare**: it runs to the next whitespace byte. Quote
   bytes inside a bare token are literal, so `nick = it's` and `x = a"b`
   parse as single tokens.
4. The expression must start with a term. A first token equal
   (case-insensitively) to `and`/`or` is an error, so `AND a = b` is
   rejected.
5. A term consumes exactly three tokens: field, operator, value, in that
   order. Operators are matched case-sensitively (`CONTAINS` is unknown).
   The field must not be empty (an empty quoted field `"" = x` is an error);
   an empty *value* is allowed only when quoted: `note = ""`.
6. A connector must appear between two terms; anything else after a complete
   term is `Err("query: expected connector, got: <token>")`. A connector with
   no following term is `Err("query: expected term after connector")`.

## 3. Evaluation rules

### 3.1 `query_match_one(op, left, right)`

Let `numeric(s)` be: optional leading `+`/`-`, then one or more ASCII digits,
then end; and the magnitude must fit a signed 64-bit integer
(`<= 2^63 - 1`). Leading zeros are allowed and fold (`010` = `10`); `+` and
`-0` fold (`+5` = `5`, `-0` = `0`); `-9223372036854775808` is **not** numeric
because the magnitude `2^63` exceeds the check. Nothing wraps.

- `=`, `!=`, `<`, `<=`, `>`, `>=`: when both sides are numeric the comparison
  is integer; otherwise it is byte-wise lexicographic via
  `xiom.string.str_compare` (`< 0` / `== 0` / `> 0`).
- `contains`, `startswith`, `endswith`: byte-wise substring tests
  (`str_contains`, `str_starts_with`, `str_ends_with`). The empty needle is
  found in every string (the `contains` case is guarded because the stdlib
  helper requires a non-empty needle).
- Any other operator: `false` (defensive; `query_parse` never produces one).

### 3.2 `query_matches(q, keys, values)`

Terms are evaluated independently against the record, then folded **strictly
left to right with no precedence**:

```
result := term(0)
for i = 1 .. n-1:
    result := result AND term(i)    if joins[i] == "and"
    result := result OR  term(i)    if joins[i] == "or"
```

So `a = 1 OR b = 2 AND c = 3` means `((a = 1 OR b = 2) AND c = 3)` -- this
deliberately differs from the usual AND-over-OR precedence and is pinned by a
test. There is no short-circuit: every term is evaluated.

Field lookup:

1. Scan `keys` left to right; the **first** `keys[j]` byte-equal to the
   term's field is the match. Duplicate keys are not merged.
2. If `j >= values.len()` (no parallel cell) or no key matches, the field is
   **missing**. A missing field makes the term `false` for every operator
   except `!=`, which is `true`.
3. Otherwise the term is `query_match_one(op, values[j], q.values[i])`.

A query with zero terms matches everything (`true`); `query_parse` never
produces one, but a hand-built `Query` with empty vectors does.

### 3.3 `query_select(headers, rows, q)`

For each row `r` (in order): the record is `keys = headers[0 .. min(width,
headers.len())]`, `values = rows[r][0 .. that length]`, where `width =
rows[r].len()`. The row matches when `query_matches` accepts it. Matched rows
are appended unchanged: all original cells are preserved, including cells
beyond `headers.len()` (they are not matchable) and excluding nothing. A row
shorter than `headers` simply has missing trailing fields. The result keeps
the original row order and content; the input vectors are not modified.

## 4. API contracts

| Function | Returns | Failure | Complexity |
|---|---|---|---|
| `query_parse(expr)` | `Result[Query, Str]` | `Err("query: ...")` per section 5 | `O(len(expr))` |
| `query_term_count(q)` | `Int` | never | `O(1)` |
| `query_to_string(q)` | `Str` | never | `O(total text)` |
| `query_match_one(op, left, right)` | `Bool` | never (unknown op -> false) | `O(|left| + |right|)` |
| `query_matches(q, keys, values)` | `Bool` | never | `O(terms * keys * cell length)` |
| `query_select(headers, rows, q)` | `Vec[Vec[Str]]` | never | `O(rows * terms * columns * cell length)` |

`query_to_string` is canonical: terms are joined with `" AND "` / `" OR "`;
fields and operators are emitted verbatim; a value is emitted bare unless it
is empty, contains whitespace, or starts with a quote byte. A value that
contains a `"` but no `'` is single-quoted; every other quoted value uses
double quotes. Values containing both quote bytes are emitted in double
quotes and may not re-parse (no escape syntax exists); everything else
re-parses to the same query.

## 5. Error catalog

All parse errors are `Err` with a message prefixed `query: `.

| Condition | Message |
|---|---|
| input is empty or whitespace-only | `query: empty expression` |
| first token is `and`/`or` (any case) | `query: expression must start with a term` |
| fewer than 3 tokens remain for a term (e.g. `a`, `a =`) | `query: incomplete term` |
| a term's field token is empty (e.g. `"" = x`) | `query: empty field name` |
| operator token not in the set (case-sensitive) | `query: unknown operator: <op>` |
| token after a complete term is not `and`/`or` | `query: expected connector, got: <token>` |
| `and`/`or` with no following term | `query: expected term after connector` |
| a quoted token has no closing quote | `query: unterminated quote` |

Validation walks left to right and the first error wins. Examples from the
suite: `a = b AND` -> expected term after connector; `a ~ b` -> unknown
operator: `~`; `a CONTAINS b` -> unknown operator: `CONTAINS`; `a = b c = d`
-> expected connector, got: `c`.

## 6. Test plan (tests/test_conformance.xi, 22 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | parse `=` | term triple and `query_term_count == 1` |
| t2 | parse `!=` | term triple, one term |
| t3 | parse `<`, `<=` | term triples |
| t4 | parse `>`, `>=` | term triples |
| t5 | parse word ops | `contains`/`startswith`/`endswith` triples (value `or` is not a connector) |
| t6 | quoted values | `"New York"`, `'Los Angeles'`, empty `""`, quoted field with a space, bare `it's` |
| t7 | connectors | lowercase/mixed-case AND/OR, `joins` == `["", "and", "or"]`, 3 terms |
| t8 | malformed 1 | trailing connector, `a =`, `a`, `~`, `CONTAINS` |
| t9 | malformed 2 | empty, whitespace-only, unterminated quote, leading connector, missing connector, empty field |
| t10 | to_string | canonical spacing, uppercase connectors, left-to-right order kept |
| t11 | to_string round trip | single-quoted spaces become double quotes; canonical text re-parses to the same term; value with an embedded `"` keeps single quotes |
| t12 | numeric match | `10 > 9`, `9 < 10`, `10 != 9`, `10 = 010`, `+5 = 5`, `-0 = 0` |
| t13 | byte-wise match | equality, case sensitivity, `<`/`>`/`<=`/`>=`/`!=`, prefix ordering |
| t14 | numeric vs lexical | `5 < +3` is false (numeric), `2 > 10` false, 2^63 magnitude not numeric (no wrap), negative numeric order, mixed sides byte-wise |
| t15 | substring ops | contains/startswith/endswith hits and misses, empty needle matches, longer needle misses |
| t16 | unknown op / empty query | `~` false, `CONTAINS` false, zero-term query matches everything and stringifies to `""` |
| t17 | query_matches | AND/OR over `name/age/city` record, numeric `age >= 30` |
| t18 | missing field | false for `=`, `<`, `contains`; true for `!=`; OR with a present field |
| t19 | left-to-right | `a = 1 OR b = 2 AND c = 3` false where precedence would be true; reverse case true where precedence would be false |
| t20 | select | 4 rows, `age >= 30 AND city = NYC` -> 2 rows in original order (`alice`, `carol`), no-match -> 0 |
| t21 | select edges | empty rows, ragged row (missing field semantics), extra cells preserved |
| t22 | select numeric | `score >= 10` selects `10`/`100`, not `9` (numeric, not lexical) |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## 7. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`
  (a scalar `Query` is passed by reference; only `Vec[Str]` and
  `Vec[Vec[Str]]` containers are used).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_query`,
  `_err_query`, `_ok_tokens`, `_err_tokens`; direct construction in a
  function that also returns a struct value miscompiles.
- `Str` values read from `Vec[Str]` elements are never compared with `==`;
  equality goes through `_streq` / `compare.str_compare`, and element reads
  are bound to typed locals (`let f: Str = q.fields[i];`).
- Byte classification uses `xiom.string.byte_at` against ASCII constants below
  128; integer arithmetic casts `(b as Int)` explicitly (byte widening).
- `Vec[Int]` reads are bound with typed locals; `Vec[Vec[Str]]` cells are read
  as `rows[r][c]` into a typed `Str` local.
- Matches over `Result`/`Option` are exhaustive (`Ok`/`Err`, `Some`/`None`);
  no `mut` patterns.
- `use` statements end with `;`, `module` does not.
- A reference-typed local passed to another `&`-parameter is re-referenced
  with an explicit `&` (`query_matches(&q, ...)` in `query_select`; the tests
  call `query_matches(&q, &keys, &values)` and
  `query_select(&headers, &rows, &q)`). A bare reference argument to a
  reference parameter miscompiles on v0.61.3: the callee reads a clobbered
  slot and the returned rows have zeroed headers (observed as
  `port: FAIL ... program_exit=-1073741819` before the fix).

## 8. Known limitations

- No parentheses, no precedence, no short-circuit evaluation: strictly
  left-to-right folding (section 3.2).
- Flat records only: string keys, string values, first-key-wins lookup;
  no nested paths, arrays, nulls, ordering or grouping, and no query
  planning/indexes (`query_select` is a linear scan).
- Operators are case-sensitive words or ASCII symbols; there are no
  `in`/`regex`/`like` operators, no negation as an operator, and no `(` `)`.
- Integer comparisons use `Int64`; magnitudes above `2^63 - 1` fall back to
  byte-wise comparison rather than reporting an error. No floats, dates or
  currencies -- values are opaque strings outside the integer fast path.
- Byte-wise text comparisons: no case folding, no Unicode collation, no
  locale awareness. Case-insensitivity applies only to the `AND`/`OR`
  connector words.
- Canonical text cannot represent values that contain both quote bytes
  (no escape sequences), and hand-built `Query` values must keep the four
  vectors parallel.
