# xiom.parser-fw

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.0` on the XIOM registry.
> **Scope:** a framework for recursive-descent and precedence-climbing parsers:
> token model and classification, grammar-rule declarations and production
> helpers, a backtracking core engine, Pratt/precedence binding powers,
> panic-mode error recovery/resynchronization and a parse-tree node model.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.parser-fw` is a deterministic, IO-free parser framework. A grammar is a
concrete arena (`Grammar`) of rule nodes -- there are no closures, no
fn-pointer values and no `Vec[StructType]`, so a grammar is plain data that a
single recursive engine (`parse_run`) interprets. The token stream is built
and owned by the caller; the engine only reads it.

The framework gives you six pieces:

- **Token model** -- kinds as `Int` constants (`P_KIND_*`), a three-parallel-
  `Vec` `TokenStream`, raw token text reconstruction and a `KindTable` for
  exact word-to-kind classification.
- **Grammar rules** -- `rule_empty`, `rule_token`, `rule_seq`/`rule_seq3`,
  `rule_choice`, `rule_repeat0`, `rule_repeat1`, `rule_optional`, `rule_eof`
  and `rule_prec`, plus `rule_patch_a`/`rule_patch_b` to wire recursion. All
  builders return rule indices; `grammar_is_consistent` checks the arena.
- **Core engine** -- `parse_run(g, root, ts, max_errors)` interprets the arena
  recursively with full backtracking: a failed rule restores the cursor and
  discards the tree nodes it created.
- **Precedence climbing** -- `rule_prec` takes an atom rule; the grammar's
  infix table (`grammar_op_add(kind, lbp, rbp)`) and prefix table
  (`grammar_prefix_add(kind, rbp)`) drive a Pratt parser. Use `rbp = lbp + 1`
  for left associativity.
- **Panic-mode recovery** -- the repetition rules report the failure, skip
  tokens to the synchronization set (`grammar_sync_add`) and resume with an
  explicit error node; bounded by `max_errors` and by progress guards.
- **Parse-tree model** -- seven parallel `Vec`s with a first-child/
  next-sibling layout, range-safe accessors and an S-expression renderer for
  tests and diagnostics.

```xi
use xiom.parser_fw;

fn main() -> Int {
  var g = grammar_new();
  let num = rule_token(&mut g, P_KIND_INT, "number");
  let expr = rule_prec(&mut g, num, "expr");
  grammar_op_add(&mut g, 20, 1, 2);

  var ts = ts_new();
  ts_push(&mut ts, P_KIND_INT, 0, 1);
  ts_push(&mut ts, 20, 1, 2);
  ts_push(&mut ts, P_KIND_INT, 2, 3);
  let out = parse_run(&g, expr, &ts, 4);
  // out.ok, out.errors, out.tree; tree_to_sexpr renders the tree.
  return 0;
}
```

### Relationship to the other text packages

`xiom.lexer-fw` produces a token stream from a `Str`; `xiom.parsing` is a
backtracking parser-combinator framework over raw `Str` input with span
results; `xiom.parser-fw` is the token-stream-driven engine that builds
parse **trees** and recovers from errors. The token stream is an interface
between the two: feed a `lexer-fw` scan into a `parser-fw` grammar by mapping
its token kinds and spans into `ts_push`.

## API

Values: `TokenStream`, `KindTable`, `Grammar`, `ParseTree`, `PState`,
`ParseOutcome` (all parallel-`Vec` records; no `Vec[StructType]`).

Rules and node kinds: `P_RULE_EMPTY..P_RULE_PREC` (0..8);
`P_NODE_RULE/TOKEN/ERROR/EMPTY` (0..3).

Grammar building: `grammar_new`, `rule_empty`, `rule_token`, `rule_seq`,
`rule_seq3`, `rule_choice`, `rule_repeat0`, `rule_repeat1`, `rule_optional`,
`rule_eof`, `rule_prec`, `rule_patch_a`, `rule_patch_b`, `grammar_op_add`,
`grammar_prefix_add`, `grammar_sync_add`, `grammar_rule_count`,
`grammar_is_consistent` and the range-safe `grammar_rule_kind/label/token/a/b`
accessors.

Engine: `parse_run(g, root, ts, max_errors) -> ParseOutcome`.

Trees: `tree_len`, `tree_node_kind/rule/token/start/end`,
`tree_first_child`, `tree_next_sibling`, `tree_child_count`, `tree_child`,
`tree_span_text`, `tree_to_sexpr`, `token_text`.

Streams and tables: `ts_new`, `ts_push`, `ts_len`, `ts_kind`, `ts_start`,
`ts_end`, `ts_kind_name`, `kt_new`, `kt_add`, `kt_len`, `kt_word`, `kt_kind`,
`kt_lookup`, `kt_classify`.

See `SPEC.md` for signatures, exact semantics, the error catalog and the
test plan.

## Backtracking and error semantics (summary)

- Every rule that returns failure has restored the cursor to its entry
  position and truncated the tree to its entry length; a failed `seq` never
  leaves the input half-consumed and choice is plain first-match-wins.
- Diagnostics track the **furthest** failure position and the first label
  recorded there; the pending failure becomes one error message either at a
  recovery point or when the top-level parse fails.
- Recovery skips stop **before** a synchronization token (the token is left
  for the next attempt); a skip that consumes nothing stops the repetition,
  and a zero-width child match also stops it, so every loop makes progress.
- `max_errors` (defaulted up to 1) bounds recovery errors; when reached the
  engine stops recovering and sets `ParseOutcome.stopped`.

## Install / usage

The package is **not yet published** on the XIOM registry; when it is, the
consumer workflow is:

```
xiom pkg install xiom.parser-fw@0.1.0
```

Until then, use it from this repository (the module is pure XIOM, no FFI):

```
use xiom.parser_fw;
```

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom-parser-fw -TimeoutSec 60
```

Expected tail: 27 `[PASS]` lines, `xiom.parser-fw: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No semantic actions.** The engine produces only the parse tree; values
  are computed by walking the tree in caller code.
- **Caller-built token streams.** Tokenization, trivia handling and keyword
  classification policy belong to the caller (a `KindTable` is provided for
  exact word classification).
- **Fully backtracking, not packrat.** No memoization and no `cut`; nested
  alternatives can re-scan tokens. Fine for small-to-medium grammars.
- **Panic-mode recovery only.** One synchronization set per grammar, no
  error productions and no automatic statement-boundary inference.
- **Single parse tree per run.** No forest, no incremental parsing.
- **Recursion depth** is bounded by the compiler's call-depth guard; very
  deep nestings hit that limit rather than growing the stack.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
