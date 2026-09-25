# xiom.hl7 -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.hl7` (`src/hl7.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for the *structure* of an HL7 v2.x
pipe-delimited message held in memory as a `Str`:

- `hl7_parse` -- message text -> `Result[Message, Str]`,
- accessors -- segment count/name/index/field-count, MSH separators, and
  fields / repetitions / components / subcomponents as `Str`,
- `hl7_write` -- `Message` -> message text (byte-exact for parsed messages),
- builder -- `hl7_builder_new` / `hl7_builder_with_separators`,
  `hl7_builder_segment`, `hl7_builder_field`, `hl7_builder_field_structured`.

MSH is special-cased exactly as the standard requires: MSH.1 is the field
separator and MSH.2 holds the four encoding characters (component,
repetition, escape, subcomponent). Every other segment is split with the
separators the message itself declares.

## 2. Non-goals

- MLLP framing or any transport; no batch/message-header processing beyond
  treating FHS/BHS/BTS/FTS as ordinary segments.
- Data-type semantics: dates, times, coded values, numeric values, names and
  identifiers stay `Str`; no table/profile validation.
- Escape-sequence decoding (`\F\`, `\S\`, `\R\`, `\E\`, `\T\`, `\X..\`,
  `\C..\`, formatting commands); field text is returned as written.
- Cross-segment field-count consistency checks, segment toggling, `Z`
  segment rules, or EHR functional profiles.
- Streaming/incremental parsing (whole `Str` in memory).
- Any FFI, file I/O or registry integration.

## 3. Wire model

```
message   = segment *( term segment ) [ term ]
segment   = name [ fs field ]
name      = 1* ( byte except fs / CR / LF )
field     = *( byte except CR / LF )
term      = CR | LF | CRLF
```

Separator discovery (MSH only):

```
MSH line  = "MSH" fs encoding [ fs field ]*
encoding  = component repetition escape subcomponent      ; exactly 4 bytes
```

- The field separator `fs` is the byte at offset 3 of the first line
  (MSH.1). It must be a **legal separator byte**: printable ASCII `!` (0x21)
  through `~` (0x7E) that is **not** an ASCII alphanumeric.
- The four bytes after `fs` up to the next `fs` (or the end of the line) are
  MSH.2 and must be exactly four legal separator bytes, pairwise distinct and
  none equal to `fs`.
- A message may use any legal dialect, e.g. `MSH*%~\$*...` declares `*`, `%`,
  `~`, `\`, `$`.

Parsing decisions (each is covered by the conformance suite):

1. **Line terminators.** Segments end at CR (0x0D, the standard), LF (0x0A)
   or CRLF; a CR immediately followed by LF is one boundary. All three shapes
   may appear in one message.
2. **Trailing terminator.** A single terminator after the last segment does
   not create a segment; the artifact line after it is ignored.
3. **Empty message.** A text with no non-terminator byte -- `""`, `"\r"`,
   `"\n"`, `"\r\n"` -- is `Err("hl7: empty message")`.
4. **First segment.** The first line must start with the three bytes `MSH`
   (case-sensitive) or the parse fails with `hl7: missing MSH segment`. The
   fourth byte is then validated as MSH.1.
5. **Empty lines.** Any zero-length line other than the final trailing
   artifact is `Err("hl7: empty segment name")`, and so is a line that starts
   with the field separator (`|X` has an empty name).
6. **Non-MSH segments.** The name is the byte run before the first field
   separator, or the whole line when there is none (a name-only segment such
   as `NTE` has zero fields). Empty names are rejected (rule 5).
7. **MSH storage.** MSH is stored like any segment, with field 1 equal to the
   field separator and field 2 equal to the four encoding characters; later
   fields start at MSH.3. `hl7_field(&m, msh, 2)` therefore returns `^~\&`
   for a default message.
8. **Field counts.** Each segment stores exactly the fields present on its
   line: empty fields between separators are preserved, a trailing separator
   yields a trailing empty field. The codec performs **no** cross-segment
   consistency check, because HL7 marks trailing fields optional; the count
   is reported per segment by `hl7_seg_field_count`.
9. **Hierarchy.** A field is split on the repetition separator, a repetition
   on the component separator, and a component on the subcomponent separator,
   all on demand (rules in section 5). No escape decoding is performed;
   splitting is still safe because HL7 escape bodies are alphanumeric and can
   never contain a separator byte.
10. **Encoding.** `Str` is treated as a UTF-8 byte buffer; all scanning is
    byte-wise and never rewrites multi-byte sequences, so non-ASCII content
    round-trips byte-exact. Bytes >= 0x80 never match an ASCII separator.

## 4. Data model

```xi
pub type Message = {
  field_sep: Str;      // MSH.1, one byte
  comp_sep: Str;       // MSH.2 byte 0
  rep_sep: Str;        // MSH.2 byte 1
  esc_sep: Str;        // MSH.2 byte 2
  sub_sep: Str;        // MSH.2 byte 3
  seg_names: Vec[Str]; // segment names, wire order
  seg_off: Vec[Int];   // seg_off[i] = start of segment i's fields in `fields`
  seg_len: Vec[Int];   // seg_len[i] = field count of segment i
  fields: Vec[Str];    // raw field texts, segment by segment
}
```

Invariants for any `Message` produced by `hl7_parse` or the builder:

- `seg_names.len() == seg_off.len() == seg_len.len()`.
- `seg_off[0] == 0` and `seg_off[i+1] == seg_off[i] + seg_len[i]`, so segment
  fields are contiguous; `fields.len()` is the total field count.
- 1-based HL7 field `f` of segment `i` is `fields[seg_off[i] + f - 1]`.
- The five separator `Str`s are exactly one byte each and pairwise distinct
  (the encoding characters are also distinct from the field separator).
- `seg_names[i]` is non-empty; segment 0 is `MSH` for parsed messages.

`Vec[StructType]` is unsupported in this compiler, so there is deliberately
no `Vec[Segment]`; the flat layout above is the storage model.

## 5. Accessor semantics

All HL7 numbers (field, repetition, component, subcomponent) are 1-based;
segment indices are zero-based.

- `hl7_seg_count` -> number of segments.
- `hl7_seg_name(m, i)` -> `Some(name)` or `None` when `i` is negative or out
  of range. Names are byte-exact (no case folding).
- `hl7_seg_index(m, name)` -> `Some(i)` for the first byte-exact match or
  `None` when absent.
- `hl7_seg_field_count(m, i)` -> stored field count, or `0` when `i` is out of
  range. For MSH the count includes fields 1 and 2.
- `hl7_field_sep` / `hl7_encoding` -> MSH.1 and MSH.2 (`encoding` is the
  concatenation component + repetition + escape + subcomponent).
- `hl7_field(m, i, f)` -> `Some(raw field text)`; `None` when `i` or `f` is
  out of range (`f < 1` included). The text is not split or decoded.
- `hl7_rep_count(m, i, f)` -> `1 +` the number of repetition separators in the
  field; `0` when the field is out of range. A field without `~` has count 1,
  a trailing `~` produces a trailing empty repetition.
- `hl7_rep(m, i, f, r)` -> `Some(repetition r)` or `None` when the field or
  repetition is out of range.
- `hl7_comp_count(m, i, f, r)` / `hl7_comp(m, i, f, r, c)` -> the same rules
  on the component separator, applied to repetition `r`.
- `hl7_sub_count(m, i, f, r, c)` / `hl7_sub(m, i, f, r, c, s)` -> the same
  rules on the subcomponent separator, applied to component `c`.
- Empty parts are preserved everywhere: reading component 2 of `A^^C` gives
  `Some("")`.

Complexity: `hl7_parse` and `hl7_write` are O(total input length); the
hierarchy accessors are O(part length).

## 6. Writing

```xi
pub fn hl7_write(m: &Message) -> Str
```

- Segments are emitted in order, separated and terminated by CR, including a
  final CR. An empty message (no segments) yields `""`.
- MSH is emitted as `MSH` + MSH.1 + MSH.2 + (`fs` + field) for fields 3..n;
  every other segment as name + (`fs` + field) for fields 1..n.
- Field texts are emitted **verbatim**: parsed messages are byte-exact round
  trips, and builder-appended values are already escaped at append time.
- Complexity O(total field bytes). Error case: none.

## 7. Builder

```xi
pub fn hl7_builder_new() -> Message
pub fn hl7_builder_with_separators(field_sep: Str, encoding: Str) -> Result[Message, Str]
pub fn hl7_builder_segment(m: &mut Message, name: Str) -> Str
pub fn hl7_builder_field(m: &mut Message, value: Str) -> Str
pub fn hl7_builder_field_structured(m: &mut Message, value: Str) -> Str
```

- `hl7_builder_new` returns an empty message with `|`, `^`, `~`, `\`, `&`.
  `hl7_builder_with_separators` validates MSH.1 and MSH.2 with the same rules
  as parsing and fails with the same messages (`hl7: invalid separator`,
  `hl7: malformed MSH segment: expected 4 encoding characters, got N`).
- `hl7_builder_segment` opens a new segment and makes it the target of the
  field functions. `MSH` may only be the first segment; opening it stores
  field 1 (the field separator) and field 2 (the encoding characters), so the
  first `hl7_builder_field` afterwards appends MSH.3. A non-MSH name opened
  first fails with `hl7: missing MSH segment`.
- `hl7_builder_field` appends a **data** field: the field separator becomes
  `\F\`, component `\S\`, repetition `\R\`, escape `\E\` and subcomponent
  `\T\` (written with the message's escape character), so no separator in
  `value` can alter the message structure.
- `hl7_builder_field_structured` appends a **wire-level** field: `^`, `~` and
  `&` in `value` are kept as structure, while the field separator becomes
  `\F\` and the escape character becomes `\E\`. Callers must escape data
  separators inside components themselves.
- Both field functions reject CR and LF (`hl7: field contains a line
  terminator`), because a segment is one line. A field appended before any
  segment fails with `hl7: no open segment`.
- Builder calls return `""` on success; success is checked by message
  emptiness, never by exceptions.
- `hl7_write` serializes the builder state, so a builder is a `Message` in
  progress; there is no separate builder type.

## 8. Error catalog

Parse failures are `Err(msg)`; builder calls return `msg` directly. Every
message starts with `"hl7: "` and is deterministic.

| Message | Trigger |
|---|---|
| `hl7: empty message` | no non-terminator byte in the input (`""`, `"\r"`, `"\n"`, `"\r\n"`) |
| `hl7: missing MSH segment` | first line does not start with `MSH`; builder opens a non-MSH segment first |
| `hl7: malformed MSH segment: too short` | MSH line shorter than 4 bytes |
| `hl7: malformed MSH segment: expected 4 encoding characters, got N` | MSH.2 is `N != 4` bytes; custom builder encoding is not 4 bytes |
| `hl7: malformed MSH segment: MSH must be the first segment` | builder opens MSH after another segment |
| `hl7: invalid separator` | MSH.1 or an encoding character is outside `!`..`~`, is alphanumeric, is duplicated, or an encoding character equals MSH.1 |
| `hl7: empty segment name` | zero-length segment line (other than the final artifact), a line starting with the field separator, or an empty builder segment name |
| `hl7: no open segment` | builder field appended before any segment is opened |
| `hl7: field contains a line terminator` | builder field value contains CR or LF |

Notes: the parse path cannot reach "MSH must be the first segment" (it is
builder-only) and cannot observe an encoding character equal to MSH.1,
because MSH.1 terminates MSH.2 structurally; both rules are still enforced by
`hl7_builder_with_separators` and the parser's defensive check.

## 9. Test plan

`tests/test_conformance.xi` (module `hl7_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | segment order | count 3, names MSH/PID/PV1, out-of-range `None`, `seg_index` hit and miss |
| t2 | MSH separators | MSH.1 `\|`, MSH.2 `^~\&`, fields 1-3, MSH field count 12 |
| t3 | field access | 1-based rows, empty fields, bounds (`0`, `9`), field-count `0` |
| t4 | repetitions | `a~b~c~` -> 4 parts incl. trailing empty, bounds |
| t5 | components | `DOE^JOHN^A`, empty middle component, bounds |
| t6 | rep components + subcomponents | component of repetition 2, subcomponents `A&B` vs `C` |
| t7 | custom separators | `MSH*%~\$*...` parse, `%`/`~`/`$` splits, byte-exact round trip |
| t8 | LF/CRLF | both parse to the same structure, write normalizes to CR |
| t9 | trailing terminator | no extra segment, MSH-only messages, byte-exact write |
| t10 | empty message | `""`, `"\r"`, `"\n"`, `"\r\n"` errors |
| t11 | missing MSH | non-MSH first line, lowercase `msh`, short `M` |
| t12 | MSH shape | too short, encoding lengths 0/2/5 |
| t13 | invalid separators | alphanumeric MSH.1, alphanumeric encoding, duplicate, space |
| t14 | empty segment name | empty line, line starting with `\|`, CRLF blank line |
| t15 | name-only segment | `NTE` has 0 fields, per-segment counts, round trip |
| t16 | empty fields | leading/middle/trailing empty fields preserved |
| t17 | builder basics | MSH positional write, data and structured fields, components |
| t18 | builder escaping | data-safe all-five escaping and structure-preserving escaping |
| t19 | builder errors | no open segment, empty name, non-MSH first, duplicate MSH, CR/LF |
| t20 | separator validation | length, charset, duplicates, field-separator collision |
| t21 | UTF-8 | multi-byte field text byte-exact through components and write |
| t22 | full round trip | `M1` byte-exact, every segment/field, reps, components, subs |
| t23 | custom builder | custom separators through build -> write -> parse |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Test dispatch is direct (`t1()` ... `t23()`); no
`Vec[fn]` table is used.

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.syslog`/`xiom.vcf`:

- `Vec[StructType]` is unsupported, so segments are stored as parallel
  homogeneous vectors plus a shared field vector (section 4).
- Every byte read is widened once with `(string.byte_at(s, i) as Int) & 0xFF`;
  byte constants live in `Int` space and non-ASCII bytes are never compared
  against raw `UInt8` literals.
- Output bytes are collected in a `Vec[UInt8]` and materialized once with
  `xiom.string.builder.sb_to_str`; `sb_push_int` formats the one integer that
  appears in error messages.
- `Ok`/`Err` for `Result[Message, Str]` are constructed only in the leaf
  helpers `_ok_msg`/`_err_msg`.
- Str equality goes through `xiom.string.compare.str_compare`; `Vec[Str]`
  elements are read into explicitly typed locals before use.
- The builder mutates the `Message` through `&mut Message` parameters, and
  every call site passes `&mut` explicitly.
- Tests call checks directly (`t1()`, ...), no `Vec[fn]` dispatch, no inline
  lambdas and no `mut` match bindings.

## 11. Known limitations

- No escape decoding: `\F\`, `\S\`, `\R\`, `\E\`, `\T\`, `\X..\` and other
  sequences are returned verbatim; structure splitting remains correct
  because escape bodies are alphanumeric.
- No transport (MLLP), no batch envelope handling, no file I/O.
- No data-type semantics or profile validation (dates, codes, numbers, names
  stay `Str`).
- No cross-segment field-count consistency check; counts are reported per
  segment.
- The parse path does not enforce "exactly one MSH" or MSH-first-only beyond
  the first line: a later `MSH` line is an ordinary segment. The builder
  enforces MSH as the first segment.
- Segment names are not restricted to the conventional three characters, and
  a name-only segment is valid with zero fields.
- `hl7_write` always appends the final CR, so LF-terminated input is
  normalized to CR.
- The builder cannot mutate fields after they are appended; rebuild or parse
  a template to change an existing message.
