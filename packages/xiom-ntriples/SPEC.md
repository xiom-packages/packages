# xiom.ntriples -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ntriples` (`src/ntriples.xi`). Pure XIOM, no FFI.
Reference: [RDF 1.1 N-Triples](https://www.w3.org/TR/n-triples/) (W3C
Recommendation, 25 February 2014).

## 1. Scope

A codec for RDF 1.1 N-Triples documents held in a `Str`:

- `nt_parse` -- document text -> `Result[NtDocument, Str]`: a flat, ordered
  triple list stored as parallel `Vec` fields (one slot per triple).
- `nt_emit` -- stable canonical text of a document (single spaces, comments
  stripped, uppercase hex escapes).
- `nt_add_triple` -- programmatic appends with the same validation the parser
  applies to term shapes.
- Read-only accessors: triple count, subject kind/text, predicate text, object
  kind/text, language tag, datatype IRI, `nt_object_has_datatype`.

The parser is byte-wise over UTF-8. Input must be well-formed UTF-8; invalid
bytes are rejected (section 7).

## 2. Non-goals

- Every Turtle feature: prefixed names, `a`, collections, blank node property
  lists, numeric/boolean literals, `@base`/`@prefix`, multi-line literals.
- RDF semantics: datatype value spaces, RDF term identity, blank node scoping
  or canonicalization across documents, graph merging, IRI resolution.
- Relative-IRI resolution and IRI syntax validation beyond the `IRIREF`
  character set (an empty IRI `<>` is accepted; it is syntactically an
  `IRIREF`).
- Unicode normalization of any kind; code points are stored exactly as
  decoded, and no case folding is applied to language tags or datatypes.
- Streaming/incremental parsing; error recovery (the first error aborts);
  line/column tracking (errors carry byte offsets only).
- The full RDF 1.1 escape set: `\b` (U+0008), `\f` (U+000C) and `\'` (U+0027)
  are valid `ECHAR`s rejected by this subset (section 4).
- Unicode blank node labels: the spec's `PN_CHARS` ranges, and `:` inside
  labels, are not supported (section 3.3).
- A UTF-8 byte order mark; a leading BOM is an "unexpected byte" error.

## 3. Supported grammar

The subset of the N-Triples grammar accepted by `nt_parse`. Productions not
listed keep their W3C meaning.

```
ntriplesDoc = line? (EOL line)* EOL?                (EOL = 1*(CR / LF))
line        = blank-line | triple-line
blank-line  = *( ws ) [ "#" *non-EOL ]
triple-line = *( ws ) triple *( ws ) [ "#" *non-EOL ]
triple      = subject *( ws ) predicate *( ws ) object *( ws ) "."
subject     = IRIREF | BLANK
predicate   = IRIREF
object      = IRIREF | BLANK | literal
literal     = STRING ( "@" LANGTAG | "^^" IRIREF )?
ws          = SPACE / TAB
EOL         = CR / LF (any run)
```

Decisions (each is covered by the conformance suite):

1. **Encoding.** Input is UTF-8; the whole input is validated before parsing
   and the first ill-formed sequence is `Err("ntriples: invalid UTF-8 byte at
   <pos>")`. Well-formed non-ASCII bytes pass through IRIs and literals
   unchanged.
2. **Terms.** A triple is exactly three terms plus `.`. Adjacent terms are
   accepted (`<a><b><c>.` parses: the W3C grammar requires whitespace only
   where terminals would otherwise merge), and a comment may follow the
   terminator after optional whitespace. Nothing but whitespace or `#` may
   follow the dot.
3. **IRIREF.** `<` ... `>` with the W3C character set; a raw `>` closes the
   IRI, and every byte the set forbids (`<= 0x20`, `<`, `>`, `"`, `{`, `}`,
   `|`, `^`, `` ` ``, `\`) is `Err("ntriples: missing '>' at <pos>")` unless it
   is the closing `>`. A line ending inside `<...>` (including a trailing
   backslash) is `Err("ntriples: unterminated IRI at <pos>")` at the `<`.
   Only `\uXXXX` and `\UXXXXXXXX` escapes are allowed.
4. **BLANK_NODE_LABEL.** `_:` followed by the documented ASCII subset:
   `[A-Za-z0-9_]` first, then `[A-Za-z0-9_.-]`, not ending in `.`. A trailing
   `.` is handed back and may terminate the triple (`_:b.`). Anything else,
   including an empty label, is `Err("ntriples: invalid blank node label at
   <pos>")` at the `_`.
5. **STRING_LITERAL_QUOTE.** `"` ... `"`. A raw `"` closes the literal; a raw
   LF or CR ends the line (and therefore the document line) because lines are
   split first, so an unescaped newline surfaces as an unterminated literal.
   Raw C0 bytes other than TAB are `Err("ntriples: raw control byte in literal
   at <pos>")`; a raw TAB is data, as in the W3C grammar; DEL (0x7F) passes
   through. An unknown escape or a malformed/non-scalar UCHAR is
   `Err("ntriples: bad escape at <pos>")` at the backslash, and a line ending
   before the closing quote is `Err("ntriples: unterminated literal at
   <pos>")` at the opening quote.
6. **Literal suffixes.** `@`/`^^` must follow the closing quote immediately
   (no whitespace). A language tag must match `[a-zA-Z]+('-'[a-zA-Z0-9]+)*`
   and end at a terminator (space, TAB, `.`, `#`, or end of line); otherwise
   `Err("ntriples: bad language tag at <pos>")` at the `@`. `^^` must be
   followed by `<`, else `Err("ntriples: missing '<' at <pos>")`; the
   datatype is a full IRIREF and may be empty (`^^<>`).
7. **Language tags** are preserved exactly (case included); datatype texts
   carry no angle brackets. No normalization is applied.
8. **Blank lines, comments, line ends.** LF, CRLF and CR documents all parse:
   any run of CR/LF is one `EOL`. Whitespace-only and `#`-comment lines
   contribute no triples. Comments run to the end of the line and may follow a
   triple (`<s> <p> <o> . # note`).
9. **Incomplete triples.** A line ending while a predicate or object is still
   required is `Err("ntriples: unexpected end of line at <pos>")` with the
   line end offset. A complete subject-predicate-object without `.` is
   `Err("ntriples: missing '.' at <pos>")`; if the next token starts a term it
   is `Err("ntriples: extra term at <pos>")` instead.
10. **Subject/object starts.** At the subject or object position only `<`,
    `_:` and (objects only) `"` are valid; any other byte is
    `Err("ntriples: unexpected byte at <pos>")`, as is non-whitespace content
    after the terminator or a non-IRI predicate byte other than the dedicated
    `missing '<'` cases (predicate and datatype).
11. **Positions.** Every error message ends with ` at <pos>`, where `<pos>` is
    a 0-based byte offset into the whole input `Str` (not the line).
12. **Determinism.** Parsing the same text always yields the same document or
    the same first error; the input is never mutated. Positions and messages
    are fixed strings built from section 7's templates.

## 4. Escape table

Inside a `STRING_LITERAL_QUOTE` (`"..."`) exactly these escapes are decoded:

| Source | Decoded | Notes |
|---|---|---|
| `\n` | LF (0x0A) | |
| `\t` | TAB (0x09) | |
| `\r` | CR (0x0D) | |
| `\"` | `"` (0x22) | quote does not close the literal |
| `\\` | `\` (0x5C) | |
| `\uXXXX` | code point | exactly four hex digits |
| `\UXXXXXXXX` | code point | exactly eight hex digits |

Inside an `IRIREF` (`<...>`) only `\uXXXX` and `\UXXXXXXXX` are decoded; any
other backslash is `Err("ntriples: bad escape at <pos>")`.

UCHAR rules (both contexts):

- hex digits are case-insensitive (`[0-9A-Fa-f]`);
- `\U` requires exactly eight digits and `\u` exactly four; a wrong digit
  count or a non-hex digit is `Err("ntriples: bad escape at <pos>")`;
- the value must be a Unicode scalar value: `U+D800`-`U+DFFF` (UTF-16
  surrogates) and values above `U+10FFFF` are
  `Err("ntriples: bad escape at <pos>")`;
- `U+0000` is `Err("ntriples: bad escape at <pos>")` because XIOM `Str`
  cannot carry an embedded NUL byte;
- the decoded code point is appended as its UTF-8 encoding;
- in an `IRIREF`, a decoded code point outside the IRIREF character set
  (controls, space, `<`, `>`, `"`, `{`, `}`, `|`, `^`, `` ` ``, `\`) is
  `Err("ntriples: missing '>' at <pos>")` at the backslash.

The valid RDF 1.1 escapes `\b`, `\f` and `\'` are deliberately outside this
subset and are reported as bad escapes.

## 5. Canonical output

`nt_emit` writes, for each triple in order:
`<subject> <predicate> <object> .` followed by LF, with exactly one space
after each term. An empty document emits `""`. Layout and escaping are fixed:

- IRIs: `<` + text + `>`. Bytes in the IRIREF-forbidden set are written as
  `\uXXXX` (or `\UXXXXXXXX` above the BMP) with **uppercase** hex; all other
  bytes, including raw multi-byte UTF-8, pass through.
- Literals: `"` + text + `"`, then `@lang` or `^^<datatype>` from the stored
  flavor flag. `\` `"` LF CR TAB use their short escapes; any other byte below
  0x20 becomes `\u00XX` with uppercase hex; everything else, including raw
  multi-byte UTF-8, passes through.
- Comments never appear; language tags and datatype IRIs are not case-folded
  or otherwise normalized.

This is a stable canonical form: `nt_parse(nt_emit(d))` equals `d` field by
field. It follows the W3C canonical layout (single spaces, no comments,
uppercase hex, no UCHAR for characters that can appear raw) with one
documented difference: W3C canonical N-Triples encodes only `"`, `\`, LF and
CR with `ECHAR` and would leave other C0 bytes raw, while this emitter also
escapes TAB as `\t` and other C0 bytes as `\u00XX`.

## 6. API contract

```xi
pub type NtDocument = {
  s_kinds: Vec[Str]; s_texts: Vec[Str];
  p_texts: Vec[Str];
  o_kinds: Vec[Str]; o_texts: Vec[Str];
  o_langs: Vec[Str]; o_dts: Vec[Str]; o_flags: Vec[Int];
}

pub fn nt_new() -> NtDocument
pub fn nt_add_triple(d: &mut NtDocument, s_kind: Str, s_text: Str, p_text: Str,
                     o_kind: Str, o_text: Str, o_lang: Str, o_dt: Str) -> Bool
pub fn nt_parse(text: Str) -> Result[NtDocument, Str]
pub fn nt_emit(d: &NtDocument) -> Str
pub fn nt_triple_count(d: &NtDocument) -> Int
pub fn nt_subject_kind(d: &NtDocument, i: Int) -> Str
pub fn nt_subject_text(d: &NtDocument, i: Int) -> Str
pub fn nt_predicate(d: &NtDocument, i: Int) -> Str
pub fn nt_object_kind(d: &NtDocument, i: Int) -> Str
pub fn nt_object_text(d: &NtDocument, i: Int) -> Str
pub fn nt_object_lang(d: &NtDocument, i: Int) -> Str
pub fn nt_object_datatype(d: &NtDocument, i: Int) -> Str
pub fn nt_object_has_datatype(d: &NtDocument, i: Int) -> Bool
```

Term kinds: subject is `"iri"` or `"bnode"`; object is `"iri"`, `"bnode"` or
`"literal"`. `p_texts[i]` is always an IRI text. `o_langs[i]` is `""` unless
`o_flags[i] == 1`; `o_dts[i]` is `""` unless `o_flags[i] == 2` (an explicit
`^^<>` stores `""` and is still reported by `nt_object_has_datatype`).
Out-of-range accessor indices return `""` (or `false`) instead of failing.

`nt_add_triple` validates the kinds, the language-tag shape, blank node
labels, and that language tag and datatype are mutually exclusive and
literal-only. It returns `false` without mutating `d` when a check fails. An
empty `o_dt` with `o_kind == "literal"` means a plain literal, so the builder
cannot express the explicit `^^<>` state that `nt_parse` can.

The module is stateless: no registry, no global state, and any number of
documents can coexist.

## 7. Error catalog

Every message is `"ntriples: " + <text> + " at " + <decimal pos>`, built with
`xiom.convert.int_to_string`; `<pos>` is a 0-based byte offset into the input.
Parsing stops at the first error.

| # | Message text | Condition |
|---|---|---|
| 1 | `invalid UTF-8 byte` | input contains an ill-formed UTF-8 sequence; pos = first byte of the sequence |
| 2 | `unterminated IRI` | a line ends inside `<...>` (including a trailing backslash); pos = `<` |
| 3 | `missing '>'` | a byte forbidden by `IRIREF` (controls, space, `<`, `>`, `"`, `{`, `}`, `|`, `^`, backtick), or a UCHAR in an IRI decoding to a forbidden character; pos = byte / backslash |
| 4 | `bad escape` | unknown escape letter; wrong `\u`/`\U` digit count or non-hex digit; surrogate code point; value > U+10FFFF; U+0000; pos = backslash |
| 5 | `unterminated literal` | a line ends inside `"..."` (including a trailing backslash); pos = opening quote |
| 6 | `raw control byte in literal` | raw byte 0x00-0x1F other than TAB inside a literal; pos = byte |
| 7 | `bad language tag` | `@` not followed by `[a-zA-Z]+('-'[a-zA-Z0-9]+)*` ending at a terminator; pos = `@` |
| 8 | `invalid blank node label` | `_:` with an empty or out-of-subset label; pos = `_` |
| 9 | `missing '<'` | an IRI is mandatory (predicate or datatype) and the byte is not `<`; pos = byte |
| 10 | `unexpected end of line` | the line ends while a predicate or object is still required; pos = line end |
| 11 | `missing '.'` | a complete subject-predicate-object is not terminated by `.`; pos = first non-whitespace byte or line end |
| 12 | `extra term` | a new term starts before the `.`; pos = term start |
| 13 | `unexpected byte` | invalid subject/object start, or non-whitespace/non-comment content after the `.`; pos = byte |

## 8. Test matrix

`tests/test_conformance.xi` (module `ntriples_tests`) runs 24 named checks,
one `fn` per check, through `assert(cond, "name")`; `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Pins |
|---|---|---|
| t1 | empty document | blank / whitespace / comment-only input -> 0 triples; `nt_emit` -> `""` (rules 8, 5) |
| t2 | IRI triples | spaces, TABs, adjacent terms; canonical single-space emit (rules 2, 5) |
| t3 | blank nodes | internal `.` and `-`, trailing-dot handback, emit (rule 4) |
| t4 | plain literals | spaces, `#` as data, empty literal, `\"` (rules 5, 8) |
| t5 | language tags | shape, case preservation, `en-419` subtags, emit (rules 6, 7) |
| t6 | datatype literals | xsd:integer text, explicit `^^<>` flag and round trip (rules 6, 7) |
| t7 | literal escapes | `\n \t \r \\` decode and canonical re-encoding (section 4, 5) |
| t8 | literal UCHAR | `\u`, `\U`, lowercase hex, UTF-8 decoding, round trip (section 4) |
| t9 | IRI UCHAR | decoding, raw-UTF-8 emit, round trip (rules 3, 5) |
| t10 | line ends / comments | LF, CRLF, CR documents, blank lines, trailing EOL runs, comments after triples (rule 8) |
| t11 | unterminated IRI | position = `<`, including trailing backslash (catalog 2) |
| t12 | missing `>` | forbidden byte and forbidden UCHAR in an IRI (catalog 3) |
| t13 | unterminated literal | position = opening quote, trailing backslash included (catalog 5) |
| t14 | bad escapes | `\q`, truncated `\u`, surrogate, > U+10FFFF, NUL, IRI context (catalog 4) |
| t15 | bad language tags | empty, leading digit, trailing dash, empty subtag, bad byte (catalog 7) |
| t16 | terminator errors | missing `.`, extra term, trailing bytes, `unexpected end of line` (catalog 10-13) |
| t17 | invalid UTF-8 | 0xFF, truncated lead, bad continuation (catalog 1) |
| t18 | raw control bytes | 0x01 rejected, raw CR ends the line, raw TAB allowed (rule 5) |
| t19 | labels & predicates | empty label, missing `<` for predicate and datatype, digit-first label (catalog 8, 9) |
| t20 | mixed round trip | parse -> emit -> parse equality and exact canonical text (section 5) |
| t21 | canonical escapes | uppercase `\u001F` / `\u007B`, builder-inserted bytes (section 5) |
| t22 | `nt_add_triple` | valid appends, invalid inserts return `false` without mutation (section 6) |
| t23 | accessors | out-of-range `""`/`false` results (section 6) |
| t24 | raw UTF-8 | non-ASCII bytes in literals and IRIs; raw re-emit and round trip (rule 1) |

Element comparisons use `xiom.string.compare.str_compare`, never `==` (BUG 17).
Raw control bytes and invalid UTF-8 are built from `Vec[UInt8]` because source
literals cannot spell them.

## 9. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported packages):

- Free functions only; no methods on `NtDocument`.
- No `Vec[StructType]`: `NtDocument` is eight parallel `Vec`s.
- `Ok`/`Err` for `Result[NtDocument, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc`; `nt_parse` builds the document and returns
  `_ok_doc(d)`.
- `Str` values read from `Vec[Str]` elements go through `str_compare`
  (BUG 17) and are bound to typed `let` locals before use; `Vec[Int]` element
  reads use `let f: Int = d.o_flags[i];`.
- `&mut Vec[UInt8]` out-parameters receive an explicit `&mut` at every call
  site (a bare value would copy and lose the bytes).
- Output is collected in `Vec[UInt8]` and materialized with
  `xiom.string.builder.sb_to_str`; decoded term text uses `Str::from_utf8`.
- Scanned byte values are widened and masked (`(b as Int) & 0xFF`) before any
  comparison against a value >= 128, so UTF-8 validation and UCHAR ranges are
  sign-safe.
- E001 borrow warnings on `&mut NtDocument` call sites are advisory; the
  mutations are observable and the suite pins them.
