# xiom.gbnf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.gbnf` (`src/gbnf.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free codec for the llama.cpp GBNF grammar format:

- `gbnf_parse` -- grammar text -> `Result[GbnfGrammar, Str]`, an ordered rule
  list with one flat expression tree per rule,
- `gbnf_validate` -- grammar text -> `Result[Int, Str]` (rule count), without
  keeping the parsed structure,
- `gbnf_emit` -- canonical GBNF text of a parsed grammar,
- read-only accessors: rule count, rule name by index, root name, rule
  existence, node count and the referenced rule names of a rule.

Duplicates and unresolved references are validated. Validation is
conservative: only structural checks are performed, with no left-recursion
analysis, no reachability analysis and no ambiguity checks.

## 2. Non-goals

- Sample generation, inference, matching or any runtime engine for the
  grammar.
- Left-recursion detection, ambiguity analysis, or any grammar transformation.
- Full llama.cpp GBNF parity: `\uNNNN`/`\UNNNNNNNN` escapes, `{m,n}`
  repetition bounds, the `.` wildcard, JSON-schema-to-grammar conversion and
  any `@`/`!` extension are out of scope.
- Adjacent repetition suffixes (`"a"**`, `"a"*?`) and `a {2,3}` bounds.
- Rich positions (line/column); errors carry a byte offset only.
- File I/O, streaming parsing, or registry integration.
- NUL bytes inside string literal values (see section 3, decision 6).
- Any FFI.

## 3. Supported grammar

```
grammar      = *( ws / comment ) *( rule *( ws / comment ) )
rule         = name ws "::=" ws alternates
alternates   = sequence *( ws "|" ws sequence )
sequence     = term *( ws term )
term         = atom [ "*" / "+" / "?" ]
atom         = literal / class / group / name
group        = "(" ws alternates ws ")"
literal      = '"' *( escaped / any-byte-except-QUOTE-and-BACKSLASH ) '"'
class        = "[" [ "^" ] *( class-item ) "]"
class-item   = class-char [ "-" class-char ]       (range only when c2 >= c1)
class-char   = escaped / any-byte-except-RBRACKET-and-BACKSLASH
escaped      = (string)  "\"" / "\\" / "\n" / "\t" / "\r" / "\xHH"
             = (class)   "\]" / "\\" / "\n" / "\t" / "\r" / "\xHH" / "\-" / "\^"
name         = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" / "-" )
ws           = SPACE / TAB / LF / CR
comment      = "#" *( any-byte-except-LF )
HH           = exactly two hex digits (0-9, a-f, A-F)
```

Decisions (each is covered by the conformance suite):

1. **Rules.** The grammar is a sequence of rules. A rule is a name, `::=`, and
   an expression; rules may follow each other on the same line or on separate
   lines. A rule body ends at the next `name ::=` definition (after optional
   whitespace and comments), at a `|` or `)` handled by the enclosing
   alternation/group, or at end of input. A reference cannot therefore be
   followed directly by a new rule definition without changing meaning; write
   the next definition after a terminator such as a newline plus the next
   `name ::=`, which is exactly what this lookahead recognizes.
2. **Names.** `[A-Za-z_][A-Za-z0-9_-]*`. A digit cannot start a name, so
   `1abc ::= "x"` is `Err("gbnf: expected rule name at 0")`.
3. **Alternation and sequence.** `|` has lower precedence than juxtaposition.
   An alternation of n sequences becomes one n-ary ALT node (not a left-leaning
   chain); a sequence of n terms becomes one n-ary SEQ node. Empty
   alternates (`|` at the start, `a || b`, a trailing `|`) and empty groups
   (`()`) are `Err("gbnf: empty expression at <pos>")`.
4. **Grouping.** Parentheses are structural only and produce no node: a group
   evaluates to its inner expression's root. Redundant groups disappear in the
   canonical form and are re-added by the emitter exactly where precedence
   requires them.
5. **Repetition.** `*` (zero or more), `+` (one or more) and `?` (zero or one)
   apply to the immediately preceding atom, which must be adjacent (no
   whitespace between atom and suffix); at most one suffix per atom. `"a" *`
   and `"a"*?` are `Err("gbnf: unexpected byte at <pos>")`.
6. **String literals.** Any byte except an unescaped `"` or `\` is literal
   content, including spaces, `#` and raw newlines. Escapes decode `\"` to
   `"`, `\\` to `\`, `\n` to LF, `\t` to TAB, `\r` to CR and `\xHH` to the
   corresponding byte. `\x00` inside a literal is
   `Err("gbnf: NUL byte is not supported at <pos>")` because XIOM `Str` cannot
   carry a NUL byte. Any other backslash sequence is
   `Err("gbnf: invalid escape in string at <pos>")`; a `\x` without two hex
   digits is `Err("gbnf: invalid hex escape at <pos>")`. An unclosed literal
   is `Err("gbnf: unterminated string at <pos>")` at the opening quote.
7. **Character classes.** `[a-z]` is a range; `[abc]` is three single chars;
   `[^...]` negates. A `-` forms a range only when both neighbours are class
   chars and the character after `-` is not the closing `]`; otherwise `-` is
   a literal member (so `[-a]`, `[a-]` and `[a\-z]` are all valid). An escaped
   `\-` is always a literal `-`. A range whose second endpoint is below the
   first is `Err("gbnf: reversed character range at <pos>")`. `[]` and `[^]`
   are `Err("gbnf: empty character class at <pos>")`. Classes support the same
   escapes as strings except `\"`, plus `\]`, `\-` and `\^`; unknown escapes
   are `Err("gbnf: invalid escape in character class at <pos>")`. Unlike
   literals, a class may contain `\x00` (the class is stored as its canonical
   ASCII spelling, never as raw bytes). An unclosed class is
   `Err("gbnf: unterminated character class at <pos>")` at the `[`.
8. **Comments and whitespace.** Spaces, tabs, LF and CR are skipped between
   tokens, and `#` starts a comment that runs to end of line. Both are skipped
   outside literals and classes only; `#` inside a literal is data.
9. **Empty grammar.** Empty or comments-only input is valid: zero rules,
   `gbnf_emit` returns `""`.
10. **Root rule.** The first defined rule is the root by convention
    (`gbnf_root_name`); the name `root` is not required.
11. **Duplicates.** Defining the same name twice is
    `Err("gbnf: duplicate rule \"<name>\" at <pos>")` where `<pos>` is the
    start of the duplicate name.
12. **References.** A bare name inside an expression is a reference. All
    references are resolved after the whole grammar is read, so forward and
    self references are legal; an undefined target is
    `Err("gbnf: unresolved reference \"<ref>\" in rule \"<rule>\"")`. No
    left-recursion check is performed.
13. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise. Non-ASCII bytes pass through literals and classes untouched,
    and the canonical emitter keeps them raw, so multi-byte UTF-8 content
    survives the round-trip byte-exactly.

## 4. Data model

```xi
pub type GbnfGrammar = {
  names: Vec[Str];         // rule names, definition order
  roots: Vec[Int];         // node index of each rule's root
  rule_starts: Vec[Int];   // first node index of each rule's subtree
  node_kinds: Vec[Int];    // 0 literal, 1 class, 2 ref, 3 seq, 4 alt,
                           // 5 star,   6 plus,  7 optional
  node_texts: Vec[Str];    // leaf payload: decoded literal bytes,
                           // canonical "[...]" class text, or a rule name
  node_starts: Vec[Int];   // internal nodes: start of the child range
  node_counts: Vec[Int];   // internal nodes: child count (0 for leaves)
  node_children: Vec[Int]; // flat pool of child node indices
}
```

Invariants:

- `names`, `roots` and `rule_starts` have the same length (the rule count);
  `roots` is strictly increasing.
- Rule `i` owns nodes `rule_starts[i] ..= roots[i]`; `roots[i]` is its root and
  `roots[i] - rule_starts[i] + 1` is its node count. Slices are contiguous and
  ordered by rule.
- Nodes are postfix: every child index is smaller than its parent index.
- SEQ and ALT have `node_counts >= 1` / `>= 2` respectively; STAR, PLUS and
  OPT have exactly one child; leaves have `node_counts == 0` and
  `node_starts == 0`.
- `node_children` slices of different nodes are disjoint.

`Vec[StructType]` is not usable in this compiler, so the tree is deliberately
flat (parallel homogeneous vectors) instead of a tree of node structs.

## 5. Canonical form

`gbnf_emit` writes one line per rule, `name ::= expression` + LF, in
definition order:

- ALT children are joined with `" | "`, SEQ children with `" "`.
- A repetition suffix is written adjacent to its operand; the operand is
  parenthesized when it is itself a SEQ, ALT or repetition.
- An ALT child of a SEQ is parenthesized; groups around other expressions are
  dropped (SEQ is associative, ALT is associative).
- Literals are re-escaped per byte: `\"`, `\\`, `\n`, `\t`, `\r`, and `\xNN`
  (lower-case hex) for the other bytes `< 0x20` and for `0x7F`; all other
  bytes, including UTF-8 continuation bytes, are raw.
- Classes are rebuilt from their parsed members: `[` + optional `^` +
  members + `]`, where each member char is escaped with `\]`, `\\`, `\-`,
  `\^`, `\n`, `\t`, `\r` or `\xNN` (lower-case hex) for the other bytes
  `< 0x20` and `0x7F`; ranges are written `c1-c2` with the endpoints escaped
  the same way.
- Comments are dropped and all whitespace is normalized.

`gbnf_emit(gbnf_parse(gbnf_emit(gbnf_parse(t)))) == gbnf_emit(gbnf_parse(t))`
for every accepted `t` (idempotent round-trip, covered by the suite).
Emission is not byte-preserving: `\x4a` prints as `J`, `(("x"))` prints as
`"x"`, comments and original spacing are gone.

## 6. API signatures

```xi
pub type GbnfGrammar = { ... }

pub fn gbnf_parse(text: Str) -> Result[GbnfGrammar, Str]
pub fn gbnf_validate(text: Str) -> Result[Int, Str]
pub fn gbnf_emit(g: &GbnfGrammar) -> Str
pub fn gbnf_rule_count(g: &GbnfGrammar) -> Int
pub fn gbnf_rule_name(g: &GbnfGrammar, i: Int) -> Str
pub fn gbnf_root_name(g: &GbnfGrammar) -> Str
pub fn gbnf_has_rule(g: &GbnfGrammar, name: Str) -> Bool
pub fn gbnf_node_count(g: &GbnfGrammar, i: Int) -> Int
pub fn gbnf_rule_refs(g: &GbnfGrammar, i: Int) -> Vec[Str]
```

Complexity: parsing is O(total input length) plus O(rules) per duplicate-name
check; `gbnf_emit` is O(total node count); `gbnf_rule_name`, `gbnf_root_name`
and `gbnf_node_count` are O(1); `gbnf_has_rule` is O(rules); `gbnf_rule_refs`
is O(nodes of the rule). Out-of-range accessors return `""`, `-1` or an empty
vector; `gbnf_rule_refs` returns a fresh vector each call.

## 7. Error catalog

All failures are `Err(msg)` where `msg` starts with `"gbnf: "`. Parse-time
messages end with the offending byte offset (`0`-based); grammar-level
messages name the rule.

| Message | Trigger |
|---|---|
| `gbnf: expected rule name at <pos>` | top-level byte that cannot start a rule name (digit, punctuation, stray `)`) |
| `gbnf: expected '::=' at <pos>` | a name not followed by `::=` |
| `gbnf: duplicate rule "<name>" at <pos>` | the same rule name defined twice; `<pos>` = start of the duplicate name |
| `gbnf: empty expression at <pos>` | empty rule body, empty alternate (`a || b`, leading or trailing `|`) or empty group `()` |
| `gbnf: unexpected byte at <pos>` | a byte that starts no atom (e.g. `@`, `*` after whitespace, a second repetition suffix) |
| `gbnf: unterminated string at <pos>` | literal without a closing `"`; `<pos>` = opening quote |
| `gbnf: unterminated character class at <pos>` | class without a closing `]`; `<pos>` = opening `[` |
| `gbnf: unterminated group at <pos>` | group without a closing `)`; `<pos>` = opening `(` |
| `gbnf: empty character class at <pos>` | `[]` or `[^]` |
| `gbnf: reversed character range at <pos>` | range `c1-c2` with `c2 < c1`; `<pos>` = first endpoint |
| `gbnf: invalid escape in string at <pos>` | unknown backslash escape in a literal; `<pos>` = the backslash |
| `gbnf: invalid escape in character class at <pos>` | unknown backslash escape in a class |
| `gbnf: invalid hex escape at <pos>` | `\x` not followed by exactly two hex digits |
| `gbnf: NUL byte is not supported at <pos>` | `\x00` inside a string literal |
| `gbnf: unresolved reference "<ref>" in rule "<rule>"` | a reference to a rule that is never defined |

## 8. Test plan

`tests/test_conformance.xi` (module `gbnf_tests`) runs 30 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple rule | parse, rule/root/has/node accessors, canonical emit (decisions 3, 5) |
| t2 | ordered rule list | definition order in names and emission (decision 1) |
| t3 | alternation | n-ary ALT, canonical `" | "` (decision 3) |
| t4 | sequence | newlines between terms normalize, n-ary SEQ (decision 3) |
| t5 | grouping | group transparency, precedence, ALT-in-SEQ parentheses (decision 4) |
| t6 | repetition | `*` `+` `?` suffixes (decision 5) |
| t7 | repetition adjacency | group operands get parentheses; `"a" *`, `"a"*?` errors (decision 5) |
| t8 | string escapes | `\xNN \n \t \r \" \\` decode and re-escape (decision 6) |
| t9 | literal line spans | raw LF/CR/TAB inside literals canonicalize to escapes (decision 6) |
| t10 | control bytes | lower-case `\xNN`; `\x00` in a class is kept (decisions 6, 7) |
| t11 | classes | ranges, negation, literal sets (decision 7) |
| t12 | class dashes | `[-a]`, `[a-]`, `[a\-z]` canonicalize (decision 7) |
| t13 | class escapes | `\] \\ \^ \- \n` round-trip (decision 7) |
| t14 | class hex ranges | `[\x00-\x1f\x7f]`, `[A-Z]` (decision 7) |
| t15 | comments | full-line, trailing and mid-expression comments dropped (decision 8) |
| t16 | `#` in literals | hash is data inside `"..."` (decisions 6, 8) |
| t17 | compact input | `root::="a"|"b"` accepted and canonicalized (decisions 8, 5) |
| t18 | consecutive rules | forward references resolve after the grammar (decisions 1, 12) |
| t19 | reference order | `gbnf_rule_refs` source order, duplicates, empty (decision 12) |
| t20 | duplicate rules | exact message and duplicate-name offset (decision 11) |
| t21 | unresolved refs | exact message with ref and rule (decision 12) |
| t22 | unterminated | string/class/group report the opening offset (decisions 6, 7, 4) |
| t23 | empty classes/ranges | `[]`, `[^]`, `[z-a]` errors (decision 7) |
| t24 | empty expressions | bare body, leading/trailing/empty alternate, `()` (decision 3) |
| t25 | bad escapes | unknown string/class escape, `\x4`, trailing `\`, `\x00` in a literal (decision 6) |
| t26 | top-level errors | junk byte, missing `::=`, `@` atom, digit-led name, dangling reference (decisions 1, 2) |
| t27 | empty grammar | `""`, comments-only, `gbnf_validate` counts (decisions 9, 10) |
| t28 | validate/left recursion | error prefix `gbnf: `, self-reference accepted (decision 12) |
| t29 | realistic grammar | canonical form and idempotent round-trip (section 5) |
| t30 | out-of-range accessors | `""` / `-1` / empty vector (section 6) |

All `Str` comparisons go through `xiom.string.compare.str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a pointer
comparison).

## 9. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported packages):

- Free functions only; no methods on `GbnfGrammar`, no inline lambdas, no
  table-driven test dispatch (`main` calls `t1()` ... `t30()` directly).
- No `Vec[StructType]`: the expression tree is parallel homogeneous vectors,
  and the parser passes plain `Str` + `Int` + `&mut Int` state to helpers
  instead of a builder object.
- `Ok`/`Err` construction lives only in the leaf constructors `_ok_grammar`,
  `_err_grammar`, `_ok_int`, `_err_int`, `_ok_text`, `_err_text`;
  `gbnf_parse` (a struct-returning function) never builds `Ok`/`Err` itself.
- `Str` values read from `Vec[Str]` elements are compared with
  `xiom.string.compare.str_compare` (BUG 17); every `Vec[Int]` element read
  binds a typed `let x: Int = ...` local first.
- `Str` cannot carry a NUL byte in this compiler, which is why `\x00` is
  rejected in string literals (class spellings never contain raw NUL).
- Literal decoding accumulates into a `Vec[UInt8]` and materializes the
  result with `Str::from_utf8` (the `xiom.serialize.csv` idiom).

## 10. Known limitations

- Subset only: no `\uNNNN`/`\UNNNNNNNN`, no `{m,n}` bounds, no wildcard, no
  case-insensitive literals, no named/anchored constructs.
- No engine: the package cannot generate, sample, match or validate strings
  against the grammar, and it performs no grammar transformations.
- Validation is conservative: left recursion, unreachable rules and ambiguous
  alternations are accepted silently.
- `\x00` is unusable in string literal values (see section 3, decision 6).
- Canonical emission is not byte-preserving; comments, grouping and escape
  spellings are normalized.
- Errors carry byte offsets only, not line/column positions.
- Duplicate detection and reference resolution are exact and case-sensitive.
