# xiom.parsing -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.parsing` (`src/parsing.xi`). Pure XIOM, no FFI, no IO, no
`Vec[Float64]`, no `Vec[StructType]`, no closures, no fn-pointer values.

## 1. Scope

A deterministic parser-combinator framework over a `Str` input:

- concrete combinator **arena** (`PGrammar`) of eight parallel `Vec` fields;
- combinators: exact literal, one-byte character class (range or named
  predicate), sequence, ordered choice, zero-or-more, one-or-more, optional,
  capture (map-to-index-range) and end-of-input;
- every successful sub-parse yields the half-open source byte range
  `[start, end)` as a `PSpan` (the span *is* the result);
- structured errors (`PError`) with the furthest failure position, its
  1-based line/column, the raw found byte, the deduplicated expected-label
  set and a rendered message;
- documented full-backtracking semantics (section 5).

`Str` is treated as a UTF-8 byte buffer; all matching is byte-wise and every
byte read is widened with `(b as Int) & 0xFF` before comparison (pinned
v0.62.1 trap: direct `UInt8` comparisons at >= 128 are miscompiled).

## 2. Non-goals

- Semantic values / ASTs: results are index ranges only; callers interpret
  slices. No grammar code generation, no regex, no lexer integration.
- Unicode character classes, case-insensitive matching, escape decoding.
- Error recovery, partial results, multiple errors.
- Packrat memoization, `cut`/commit operators, longest-match choice.
- Streaming input, incremental parsing, whitespace handling as a built-in
  (trivia is grammar-level).

## 3. Values

```
PSpan  = { start: Int; end: Int; present: Bool }
PPoint = { line: Int; col: Int }
PError = { pos: Int; line: Int; col: Int; found: Str; message: Str; expected: Vec[Str] }
PState = { source: Str; pos: Int; fail_pos: Int; expected: Vec[Str] }
PGrammar = { kinds: Vec[Int]; labels: Vec[Str]; literals: Vec[Str];
             class_lo: Vec[Int]; class_hi: Vec[Int]; class_pred: Vec[Int];
             child_a: Vec[Int]; child_b: Vec[Int] }
```

`start` is inclusive and `end` exclusive; `present` is false only for an
OPTIONAL result that took the absent branch (then `start == end`). `pos` is a
0-based byte offset; `line`/`col` are 1-based.

## 4. Grammar arena

Node `i` is fully described by index `i` in each of the eight parallel
vectors:

| Field | Used by | Meaning |
|---|---|---|
| `kinds[i]` | all | `PARSE_KIND_*` (0..9). |
| `labels[i]` | all | Error label reported when the node's own match fails. |
| `literals[i]` | LITERAL | Exact text to match. |
| `class_pred[i]` | CLASS | `PARSE_PRED_*` (0..7). |
| `class_lo[i]`, `class_hi[i]` | CLASS + RANGE | Inclusive byte bounds. |
| `child_a[i]`, `child_b[i]` | SEQ/ALT, unary kinds | Child node indices; `-1` when unused. |

Builders (`_node_push` is the single private push site, so lengths cannot
drift): `parse_literal`, `parse_class_range`, `parse_class_pred`,
`parse_seq`, `parse_alt`, `parse_many`, `parse_many1`, `parse_optional`,
`parse_capture`, `parse_eof`. Each returns the new node index.

Recursive grammars are wired with `parse_patch_child_a(g, node, child)` and
`parse_patch_child_b(g, node, child)` after the referenced nodes exist;
out-of-range `node` is a no-op.

Invariant: `parse_is_consistent(g)` is true iff all eight vectors have equal
length. `parse_node_kind/label/literal/pred/lo/hi/child_a/child_b` are
range-safe with defaults (`PARSE_KIND_NONE`, `""`, `""`, `PARSE_PRED_NONE`,
`0`, `0`, `-1`, `-1`).

Kinds: `PARSE_KIND_NONE=0`, `LITERAL=1`, `CLASS=2`, `SEQ=3`, `ALT=4`,
`MANY=5`, `MANY1=6`, `OPTIONAL=7`, `CAPTURE=8`, `EOF=9`.
Predicates: `PARSE_PRED_NONE=0`, `RANGE=1`, `DIGIT=2`, `ALPHA=3`, `ALNUM=4`,
`SPACE=5`, `IDENT_START=6`, `IDENT_BYTE=7`.

Predicate table (one byte, widened Int domain):

| Predicate | Matches |
|---|---|
| RANGE | `lo <= b <= hi` (an inverted range never matches). |
| DIGIT | `0x30..0x39`. |
| ALPHA | `A..Z` or `a..z`. |
| ALNUM | ALPHA or DIGIT. |
| SPACE | `0x20`, `0x09`, `0x0A`, `0x0D`. |
| IDENT_START | ALPHA or `_` (`0x5F`). |
| IDENT_BYTE | IDENT_START or DIGIT. |
| NONE / unknown | never. |

## 5. Combinator semantics and backtracking

`parse_run(g, node, st)` is one recursive dispatch. Let `start = st.pos` at
entry. Every failure restores `st.pos = start` before returning `Err`; every
success leaves `st.pos` at the first byte after the match.

| Kind | Success | Failure |
|---|---|---|
| LITERAL | `source[pos..pos+n)` equals the node literal (`str_compare`), `n = len(literal)`; empty literal succeeds zero-width. Span `[start, start+n)`. | label, at `start`. Consumes nothing. |
| CLASS | byte at `start` is in `0..255` and satisfies the predicate; consumes 1 byte. | label, at `start`. |
| SEQ | child_a then child_b; span `[start, end of child_b)`. | the failing child's error; position restored to `start` even when child_a consumed. |
| ALT | child_a; on failure, position reset to `start`, then child_b; the first success wins (no longest-match). Span = the winning child's span. | the second child's error; position restored. Expected sets carry labels recorded at the furthest position across both children. |
| MANY | repeat child_a while it succeeds; span `[start, st.pos)`. Never fails. | -- a failed iteration is rolled back and ends the loop. |
| MANY1 | as MANY, but the first iteration must succeed. | the first child error; position restored. A zero-width first success returns a zero-width span (guard). |
| OPTIONAL | child_a's span when it succeeds. | never; a failed child is rolled back and the result is `PSpan{ start; start; present: false }`. |
| CAPTURE | child_a's span unchanged (map-to-index-range). | the child error; position restored. |
| EOF | zero-width span at `start` when `start >= len(source)`. | label `"end of input"` (the node's label) at `start`. |

Loop guard: an iteration that succeeds with `span.end == position before the
iteration` terminates MANY/MANY1, so a nullable child (e.g.
`many(optional(x))`) cannot diverge.

Malformed nodes (child index `-1` or out of range on a consumed slot, or an
unknown kind) fail with expected label `"unknown-combinator"` at `start`.

`parse_run_all(g, node, source)` creates a fresh state, runs `node`, and then
requires `st.pos == len(source)`: a trailing byte fails with expected label
`"end of input"` recorded at that byte. On success the span equals `[0, n)`
for `n = len(source)`.

## 6. Positions and errors

- **Line/column.** 1-based, computed over raw bytes: LF (`0x0A`) advances the
  line and resets the column to 1; every other byte increments the column.
  CRLF therefore counts as one newline (the LF) and a lone CR is an ordinary
  column. Positions are byte offsets, not character offsets.
- **Furthest failure.** Each leaf failure records `(position, label)` into the
  state: a position farther than `fail_pos` resets the expected set to that
  label; an equal position appends the label once (`str_compare` dedup,
  insertion order). The error is rendered from the recorded state, so it
  reports the furthest position and everything expected there -- including
  labels from speculative probes.
- **Fields.** `pos`, `line`, `col`, `found` (the raw single byte at `pos`,
  `""` at end of input), `expected` (as above), `message`.
- **Message format** (exact):
  `parse error at line L, column C: expected <e1>, <e2>, ...; found <found>`
  where `<found>` is `'<byte>'` for printable ASCII (0x20..0x7E),
  `byte 0xNN` (uppercase hex) for any other byte, and `end of input` at/beyond
  the end. The expected list joins labels with `", "`.

Error accessors: `parse_error_pos/line/col/found/message`,
`parse_error_expected_count`, `parse_error_expected(e, i)` (`""` out of
range).

## 7. API signatures

```xi
pub const PARSE_KIND_NONE: Int = 0;  // .. PARSE_KIND_EOF = 9
pub const PARSE_PRED_NONE: Int = 0;  // .. PARSE_PRED_IDENT_BYTE = 7

pub type PSpan = { start: Int; end: Int; present: Bool; }
pub type PPoint = { line: Int; col: Int; }
pub type PError = { pos: Int; line: Int; col: Int; found: Str; message: Str; expected: Vec[Str]; }
pub type PState = { source: Str; pos: Int; fail_pos: Int; expected: Vec[Str]; }
pub type PGrammar = { kinds: Vec[Int]; labels: Vec[Str]; literals: Vec[Str];
                      class_lo: Vec[Int]; class_hi: Vec[Int]; class_pred: Vec[Int];
                      child_a: Vec[Int]; child_b: Vec[Int]; }

pub fn parse_grammar_new() -> PGrammar
pub fn parse_node_count(g: &PGrammar) -> Int
pub fn parse_is_consistent(g: &PGrammar) -> Bool
pub fn parse_literal(g: &mut PGrammar, text: Str, label: Str) -> Int
pub fn parse_class_range(g: &mut PGrammar, lo: Int, hi: Int, label: Str) -> Int
pub fn parse_class_pred(g: &mut PGrammar, pred: Int, label: Str) -> Int
pub fn parse_seq(g: &mut PGrammar, a: Int, b: Int) -> Int
pub fn parse_alt(g: &mut PGrammar, a: Int, b: Int) -> Int
pub fn parse_many(g: &mut PGrammar, a: Int) -> Int
pub fn parse_many1(g: &mut PGrammar, a: Int) -> Int
pub fn parse_optional(g: &mut PGrammar, a: Int) -> Int
pub fn parse_capture(g: &mut PGrammar, a: Int) -> Int
pub fn parse_eof(g: &mut PGrammar) -> Int
pub fn parse_patch_child_a(g: &mut PGrammar, node: Int, child: Int)
pub fn parse_patch_child_b(g: &mut PGrammar, node: Int, child: Int)

pub fn parse_node_kind(g: &PGrammar, i: Int) -> Int
pub fn parse_node_label(g: &PGrammar, i: Int) -> Str
pub fn parse_node_literal(g: &PGrammar, i: Int) -> Str
pub fn parse_node_pred(g: &PGrammar, i: Int) -> Int
pub fn parse_node_lo(g: &PGrammar, i: Int) -> Int
pub fn parse_node_hi(g: &PGrammar, i: Int) -> Int
pub fn parse_node_child_a(g: &PGrammar, i: Int) -> Int
pub fn parse_node_child_b(g: &PGrammar, i: Int) -> Int
pub fn parse_kind_name(kind: Int) -> Str
pub fn parse_pred_name(pred: Int) -> Str

pub fn parse_state_new(source: Str) -> PState
pub fn parse_pos(st: &PState) -> Int
pub fn parse_at_end(st: &PState) -> Bool
pub fn parse_peek(st: &PState) -> Int

pub fn parse_run(g: &PGrammar, node: Int, st: &mut PState) -> Result[PSpan, PError]
pub fn parse_run_all(g: &PGrammar, node: Int, source: Str) -> Result[PSpan, PError]

pub fn parse_span_start(sp: &PSpan) -> Int
pub fn parse_span_end(sp: &PSpan) -> Int
pub fn parse_span_len(sp: &PSpan) -> Int
pub fn parse_span_present(sp: &PSpan) -> Bool
pub fn parse_span_text(source: Str, sp: &PSpan) -> Str

pub fn parse_error_pos(e: &PError) -> Int
pub fn parse_error_line(e: &PError) -> Int
pub fn parse_error_col(e: &PError) -> Int
pub fn parse_error_found(e: &PError) -> Str
pub fn parse_error_message(e: &PError) -> Str
pub fn parse_error_expected_count(e: &PError) -> Int
pub fn parse_error_expected(e: &PError, i: Int) -> Str
```

Complexity: builders and accessors are O(1); `parse_run` is O(consumed bytes)
per node plus the cost of every alternative tried (full backtracking, no
memoization), and recursion follows the grammar depth; `parse_run_all` adds
one trailing comparison; error rendering is O(source + expected set) per
failure.

## 8. Test plan

`tests/test_conformance.xi` (module `parsing_tests`) runs 28 named checks via
`assert(cond, "name")`, one `fn` per check, direct calls (no fn tables); `main`
returns the failure count (0 = green). Fixtures: a recursive arithmetic
grammar and a compact JSON-subset grammar, both built in-test; the arithmetic
and JSON node ids are pinned by build order and re-checked in t25.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | literal match | exact byte span, text and cursor advance (5) |
| t2 | literal mismatch | error pos/line/col/expected/found (6) |
| t3 | empty literal | zero-width success at any position (5) |
| t4 | class range | inclusive byte range, mismatch error (4) |
| t5 | named predicates | digit/alpha/alnum/space/ident-start/ident-byte incl. non-ASCII byte (4) |
| t6 | seq | span, order, error at the second child, rollback (5) |
| t7 | seq rollback | alt recovers after a consumed-then-failed sequence (5) |
| t8 | alt order | first success wins, no longest match (5) |
| t9 | many | empty, greedy, stops at first failure, cursor (5) |
| t10 | many1 | one-or-more, zero-width failure at pos 0 (5) |
| t11 | optional | present/absent spans, never fails (5) |
| t12 | capture | map-to-index-range equals child span, absent capture (5) |
| t13 | capture backtracking | range after a failed alt branch (5) |
| t14 | eof | end-of-input check and run_all trailing error (5) |
| t15 | line/column | LF lines and mid-line columns (6) |
| t16 | expected dedup | duplicate labels collapse at one position (6) |
| t17 | furthest failure | later failure wins the expected set (6) |
| t18 | message text | exact message, end-of-input and `byte 0x01` (6) |
| t19 | arith full parse | `1+2*3`, `(1+2)*3`, `007` (5) |
| t20 | arith spans | term/expr/paren/atom subparse ranges (5) |
| t21 | arith error | trailing operator -> expected `digit`/`'('` at line 1 col 3 (6) |
| t22 | json object | `{"a":[1,true,null]}` parses fully (5) |
| t23 | json nested | `[[1],[2]]`, string content spans (5) |
| t24 | json malformed | `[1,]` -> furthest failure with 7 expected labels (6) |
| t25 | arena invariants | parallel-vector consistency, kinds/labels/children, bounded accessors (4) |
| t26 | determinism | repeated parses agree on spans and errors (5) |
| t27 | many guard | `many(optional(x))` terminates (5) |
| t28 | patching | placeholder failure label, child patch, no-op patch (4) |

Determinism: the same grammar and source always produce the same span or the
same error; the source is never mutated and no state is shared between runs.

## 9. Compiler / stdlib notes (pinned v0.62.1)

- Every byte read goes through `(b as Int) & 0xFF` before comparison; the
  >= 128 path is covered by the t5 non-ASCII case.
- `Ok`/`Err` literals exist only in the leaf constructors `_ok_span` and
  `_err_span`; all other functions return results through them.
- No `Vec[StructType]`: the arena and the state hold parallel `Vec[Int]` /
  `Vec[Str]` fields only; `_node_push` is the single push site (t25 checks
  consistency).
- `Str` values read from `Vec[Str]` elements go through typed locals and
  `str_compare` (BUG 17); `Vec[Int]` element reads use typed locals.
- Free functions only; no indexed `Vec[fn]` dispatch; no `[T,U]` callbacks; no
  inline lambdas.
- Bitwise/additive mixes are parenthesized (`(b as Int) & 0xFF`); all byte
  arithmetic is additive and comparisons happen in the widened Int domain.
