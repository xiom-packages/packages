# xiom.parsing

> **Status:** `incubating` -- conformance-tested (28/28); not yet published on the XIOM registry.
> **Scope:** a spanned parser-combinator framework over a `Str` input:
> literal, character-class, seq, alt, many/many1, optional, capture and EOF
> combinators; half-open byte-index results; structured line/column errors
> with expected sets; documented full backtracking.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.parsing` is a deterministic, IO-free parser-combinator framework. A
grammar is an arena (`PGrammar`) of concrete combinator nodes -- there are no
closures, no fn-pointer values and no `Vec[StructType]`, so a grammar is plain
data that a single recursive engine (`parse_run`) interprets.

Every successful sub-parse returns a `PSpan { start; end; present }`, the
half-open source byte range `[start, end)` of the recognized text. There is no
separate semantic value: the span **is** the result, so a caller evaluates a
parse by slicing the source (`parse_span_text`) and interpreting that slice
with its own code. This keeps the framework generic without generics.

Failure is structured: leaves record the failing byte offset and their label
into the mutable state; the error returned when a top-level parse fails
describes the **furthest** failure position, its 1-based line/column and the
deduplicated set of labels expected there.

```xi
use xiom.parsing;
use xiom.io;

fn main() -> Int {
  var g = parse_grammar_new();
  let digit = parse_class_pred(&mut g, PARSE_PRED_DIGIT, "digit");
  let number = parse_many1(&mut g, digit);
  let eof = parse_eof(&mut g);
  let root = parse_seq(&mut g, number, eof);
  let r = parse_run_all(&g, root, "42");
  match r {
    Ok(sp) => {
      let s: PSpan = sp;
      io.println(parse_span_text("42", &s));   // "42"
    },
    Err(e) => {
      let er: PError = e;
      io.println(er.message);                  // "parse error at line ..."
    },
  }
  return 0;
}
```

Recursive grammars are wired with `parse_patch_child_a` / `parse_patch_child_b`
after their nodes exist (see the JSON-subset fixture in the conformance suite).

### Relationship to the other text packages

| Package | What it does | Where the overlap ends |
|---|---|---|
| `xiom.lexer-fw` | scanner framework: byte matchers, keyword table, token stream with line/col. | It produces flat tokens; this package composes parsers (seq/alt/many/optional/capture), reports index ranges for arbitrary subtrees and structured expected-set errors. They compose well: lex, then parse tokens, or parse bytes directly. |
| `xiom.lexing` / `xiom.tokenizer` | fixed configurable tokenizers. | Neither offers composable combinators, backtracking or spans. |
| `xiom.regex` | pattern matching over text. | Different tool: regex cannot express recursive grammar structure with named expected sets, and this framework needs no pattern compilation. |

## API

Grammar construction (`g` is `&mut PGrammar`; each returns the new node
index). All builders push to all eight parallel vectors through one private
push site, so the arena cannot drift:

| Function | Node | Semantics |
|---|---|---|
| `parse_literal(g, text, label)` | literal | Matches `text` exactly (empty matches zero-width). |
| `parse_class_range(g, lo, hi, label)` | class | Matches one byte in the inclusive range `lo..hi`. |
| `parse_class_pred(g, pred, label)` | class | Matches one byte satisfying `PARSE_PRED_*` (digit, alpha, alnum, space, ident-start, ident-byte). |
| `parse_seq(g, a, b)` | seq | `a` then `b`; all-or-nothing. |
| `parse_alt(g, a, b)` | alt | Ordered choice `a` else `b`, full backtracking. |
| `parse_many(g, a)` | many | Zero or more `a`; greedy; never fails. |
| `parse_many1(g, a)` | many1 | One or more `a`; greedy. |
| `parse_optional(g, a)` | optional | `a` or a zero-width absent span; never fails. |
| `parse_capture(g, a)` | capture | Map-to-index-range: reports `a`'s span unchanged. |
| `parse_eof(g)` | EOF | Succeeds zero-width only at end of input. |
| `parse_patch_child_a/b(g, node, child)` | -- | Rewire a child (recursive grammars); out-of-range is a no-op. |

Arena and introspection: `parse_grammar_new`; `parse_node_count`;
`parse_is_consistent` (all eight vectors same length); `parse_node_kind`,
`parse_node_label`, `parse_node_literal`, `parse_node_pred`, `parse_node_lo`,
`parse_node_hi`, `parse_node_child_a`, `parse_node_child_b` (range-safe:
defaults on out-of-range indices); `parse_kind_name`, `parse_pred_name`.

State and engine:

| Function | Returns | Description |
|---|---|---|
| `parse_state_new(source)` | `PState` | Fresh state at offset 0, no recorded failure. |
| `parse_pos(st)` / `parse_at_end(st)` / `parse_peek(st)` | `Int` / `Bool` / `Int` | Cursor, end test, byte at cursor (0..255, `-1` at end). |
| `parse_run(g, node, st)` | `Result[PSpan, PError]` | Run one node against the state; advances on success, restores on failure. |
| `parse_run_all(g, node, source)` | `Result[PSpan, PError]` | Fresh state + run + require the whole source consumed (trailing byte fails with `"end of input"`). |

Spans and errors: `parse_span_start/end/len/present`; `parse_span_text(source, sp)`
(raw slice, clamped); `parse_error_pos/line/col/found/message`;
`parse_error_expected_count`; `parse_error_expected(e, i)` (`""` out of
range).

Kinds: `PARSE_KIND_NONE .. PARSE_KIND_EOF` (0..9); predicates
`PARSE_PRED_NONE .. PARSE_PRED_IDENT_BYTE` (0..7).

## Backtracking semantics (summary)

- Every combinator restores `PState.pos` to the position it saw when it (or a
  child it owns) fails; a failed `seq` never leaves the input half-consumed.
- `alt` is ordered choice: first success wins, no longest-match search.
- `many`/`many1` are greedy and stop at the first child failure; the failed
  iteration is rolled back. `many` never fails; `many1` fails only when the
  first iteration fails. A successful zero-width iteration terminates the
  loop, so many over a nullable child cannot diverge.
- `optional` never fails; the absent case is a zero-width span with
  `present == false`.
- Expected sets include labels from speculative probes (for example the
  iteration that ended a `many` loop); they are diagnostics, not a proof that
  the grammar could have continued there.

See `SPEC.md` for the full statement, the error catalog and the test plan.

## Install / usage

The package is **not yet published** on the XIOM registry; when it is, the
consumer workflow is:

```
xiom pkg install xiom.parsing@0.1.0
```

Until then, use it from this repository (the module is pure XIOM, no FFI):

```
use xiom.parsing;
```

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.parsing
```

Expected tail: 28 `[PASS]` lines, `xiom.parsing: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Spans, not trees.** Results are `[start, end)` ranges only; there is no
  semantic value or node-kind tagging. Callers slice the source and
  interpret it (grammar node ids can name subtrees for that purpose).
- **Byte-oriented.** Classes match single bytes; positions are byte offsets,
  not character offsets. Non-ASCII bytes inside a match are passed through
  byte-exact but no character classes cover them (use explicit ranges).
- **No whitespace magic.** Trivia is grammar-level: wrap tokens with a
  whitespace-skipping node if needed (the conformance fixtures parse compact
  inputs).
- **First error only.** No error recovery and no partial results; the error
  reports the furthest failure reached.
- **Fully backtracking, not packrat.** No memoization and no `cut`; nested
  alternatives can re-scan input. Fine for small-to-medium grammars.
- **Single pass, in-memory.** No streaming; the whole source is a `Str`.
- **Recursion depth** is bounded by the compiler's call-depth guard; very deep
  nestings hit that limit rather than growing the stack.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
