# xiom.ris -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ris` (`src/ris.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free RIS **codec** for in-memory `Str` documents:

- `ris_parse` -- RIS text -> `Result[RisDoc, Str]`,
- flat record/field accessors (`ris_record_count`, `ris_field_count`,
  `ris_field_tag`, `ris_field_value`, `ris_get_field`),
- `ris_emit` -- canonical RIS text,
- documented round-trip: `ris_parse(ris_emit(d))` preserves every record,
  field tag and field value in document order.

The document model is flat: per-record slices of two shared pools
(`field_tags`, `field_values`) are described by parallel `Vec[Int]` range
vectors (`field_starts`, `field_counts`). `Vec[StructType]` is not usable in
this compiler, so there is no tree of record structs. Every parsed record
starts with its `TY` field, stored like any other field.

## 2. Non-goals

- Citation formatting, reference labels, sorting, deduplication, merging.
- LaTeX / markup processing; values are opaque bytes except for the line
  rules below.
- RIS type or tag schema validation: `TY` receives no vocabulary check and
  all tags are stored as written.
- `RIS`-adjacent dialects that use a different tag separator (one space, tab,
  `XX -` without the second space) or parenthesis-style records.
- File I/O, streaming or incremental parsing, registry integration.
- Rich error recovery: parsing stops at the first error.
- Unicode validation or normalization; `Str` is treated as a UTF-8 byte
  buffer and multi-byte sequences pass through byte-exact.
- CR-only (classic Mac) line endings; only LF and CRLF are line terminators.

## 3. Supported grammar

```
document   = *( blank-line / record )
record     = ty-line *( blank-line / tag-line / cont-line ) er-line
ty-line    = "TY" "  - " value
tag-line   = tag "  - " value / tag "  -"
er-line    = "ER" "  - " value / "ER" "  -"
tag        = tag-byte tag-byte
tag-byte   = "A".."Z" / "a".."z" / "0".."9"
value      = *value-byte                  ; any byte except LF (CR possible)
cont-line  = non-blank line that is not a tag-line candidate
blank-line = *( SP / TAB )
line       = *( byte-except-LF ) [ CR ] LF / *( byte-except-LF )
```

`ty-line` is exactly a `tag-line` with tag `TY`; `er-line` is exactly a
`tag-line` with tag `ER`.

Decisions (each is covered by the conformance suite):

1. **Lines and endings.** The input is split at LF (`0x0A`). One trailing CR
   (`0x0D`) is removed from each line, so CRLF and LF both work and may be
   mixed in one document. A final line without a terminator is still a line;
   a trailing terminator does not create an extra line. A CR not followed by
   LF is data (CR-only line endings are not supported). Line numbers in error
   messages are 1-based.
2. **Blank lines.** A line whose text is empty after
   `xiom.string.str_trim` (SP, TAB, LF, CR) is blank and is ignored
   everywhere: before the first record, between and after records, and inside
   a record. Blank lines are not record terminators.
3. **Tag-line shape.** The *head* of a line is its maximal leading run of
   bytes that are neither SP nor TAB. A line is a tag-line candidate exactly
   when the head is immediately followed by SP SP `-` SP (normal form, value
   follows) or, at end of line, by SP SP `-` (empty-value form). No other
   spacing is accepted: `TI - x`, `TI  -x` and `TI\t- x` are not tag lines.
   A line with an empty head (indented) is never a tag line.
4. **Tag validation.** A candidate whose head is not exactly two bytes is
   `Err("ris: tag not 2 chars at <line>: <head snippet>")`. A candidate whose
   two tag bytes are not `A-Za-z0-9` is
   `Err("ris: malformed tag line at <line>: <line snippet>")`. Tags are stored
   as written and matched case-sensitively; `TI` and `ti` are different tags.
5. **Values.** The value of a tag line is everything after the delimiter
   with leading and trailing whitespace removed (`xiom.string.str_trim`: SP,
   TAB, LF, CR); interior bytes (including further `"  - "` sequences) are
   preserved. `TI  - ` and `TI  -` both have value `""`. The value of an `ER`
   line is ignored.
6. **Continuations.** Inside a record, every non-blank line that is not a
   tag-line candidate is a continuation: its trimmed text is appended to the
   value of the most recent tag line with exactly one space, then the merged
   value is trimmed again. A continuation may target any tag line, including
   `TY`. A continuation whose first word is immediately followed by
   `"  - "` is indistinguishable from a malformed tag line and errors
   (decision 4).
7. **Record structure.** Outside a record, a valid `TY` line opens one.
   Inside a record, `TY` is `Err("ris: missing ER at <line>")` (the previous
   record never got its `ER`), `ER` closes the record, and every other valid
   tag line appends a field in document order. Tags other than `ER` may
   repeat; `ris_get_field` then returns the first occurrence (first-value
   semantics).
8. **`ER` uniqueness.** An `ER` line outside a record when no record has been
   completed yet is `Err("ris: missing TY at <line>: ER")`; when at least one
   record has already been completed it is
   `Err("ris: duplicate ER at <line>")`. An open record at end of input is
   `Err("ris: missing ER")`.
9. **Text outside records.** A non-blank line outside a record that is not a
   tag-line candidate is
   `Err("ris: text before first TY at <line>: <snippet>")`; a valid tag line
   whose tag is not `TY` is `Err("ris: missing TY at <line>: <tag>")`. This
   holds before the first record and between records.
10. **Unknown tags.** Any syntactically valid two-byte tag is accepted and
    preserved; the codec never interprets tag semantics beyond `TY`/`ER`
    structure.
11. **Snippets.** `<snippet>` is the first at most 24 bytes of the offending
    line (or head); no whitespace stripping is applied to snippets.
12. **Determinism.** Parsing the same text yields the same document or the
    same error; the input is never mutated.

## 4. Data model

```xi
pub type RisDoc = {
  field_starts: Vec[Int];   // record r's first index in the field pools
  field_counts: Vec[Int];   // record r's field count
  field_tags: Vec[Str];     // flat tag pool, document order, as written
  field_values: Vec[Str];   // flat trimmed value pool, document order
}
```

Invariants: `field_starts.len() == field_counts.len()` is the record count;
`field_tags.len() == field_values.len()`; for every record `r`,
`field_starts[r] + field_counts[r] <= field_tags.len()`. Every record
produced by `ris_parse` has at least one field and its first tag is `TY`.
The struct fields are public, but documents should be built with `ris_parse`:
`ris_emit` relies on the `TY`-first invariant.

`Vec[StructType]` is not usable in this compiler, so the model is
deliberately flat instead of a tree of record/field structs.

## 5. API signatures

```xi
pub fn ris_parse(text: Str) -> Result[RisDoc, Str]
pub fn ris_record_count(d: &RisDoc) -> Int
pub fn ris_field_count(d: &RisDoc, r: Int) -> Int
pub fn ris_field_tag(d: &RisDoc, r: Int, j: Int) -> Str
pub fn ris_field_value(d: &RisDoc, r: Int, j: Int) -> Str
pub fn ris_get_field(d: &RisDoc, r: Int, tag: Str) -> Option[Str]
pub fn ris_emit(d: &RisDoc) -> Str
```

Accessors are total: out-of-range record/field indices yield `""`, `0` or
`None`. `ris_get_field` matches tags byte-exactly (case-sensitive) and
returns the first field with the tag. Parsing is O(total input length);
index accessors are O(1); `ris_get_field` is linear in the record's field
count.

## 6. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"ris: "`.
`<line>` is a 1-based line number; `<snippet>` is at most 24 bytes of the
offending line (or head).

| Message | Trigger |
|---|---|
| `ris: text before first TY at <line>: <snippet>` | non-blank line outside any record that is not a tag-line candidate |
| `ris: missing TY at <line>: <tag>` | valid tag line outside any record whose tag is not `TY` (including `ER` before any record) |
| `ris: missing ER` | end of input while a record is open |
| `ris: missing ER at <line>` | `TY` tag line inside an open record |
| `ris: duplicate ER at <line>` | `ER` tag line outside a record after at least one record was completed |
| `ris: tag not 2 chars at <line>: <head>` | tag-line candidate whose head is not exactly two bytes |
| `ris: malformed tag line at <line>: <snippet>` | tag-line candidate whose two tag bytes are not `A-Za-z0-9` |

## 7. Canonical emission and round-trip

`ris_emit` writes every record as its fields in document order, each as
`TAG  - value` plus LF, then one `ER  - ` line (the full six-byte prefix,
empty value) plus LF. Blank lines, CRLF endings, continuation lines and
original spacing are not reproduced; layout is canonicalized, the data is
not. The output always re-parses, so `ris_parse(ris_emit(d))` preserves
every record, tag and trimmed value, and `ris_emit` is idempotent on its own
output. An empty document emits `""`.

## 8. Test plan

`tests/test_conformance.xi` (module `ris_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple record | record/field counts, tag/value order, `ris_get_field` |
| t2 | blank lines between records | ER-terminated records with blank separators |
| t3 | unknown tags | `PB`/`N1`/`ZZ` preserved; `ER  -` empty-value form |
| t4 | trimming | outer SP/TAB trimmed, inner spacing kept, empty value |
| t5 | continuations | joined with one space; blank lines ignored |
| t6 | line endings | CRLF, LF and mixed inputs normalize |
| t7 | duplicate tags | both kept in order; first-value semantics |
| t8 | delimiter in value | `A  - B` is data |
| t9 | missing TY | `AU`/`ER` before any record; tag after a completed record |
| t10 | missing ER | EOF (with/without final LF); `TY` inside an open record |
| t11 | tag validation | `ABC  -`/`A  -` -> not 2 chars; `T!  -` -> malformed |
| t12 | text before first TY | leading prose, `%` comment, junk after a record |
| t13 | duplicate ER | immediate and blank-line-separated second ER |
| t14 | round-trip | CRLF, continuation, empty value, unknown tag, 2 records |
| t15 | empty input | `""` and whitespace-only -> 0 records, `""` emission |
| t16 | bounds | out-of-range accessors return `0`, `""`, `None` |
| t17 | canonical emission | exact bytes for messy and multi-record input |
| t18 | tag case | `TI` vs `ti` distinct; case preserved |
| t19 | continuation targets | continuation after `TY`, after an empty value (round-tripped) and after an indented line |
| t20 | boundary tags | digit tags (`N1`); whitespace-only line inside a record |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.lexing` /
`xiom.vcf` idioms and documents these compiler-driven choices (XIOM
v0.61.3):

- `Vec[StructType]` is unsupported, so the document is four parallel
  homogeneous vectors with per-record ranges (no `Vec[RisRecord]`).
- Every byte read goes through `_ris_byte_at(s, i)`, which returns
  `(string.byte_at(s, i) as Int) & 0xFF`; constants live in Int space, so no
  value is ever compared against a raw `UInt8`.
- Str equality between `Vec[Str]` elements goes through
  `compare.str_compare` after binding a typed local (BUG 17).
- Int element reads are bound to typed locals (`let start: Int = ...`).
- `Ok`/`Err` for `Result[RisDoc, Str]` are constructed only in the leaf
  helpers `_ris_ok_doc`, `_ris_err_at`, `_ris_err_line` and `_ris_err`.
- Tests dispatch directly (`t1()` ... `t20()`); indexed `Vec[fn]` calls are
  not used.
- Free functions only; `&mut RisDoc` mutation is passed explicitly at every
  call site (`_ris_flush(&mut doc, ...)`).
- `xiom.string.str_trim`, `xiom.string.str_slice`, `xiom.string.byte_at` and
  `xiom.convert.int_to_string` are the only stdlib calls.

## 10. Known limitations

- One-space or tab-separated tag lines, `XX -` without the second space, and
  indented tag lines are not tag lines; inside a record they become
  continuation text (or a malformed-tag error when they mimic the exact
  delimiter shape with a wrong-length head).
- `ER` must be unique per record and its value is ignored; the emitter always
  writes an empty one.
- A record cannot be closed implicitly by a blank line or a new `TY`; both
  produce errors rather than guessing record boundaries.
- Repeated non-structural tags are kept with first-value semantics; no
  deduplication, no per-tag cardinality checks and no tag vocabulary checks.
- Continuation text is trimmed and joined with single spaces, so the
  original line breaks and indentation are not recoverable.
- CR-only line endings are unsupported and an embedded CR is ordinary data.
- Errors carry a line number and a byte snippet, not a column.
- Emitter canonicalizes layout (no blank lines, LF only) and does not
  reproduce the input formatting.
- No citation formatting, no LaTeX, no file I/O.
