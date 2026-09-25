# xiom.ply -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ply` (`src/ply.xi`). Pure XIOM, no FFI, no dependencies beyond
`xiom.std`.

## 1. Scope

An in-memory codec for the ASCII subset of the PLY polygon file format:

- header parsing: `ply`, `format ascii 1.0`, `comment ...`,
  `element <name> <count>`, `property <type> <name>` with the eight scalar
  types, `end_header`;
- body parsing: rows are consumed element by element in declaration order and
  every row must carry exactly one token per declared property;
- scalar validation: integer tokens (`char`, `uchar`, `short`, `ushort`,
  `int`, `uint`) are range-checked, `float`/`double` tokens are
  syntax-checked; every token is preserved verbatim as text;
- element count validation: declared counts and actual rows must agree, and
  no line may follow the last declared row;
- a header builder and a canonical whole-document builder that round-trips
  canonical input;
- read-only structural accessors (elements, properties, comments, rows) and
  an integer conversion helper.

The input is a `Str` treated as a byte buffer; the output is a `PlyDoc`
holding only flat parallel vectors, because this compiler (v0.61.3) cannot
hold `Vec[StructType]`.

## 2. Non-goals

- No binary PLY (`binary_little_endian`, `binary_big_endian`); the format
  line must be exactly `ascii 1.0`.
- No `property list` and therefore no variable-length rows: the subset is
  scalar-only. A face is modelled as fixed-width scalar properties (for
  example `uchar vertex_count` plus per-corner `int` slots); variable-arity
  polygons must be normalized by the caller or carried by another format.
- No mesh topology operations: no triangulation, adjacency, edges, normals,
  vertex deduplication, index remapping or geometric predicates.
- No floating-point arithmetic: there is no `Vec[Float64]` in this compiler,
  and this module never converts a float. `float`/`double` values stay text.
- No file I/O, no streaming API, no error recovery: the first error aborts
  and no partial document is returned.
- No writer for arbitrary values: `ply_build` emits the stored text tokens
  and does not re-validate them.

## 3. Grammar and layout

`ws` is space or TAB; lines end at LF and one CR immediately before the LF is
dropped (CRLF). The final line needs no terminator.

```
document    = magic LF format LF header-record* "end_header" LF row*
magic       = "ply"
format      = "format" ws+ "ascii" ws+ "1.0"
header-record = comment | element | property
comment     = "comment" ( ws+ text )?
element     = "element" ws+ name ws+ count
property    = "property" ws+ scalar-type ws+ name
scalar-type = "char" | "uchar" | "short" | "ushort" | "int" | "uint"
            | "float" | "double"
count       = digit+                      ; non-negative, leading zeros allowed
name        = token                       ; any non-empty run of non-ws bytes
row         = value ( ws+ value )*        ; exactly the current element's
                                          ; property count, in order
```

Decisions (each one is covered by the conformance suite):

1. **Header line 1** must be exactly one token `ply` (case-sensitive). The
   magic line may carry surrounding spaces/TABs.
2. **Header line 2** must be exactly `format ascii 1.0` (three tokens,
   case-sensitive). Anything else -- including a missing line, a binary
   format, another version or trailing tokens -- is
   `Err("ply: unsupported format line")`.
3. **`comment`** lines are collected and their text (bytes after the keyword)
   is trimmed of leading/trailing space/TAB. Comments may appear anywhere in
   the header; `ply_build` re-emits them directly after the format line.
4. **Elements** are declared in order with a digits-only count. An element's
   properties are the `property` lines that follow it until the next
   `element` (or `end_header`). Property lines before the first element are
   malformed.
5. **Properties** are scalar-only. The type token must be one of the eight
   names; `list` and any other spelling (including `Int`, `uint8`, `int64`)
   are `unknown property type`. Property names may repeat; lookups return the
   first match.
6. **`end_header`** carries no other tokens. Header lines with an
   unrecognized keyword, empty lines inside the header and `end_header` with
   trailing tokens are `unknown header record`.
7. **Body rows** are assigned to elements in declaration order: element `e`
   consumes `elem_counts[e]` consecutive rows, and each row must split into
   exactly `property_count(e)` tokens. There are no row separators other than
   the line break, so blank lines are rows with zero tokens (only valid for
   property-less elements).
8. **Element counts** must be satisfied exactly. If the body ends early the
   error is `element count mismatch`; if lines remain after the last declared
   row the error is `trailing rows` at the first extra line.
9. **Errors stop the parse.** The first failing line is reported; the partial
   document is discarded. Line numbers are 1-based physical lines (blank and
   comment lines count; `end_header` is the last header line).

## 4. Scalar types and value validation

| Type | Code | Range | Token validation |
|---|---|---|---|
| `char` | 1 | -128..127 | integer |
| `uchar` | 2 | 0..255 | integer |
| `short` | 3 | -32768..32767 | integer |
| `ushort` | 4 | 0..65535 | integer |
| `int` | 5 | -2147483648..2147483647 | integer |
| `uint` | 6 | 0..4294967295 | integer |
| `float` | 7 | IEEE-754 binary32 | number syntax only |
| `double` | 8 | IEEE-754 binary64 | number syntax only |

Integer token grammar:

```
integer = sign? digit+          ; sign = "+" | "-"
```

Leading zeros are allowed and ignored for the digit count; a leading `+` is
accepted. The magnitude is scanned into Int64 with an overflow guard, so a
token with more than 19 significant digits is `bad integer range` rather than
wrapping. A syntax error (a letter, a dot, an exponent, `--1`, a bare sign)
is `malformed value`. The sign is applied after the magnitude scan and the
result must satisfy the declared type's range; `-0` is 0 and is accepted for
unsigned types.

Number token grammar (`float`, `double`):

```
number = sign? ( digit+ ( "." digit* )? | "." digit+ ) exponent?
exponent = ( "e" | "E" ) sign? digit+
```

At least one mantissa digit is required. Accepted: `1`, `-0.5`, `.5`, `5.`,
`1e3`, `+1.5E-2`, `-0`, `1E-10`. Rejected: `nan`, `inf`, `0x10`, `1.2.3`,
`.`, `1e`, `1e+`, `--1`. No range, precision or special-value semantics are
attached to float/double tokens: they are validated for syntax only and kept
verbatim.

## 5. Data model

```xi
pub type PlyDoc = {
  elem_names: Vec[Str];
  elem_counts: Vec[Int];
  elem_prop_starts: Vec[Int];
  elem_prop_ends: Vec[Int];
  prop_types: Vec[Int];
  prop_names: Vec[Str];
  comments: Vec[Str];
  tokens: Vec[Str];
}
```

- Element `e` is `elem_names[e]` with `elem_counts[e]` rows.
- Element `e` owns property indices `[elem_prop_starts[e], elem_prop_ends[e])`;
  `prop_types[p]` is a code from section 4 and `prop_names[p]` the name.
- `tokens` is the flat body stream in source order. Because every scalar row
  has one token per property, element `e`'s tokens are `elem_counts[e] *
  property_count(e)` consecutive entries after those of earlier elements.
- `comments[i]` is the trimmed text of the i-th comment.
- Values are the original text tokens; nothing is parsed at parse time beyond
  validation, so no precision is lost.

Documents produced by `ply_parse` always keep the parallel vectors aligned;
the accessors and both builders also defend against out-of-range indices and
skewed vectors (returning the documented sentinels, or skipping inconsistent
declarations while building a header).

## 6. API contract

```xi
pub fn ply_parse(text: Str) -> Result[PlyDoc, Str]
pub fn ply_build(doc: &PlyDoc) -> Result[Str, Str]
pub fn ply_build_header(doc: &PlyDoc) -> Str

pub fn ply_element_count(doc: &PlyDoc) -> Int
pub fn ply_element_name(doc: &PlyDoc, e: Int) -> Str
pub fn ply_element_rows(doc: &PlyDoc, e: Int) -> Int
pub fn ply_element_property_count(doc: &PlyDoc, e: Int) -> Int
pub fn ply_element_property(doc: &PlyDoc, e: Int, j: Int) -> Int
pub fn ply_property_name(doc: &PlyDoc, p: Int) -> Str
pub fn ply_property_type(doc: &PlyDoc, p: Int) -> Int
pub fn ply_property_element(doc: &PlyDoc, p: Int) -> Int
pub fn ply_property_index(doc: &PlyDoc, e: Int, name: Str) -> Int
pub fn ply_token_count(doc: &PlyDoc) -> Int
pub fn ply_comment_count(doc: &PlyDoc) -> Int
pub fn ply_comment(doc: &PlyDoc, i: Int) -> Str
pub fn ply_row_value(doc: &PlyDoc, e: Int, r: Int, j: Int) -> Str
pub fn ply_value_int(doc: &PlyDoc, e: Int, r: Int, j: Int) -> Result[Int, Str]

pub fn ply_type_name(code: Int) -> Str
pub fn ply_type_code(name: Str) -> Int
pub fn ply_type_is_integer(code: Int) -> Bool
```

Accessor defaults: `ply_element_name`/`ply_property_name`/`ply_comment`/
`ply_row_value` return `""` out of range (a stored token is never empty, so
`""` is unambiguous); `ply_element_rows`, `ply_element_property_count`,
`ply_property_type` and `ply_token_count` return `0`;
`ply_element_property`, `ply_property_index` and `ply_property_element`
return `-1`.

Canonical emission: `ply_build` and `ply_build_header` write LF line endings,
single spaces between tokens, comments immediately after the format line and
a final LF. `ply_build` emits the stored tokens verbatim and fails with
`ply: element count mismatch` when the declared counts and the token stream
disagree; `ply_build_header` never fails (skewed declarations are skipped).
For a document parsed from canonical input, `ply_build` reproduces the input
byte-exactly; parsing the result yields an equivalent document.

Complexity: `ply_parse` is O(text bytes); `ply_build`/`ply_build_header` are
O(output bytes); element lookups are O(elements), property lookups
O(properties of the element), `ply_row_value` O(elements + 1), and
`ply_value_int` O(elements + digits). Memory is O(elements + properties +
comments + body tokens).

## 7. Error catalog

| Message | Condition | Reported |
|---|---|---|
| `ply: missing magic` | no first line, or its tokens are not exactly `ply` | line 1 |
| `ply: unsupported format line` | no second line, or its tokens are not exactly `format ascii 1.0` | line 2 (or missing) |
| `ply: unknown header record at line N` | unrecognized header keyword, an empty header line, or `end_header` with extra tokens | the record line |
| `ply: malformed element at line N` | `element` without exactly name and count, or a count that is not digits only | the element line |
| `ply: malformed property at line N` | `property` with fewer than two tokens, a known type with a wrong token count, or a property before the first element | the property line |
| `ply: unknown property type at line N` | the type token is outside the eight scalar names (includes `list`) | the property line |
| `ply: missing end_header` | input ends while the header is open | none |
| `ply: element count mismatch` | the body ends before every declared row was read | none |
| `ply: row token-count mismatch at line N` | a row has more or fewer tokens than its element's property count | the row line |
| `ply: malformed value at line N` | an integer token is not an integer, or a float/double token is not a number | the row line |
| `ply: bad integer range at line N` | an integer token is outside its declared type range or beyond Int64 | the row line |
| `ply: trailing rows at line N` | lines remain after the last declared row | the first extra line |

`ply_build` adds `ply: element count mismatch` for an inconsistent document.
`ply_value_int` adds: `ply: property out of range` (bad property slot),
`ply: value out of range` (bad element/row), `ply: value is not an integer`
(float/double property), `ply: malformed value` and `ply: bad integer range`
(a hand-built document with an invalid token). Messages are built with
`xiom.convert.int_to_string`; `N` is the 1-based physical line number.

## 8. Test plan

`tests/test_conformance.xi` (module `ply_tests`) runs 25 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). All string comparisons go through
`xiom.string.compare.str_compare` (BUG 17 discipline).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | header: elements, properties, comments and lookups | counts, names, type codes, ownership, name lookup, comment preservation |
| t2 | body: tokens preserved verbatim; integers convert | text tokens, out-of-range sentinels, `ply_value_int` and its errors |
| t3 | round-trip: header and document rebuild byte-exact | `ply_build_header`/`ply_build` on the fixture, re-parse equivalence |
| t4 | CRLF normalized to LF | CR before LF dropped; canonical output |
| t5 | extra spaces and TABs | tolerant separators; canonical output |
| t6 | missing magic | empty input, `nope`, `PLY`, `ply extra`, leading blank line, `plyx` |
| t7 | only `format ascii 1.0` | missing line, `1.1`, binary, short line, extra token, comment in its place |
| t8 | unknown property types | `list`, `int64`, `Int`, `uint8`, `string` with line numbers |
| t9 | malformed elements | missing count, negative, decimal, letter, `+1`, hex count |
| t10 | malformed properties | before any element, missing type, missing name, extra token |
| t11 | unknown header records | empty header line, unknown keyword, `elementx`, `end_header extra`, second `ply` |
| t12 | missing end_header | header ends at format, after element, without LF, after comment |
| t13 | element count mismatch | one element short, second element short, no rows at all |
| t14 | row token-count mismatch | one of two tokens, three of two, second row wrong |
| t15 | bad integer range | every type's upper/lower overflow plus a 20-digit token |
| t16 | integer boundaries and forms | min/max of all six types, `+5`, `-0`, `007`, long leading zeros |
| t17 | malformed values | decimals for ints, letters, signs, `nan`, `inf`, `1e`, `1.2.3`, `.`, hex, `--1` |
| t18 | float/double tokens | accepted number forms kept verbatim; round-trip; no integer conversion |
| t19 | trailing rows | extra value line, blank line, junk line, all with the right line number |
| t20 | empty document and defaults | every accessor default and the empty build |
| t21 | zero-count elements | `element camera 0` consumes nothing; property order preserved |
| t22 | type table | names, codes, case sensitivity, integer classification |
| t23 | comment normalization | comments anywhere in the header, re-emitted after format |
| t24 | physical line numbers | error lines count comments and header lines |
| t25 | build mismatch | a hand-built `PlyDoc` with missing tokens is rejected |

## 9. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the sibling ported packages):

- Free functions only; no methods on `PlyDoc`, no lambdas, no `Vec[fn]`
  dispatch.
- No `Vec[StructType]`, no `Vec[Float64]`: `PlyDoc` is eight parallel
  vectors and values are text.
- `Ok`/`Err` construction is confined to the `_ply_ok_doc`/`_ply_err_doc`,
  `_ply_ok_str`/`_ply_err_str` and `_ply_ok_int`/`_ply_err_int` leaf helpers.
- Str comparisons go through `xiom.string.compare.str_compare` (BUG 17:
  `==` on Str values read from `Vec[Str]` elements is a pointer comparison).
- Bytes are read as `(string.byte_at(s, i) as Int) & 0xFF`; every `Vec`
  element read is bound with an explicit type.
- Output is built with `xiom.string.builder` (single allocation at
  `sb_to_str`).
- No literal `>= 128` comparison on a byte value; the scanner only compares
  against ASCII constants.

## 10. Known limitations

- The `property list` construct and therefore variable-arity faces are out of
  scope; such files are rejected at the property type check.
- Values are text: integer conversion is explicit, floats are never decoded,
  and no rounding or float validation of magnitude happens.
- Strict count matching is positional: an element whose declared count is too
  small leaves the surplus rows to the next element, so the format cannot
  mark row boundaries and the first mismatch is only detected when the
  following element runs out (or as trailing rows at the end).
- `ply_build` re-emits stored tokens without re-validating them; a hand-built
  document can therefore produce invalid PLY text as long as its token count
  is consistent.
- Comments lose their original position (they are re-emitted after the format
  line) and their leading/trailing whitespace; internal text is preserved.
- Element counts are Int64-bounded and integer values allow at most 19
  significant digits (leading zeros ignored).
- The input is bytes: no UTF-8 validation, no BOM stripping; a non-ASCII byte
  in a header keyword makes the record unknown.
- Whole-document, in-memory parsing only.
