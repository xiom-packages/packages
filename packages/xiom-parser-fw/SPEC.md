# xiom.parser-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.parser_fw` (`src/parser_fw.xi`). Pure XIOM, no FFI, no IO, no
`Vec[Float64]`, no `Vec[StructType]`, no closures, no fn-pointer values.

## 1. Scope

A framework for hand-written recursive-descent and precedence-climbing
parsers driven by a caller-provided token stream (`TokenStream`, three
parallel `Vec`s: kinds, starts, ends):

- token kinds as `Int` constants (`P_KIND_*`), token-text reconstruction and
  an exact-word `KindTable` classification;
- a concrete grammar arena (`Grammar`) of rules: empty, token, sequence,
  ordered choice, zero/one-or-more, optional, EOF and precedence-climbing,
  with patch helpers for recursive rules;
- a backtracking core engine (`parse_run`) that interprets the arena and
  produces a parse tree plus diagnostics;
- Pratt/precedence climbing over an atom rule with infix (lbp/rbp) and prefix
  (rbp) binding-power tables;
- panic-mode error recovery/resynchronization in the repetition rules,
  bounded by an error budget and by progress guards;
- a parse-tree node model (seven parallel `Vec`s, first-child/next-sibling)
  with range-safe accessors, span text and an S-expression renderer.

The engine is pure: it never mutates the token stream, reads no ambient state
and returns one `ParseOutcome`.

## 2. Non-goals

- Lexing/tokenization: the caller builds the token stream (use
  `xiom.lexer-fw` for scanning and map its kinds/spans into `ts_push`).
- Semantic actions, AST construction, attribute evaluation or code
  generation: the engine yields the parse tree only.
- Packrat memoization, `cut`/commit operators, longest-match choice,
  incremental/streaming parsing, error productions and multiple
  synchronization sets.
- Error recovery outside the repetition rules; a failed token/seq/choice
  simply backtracks (the failure is tracked for diagnostics).
- Unicode-aware token kinds; kinds are opaque `Int`s and words are compared
  byte-exact via `str_compare`.

## 3. Token model

Kinds: `P_KIND_NONE=0`, `P_KIND_EOF=1`, `P_KIND_IDENT=2`, `P_KIND_INT=3`,
`P_KIND_STRING=4`, `P_KIND_OP=5`, `P_KIND_PUNCT=6`, `P_KIND_KEYWORD=7`
(caller-defined kinds are allowed and expected; operator tables are keyed by
them). `ts_kind_name` maps the constants to
`"none"/"EOF"/"ident"/"int"/"string"/"op"/"punct"/"keyword"` and anything
else to `"?"`.

`TokenStream = { kinds: Vec[Int]; starts: Vec[Int]; ends: Vec[Int] }`.
Token `i` spans `[starts[i], ends[i])` in the caller's `Str` source. The
engine treats a position `>= ts_len(ts)` as EOF and never appends a sentinel.
Out-of-range reads: `ts_kind` -> `P_KIND_EOF`, `ts_start`/`ts_end` -> `-1`,
`token_text` -> `""`. `ts_push` mirrors every push across all three vectors
(single push site).

`KindTable = { words: Vec[Str]; kinds: Vec[Int] }`: `kt_add` registers a word
and kind; `kt_lookup` is exact, case-sensitive and first-match-wins;
`kt_classify` falls back to `P_KIND_IDENT`. Empty words never match. All
accessors are range-safe (`""` / `P_KIND_NONE`).

## 4. Grammar arena

`Grammar` holds the rule vectors `rule_kind`, `rule_label`, `rule_token`,
`rule_a`, `rule_b` (equal lengths; `grammar_is_consistent` checks this) plus
the operator tables `op_kind/op_lbp/op_rbp`, `pre_kind/pre_rbp` and the
synchronization set `sync_kind`. `rule_push` is the single rule append site,
so the five rule vectors cannot drift.

Rule kinds:

| Constant | Kind | Children | Semantics |
|---|---|---|---|
| `P_RULE_EMPTY` | 0 | none | Always succeeds; one `P_NODE_EMPTY` node. |
| `P_RULE_TOKEN` | 1 | none | Matches one token of `rule_token[r]`; one `P_NODE_TOKEN` node. |
| `P_RULE_SEQ` | 2 | `a`,`b` | Both children in order; one `P_NODE_RULE` wrapping them. |
| `P_RULE_CHOICE` | 3 | `a`,`b` | Ordered choice, first success wins (the child node is returned unwrapped). |
| `P_RULE_REPEAT0` | 4 | `a` | Zero or more `a`; one `P_NODE_RULE` with the iteration nodes; never fails. |
| `P_RULE_REPEAT1` | 5 | `a` | One or more `a`; fails iff no iteration ever matched. |
| `P_RULE_OPTIONAL` | 6 | `a` | `a` or one `P_NODE_EMPTY`; never fails. |
| `P_RULE_EOF` | 7 | none | Succeeds at end of token stream; one `P_NODE_EMPTY`. |
| `P_RULE_PREC` | 8 | `a` | Precedence climbing over atom `a` (section 6). |

Builders: `rule_empty`, `rule_token`, `rule_seq` (binary), `rule_seq3`
(`a b c`, nested pairs, label on the outer rule), `rule_choice`,
`rule_repeat0`, `rule_repeat1`, `rule_optional`, `rule_eof`, `rule_prec`.
Each returns the new rule index. Recursion is wired with `rule_patch_a` /
`rule_patch_b` after the referenced rule exists; out-of-range indices are a
no-op. Range-safe accessors: `grammar_rule_kind` (`-1`), `grammar_rule_label`
(`""`), `grammar_rule_token` (`-1`), `grammar_rule_a`/`grammar_rule_b` (`-1`).

Operator registration: `grammar_op_add(kind, lbp, rbp)` (infix),
`grammar_prefix_add(kind, rbp)` (prefix), `grammar_sync_add(kind)`
(recovery). Lookups are linear and first-match-wins.

## 5. Engine semantics

`parse_run(g, root, ts, max_errors)` creates a fresh tree and state, runs
`root`, and returns a `ParseOutcome`:

- **Backtracking invariant.** Every rule that returns failure (-1) has
  restored the cursor to its entry position and truncated the tree to its
  entry node count. Therefore `seq` is atomic, choice is first-match-wins,
  and a failed attempt leaves no nodes behind.
- **Token rule.** Consumes one token on kind match; on mismatch records the
  failure at the cursor with the rule label and fails.
- **Sequence.** `a` then `b`; any failure restores the entry state. The rule
  node spans `[start token of a, end token of b)`.
- **Choice.** Tries `a`, then `b` after a clean failure of `a`; returns the
  winning child node directly (no wrapper). If both fail, the rule fails and
  the furthest-failure record is unchanged.
- **Repeat.** Iterates the child; each iteration resets the pending-failure
  record. A child success appends its node and extends the list span; a
  zero-width child success stops the loop after appending once (progress
  guard). A child failure triggers recovery (section 7). `repeat0` always
  succeeds; `repeat1` fails iff no iteration ever matched and rolls back.
- **Optional.** Child success passes the child node through; failure restores
  the entry state and yields one `P_NODE_EMPTY`.
- **EOF.** Succeeds at `pos >= ts_len`; otherwise records the labelled
  failure.
- **Diagnostics.** `_record_fail` keeps the furthest failure position; at an
  equal position the first label recorded wins (deterministic). The pending
  failure is materialized as one error message at a recovery point or when
  the top-level parse fails; the top-level fallback message is
  `"parser: syntax error at token <n>"` when no label is pending.
- **Budgets.** Loop iterations and sibling walks are capped (100000), and
  `max_errors < 1` is raised to 1.

## 6. Precedence climbing (Pratt)

`rule_prec(g, atom, label)` parses expressions with `min_bp = 0`:

1. **Prefix loop.** While the current token kind has a prefix row, consume the
   operator token, parse the operand recursively with `min_bp = prefix rbp`,
   and wrap `(op operand)` in a rule node.
2. **Atom.** Otherwise parse `atom`; a failure records the prec label at that
   position and fails the whole rule (restoring entry state).
3. **Infix loop.** While the current kind has an infix row with
   `lbp >= min_bp`: consume the operator token, parse the right operand with
   `min_bp = rbp`, and wrap `(left op right)` in a rule node with the same
   rule index. `rbp = lbp + 1` gives left associativity; `rbp > lbp` gives
   right associativity.

The operand recursion is data-driven through the same rule index; no
function-pointer dispatch is used anywhere (v0.62.2 trap 5). Registered
prefix binding powers should exceed the infix lbp they must bind tighter
than.

## 7. Panic-mode recovery

Recovery is attempted in `repeat0`/`repeat1` when a child fails:

- `_can_recover` requires a non-empty synchronization set, a cursor not at
  EOF and not already at a sync token, and a non-exhausted error budget.
- The pending failure is materialized (`parser: expected <label> at token
  <n>`) and tokens are skipped until EOF or a sync token; the sync token
  itself is **left unconsumed** for the next attempt.
- The skipped tokens become one `P_NODE_ERROR` child spanning
  `[skip_start, pos)`; `recovered` counts the skipped tokens.
- A skip that consumes nothing stops the loop; the `max_errors`-th error
  stops recovery and sets `stopped = true`. Both guard against divergence.
- `repeat1` still fails iff no iteration ever matched after the whole loop.

## 8. Parse-tree model

`ParseTree` = seven parallel `Vec`s: `node_kind`, `node_rule`, `node_token`,
`node_start`, `node_end`, `node_first`, `node_next` (single push site:
`_tree_push`). Children use first-child/next-sibling: `node_first[i]` is the
first child or -1; `node_next[c]` is c's next sibling or -1.

Node kinds: `P_NODE_RULE=0` (interior rule node; `node_rule` names the
production), `P_NODE_TOKEN=1` (leaf; `node_token` is the token index),
`P_NODE_ERROR=2` (recovery span), `P_NODE_EMPTY=3` (empty match).

Interior and error nodes span the token range `[node_start, node_end)`; token
nodes span exactly one token; empty nodes span `[pos, pos)`. `tree_span_text`
returns the raw source slice covered by a node (or `""` when empty/out of
range). `tree_to_sexpr` renders a node recursively: tokens as their raw text,
error nodes as `<err>`, empty nodes as `<empty>`, rule nodes as
`(label children...)` with the label omitted for precedence nodes and
`(label)` for a childless labelled node.

Accessors are range-safe: `tree_len`, `tree_node_kind/rule/token/start/end`
(`-1`), `tree_first_child`/`tree_next_sibling` (`-1`), `tree_child_count`
(0), `tree_child` (`-1`).

## 9. Error catalog

| Message | Condition |
|---|---|
| `parser: expected <label> at token <n>` | the furthest recorded failure has a rule label (`<n>` is a 0-based token index). |
| `parser: syntax error at token <n>` | the top-level parse failed with no labelled failure pending. |

Recovery errors use the same `expected` form at the failure position of the
failed iteration. The error list is ordered by occurrence; the first entry is
the first materialized failure.

## 10. API signatures

```xi
pub const P_KIND_NONE: Int = 0;          // ... through P_KIND_KEYWORD = 7
pub const P_RULE_EMPTY: Int = 0;         // ... through P_RULE_PREC = 8
pub const P_NODE_RULE: Int = 0;          // ... through P_NODE_EMPTY = 3

pub type TokenStream = { kinds: Vec[Int]; starts: Vec[Int]; ends: Vec[Int]; }
pub type KindTable = { words: Vec[Str]; kinds: Vec[Int]; }
pub type Grammar = { rule_kind: Vec[Int]; rule_label: Vec[Str];
                     rule_token: Vec[Int]; rule_a: Vec[Int]; rule_b: Vec[Int];
                     op_kind: Vec[Int]; op_lbp: Vec[Int]; op_rbp: Vec[Int];
                     pre_kind: Vec[Int]; pre_rbp: Vec[Int]; sync_kind: Vec[Int]; }
pub type ParseTree = { node_kind: Vec[Int]; node_rule: Vec[Int];
                       node_token: Vec[Int]; node_start: Vec[Int];
                       node_end: Vec[Int]; node_first: Vec[Int];
                       node_next: Vec[Int]; }
pub type PState = { pos: Int; errors: Vec[Str]; fail_pos: Int;
                    fail_label: Str; recovered: Int; max_errors: Int;
                    stopped: Bool; }
pub type ParseOutcome = { ok: Bool; root: Int; pos: Int; errors: Vec[Str];
                          error_count: Int; recovered: Int; stopped: Bool;
                          tree: ParseTree; }

pub fn ts_new() -> TokenStream
pub fn ts_push(t: &mut TokenStream, kind: Int, start: Int, end: Int)
pub fn ts_len(t: &TokenStream) -> Int
pub fn ts_kind(t: &TokenStream, i: Int) -> Int
pub fn ts_start(t: &TokenStream, i: Int) -> Int
pub fn ts_end(t: &TokenStream, i: Int) -> Int
pub fn ts_kind_name(kind: Int) -> Str
pub fn token_text(source: Str, t: &TokenStream, i: Int) -> Str

pub fn kt_new() -> KindTable
pub fn kt_add(t: &mut KindTable, word: Str, kind: Int)
pub fn kt_len(t: &KindTable) -> Int
pub fn kt_word(t: &KindTable, i: Int) -> Str
pub fn kt_kind(t: &KindTable, i: Int) -> Int
pub fn kt_lookup(t: &KindTable, word: Str) -> Int
pub fn kt_classify(t: &KindTable, word: Str) -> Int

pub fn grammar_new() -> Grammar
pub fn rule_empty(g: &mut Grammar, label: Str) -> Int
pub fn rule_token(g: &mut Grammar, token_kind: Int, label: Str) -> Int
pub fn rule_seq(g: &mut Grammar, a: Int, b: Int, label: Str) -> Int
pub fn rule_seq3(g: &mut Grammar, a: Int, b: Int, c: Int, label: Str) -> Int
pub fn rule_choice(g: &mut Grammar, a: Int, b: Int, label: Str) -> Int
pub fn rule_repeat0(g: &mut Grammar, child: Int, label: Str) -> Int
pub fn rule_repeat1(g: &mut Grammar, child: Int, label: Str) -> Int
pub fn rule_optional(g: &mut Grammar, child: Int, label: Str) -> Int
pub fn rule_eof(g: &mut Grammar, label: Str) -> Int
pub fn rule_prec(g: &mut Grammar, atom: Int, label: Str) -> Int
pub fn rule_patch_a(g: &mut Grammar, rule: Int, child: Int)
pub fn rule_patch_b(g: &mut Grammar, rule: Int, child: Int)
pub fn grammar_op_add(g: &mut Grammar, token_kind: Int, lbp: Int, rbp: Int)
pub fn grammar_prefix_add(g: &mut Grammar, token_kind: Int, rbp: Int)
pub fn grammar_sync_add(g: &mut Grammar, token_kind: Int)
pub fn grammar_rule_count(g: &Grammar) -> Int
pub fn grammar_is_consistent(g: &Grammar) -> Bool
pub fn grammar_rule_kind(g: &Grammar, r: Int) -> Int
pub fn grammar_rule_label(g: &Grammar, r: Int) -> Str
pub fn grammar_rule_token(g: &Grammar, r: Int) -> Int
pub fn grammar_rule_a(g: &Grammar, r: Int) -> Int
pub fn grammar_rule_b(g: &Grammar, r: Int) -> Int

pub fn parse_run(g: &Grammar, root: Int, ts: &TokenStream, max_errors: Int) -> ParseOutcome

pub fn tree_new() -> ParseTree
pub fn tree_len(tr: &ParseTree) -> Int
pub fn tree_node_kind(tr: &ParseTree, i: Int) -> Int
pub fn tree_node_rule(tr: &ParseTree, i: Int) -> Int
pub fn tree_node_token(tr: &ParseTree, i: Int) -> Int
pub fn tree_node_start(tr: &ParseTree, i: Int) -> Int
pub fn tree_node_end(tr: &ParseTree, i: Int) -> Int
pub fn tree_first_child(tr: &ParseTree, i: Int) -> Int
pub fn tree_next_sibling(tr: &ParseTree, i: Int) -> Int
pub fn tree_child_count(tr: &ParseTree, i: Int) -> Int
pub fn tree_child(tr: &ParseTree, i: Int, k: Int) -> Int
pub fn tree_span_text(source: Str, ts: &TokenStream, tr: &ParseTree, i: Int) -> Str
pub fn tree_to_sexpr(g: &Grammar, source: Str, ts: &TokenStream, tr: &ParseTree, node: Int) -> Str
```

Complexity: builders and accessors are O(1) except the linear operator/
sync-set lookups (O(|table|)) and tree walks (O(children)); the engine is
O(tokens * rules) in the worst case (full backtracking), bounded by the
iteration caps; `tree_to_sexpr` is O(tree size).

## 11. Test plan

`tests/test_conformance.xi` (module `parser_fw_tests`) runs 27 named checks
via `assert(cond, name)`, one `fn` per check, and `main` returns the failure
count (0 = green). Fixtures are built in-test: hand-pushed token streams, an
expression grammar (atoms, `+ - * /`, unary minus, parentheses) and a
statement-list grammar with a panic set.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | token stream | push/len/kind/start/end, EOF and -1 ranges, raw text, kind names (3) |
| t2 | kind table | exact lookup, identifier fallback, range safety (3) |
| t3 | grammar arena | builders, accessors, recursion patch, parallel-vector consistency (4) |
| t4 | empty and EOF rules | empty match, end-of-input guard, exact error (4) |
| t5 | token rule | kind match, span, cursor advance, token-node fields (5) |
| t6 | token rule failure | root -1, cursor restored, exact expected message (5, 9) |
| t7 | sequence rule | children in order, span, labelled S-expression (5) |
| t8 | sequence rollback | failed tail restores cursor and discards partial nodes (5) |
| t9 | choice first | first alternative wins without a wrapper node (5) |
| t10 | choice second | second alternative after a clean first failure (5) |
| t11 | choice diagnostics | furthest failure position and first label win (5) |
| t12 | repeat0 empty | one empty list node (5) |
| t13 | repeat0 many | child order and growing span (5) |
| t14 | repeat0 guard | zero-width child match stops the loop after one node (5) |
| t15 | repeat1 empty | no first match fails and rolls back completely (5) |
| t16 | repeat1 many | many matches succeed (5) |
| t17 | optional | present passes through, absent yields one empty node (5) |
| t18 | precedence add/mul | `*` binds tighter than `+` (6) |
| t19 | precedence mul/add | lower operator joins the completed group (6) |
| t20 | left associativity | `rbp = lbp + 1` (6) |
| t21 | prefix minus | prefix binds only its operand (6) |
| t22 | parentheses | override binding; recursion is data-driven (4, 6) |
| t23 | EOF guard | trailing tokens fail an expression-plus-EOF root (5) |
| t24 | panic recovery | skip to sync set, error node, parsing continues (7, 8) |
| t25 | recovery budget | `max_errors=1` stops after the first recovery (7) |
| t26 | tree accessors | sibling walk, child indexing, range safety (8) |
| t27 | determinism | repeated parses identical |

Determinism: parsing the same stream with the same grammar yields the same
tree, errors, cursor and recovery counts; the stream is never mutated.

## 12. Compiler / stdlib notes (pinned v0.62.2)

- No `Result` types at all: every fallible path returns `-1`/`Bool`/state, so
  the struct-payload `Ok`/`Err` construction trap cannot arise; no `match`
  statements are used.
- `Str` values read from `Vec[Str]` elements go through typed locals and are
  compared with `xiom.string.compare.str_compare` (BUG 17); Vec element reads
  use typed locals.
- Parallel Vecs are pushed only through the single sites `ts_push`,
  `_rule_push`, `_tree_push` and the operator registrars, so lengths cannot
  drift (trap 16); `grammar_is_consistent` pins the rule invariant in tests.
- No indexed `Vec[fn]` dispatch and no function values: rule dispatch is an
  explicit `if`-chain on the declared kind (trap 5).
- Recovery and tree walks are progress-guaranteed: loop guards, sibling-walk
  guards, no-progress stops and zero-width-match stops (trap D).
- Tree fields that are pushed but initially unset use sentinels (`-1`) and
  every walk checks them; no direct `UInt8` comparisons exist in this module
  (no byte domain), so the widen/mask trap does not apply.
