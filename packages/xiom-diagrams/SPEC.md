# xiom.diagrams -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.diagrams` (`src/diagrams.xi`). Pure XIOM, no FFI, no file I/O.
Text in, text out: `Str` documents and `Str` errors.

## 1. Scope

A parser and a canonical serializer for a Graphviz DOT subset:

- parse `graph` / `digraph` documents (`dot_parse`),
- node statements, edge statements (`->` / `--`), attribute statements and
  bracketed attribute lists,
- quoted strings with a small, fully documented escape set,
- `#` and `//` line comments,
- optional semicolons and empty statements,
- deterministic serialization of the model (`dot_serialize`),
- a builder API for programmatic construction (`dot_new`, `dot_add_node`,
  `dot_add_edge`, `dot_add_attr`, `dot_attr_pair`),
- accessors for the flat model (`dot_stmt_count`, `dot_stmt_kind`,
  `dot_stmt_id`, `dot_stmt_target`, `dot_stmt_attrs`, `dot_node_count`,
  `dot_edge_count`, `dot_attr_count`, `dot_name`, `dot_is_directed`,
  `dot_is_consistent`),
- attribute lookup inside a canonical body (`dot_attr_get`),
- string escaping (`dot_escape`, `dot_unescape`) and error-code extraction
  (`dot_error_code`).

The parser is syntactic, not semantic: it does not build a graph-theoretic
model (no node table, no deduplication, no reachability), does not resolve
`node [..]` / `edge [..]` / `graph [..]` default-attribute statements (they
parse as node statements named `node`, `edge`, `graph` and round-trip
verbatim), and does not render images.

## 2. Non-goals

- No subgraphs, `subgraph` / `cluster` keywords, or nested braces.
- No ports (`a:port`), compass points (`n`, `se`, ...), or `@` attrs.
- No HTML-like strings (`<...>`), no multi-line concatenated strings with `+`.
- No edge direction relative to `rankdir`, no layout, no coordinate geometry.
- No `strict` modifier, no `node`/`edge`/`graph` default semantics.
- No numbers with leading `-` as unquoted identifiers (write `"‑1"` quoted or
  a bare digit run); unquoted identifiers are `[A-Za-z0-9_]+`.
- No `/* ... */` comments (only `#` and `//`).
- No NUL bytes anywhere in the input (see section 9).
- No file I/O, no FFI, no registry integration.

## 3. Grammar

```
document  = ws* ( "graph" | "digraph" ) ws* name? ws* "{" body "}" ws* EOF
name      = id | string
body      = ( ";" | stmt ";"? )*                 // semicolons optional
stmt      = attr_stmt | edge_stmt | node_stmt
attr_stmt = id ws* "=" ws* value
edge_stmt = id ( ws* edgeop ws* value )+ attr_list?
node_stmt = id attr_list?
attr_list = "[" ws* "]"
          | "[" ws* pair ( ws* ( "," | ";" ) ws* pair )* ws* ( "," | ";" )? ws* "]"
pair      = ( id | string ) ws* "=" ws* value
value     = id | string
edgeop    = "->" | "--"
id        = [A-Za-z0-9_]+
string    = '"' ( "\" | "\\" | "\n" | "\t" | "\r" | byte )* '"'
comment   = ( "#" | "//" ) *( byte except LF )   // outside strings
ws        = SP | TAB | CR | LF
```

Notes:

- `body` is `( ";" | stmt ";"? )*`: a `;` after a statement is optional, and
  bare `;` statements are allowed and ignored.
- Comments behave as whitespace at any point between tokens; inside a quoted
  string `#` and `//` are data.
- A quoted string may span lines (a raw LF inside it is part of the value and
  serializes back as `\n`).
- An `edge_stmt` is a chain: `a -> b -> c [x=1]` becomes two edges `a -> b`
  and `b -> c`, both carrying `x=1`. Mixed operators in one chain are
  rejected with `E_EDGE_OP_MISMATCH` (`->` requires `digraph`, `--` requires
  `graph`).
- `value` in `edge_stmt` may be an `id` or a `string`.

## 4. Model and canonical form

```xi
pub type DotGraph = {
  directed: Bool;
  name: Str;
  stmt_kind: Vec[Int];
  stmt_id: Vec[Str];
  stmt_target: Vec[Str];
  stmt_attrs: Vec[Str];
}
```

The four vectors are index-aligned, one entry per statement
(`Vec[StructType]` is unsupported in this compiler, so the model is flat):

| kind | statement | `stmt_id` | `stmt_target` | `stmt_attrs` |
|---|---|---|---|---|
| 0 | node | node id | `""` | attribute body |
| 1 | edge | tail id | head id | attribute body |
| 2 | attr (`k = v`) | key | value | `""` |

All three text vectors store **canonical DOT text**, produced by applying
`dot_escape`-based quoting exactly once:

- a text that is a non-empty run of `[A-Za-z0-9_]` is stored bare;
- every other text (including `""` and anything with a space, quote,
  backslash, newline, `#`, or non-ASCII byte) is stored as a quoted string
  with `"` -> `\"`, `\` -> `\\`, LF -> `\n`, TAB -> `\t`, CR -> `\r`.

The attribute body of a node/edge is canonical too: pairs joined with `", "`,
keys and values quoted only when needed, no brackets (e.g.
`label="a b", shape=box`). `dot_attr_pair` builds one such pair.

The add functions (`dot_add_node`, `dot_add_edge`, `dot_add_attr`) take **raw**
text and apply canonicalization; the parse path stores raw text internally and
canonicalizes through the same functions. The accessors return canonical text
(as stored), so `dot_stmt_id` on `"node one" -> n2` returns `"node one"` with
its quotes.

Documented normalizations (parse -> serialize is not byte-identical for these,
but canonical and idempotent):

1. Edge chains expand to one edge per adjacent pair; attributes replicate.
2. `[]` (empty attribute list) is dropped; the statement serializes without it.
3. Attribute separators `,` and `;` become `, `.
4. Needless quotes are removed (`"a"` -> `a`); required quotes are re-added.
5. Comments, whitespace and statement separators are not preserved; statement
   order is.
6. Every statement is terminated with `;` in the output.

## 5. Escaping

`dot_escape(s)` maps exactly five bytes and passes every other byte
(including multi-byte UTF-8 and control bytes) through unchanged:

| Input | Output |
|---|---|
| `"` (34) | `\"` |
| `\` (92) | `\\` |
| LF (10) | `\n` |
| TAB (9) | `\t` |
| CR (13) | `\r` |

`dot_unescape(s)` is the inverse: it accepts exactly those five escapes and
returns `Err("E_BAD_ESCAPE@<line>:<col>")` at the first backslash that is not
followed by one of `" \ n t r` (a trailing backslash at end of input
included). It rejects a raw NUL byte with `Err("E_BAD_CHAR@<line>:<col>")`.
Inside the parser's quoted strings the same five escapes are recognized and an
unknown escape is `E_BAD_ESCAPE` at the backslash.

The parser additionally rejects a raw NUL byte in a string with `E_BAD_CHAR`;
all other bytes (UTF-8 included) are data.

## 6. Error catalog

Every parse / lookup error is a `Str` of the form `CODE@line:col` (1-based,
columns in bytes). `dot_error_code(msg)` returns the part before the first
`@`. Positions:

- lexical errors: the offending byte; `E_UNTERMINATED_STRING` points at the
  opening quote; `E_BAD_ESCAPE` at the backslash;
- EOF errors (`E_EXPECTED_RBRACE`, `E_EMPTY_INPUT`, `E_TRAILING_INPUT` is not
  an EOF error): the end-of-input position;
- token errors: the start of the offending token.

| Code | Meaning | Position |
|---|---|---|
| `E_EMPTY_INPUT` | input is empty or only whitespace/comments | EOF |
| `E_EXPECTED_GRAPH_KEYWORD` | first token is not `graph` / `digraph` | token |
| `E_EXPECTED_LBRACE` | `{` missing after keyword/name | token |
| `E_EXPECTED_RBRACE` | EOF before `}` | EOF |
| `E_UNEXPECTED_TOKEN` | token cannot start a statement | token |
| `E_EXPECTED_STMT_END` | after an id, expected `=`, `->`, `--`, `[`, `;`, `}` | token |
| `E_EXPECTED_EDGE_TARGET` | an edge operand is missing | token |
| `E_EDGE_OP_MISMATCH` | `->` in a `graph` or `--` in a `digraph` | operator |
| `E_EXPECTED_ATTR_KEY` | attribute key missing in a list | token |
| `E_EXPECTED_EQUALS` | `=` missing after a key | token |
| `E_EXPECTED_ATTR_VALUE` | attribute value missing after `=` | token |
| `E_EXPECTED_ATTR_SEP` | expected `,`, `;` or `]` after a value | token |
| `E_UNTERMINATED_STRING` | quoted string reaches EOF | opening quote |
| `E_BAD_ESCAPE` | unknown / trailing backslash escape | backslash |
| `E_BAD_CHAR` | raw NUL byte | the byte |
| `E_UNEXPECTED_CHAR` | byte that cannot start any token | the byte |
| `E_TRAILING_INPUT` | non-comment input after `}` | token |
| `E_ATTR_BODY` | `dot_attr_get` body does not start a pair | token |
| `E_ATTR_NOT_FOUND` | `dot_attr_get` key absent | no position |
| `E_INTERNAL` | parallel-vector guard tripped (not reachable via the API) | token |

## 7. Serialization layout

`dot_serialize(g)` returns, with LF separators and **no trailing newline**:

```
digraph NAME {
  stmt;
  stmt;
}
```

Equivalently: `("digraph"|"graph") + (" " + name)? + " {" + ("\n  " + stmt +
";") * n + "\n}"`. Statements keep stored order; edge statements use `->` for
directed graphs and `--` for undirected ones. An empty graph is two lines
(`digraph {\n}`). When the parallel vectors have drifted, only the shortest
prefix is serialized (never an out-of-bounds read); unknown kind values render
as node statements.

## 8. API signatures

```xi
pub type DotGraph = {
  directed: Bool; name: Str;
  stmt_kind: Vec[Int]; stmt_id: Vec[Str];
  stmt_target: Vec[Str]; stmt_attrs: Vec[Str];
}

pub fn dot_parse(text: Str) -> Result[DotGraph, Str]
pub fn dot_serialize(g: &DotGraph) -> Str
pub fn dot_new(directed: Bool, name: Str) -> DotGraph
pub fn dot_add_node(g: &mut DotGraph, id: Str, attrs: Str)
pub fn dot_add_edge(g: &mut DotGraph, from: Str, to: Str, attrs: Str)
pub fn dot_add_attr(g: &mut DotGraph, key: Str, value: Str)
pub fn dot_attr_pair(key: Str, value: Str) -> Str
pub fn dot_escape(s: Str) -> Str
pub fn dot_unescape(s: Str) -> Result[Str, Str]
pub fn dot_attr_get(body: Str, key: Str) -> Result[Str, Str]
pub fn dot_error_code(msg: Str) -> Str
pub fn dot_name(g: &DotGraph) -> Str
pub fn dot_is_directed(g: &DotGraph) -> Bool
pub fn dot_is_consistent(g: &DotGraph) -> Bool
pub fn dot_stmt_count(g: &DotGraph) -> Int
pub fn dot_node_count(g: &DotGraph) -> Int
pub fn dot_edge_count(g: &DotGraph) -> Int
pub fn dot_attr_count(g: &DotGraph) -> Int
pub fn dot_stmt_kind(g: &DotGraph, i: Int) -> Int        // -1 out of range
pub fn dot_stmt_id(g: &DotGraph, i: Int) -> Str          // "" out of range
pub fn dot_stmt_target(g: &DotGraph, i: Int) -> Str      // "" out of range
pub fn dot_stmt_attrs(g: &DotGraph, i: Int) -> Str       // "" out of range
```

Complexity: parsing and serialization are linear in the input / output size;
accessors are O(1) except the `_count` helpers (O(statement count)) and
`dot_attr_get` (O(body length)).

## 9. Known limitations

- NUL (`0x00`) is outside the codec's contract: the lexer and `dot_unescape`
  reject it, and `dot_escape` must not be given it (building a `Str` from
  bytes with `0x00` aborts at runtime in this compiler). Every other byte
  round-trips.
- The parser is syntactic: no node deduplication, no default-attribute
  (`node [..]`) semantics, no subgraphs/ports/HTML strings/`strict`.
- Unquoted identifiers are ASCII `[A-Za-z0-9_]+`; `-1` and `a.b` must be
  quoted.
- `#` starts a comment wherever it appears outside a string (Graphviz only
  treats it specially at line starts); put `#` inside a quoted string to use
  it as data.
- `dot_serialize` returns `Str` and cannot fail; graphs with drifted parallel
  vectors serialize their shortest consistent prefix (see `dot_is_consistent`).
- No streaming parser; the whole document is a `Str`.

## 10. Test plan

`tests/test_conformance.xi` (module `diagrams_tests`) runs 34 named checks,
one `fn` per check, called directly from `main` (no table-driven dispatch),
and returns the failure count (0 = green).

| # | Check | Pins |
|---|---|---|
| t01 | escape exact | `"`, `\`, LF, TAB, CR table |
| t02 | escape passthrough | UTF-8, `#`, empty, plain |
| t03 | unescape exact | inverse; empty input |
| t04 | unescape errors | `E_BAD_ESCAPE` incl. line/col and trailing backslash |
| t05 | round-trip | text + control bytes `\u{0001}`, `\u{001F}` |
| t06 | parse edge | digraph, name, kind 1, ids, consistency |
| t07 | parse undirected | `--`, anonymous, no semicolons |
| t08 | node attrs | canonical body, kind 0 |
| t09 | attr escaping | canonicalization + `dot_attr_get` found/missing |
| t10 | attr statement | kind 2, key/value |
| t11 | comments | `#` and `//`, inside and around statements |
| t12 | semicolons / `[]` | empty statements, empty attr list, serialize |
| t13 | chain | pairwise edges, replicated attrs |
| t14 | serialize basic | exact layout, `dot_attr_pair` |
| t15 | serialize undirected | quoted name and id, attr statement |
| t16 | serialize empty | `digraph {\n}` / `graph {\n}` |
| t17 | normalization | separators, needless quotes, `#fff` value |
| t18 | idempotence | parse -> serialize -> parse -> serialize |
| t19 | `E_UNTERMINATED_STRING` | position at opening quote |
| t20 | `E_EXPECTED_GRAPH_KEYWORD` / `E_EXPECTED_LBRACE` | keyword, missing `{` |
| t21 | `E_EXPECTED_LBRACE` | after a name |
| t22 | `E_EXPECTED_RBRACE` | single-line and EOF-at-line-3 |
| t23 | `E_EDGE_OP_MISMATCH` | both directions, mid-chain |
| t24 | `E_BAD_ESCAPE` | in a parsed string |
| t25 | attr-list errors | equals, separator, value, key |
| t26 | `E_TRAILING_INPUT` | after `}` |
| t27 | `E_EMPTY_INPUT` | empty and comment-only |
| t28 | `E_UNEXPECTED_CHAR` | `@`, lone `-` |
| t29 | `E_UNEXPECTED_TOKEN` | `,`, `=` after an edge |
| t30 | `dot_error_code` | with and without `@` |
| t31 | `dot_attr_get` | quoted key, missing, malformed, `;` |
| t32 | builder/stats/guard | counts, kinds, out-of-range, drift |
| t33 | `dot_attr_pair` | quoting/escaping per side |
| t34 | canonical ids | quoted id accessor + serialize |

All Str equality goes through `xiom.string.compare`'s `str_compare`, never
`==` (BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison; `.len()` on such elements is unreliable too).

## 11. Compiler / stdlib notes (v0.62.1)

- Free functions only; no `self` methods, no inline lambdas, no
  `Vec[StructType]`; the model is four parallel vectors.
- `Ok`/`Err` for `Result[DotGraph, Str]` are constructed only in the leaf
  helpers `_ok_graph` / `_err_graph`; `Result[Str, Str]` uses `_ok_str` /
  `_err_str` (constructing Results directly inside other functions
  miscompiles on this compiler).
- String equality/emptiness uses `str_compare`; text vectors are never
  compared with `==` or measured with `.len()`.
- Every push to a model vector is mirrored on all sibling vectors by
  construction; `_parse_edge_stmt` re-checks tail/head lengths before use and
  `dot_serialize` clamps to the shortest vector.
- Byte constants are all < 128, so `byte_at` results are compared directly
  (no widening/masking needed).
- All output bytes go through `Vec[UInt8]` + `xiom.string.builder.sb_to_str`;
  NUL is rejected before it can reach `sb_to_str`.
- Int -> Str (positions) is a local decimal renderer; the conversion tower is
  not used.
