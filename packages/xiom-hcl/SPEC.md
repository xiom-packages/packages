# xiom.hcl -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.hcl` (`src/hcl.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free structural parser for a documented HCL2 subset:

- `hcl_parse` -- document text -> `Result[HclDoc, Str]`,
- counts, per-body navigation, first-match attribute lookup,
- `hcl_emit` -- `HclDoc` -> canonical HCL text.

The parser understands attributes, nested blocks, labels, comments and
whitespace. It never evaluates expressions, resolves variables or applies a
schema; expression text is stored raw and re-emitted verbatim. Heredocs,
functions/for-expressions and interpolation are out of scope and documented
as errors or raw text respectively.

## 2. Data model

```xi
pub type HclDoc = {
  source: Str;                  // the exact input text (for body slicing)
  attr_names: Vec[Str];         // attribute name, document order
  attr_values: Vec[Str];        // raw expression text, trimmed at both ends
  attr_lines: Vec[Int];         // 1-based line where the attribute starts
  attr_parents: Vec[Int];       // owning block index, -1 = top level
  attr_offsets: Vec[Int];       // byte offset of the name (emit ordering)
  block_types: Vec[Str];        // block type name, document order
  block_label_counts: Vec[Int]; // number of labels of each block
  block_label_starts: Vec[Int]; // first index into block_labels
  block_labels: Vec[Str];       // flat pool of decoded labels
  block_parents: Vec[Int];      // owning block index, -1 = top level
  block_body_starts: Vec[Int];  // byte after "{" (body slice start)
  block_body_ends: Vec[Int];    // byte of "}" (body slice end, exclusive)
  block_lines: Vec[Int];        // 1-based line where the block starts
  block_offsets: Vec[Int];      // byte offset of the type name
}
```

Invariants:

- `attr_names.len() == attr_values.len() == attr_lines.len() ==
  attr_parents.len() == attr_offsets.len()`; the same holds for the eight
  block vectors.
- Attribute and block indices are document order (the order the statements
  begin), across all nesting levels. `attr_offsets`/`block_offsets` let a
  body restore the original interleaved order of its attributes and blocks.
- For every block `i`, labels live in
  `block_labels[block_label_starts[i] .. block_label_starts[i] +
  block_label_counts[i]]`; the label pool has no other readers.
- `block_body_starts[i] <= block_body_ends[i]` and both are byte offsets
  into `source`; the body text is `source[start..end)`.
- `-1` means top level for `attr_parents`/`block_parents`; accessors return
  `-2` for an out-of-range index so it cannot be confused with top level.

`Vec[StructType]` is not usable in this compiler, so the document is
deliberately flat (parallel homogeneous vectors) instead of a tree of
block structs.

## 3. Grammar

```
document   = *( statement / trivia )
statement  = attribute / block / "}"            ; "}" closes the open block
attribute  = ident h-ws "=" h-ws expression
block      = ident *( h-ws label ) h-ws "{" *( statement / trivia ) "}"
label      = '"' *( escaped-byte / byte-except-'"'-LF ) '"'
trivia     = h-ws / newline / comment
comment    = "#" *( byte except LF ) / "//" *( byte except LF ) / "/*" ... "*/"
expression = *( byte-except-LF / quoted-string / bracket-at-depth>0-LF )
             ; ends at LF or a depth-0 "#", "//" or "/*"
ident      = ( letter / "_" ) *( letter / digit / "_" / "-" )
h-ws       = SP / TAB
```

Decisions (each is covered by the conformance suite):

1. **Lines.** LF terminates a line; a CR before LF is whitespace and is
   skipped. A final line without a newline is still parsed. A UTF-8 BOM is
   not stripped and becomes the first identifier byte (which makes it a
   stray token).
2. **Whitespace.** Spaces, tabs, CRs and blank lines are tolerated anywhere
   between statements and inside block headers. Spaces and tabs are
   equivalent; newlines are allowed inside an expression only while a
   bracket is open.
3. **Comments.** `#` and `//` run to the end of the line; `/* ... */` spans
   lines and does not nest (the first `*/` closes it). Comments are parsed
   and dropped: nothing is stored and `hcl_emit` never writes comments.
   Comments are recognized between statements and at expression
   depth 0; a comment marker inside a quoted string is data.
4. **Attribute values (raw capture).** The value is every byte after the
   `=` up to the end of its logical line, with the edge whitespace trimmed
   and CR removed by `str_trim`. Inside the capture, quoted strings skip
   escaped bytes, and `[ ] { } ( )` must nest and close in order; an
   unmatched, extra or mismatched closer is
   `Err("hcl: unbalanced brackets in expression at line N")`. Multi-line
   lists/objects therefore capture whole: the capture continues across LFs
   while at least one bracket is open.
5. **Expression termination at depth 0.** An LF, `#`, `//` or `/*` at
   bracket depth 0 outside a string ends the expression. `//` is a comment,
   never division, so an unquoted URL ends at `http:`. A value cannot start
   with a comment: `a = # c` and `a = /* c */ 1` are
   `Err("hcl: missing attribute value at line N")`.
6. **Quoted strings.** `"..."` inside an expression may contain escaped
   bytes (`\` plus the next byte, not decoded) and must close before the
   end of the line: a raw LF or EOF inside is
   `Err("hcl: unterminated string in expression at line N")`.
7. **Identifiers.** Letters, digits, `_` and `-`; the first byte must be a
   letter or `_`. Attribute names are bare identifiers (no dotted paths).
8. **Blocks.** `type` followed by zero or more quoted labels on the same
   line, then `{`; the body runs to the matching `}` (nested blocks counted)
   and its byte range is stored verbatim. Two labels may not decode to the
   same text within one header:
   `Err("hcl: duplicate block label at line N")`. Repeated blocks with the
   same type and labels at the same level are allowed and both retained.
9. **Labels.** A label's text is decoded: `\"` becomes `"` and `\\` becomes
   `\`; any other backslash escape is
   `Err("hcl: invalid escape in block label at line N")`. An LF or EOF
   before the closing quote is
   `Err("hcl: unterminated string in block label at line N")`.
10. **Duplicate attributes.** A repeated attribute name in one body is
    allowed: all copies are stored in document order and
    `hcl_attr_lookup_in` returns the first (lowest index). This is the
    documented policy; HCL schemas may reject duplicates, but the structural
    parser does not.
11. **Heredocs.** `<<` at the start of an expression is rejected with
    `Err("hcl: heredocs are not supported at line N")`; `<<` in any other
    position is raw text.
12. **NUL bytes.** Any NUL byte anywhere in the input is rejected with
    `Err("hcl: NUL byte in input at line N")`. `sb_to_str` truncates at a
    NUL, so this guard keeps `hcl_emit` lossless for every parsed document.
13. **Emission.** One statement per line, LF line endings (output ends with
    LF unless the document is empty), attributes as `name = value` with
    single spaces around `=`, blocks as `type "label" "label2" {`, `{}` for
    a block with no children, and two spaces of indentation per nesting
    level. Bodies are emitted in original document order (attributes and
    blocks interleaved as parsed). Values are written verbatim, so a value
    with internal LFs keeps its own continuation indentation.
14. **Round trip.** A canonical document (exactly what `hcl_emit` writes,
    built from single-line attribute values or values whose continuation
    lines are already canonical) parses and re-emits byte-for-byte, and
    emit is idempotent for every parsed document.
15. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning
    is byte-wise; only ASCII bytes are special, so non-ASCII names, labels
    and values pass through byte-exact.

## 4. API signatures

```xi
pub fn hcl_parse(text: Str) -> Result[HclDoc, Str]
pub fn hcl_emit(d: &HclDoc) -> Str

pub fn hcl_attr_total(d: &HclDoc) -> Int
pub fn hcl_block_total(d: &HclDoc) -> Int
pub fn hcl_attr_count_in(d: &HclDoc, parent: Int) -> Int
pub fn hcl_attr_count(d: &HclDoc) -> Int
pub fn hcl_block_count_in(d: &HclDoc, parent: Int) -> Int
pub fn hcl_block_count(d: &HclDoc) -> Int
pub fn hcl_child_total(d: &HclDoc, parent: Int) -> Int

pub fn hcl_attr_name(d: &HclDoc, idx: Int) -> Str
pub fn hcl_attr_value(d: &HclDoc, idx: Int) -> Str
pub fn hcl_attr_line(d: &HclDoc, idx: Int) -> Int
pub fn hcl_attr_parent(d: &HclDoc, idx: Int) -> Int

pub fn hcl_block_type(d: &HclDoc, idx: Int) -> Str
pub fn hcl_block_line(d: &HclDoc, idx: Int) -> Int
pub fn hcl_block_parent(d: &HclDoc, idx: Int) -> Int
pub fn hcl_block_label_count(d: &HclDoc, idx: Int) -> Int
pub fn hcl_block_label(d: &HclDoc, idx: Int, k: Int) -> Str
pub fn hcl_block_labels(d: &HclDoc, idx: Int) -> Vec[Str]
pub fn hcl_block_body_start(d: &HclDoc, idx: Int) -> Int
pub fn hcl_block_body_end(d: &HclDoc, idx: Int) -> Int
pub fn hcl_block_body(d: &HclDoc, idx: Int) -> Str
pub fn hcl_child_block(d: &HclDoc, parent: Int, k: Int) -> Int
pub fn hcl_child_attr(d: &HclDoc, parent: Int, k: Int) -> Int
pub fn hcl_attr_lookup_in(d: &HclDoc, parent: Int, name: Str) -> Int
pub fn hcl_attr_lookup(d: &HclDoc, name: Str) -> Int
pub fn hcl_attr_value_in(d: &HclDoc, parent: Int, name: Str) -> Option[Str]
```

Complexity: parsing is O(total input length) plus one byte scan per captured
byte; accessors that filter by parent are O(total attribute/block count);
`hcl_emit` is O(total output length * document size) in the worst case
because each body filters its children from the flat vectors.

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"hcl: "` and `N`
is the 1-based line of the offending statement (or comment/label):

| Message | Trigger |
|---|---|
| `hcl: unmatched '}' at line N` | a `}` with no open block, e.g. `}` or `a { } }` |
| `hcl: unterminated block starting at line N` | EOF while a block is open |
| `hcl: unterminated string in expression at line N` | LF or EOF inside `"..."` in a value |
| `hcl: unbalanced brackets in expression at line N` | extra/mismatched closer, or EOF with a bracket still open |
| `hcl: unterminated string in block label at line N` | LF or EOF inside a label's quotes |
| `hcl: invalid escape in block label at line N` | `\x` other than `\"` and `\\` in a label |
| `hcl: unterminated block comment at line N` | `/*` with no closing `*/` before EOF |
| `hcl: invalid attribute name at line N` | statement begins with `=` |
| `hcl: missing attribute value at line N` | `a =`, `a = # c`, `a = /* c */ 1` |
| `hcl: heredocs are not supported at line N` | value starts with `<<` |
| `hcl: block has no type at line N` | statement begins with `"` or `{` |
| `hcl: expected '=' or '{' after '<name>' at line N` | `foo`, `foo bar` |
| `hcl: expected '{' after block labels at line N` | `a "x"`, `a "x" = 1` |
| `hcl: duplicate block label at line N` | `b "x" "x" {}` |
| `hcl: stray token at line N` | any other statement byte, e.g. `+ 1`, `123 = 4` |
| `hcl: NUL byte in input at line N` | an actual NUL byte anywhere |

The accessors and `hcl_emit` are total: every out-of-range index yields the
documented empty value (`""`, `0`, `-1`, `-2`, empty `Vec[Str]`, `None`).

## 6. Test plan

`tests/test_conformance.xi` (module `hcl_tests`) runs 26 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | top-level attributes | names, raw values, lines, parents, zero blocks |
| t2 | comments | `#`, `//`, `/* */`, trailing, inline; markers in strings are data |
| t3 | labeled block | type, two labels, parent -1, line, body attributes |
| t4 | nested blocks | parent indices, child navigation, body attrs, sibling order |
| t5 | multi-line capture | list and object values whole; `#`/`//`/`]`/`/*` in strings ignored |
| t6 | CRLF/whitespace | CRLF, tabs, blank lines; canonical emit |
| t7 | duplicate attributes | allowed; lookup first-match; `None` for absent |
| t8 | scoped lookup | per-body `hcl_attr_lookup_in`; top-level `k` is the last attr |
| t9 | canonical emit | exact bytes: 2-space indent, normalized spacing, comments dropped |
| t10 | round trip | canonical input emit == input; second emit identical |
| t11 | empty block | `{}` form, re-parses, idempotent |
| t12 | label escapes | `\"`/`\\` decode and re-encode exactly |
| t13 | unbalanced braces | unmatched `}`, unterminated block at EOF |
| t14 | string errors | LF/EOF in expression strings, correct line |
| t15 | comment error | unterminated `/* */`, correct line |
| t16 | label errors | LF/EOF in labels |
| t17 | escape error | `\q` rejected; `\\` accepted |
| t18 | statement errors | bad name, missing value, stray token, no type, no brace |
| t19 | bracket errors | extra, mismatched, EOF-open brackets; balanced mix accepted |
| t20 | heredocs | `<<EOF`/`<<-EOF` rejected; `a = 1 << 2` raw |
| t21 | duplicate labels | same-header duplicate rejected; repeated blocks allowed |
| t22 | empty documents | `""` and comment-only parse to zero and emit `""` |
| t23 | body ranges | exact start/end offsets and verbatim body slice |
| t24 | nesting depth | 3 levels emit with correct per-level indentation |
| t25 | `//` handling | unquoted URL truncates; quoted URL preserved |
| t26 | line numbers | correct across multi-line values and comments |

All element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 7. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.ini`/`xiom.toml` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is fourteen parallel
  homogeneous vectors plus `source` (no `Vec[HclBlock]`).
- `Ok`/`Err` for `Result[HclDoc, Str]` (a struct payload) are constructed
  only in the leaf helpers `_ok_doc`/`_err_doc`.
- Str equality between `Vec[Str]` elements goes through `str_compare`
  (BUG 17); elements are read into typed locals before comparison or use.
- `Vec.pop()` is used as a statement to pop the bracket/block stacks; the
  value is read into a typed local first.
- Recursive descent is avoided: the parser keeps an explicit
  `Vec[Int]` stack of open block indices, and the emitter recurses through
  `_emit_body`/`_emit_block` (self- and mutual recursion both compile on
  v0.61.3).
- Tests dispatch directly (`t1()` ... `t26()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, and every `match` is exhaustive.

## 8. Known limitations

- No expression evaluation, type system, schema validation, variables,
  functions, for-expressions or interpolation; values are raw text.
- No heredocs (explicit error); no `<<` handling beyond the start-of-value
  rejection.
- Comments and original formatting are not preserved; emit normalizes them.
- Duplicate attributes are allowed with first-match lookup; this is looser
  than Terraform's own duplicate-attribute rejection.
- Only `\"` and `\\` escapes are decoded in labels; expression strings are
  raw and their escapes are not interpreted.
- Unquoted `//` (and depth-0 `#`/`/*`) truncates the expression text.
- A label cannot contain a raw LF, and a label's decoded text cannot be
  re-emitted if it contains bytes that require other escapes; that cannot
  arise from a parsed document because such escapes are rejected.
- NUL bytes are rejected everywhere.
- No file I/O, no streaming, no registry integration; errors carry line
  numbers but no column positions.
