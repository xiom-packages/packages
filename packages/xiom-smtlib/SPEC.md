# xiom.smtlib -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.smtlib` (`src/smtlib.xi`). Pure XIOM, no FFI.

## 1. Scope

A pure-XIOM SMT-LIB2 text reader and canonical emitter for a documented
subset:

- `smtlib_parse`: scan and parse one `Str` into a flat `SmtDoc`, validating
  the lexical rules below and the shape of the ten supported top-level
  commands;
- a flat node model (parallel vectors plus child ranges) with a command
  index, byte offsets, and read-only accessors for kinds, texts, parents,
  children and command arguments;
- `smtlib_emit`: canonical serialization (one command per line, single
  spaces between list elements, canonical string escapes), stable under
  reparse.

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise. Node
text is a slice of the input except for strings, whose escapes are decoded
(decoding only produces the bytes the escape table defines, so valid input
stays valid UTF-8). Terms and sort expressions are pass-through data.

## 2. Non-goals

- No solving, no sort checking, no type inference, no proof production or
  checking, no model construction, no SMT-LIB 2.6 semantic validation.
- No commands beyond the ten in section 6 (`declare-sort`, `define-sort`,
  `push`/`pop`, `get-value`, `define-fun-rec`, ... are
  `smtlib: unknown command`).
- No quoted symbols (`|...|`), no `#x`/`#b` constants, no `\u{...}`
  escapes, no indexed-identifier sugar beyond treating lists as sorts/terms.
- No macro expansion or special treatment of `let`, `forall`, `exists`,
  `!`, `as`, `_`, `match`: everything inside a term is pass-through.
- No s-expression attribute values in `set-option`/`set-info` (atoms only).
- No error recovery: the first bad construct aborts the parse with one
  deterministic `Err`; no partial documents.
- No comments in the emitted output; no preservation of original spacing.
- No line/column tracking (byte offsets only), no streaming, no file I/O.

## 3. Lexical grammar

Whitespace (space, tab, LF, CR) separates tokens. A `;` comment runs to the
next LF or CR (or end of input) and is skipped anywhere a token may start.
Tokens:

```
document   = *( ws | comment | command )
comment    = ";" *( any-byte except LF and CR )
command    = "(" s-expr* ")"                       (shape-validated)
s-expr     = atom | "(" s-expr* ")"
atom       = symbol | keyword | numeral | decimal | string

symbol     = symbol-start *symbol-char
symbol-char= "a".."z" | "A".."Z" | "0".."9"
           | "~" | "!" | "@" | "$" | "%" | "^" | "&" | "*" | "_"
           | "+" | "=" | "<" | ">" | "." | "?" | "/" | "-"
symbol-start = symbol-char except a digit

keyword    = ":" symbol-start *symbol-char          (text keeps the ":")

numeral    = "0" | ( "1".."9" ) *digit
decimal    = numeral "." 1*digit                    (fraction may use zeros)
```

Decisions (each is covered by the conformance suite):

1. **Symbols.** A maximal run of symbol characters starting with a
   non-digit, non-`:` byte. `+`, `-`, `=`, `<`, `>`, `.` and words like
   `true` or `QF_LIA` are symbols. `1a`, `1.5e3`, `1-2` and `007` are
   malformed numbers (see rule 4), not symbol/numeral pairs.
2. **Keywords.** `:` followed by a symbol start and symbol characters; the
   stored text includes the colon (`:named`). `:1`, `:` alone and `:(` are
   `smtlib: malformed keyword` at the colon.
3. **Numerals.** `0` or a non-zero digit followed by digits. A leading zero
   (`007`) is `smtlib: malformed numeric token` at the first digit; there
   is no sign and no leading `+` (a leading `-`/`+` starts a symbol).
4. **Decimals.** Integer part as a numeral, then `.`, then at least one
   digit (`0.5`, `3.14`, `10.00`; fraction leading zeros are allowed). A
   dangling dot (`1.`), a missing integer part (`.5` is the symbol `.5`),
   and a symbol character directly after the digits (`1a`, `1.5e3`,
   `1.2.3`) are `smtlib: malformed numeric token` at the first digit.
   Both numerals and decimals are validated text tokens; no float
   conversion happens and the source text is preserved verbatim.
5. **Strings.** Open with `"` and close with the next unescaped `"`.
   `""` decodes to one `"`; inside the quotes, `\\`, `\"`, `\n`, `\r` and
   `\t` decode to backslash, quote, LF, CR and TAB (the
   doubled-quote-and-backslash subset; `\u{...}` is not supported). Any
   other backslash sequence is `smtlib: invalid escape` at the backslash.
   A raw LF/CR/TAB inside a string is kept verbatim; a raw NUL byte is
   rejected. End of input before the closing quote (including a trailing
   backslash) is `smtlib: unterminated string` at the opening quote.
6. **Comments.** `;` starts a comment; it is skipped like whitespace, but a
   `;` inside a string is literal text.
7. **Empty input.** An empty or comments-only document parses to zero nodes
   and zero commands (not an error); `smtlib_emit` returns `""`.
8. **Depth.** Lists may nest at most 128 deep on any path (the command list
   plus 127 nested lists); the next level is
   `smtlib: nesting depth exceeds limit of 128`.
9. **Determinism.** Parsing the same text yields the same nodes, offsets,
   commands and errors; the input is never mutated.

## 4. Document model

`SmtDoc` stores nodes in depth-first pre-order (one entry per list and per
atom), all in parallel vectors; `Vec[StructType]` is not used because XIOM
v0.61.3 cannot hold it:

- node 0 is the root list of the first command, and `commands[c]` is the
  root node of the c-th top-level command in source order;
- `kinds[i]` is one of the kind codes; `texts[i]` is the source text for
  symbols/keywords/numerals/decimals, the decoded content for strings, and
  `""` for lists;
- `parents[i]` is the containing list node, `-1` for a command root;
- node `i`'s direct children are the contiguous slice
  `children[child_starts[i] .. child_starts[i] + child_lengths[i]]`
  (`child_lengths[i] == 0` for atoms); the slice is in source order;
- `starts[i]`/`ends[i]` are the byte offsets of the node in the parsed
  input: an atom spans its token, a list spans its `(` through its `)`.

Kind codes: `smtlib_kind_list()` = 0, `smtlib_kind_symbol()` = 1,
`smtlib_kind_keyword()` = 2, `smtlib_kind_numeral()` = 3,
`smtlib_kind_decimal()` = 4, `smtlib_kind_string()` = 5;
`smtlib_kind_name(k)` maps a code to `"list"`, `"symbol"`, `"keyword"`,
`"numeral"`, `"decimal"`, `"string"` or `""`.

Accessor conventions: out-of-range indices never panic and return `-1`
(integers and node indices), `""` (texts) or `0` (counts). `smtlib_kind`
returns `-1` out of range, which no valid document contains, so it is safe
as a validity probe.

## 5. Shape predicates

- **Sort:** a symbol node, or a non-empty list node. The contents of a list
  sort are not validated (no sort checking).
- **Term:** any atom except a keyword, or a non-empty list node. The
  contents of a term list are not validated (pass-through).
- **Attribute value:** a symbol, numeral, decimal or string node (no
  keywords, no lists).

## 6. Command table

Commands are validated in source order after the whole document is parsed.
For each command the head must be a symbol: a non-symbol head is
`smtlib: misplaced token`; an unknown symbol is
`smtlib: unknown command '<name>'`; `()` is `smtlib: empty command`. Arity
is checked first, then arguments left to right.

| Command | Accepted shape | Argument checks |
|---|---|---|
| `set-logic` | `(set-logic <symbol>)` | 1 arg, symbol. |
| `set-option` | `(set-option <keyword> <atom>)` | 2 args; arg 1 keyword; arg 2 attribute value. |
| `set-info` | `(set-info <keyword> <atom>)` | 2 args; arg 1 keyword; arg 2 attribute value. |
| `declare-const` | `(declare-const <symbol> <sort>)` | 2 args; symbol; sort. |
| `declare-fun` | `(declare-fun <symbol> (<sort> ...) <sort>)` | 3 args; symbol; arg 2 list whose items are sorts; arg 3 sort. |
| `define-fun` | `(define-fun <symbol> ((<name> <sort>) ...) <sort> <term>)` | 4 args; symbol; arg 2 list of 2-element lists (symbol then sort); arg 3 sort; arg 4 term. |
| `assert` | `(assert <term>)` | 1 arg, term. |
| `check-sat` | `(check-sat)` | 0 args. |
| `get-model` | `(get-model)` | 0 args. |
| `exit` | `(exit)` | 0 args. |

`(declare-fun f ())` (missing return sort) is the arity error
`smtlib: declare-fun expects 3 arguments, got 2`. Parameter lists may be
empty (`(declare-fun f () Bool)` is accepted). `(default)` and any other
head symbol is `smtlib: unknown command`.

## 7. Error catalog

All messages are fixed: `"smtlib: "` + text + optional decimal position
built with `xiom.convert.int_to_string`. Positions are byte offsets into the
parsed input. The first error aborts the parse.

| Message | Condition | Position |
|---|---|---|
| `smtlib: unexpected byte at <pos>` | a byte that starts no token (punctuation, `#`, `\|`, `[`, non-ASCII outside a string, ...); also a raw NUL byte inside a string | the byte |
| `smtlib: malformed keyword at <pos>` | `:` not followed by a symbol start (digit, whitespace, paren, end of input) | the colon |
| `smtlib: malformed numeric token at <pos>` | leading zero in the integer part; decimal point with no fraction digit; symbol character directly after the digits | the first digit |
| `smtlib: invalid escape at <pos>` | a backslash followed by a byte other than `"`, `\`, `n`, `r`, `t` inside a string | the backslash |
| `smtlib: unterminated string at <pos>` | no closing `"` before end of input, including a trailing backslash | the opening quote |
| `smtlib: unbalanced parenthesis at <pos>` | an unmatched `)`; or a list whose closing `)` is missing | the `)`; or the unclosed `(` |
| `smtlib: expected command at <pos>` | a top-level token that is an atom (symbol/keyword/numeral/decimal/string) | the atom |
| `smtlib: empty command at <pos>` | a top-level `()` | the `(` |
| `smtlib: misplaced token at <pos>` | a command whose head is not a symbol | the head |
| `smtlib: unknown command '<name>' at <pos>` | head symbol not in the section-6 table | the head |
| `smtlib: nesting depth exceeds limit of 128` | a list nested at depth 128 | none |
| `smtlib: <cmd> expects <n> argument(s), got <m>` | wrong argument count (`argument` for 1, `arguments` otherwise) | none |
| `smtlib: <cmd> expects <what> at <pos>` | wrong argument kind: `a symbol`, `a keyword`, `an atom`, `a sort`, `a term`, `a parameter list`, `a sorted variable` | the argument node |

Example: `(declare-const x 3)` ->
`smtlib: declare-const expects a sort at 17`; `(set-logic :foo)` ->
`smtlib: set-logic expects a symbol at 11`.

## 8. API contract

```xi
pub type SmtDoc = {
  kinds: Vec[Int]; texts: Vec[Str]; parents: Vec[Int];
  child_starts: Vec[Int]; child_lengths: Vec[Int]; children: Vec[Int];
  starts: Vec[Int]; ends: Vec[Int]; commands: Vec[Int];
}

pub fn smtlib_kind_list() -> Int
pub fn smtlib_kind_symbol() -> Int
pub fn smtlib_kind_keyword() -> Int
pub fn smtlib_kind_numeral() -> Int
pub fn smtlib_kind_decimal() -> Int
pub fn smtlib_kind_string() -> Int
pub fn smtlib_kind_name(k: Int) -> Str
pub fn smtlib_max_depth() -> Int

pub fn smtlib_parse(text: Str) -> Result[SmtDoc, Str]
pub fn smtlib_emit(doc: &SmtDoc) -> Str

pub fn smtlib_node_count(doc: &SmtDoc) -> Int
pub fn smtlib_command_count(doc: &SmtDoc) -> Int
pub fn smtlib_kind(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_node_text(doc: &SmtDoc, i: Int) -> Str
pub fn smtlib_symbol_text(doc: &SmtDoc, i: Int) -> Str
pub fn smtlib_parent(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_child_count(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_child_start(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_child(doc: &SmtDoc, i: Int, n: Int) -> Int
pub fn smtlib_node_start(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_node_end(doc: &SmtDoc, i: Int) -> Int
pub fn smtlib_command_node(doc: &SmtDoc, c: Int) -> Int
pub fn smtlib_command_head(doc: &SmtDoc, c: Int) -> Int
pub fn smtlib_command_name(doc: &SmtDoc, c: Int) -> Str
pub fn smtlib_command_arg_count(doc: &SmtDoc, c: Int) -> Int
pub fn smtlib_command_arg(doc: &SmtDoc, c: Int, a: Int) -> Int
```

Cost: `smtlib_parse` is O(n) over the input bytes plus the counting sort
that builds child ranges, O(nodes); `smtlib_emit` is O(total node text);
all accessors are O(1).

## 9. Emitter and round trip

`smtlib_emit` is canonical, not a formatter for the input's spacing:

1. one command per line, LF between commands and **no** trailing newline;
   an empty document yields `""`;
2. list elements are separated by exactly one space; parentheses are not
   padded;
3. symbols/keywords/numerals/decimals are copied verbatim (so `0.50` stays
   `0.50`);
4. string content is re-escaped as `""` for `"`, `\\` for `\`, `\n` for LF,
   `\r` for CR, `\t` for TAB, and every other byte verbatim;
5. comments are dropped.

Round-trip guarantee: for every document `d` produced by
`smtlib_parse(text)`, `smtlib_parse(smtlib_emit(d))` succeeds and yields the
same node kinds, texts, parent links, child counts, child order and command
roots; `smtlib_emit` is idempotent (`emit(parse(emit(d))) == emit(d)`).
Source offsets may differ wherever the canonical text differs from the
input (whitespace, comments, escape spelling).

## 10. Test plan

`tests/test_conformance.xi` (module `smtlib_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full script | all ten command heads parse, in source order (section 6) |
| t2 | declare-fun accessors | symbol, parameter list contents, return sort, arg bounds |
| t3 | comments | `;` skipped outside strings, literal inside (rule 6) |
| t4 | emitter spacing | single-space normalization, LF join, empty document (9.1-9.2) |
| t5 | numerals/decimals | kind split and verbatim text (rules 3-4) |
| t6 | doubled quote | `""` decodes and re-emits canonically (rule 5) |
| t7 | backslash escapes | `\n \t \\ \" \r` decode (rule 5) |
| t8 | emitter escapes | canonical escapes are a fixed point (9.4) |
| t9 | keywords | `:name` keeps the colon; symbol/decimal values (rule 2) |
| t10 | sorts | symbol sorts, nested sort lists, empty parameter list |
| t11 | define-fun | 2-element parameters, return sort, body accessors |
| t12 | assert attributes | `!`/`:named` pass through and normalize |
| t13 | empty input | zero nodes/commands, `""` emit (rule 7) |
| t14 | round trip | shape stability and emit idempotence (section 9) |
| t15 | unbalanced parens | extra `)` and missing `)` positions |
| t16 | string errors | unterminated quote, invalid escape, trailing backslash |
| t17 | numeric errors | leading zero, dangling dot, trailing symbol char |
| t18 | command errors | empty, expected, unknown, misplaced (section 6) |
| t19 | arity errors | missing/extra args, `declare-fun` missing return sort |
| t20 | argument kinds | symbol/keyword/atom/sort/parameter-list errors |
| t21 | define-fun shapes | parameter list, sorted variables, sort, term |
| t22 | accessor bounds | `-1`/`""`/`0` for every out-of-range shape (section 4) |
| t23 | depth limit | 128 lists accepted, 129 rejected (rule 8) |
| t24 | positions/determinism | byte ranges, child order, repeated parses agree |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); helpers `parse_ok`, `parse_err`, `emit_of`,
`tree_shape_eq` and `roundtrip_stable` compare whole results field by field.

## 11. Known limitations

- Fixed command set and fixed shapes; term/sort contents are pass-through,
  so `(assert (bogus :x))` is accepted while `(assert :x)` is not.
- No quoted symbols, `#x`/`#b` constants, `\u{...}` escapes or
  s-expression attribute values.
- Numbers stay text: no value range checks, no float parsing, no rounding.
- First-failure-only errors with byte offsets; no recovery, no partial
  documents, no line/column.
- The nesting limit is 128 lists per path; deeper documents are rejected.
- Comments and original whitespace are not preserved by the emitter.
- Non-ASCII bytes outside strings are `smtlib: unexpected byte`, so
  symbols are ASCII-only (SMT-LIB simple symbols are ASCII by definition).
- NUL bytes are rejected; `smtlib_emit` is not a byte-for-byte formatter for
  arbitrary binary-ish input.

## 12. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported codecs):

- Free functions only; no methods on `SmtDoc`.
- No `Vec[StructType]`: `SmtDoc` is parallel vectors plus one flat
  `children` array with `child_starts`/`child_lengths` ranges, built with a
  counting sort by parent (the `xiom.plist` idiom).
- `Ok`/`Err` construction lives only in the leaf helpers `_ok_int`,
  `_err_int`, `_ok_doc` and `_err_doc`; `smtlib_parse` returns through
  `_ok_doc(_finish(...))`.
- `Str` values read from `Vec[Str]` elements are bound to typed locals and
  compared with `xiom.string.compare.str_compare` (BUG 17); `.len()` is
  never called on an element expression directly.
- `Vec[Int]` element reads use typed locals; byte reads widen with
  `(b as Int) & 0xFF` before entering Int arithmetic or comparisons.
- Strings are materialized from a `Vec[UInt8]` buffer with
  `Str::from_utf8`; `xiom.string.builder.sb_push_str` appends into the
  emitter buffer (never `sb_to_str`, which NUL-terminates).
- No `Vec[fn]` dispatch, no generics, no `mut` match patterns, no
  `Float64`; all matches are exhaustive and every parallel vector is
  pushed together in `_push_tok`/`_push_node`, with guards on every
  accessor.
