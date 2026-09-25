# xiom.ass -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ass` (`src/ass.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for a documented subset of Advanced SubStation
Alpha (ASS) and SSA v4 subtitles:

- `ass_parse` -- document -> `Result[Ass, Str]`;
- `ass_format` -- canonical serialization (documented section kind order,
  LF, raw lines verbatim);
- `ass_parse_timestamp` / `ass_format_timestamp` -- the `h:mm:ss.cc`
  timestamp grammar on its own;
- accessors for sections, Script Info pairs, Format declarations, styles,
  events (Dialogue/Comment), by-name and by-position field lookup, parsed
  start/end centiseconds, and event Text/Style.

The codec keeps every non-header line byte-exact (after CR/LF
normalization), validates the documented subset strictly, and round-trips
canonical documents `parse -> format -> parse`.

## 2. Non-goals

- Style rendering, layout, text shaping, font handling.
- Override-tag (`{...}`) interpretation: tags are raw Text bytes.
- `\N`/`\n`/`\h` escape interpretation: raw Text bytes.
- Font/image attachment parsing (`[Fonts]`, `[Graphics]` are other sections
  preserved raw).
- SSA v4 semantic differences beyond the documented per-section Format
  handling: `[V4 Styles]` and `[V4+ Styles]` are treated identically.
- SSA `Picture:`, `Sound:`, `Movie:` and `Command:` events; only `Dialogue:`
  and `Comment:` rows are documented.
- Encoding conversion: `Str` is treated as a UTF-8 byte buffer and never
  re-encoded; no BOM stripping.
- Streaming/incremental parsing; subtitle timing validation beyond the
  timestamp shape (no ordering or overlap checks).
- Any FFI, file I/O, or registry integration.

## 3. Data model

```xi
pub type Ass = {
  section_names: Vec[Str];        // section name, trimmed
  section_kinds: Vec[Int];        // 0 info, 1 styles, 2 Events, 3 other
  section_starts: Vec[Int];       // range into section_lines
  section_ends: Vec[Int];         // exclusive
  section_lines: Vec[Str];        // every non-header line, verbatim
  section_fmt_starts: Vec[Int];   // range into format_fields, -1 when none
  section_fmt_ends: Vec[Int];     // -1 when none
  format_fields: Vec[Str];        // declared field names, document order
  info_keys: Vec[Str];            // Script Info keys
  info_values: Vec[Str];          // Script Info values
  style_sections: Vec[Int];       // owning section of each Style row
  style_starts: Vec[Int];         // range into style_fields
  style_ends: Vec[Int];           // exclusive
  style_fields: Vec[Str];         // Style row field values
  event_kinds: Vec[Int];          // 0 Dialogue, 1 Comment
  event_sections: Vec[Int];       // owning section of each event row
  event_starts: Vec[Int];         // parsed Start in centiseconds, -1 absent
  event_ends: Vec[Int];           // parsed End in centiseconds, -1 absent
  event_fstarts: Vec[Int];        // range into event_fields
  event_fends: Vec[Int];          // exclusive
  event_fields: Vec[Str];         // event row field values
}
```

Invariants of a parsed value:

- `section_names`, `section_kinds`, `section_starts`, `section_ends`,
  `section_fmt_starts` and `section_fmt_ends` have the same length (the
  section count), and section ranges tile `section_lines` in document order
  (`section_ends[i] <= section_starts[i + 1]`).
- Every style/event row's owning-section index is valid and its field range
  is non-empty, in order and lies inside the shared field pool.
- `event_starts`/`event_ends` hold the parsed Start/End of the row, or -1
  when the row's section Format declares no such field.
- `format_fields` holds every declared Format name and every materialized
  default `[Events]` mapping in document order.

`Vec[StructType]` is unsupported in this compiler, so the document is
deliberately flat: parallel homogeneous vectors plus ranges into shared
pools. Hand-built `Ass` values with drifted vector lengths cannot cause
out-of-range reads: every accessor and `ass_format` clamp against the actual
lengths (section 8).

## 4. Document grammar

```
document   = *blank section *( section ) *blank-in-section
section    = header LF *( line )        ; every line until the next header
header     = "[" ws* name ws* "]" ws*   ; name non-empty, no other trailing bytes
line       = *( byte except LF )        ; stored verbatim
blank      = ""                          ; exactly zero bytes
```

Physical lines are split on LF with a CR immediately before LF removed
(section 5.1).

Section kinds (exact, case-sensitive names after trimming):

| Name | Kind | Treatment |
|---|---|---|
| `Script Info` | 0 | `key: value` pairs indexed; raw lines kept |
| `V4+ Styles` | 1 | Format declaration + Style rows |
| `V4 Styles` | 1 | Format declaration + Style rows |
| `Events` | 2 | Format declaration (or default) + Dialogue/Comment rows |
| anything else | 3 | raw lines only |

```
style-row   = "Style:" value
event-row   = ( "Dialogue:" | "Comment:" ) value
format-row  = "Format:" value
value       = *( byte except LF )        ; raw to end of line
```

## 5. Parsing decisions (each is covered by the conformance suite)

1. **Physical lines.** `text` is split on LF. A CR immediately before LF is
   removed, so CRLF documents produce the same lines as LF documents. A
   trailing LF does not produce a final empty line. A lone CR is not a line
   ending and stays inside its line.
2. **Blank lines.** A blank line is a zero-byte line. A whitespace-only line
   is content. Blank lines before the first section are ignored; blank lines
   inside a section are stored verbatim.
3. **Text before the first section.** A non-blank line before the first
   header is `Err("ass: text before first section")`. A leading UTF-8 BOM is
   not stripped, so it triggers this error.
4. **Section headers.** A line whose first byte is `[` always starts a new
   section, even inside another section. The name is the text between the
   first `[` and the first `]`, trimmed of spaces and tabs. A missing `]` is
   `Err("ass: unterminated section name")`; an empty name or any
   non-space/tab byte after the `]` is `Err("ass: bad section name")`.
   Names are matched case-sensitively.
5. **Section storage.** Every non-header line of every section is appended to
   the shared `section_lines` pool in document order, including blank lines,
   Format declarations and row lines; a section owns the half-open range
   `[section_starts[i], section_ends[i])`. The header itself is not stored
   (it is reconstructed canonically as `[name]`).
6. **Empty input.** A document with no sections at all is
   `Err("ass: empty input")` (after the control-byte scan).
7. **Missing Events.** A document without an `[Events]` section is
   `Err("ass: missing [Events]")`. This check runs before any section record
   is parsed, so it wins over a malformed Format elsewhere in the document.
8. **Script Info.** Inside kind-0 sections, blank lines and lines whose
   first byte is `;` are skipped (raw lines are still stored). Every other
   line must contain a `:`; the key is the trimmed text before the first
   colon (non-empty) and the value the trimmed text after it. A line without
   a colon or with an empty key is `Err("ass: bad script info line")`.
   Pairs from all Script Info sections aggregate in document order.
9. **Format declarations.** Inside kinds 1 and 2, the section's first
   `Format:` line is its declaration. The text after the colon is split on
   commas; each name is trimmed and must be non-empty. An empty declaration,
   an empty name (`Format: Name,,Fontsize`) or a second `Format:` line in
   the same section is `Err("ass: bad Format")`. Field names are arbitrary
   and matched case-sensitively; duplicates are allowed and first match wins.
10. **Default Events Format.** An `[Events]` section without a Format line
    uses the documented default mapping `Layer, Start, End, Style, Name,
    MarginL, MarginR, MarginV, Effect, Text`, materialized into
    `format_fields` (it is not re-emitted; the emitter writes stored raw
    lines).
11. **Dialogue/Comment before Format.** When an `[Events]` section has a
    Format line, a Dialogue row before it is
    `Err("ass: dialogue before Format")` and a Comment row before it is
    `Err("ass: comment before Format")`. When the section has no Format line
    the default mapping (rule 10) applies to every row, so no such error can
    fire.
12. **Style before Format.** A Style row before its section's Format line,
    or in a styles section with no Format line, is
    `Err("ass: style before Format")`.
13. **Unexpected lines.** Any other non-blank line in a kind 0-2 section is
    `Err("ass: unexpected line")` (for example SSA `Picture:` events).
    Kind-3 sections accept any line except a header.
14. **Row splitting.** A `Style:`/`Dialogue:`/`Comment:` value is split into
    exactly as many fields as the section's Format declares: the first
    `n - 1` commas are separators and the remainder belongs to the last
    field. All fields except the last are trimmed of spaces/tabs; the last
    declared field is captured raw to the end of the line. A row with fewer
    than `n - 1` commas is `Err("ass: field count mismatch")`; extra commas
    stay inside the last field. (`n >= 1`; with `n = 1` the whole value is
    the raw last field.)
15. **Start/End lookup.** For each event row, the first declared field named
    `Start` and the first named `End` are looked up in the section's Format.
    Their values are validated as timestamps (section 6) and stored as
    centiseconds. When a name is absent, no validation happens for it and
    the corresponding accessor returns -1.
16. **Control bytes.** Rejected anywhere in the input: C0 bytes other than
    TAB (9), LF (10) and CR (13), plus DEL (0x7F), as
    `Err("ass: control byte")`. The scan runs before line splitting.
    Bytes >= 0x80 are UTF-8 continuation/lead bytes and pass through.
17. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites or splits multi-byte sequences, so
    non-ASCII Text and raw lines round-trip exactly.
18. **Validation order.** Control bytes; section collection (text before the
    first section, unterminated/bad names) in document order; empty input;
    missing `[Events]`; then each section in document order, whose first
    failure (`bad Format`, `style/event before Format`, `unexpected line`,
    `field count mismatch`, timestamp shape, timestamp range) is returned.
    Errors carry no line/column numbers.

## 6. Timestamp grammar

```
timestamp = h ":" MM ":" SS "." cc
h         = 1DIGIT (0..9)
MM, SS    = 2DIGIT (00..59)     ; above 59 is an out-of-range error
cc        = 2DIGIT (00..99)
```

- The timestamp is exactly 10 bytes; no surrounding whitespace is allowed by
  `ass_parse_timestamp` (row fields are trimmed by rule 14, except a raw last
  field).
- A two-digit hour (`00:00:00.00`) is a bad shape; the documented policy is
  one hour digit.
- Minutes or seconds above 59 are `ass: timestamp out of range`, not a shape
  error.
- Values convert to centiseconds: `h*360000 + MM*6000 + SS*100 + cc`.
- Canonical output prints the hour without padding: `0:00:00.00` ...
  `9:59:59.99`. Values at or above 10 hours (`ass_format_timestamp(3600000)`
  = `10:00:00.00`) are produced but rejected on read, so they do not
  round-trip.

## 7. Canonical output

`ass_format` emits sections in the documented kind order:

1. all kind-0 (Script Info) sections, in document order;
2. all kind-1 (styles) sections, in document order;
3. all kind-2 (Events) sections, in document order;
4. all kind-3 (other) sections, in document order.

For each section it writes `"[" + name + "]" + LF` followed by every stored
raw line verbatim plus LF. Nothing is renumbered or reformatted: rows keep
document order, field spacing, field values and timestamp text exactly as
stored. Consequences: CRLF becomes LF; a section placed out of kind order
moves; blank lines before the first section are dropped; headers normalize to
`[name]` (trimmed name, no padding). An input already in canonical order
with exact headers round-trips byte-exactly. An empty document formats to
`""`.

Defensive clamping: `ass_format` computes the section count as the minimum
length of the section vectors and clamps every raw-line range into `[0,
section_lines.len()]`, so a hand-built `Ass` with drifted vectors emits at
most the consistent prefix instead of reading out of bounds.

## 8. API signatures

```xi
pub type Ass = { ... }                                   ; see section 3

pub fn ass_parse(text: Str) -> Result[Ass, Str]
pub fn ass_format(a: &Ass) -> Str
pub fn ass_parse_timestamp(t: Str) -> Result[Int, Str]
pub fn ass_format_timestamp(cs: Int) -> Str
pub fn ass_section_count(a: &Ass) -> Int
pub fn ass_section_name(a: &Ass, i: Int) -> Str
pub fn ass_section_kind(a: &Ass, i: Int) -> Int
pub fn ass_section_line_count(a: &Ass, i: Int) -> Int
pub fn ass_section_line(a: &Ass, i: Int, j: Int) -> Str
pub fn ass_format_field_count(a: &Ass, sec: Int) -> Int
pub fn ass_format_field(a: &Ass, sec: Int, j: Int) -> Str
pub fn ass_info_count(a: &Ass) -> Int
pub fn ass_info_key(a: &Ass, i: Int) -> Str
pub fn ass_info_value(a: &Ass, i: Int) -> Str
pub fn ass_info_value_by_key(a: &Ass, key: Str) -> Str
pub fn ass_style_count(a: &Ass) -> Int
pub fn ass_style_field_count(a: &Ass, i: Int) -> Int
pub fn ass_style_field_at(a: &Ass, i: Int, j: Int) -> Str
pub fn ass_style_field(a: &Ass, i: Int, name: Str) -> Str
pub fn ass_event_count(a: &Ass) -> Int
pub fn ass_dialogue_count(a: &Ass) -> Int
pub fn ass_comment_count(a: &Ass) -> Int
pub fn ass_event_kind(a: &Ass, i: Int) -> Int
pub fn ass_event_field_count(a: &Ass, i: Int) -> Int
pub fn ass_event_field_at(a: &Ass, i: Int, j: Int) -> Str
pub fn ass_event_field(a: &Ass, i: Int, name: Str) -> Str
pub fn ass_event_start_cs(a: &Ass, i: Int) -> Int
pub fn ass_event_end_cs(a: &Ass, i: Int) -> Int
pub fn ass_event_text(a: &Ass, i: Int) -> Str
pub fn ass_event_style(a: &Ass, i: Int) -> Str
```

Accessor sentinels: `ass_section_kind`, `ass_event_kind`,
`ass_event_start_cs` and `ass_event_end_cs` return `-1` for a negative or
out-of-range index (the time accessors also return `-1` when the row's
Format declares no such field); `ass_section_name`, `ass_section_line`,
`ass_format_field`, `ass_info_key`, `ass_info_value`,
`ass_info_value_by_key`, `ass_style_field_at`, `ass_style_field`,
`ass_event_field_at`, `ass_event_field`, `ass_event_text` and
`ass_event_style` return `""`; `ass_section_line_count`,
`ass_format_field_count`, `ass_style_field_count` and
`ass_event_field_count` return `0`.

Complexity: `ass_parse` and `ass_format` are O(input or section-line size);
timestamp helpers are O(1); every accessor is O(1) except the by-name field
lookups, which scan the section's Format fields (bounded by the declaration
size), and `ass_dialogue_count`/`ass_comment_count`, which are O(events).

## 9. Error catalog

All failures are `Err(msg)` where `msg` starts with `"ass: "` and carries no
line/column number:

| Message | Trigger |
|---|---|
| `ass: control byte` | A C0 byte other than TAB/LF/CR, or DEL (0x7F), occurs anywhere in the input. |
| `ass: empty input` | The document has no sections (empty or blank lines only). |
| `ass: text before first section` | A non-blank line before the first header (including a leading BOM). |
| `ass: unterminated section name` | A `[` line has no closing `]`. |
| `ass: bad section name` | The trimmed name is empty, or non-space/tab bytes follow the `]`. |
| `ass: missing [Events]` | The document has no `[Events]` section. |
| `ass: bad Format` | Empty declaration, empty field name, or a second `Format:` line in one section. |
| `ass: bad script info line` | A Script Info line without a colon or with an empty key. |
| `ass: style before Format` | A Style row precedes its Format line, or its section has no Format line. |
| `ass: dialogue before Format` | A Dialogue row precedes its Events section's Format line. |
| `ass: comment before Format` | A Comment row precedes its Events section's Format line. |
| `ass: field count mismatch` | A row holds fewer commas than its Format has fields (minus one). |
| `ass: bad timestamp shape` | A Start/End value is not exactly 10 bytes of `h:mm:ss.cc` with digits/separator as specified. |
| `ass: timestamp out of range` | A Start/End value has minutes or seconds above 59. |
| `ass: unexpected line` | Any other non-blank line in a kind 0-2 section. |

## 10. Test plan

`tests/test_conformance.xi` (module `ass_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | events parse | counts, kinds, exact times, Text with comma, Style, Layer/Name lookup, default 10 fields (rules 9, 10, 14, 15) |
| t2 | default mapping | Format-less `[Events]`, field names 0/1/9, times, byte-exact emit (rule 10) |
| t3 | custom mapping | reordered `End, Start, Style, Text` maps by name (rules 9, 15) |
| t4 | first match | duplicate `Text` names: accessor takes the first (rule 9) |
| t5 | timestamps | 0/1/372345/3599999, format and clamp, 10-hour output, shape vs range catalog (section 6) |
| t6 | event timestamps | bad Start shape, Start range, bad End shape (rule 15) |
| t7 | event before Format | Dialogue and Comment policies (rule 11) |
| t8 | style before Format | row before the declaration and no declaration at all (rule 12) |
| t9 | bad Format | empty, gapped and duplicated declarations (rule 9) |
| t10 | field count | short Style and event rows error; extra commas stay in the last field (rule 14) |
| t11 | empty / missing Events | no `[Events]`; `""`, LF-only, CRLF-only (rules 6, 7) |
| t12 | section names | unterminated, empty name, trailing junk, text before the first section (rules 3, 4) |
| t13 | control bytes | 0x01 and DEL rejected; TAB is text (rule 16) |
| t14 | Script Info | comments skipped, pairs preserved, first-match by key, bad line catalog (rule 8) |
| t15 | other sections | raw preservation, kind order, re-parse (rules 5, 7) |
| t16 | normalization | CRLF, padded headers, leading blanks -> LF canonical text (rule 4, section 7) |
| t17 | round trip | canonical doc parse -> format -> parse -> format, byte-exact (section 7) |
| t18 | sentinels | every accessor at negative and high indices (section 8) |
| t19 | multiple sections | two styles + two Events sections aggregate, per-section Formats (rules 5, 9) |
| t20 | drifted vectors | hand-built `Ass` with mismatched vectors is clamped (section 7) |
| t21 | raw text | UTF-8, `\N` escapes and `{...}` override blocks round-trip byte-exact (rules 14, 17) |
| t22 | by position | `_field_at` accessors and the raw split of the canonical rows (rule 14) |
| t23 | no Start/End | a Format without Start/End parses; time accessors return -1 (rule 15) |

Every string comparison in the suite goes through
`xiom.string.compare.str_compare` (BUG 17 discipline) and every element read
goes through a typed local.

## 11. Field-by-name and row semantics notes

- The mapping is positional for splitting but named for lookup: field `j` of
  a row corresponds to the `j`-th declared Format name, and `Start`, `End`,
  `Text` and `Style` are found by scanning those names from the start.
- Because the last declared field is the raw remainder, the documented
  formats put `Text` last. A declaration that places another name after
  `Text` makes that other name raw instead; this is the documented comma
  policy, not a special case for Text.
- Style rows have no free-text field in the documented formats; their last
  field is nevertheless captured raw by the same rule.
- `[V4 Styles]` and `[V4+ Styles]` differ only in the Format lines their
  files carry; the codec applies no per-variant defaults or semantics.

## 12. Compiler / stdlib notes (v0.61.3)

- **Flat storage.** No `Vec[StructType]`: sections, formats, rows and values
  live in parallel vectors referencing shared pools by ranges.
- **Ok/Err confinement.** Results are constructed only in the leaf helpers
  `_ok_ass`, `_err_ass`, `_ok_int`, `_err_int`; internal parsers return `""`
  on success or an `"ass: ..."` message.
- **Bytes as Int.** Every `xiom.string.byte_at` read goes through
  `_byte(s, pos) -> Int`, which masks with `& 0xFF`, so no `UInt8` constant
  >= 128 is involved in a comparison and no widened byte can be negative.
- **No Str `==`.** String equality uses
  `xiom.string.compare.str_compare`; Vec element reads are bound to typed
  locals before use.
- **Trim helper.** `_trim_from` exists so a Str read from a `Vec[Str]`
  element is never trimmed with an explicit `s.len()` call at the call site.
- **No `match`, no lambdas, no `Vec[fn]`.** Parsing is `if`/`elif`/`while`
  only; the test suite calls `t1()` ... `t23()` directly.
- **No conversion imports.** Non-negative decimal formatting is local
  (`_int_str`, `_pad2`).
- **No borrow-in-struct warning.** The per-section parsers take `raw` as
  `&mut Vec[Str]` (read-only in practice) because mixing `&mut` and `&`
  borrows of a local that is later moved into a struct raises warning[E001]
  `cannot store borrow in struct` on this compiler.
- **Drift guards.** `ass_format` and every range accessor clamp/min against
  the actual vector lengths.

## 13. Known limitations

- Whole-document, in-memory only: no streaming API.
- Strict timestamps on read: exactly one hour digit and exactly two digits
  per smaller field; times at or above 10 hours fail to re-parse.
- Structured sections accept only their documented lines; other SSA event
  kinds and unknown records inside `[V4+ Styles]`/`[V4 Styles]`/`[Events]`
  are errors.
- Section headers are recognized by a leading `[`, so kind-3 sections cannot
  contain bracket lines.
- Blank means zero bytes; whitespace-only lines are content and are errors in
  structured sections.
- Override tags, escapes and font attachments are never interpreted.
- No ordering, overlap or duration validation of events.
- A leading UTF-8 BOM is not stripped.
- Errors carry no line/column numbers.
