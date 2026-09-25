# xiom.vcf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.vcf` (`src/vcf.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for an RFC 6350 subset of vCard text held in
memory as a `Str`:

- `vcf_parse_card` -- one card -> `Result[VCard, Str]`,
- `vcf_parse_stream` -- one or more cards -> `Result[VCardStream, Str]`,
- `vcf_property_count` / `vcf_property` / `vcf_prop_index` /
  `vcf_prop_value` / `vcf_props_all` / `vcf_param_value` -- model access,
- `vcf_stream_count` / `vcf_stream_version` / `vcf_stream_property_count` /
  `vcf_stream_property` -- stream access,
- `vcf_escape` / `vcf_escape_component` / `vcf_unescape` -- value coding,
- `vcf_build_n` / `vcf_build_adr` / `vcf_build_card` -- card construction,
- `vcf_write` / `vcf_write_stream` -- canonical serialization.

The codec owns: content-line syntax (optional group, parameters, value),
CRLF folding/unfolding, backslash value escaping, the
`BEGIN:VCARD`/`VERSION:3.0|4.0`/`END:VCARD` envelope, and multi-card
streams. It answers "what properties does this card carry, with which
parameters and decoded values?" and nothing more.

## 2. Non-goals

- **No binary payload decoding**: `PHOTO`, `LOGO`, `SOUND`, `KEY` are ordinary
  text values; base64 and `data:` payloads pass through verbatim.
- **No charset conversion**: no `CHARSET`, `ENCODING`, quoted-printable or
  base64 interpretation; bytes are preserved.
- **No vCard 2.1 quirks**: VERSION 2.1 is rejected. The only tolerances are
  LF/lone-CR line endings, a leading UTF-8 BOM, bare (equals-less) parameter
  segments, and unknown backslash escapes.
- **No property semantics**: N/ADR/ORG/GEO are not decomposed into
  components; no date, phone, URI or language validation; no group
  semantics; no RFC 6868 caret-decoding in parameter values; only the first
  comma-separated value of a parameter is returned.
- **No byte-exact round-tripping**: parse decodes escapes and uppercases
  names; write re-encodes canonically. Parse -> write -> parse is
  model-preserving (section 9).
- FFI, file I/O, network I/O, registry integration.

## 3. Data model

```xi
pub type VcfProperty = {
  group: Str;   // group prefix before "."; "" when none
  name: Str;    // property name, ASCII-uppercased on parse
  params: Str;  // raw parameter section without the leading ";"; "" when none
  value: Str;   // decoded (unescaped) value
  raw: Str;     // the original logical content line
}

pub type VCard = {
  version: Str;        // "3.0" or "4.0"
  groups: Vec[Str];    // parallel per-property vectors, index-aligned
  names: Vec[Str];
  params: Vec[Str];
  values: Vec[Str];
  raws: Vec[Str];
}

pub type VCardStream = {
  versions: Vec[Str];  // one entry per card, in order
  firsts: Vec[Int];    // start index of card i inside the property vectors
  counts: Vec[Int];    // property count of card i
  groups: Vec[Str];    // all properties of all cards, in document order
  names: Vec[Str];
  params: Vec[Str];
  values: Vec[Str];
  raws: Vec[Str];
}
```

Invariants. `VCard`: the five vectors have equal lengths; they hold every
content line between VERSION and END:VCARD in document order (BEGIN, VERSION
and END are structural and are not stored). `VCardStream`: `versions`,
`firsts` and `counts` have equal lengths; the five property vectors have
equal lengths; card `i` owns the index range
`[firsts[i], firsts[i] + counts[i])`.

`Vec[StructType]` is not usable in this compiler, so a card is a struct of
parallel vectors and a stream is one flat property list plus per-card index
vectors (no `Vec[VCard]`).

## 4. Grammar

```
stream      = *( card-separator ) card *( card-separator card ) *( card-separator )
card-separator = *blank-line
card        = "BEGIN:VCARD" eol "VERSION" ":" ( "3.0" / "4.0" ) eol
              *( property eol ) "END:VCARD"
property    = [ group "." ] name [ params ] ":" value
group       = 1*( ALPHA / DIGIT / "-" )
name        = 1*( ALPHA / DIGIT / "-" )
params      = ";" param-text        ; captured verbatim, not validated
value       = *( byte except CR / LF )
eol         = LF / CRLF / CR
blank-line  = eol                    ; zero-length logical line
```

Parsing decisions (each is covered by the conformance suite):

1. **Line splitting.** A physical line ends at LF, CRLF or a lone CR; a final
   line without a terminator is still a line, and a trailing terminator does
   not produce an extra empty line.
2. **Unfolding.** A physical line whose first byte is SPACE or TAB is a
   continuation: the line terminator and exactly one leading whitespace byte
   are removed and the rest is appended directly (no separator) to the
   previous logical line. A continuation with no previous logical line (only
   possible as the first line of the text) stays a standalone logical line.
   A folding-whitespace-only continuation contributes nothing.
3. **BOM.** A UTF-8 byte-order mark (`EF BB BF`) on the very first logical
   line is ignored; elsewhere it is ordinary data.
4. **Blank lines.** Zero-length logical lines are skipped before the first
   card, between cards, inside a card and after the last card. They are not
   stored as properties.
5. **Card envelope.** The first non-blank logical line outside a card must
   scan as a bare `BEGIN` property whose value is `VCARD` (case-insensitive);
   the card ends at the first bare `END:VCARD`. `BEGIN`, `END` and `VERSION`
   are recognized only in their bare form: any group or parameter section
   makes them ordinary property lines (for `VERSION` that means the card is
   reported as `missing VERSION`).
6. **VERSION.** The first property of a card must be `VERSION:3.0` or
   `VERSION:4.0` (exact value, no surrounding whitespace tolerance). It is
   stored in `version`, not in the property vectors. A second `VERSION` in
   the same card is `Err("vcf: duplicate VERSION")`; any card whose first
   stored property is not `VERSION`, or which closes without one, is
   `Err("vcf: missing VERSION")`.
7. **Names and groups.** Names and groups are ASCII `A-Z a-z 0-9 -` tokens.
   The name is uppercased byte-wise (`A-Z` only) and stored; the group is
   stored verbatim. An empty name (`:v`), an empty name after a dot
   (`item1.:v`) or a non-token byte before the colon (`NOT A LINE`) is
   malformed.
8. **Parameters.** Everything between the first `;` after the name and the
   value colon is captured verbatim (without the leading `;`). Quoted strings
   (`"..."`) hide `;` and `:` while scanning for the value colon; unbalanced
   quotes make the line malformed. Parameter text is otherwise not validated:
   empty segments and equals-less segments are tolerated and preserved.
9. **Values.** The value is everything after the value colon, decoded with
   `vcf_unescape` (section 6). Values are never trimmed, so leading and
   trailing whitespace survives. Later colons are value bytes.
10. **`parse_card` vs `parse_stream`.** `vcf_parse_card` accepts exactly one
    card; after its `END:VCARD`, any further non-blank line is
    `Err("vcf: unexpected content after END:VCARD: <line>")`.
    `vcf_parse_stream` accepts one or more cards separated by blank lines and
    ignores trailing blanks. `Err("vcf: empty input")` when there is no
    non-blank content at all.
11. **Encoding.** `Str` is a UTF-8 byte buffer; scanning is byte-wise and
    never rewrites multi-byte sequences.

## 5. Content-line access

```xi
pub fn vcf_property_count(v: &VCard) -> Int
pub fn vcf_property(v: &VCard, i: Int) -> VcfProperty
pub fn vcf_prop_index(v: &VCard, name: Str) -> Int
pub fn vcf_prop_value(v: &VCard, name: Str) -> Option[Str]
pub fn vcf_props_all(v: &VCard, name: Str) -> Vec[Str]
pub fn vcf_param_value(v: &VCard, i: Int, pname: Str) -> Option[Str]
```

- `vcf_property` returns the all-empty property (every field `""`) when `i`
  is negative or >= the count; callers check `name`.
- `vcf_prop_index` uppercases `name` with the same ASCII rule as stored
  names, so `"tel"` and `"TEL"` are equivalent; -1 when absent.
- `vcf_prop_value` returns the first matching value; `vcf_props_all` returns
  a fresh vector with every matching value in document order (empty when
  absent).
- `vcf_param_value` scans property `i`'s parameter text in `;`-separated
  segments (respecting quoted strings). A segment without an `=` at index
  > 0 is skipped; a segment whose key matches `pname` case-insensitively
  yields its first comma-separated value (commas inside quotes do not
  split). A value wrapped in double quotes loses exactly those outer quotes.
  Negative/out-of-range `i`, no parameter text, or no match -> `None`.

## 6. Escaping

`vcf_escape` (text values) and `vcf_escape_component` (N/ADR components)
encode; `vcf_unescape` decodes:

| Input byte | `vcf_escape` | `vcf_escape_component` |
|---|---|---|
| `\` | `\\` | `\\` |
| LF | `\n` | `\n` |
| CRLF | `\n` | `\n` |
| lone CR | `\n` | `\n` |
| `;` | `\;` | `;` (component separator, kept) |
| `,` | `\,` | `\,` (list separator inside a component, escaped) |
| anything else | unchanged | unchanged |

Decoding (`vcf_unescape`): `\\` -> `\`, `\n` and `\N` -> LF, `\;` -> `;`,
`\,` -> `,`, any other `\X` -> `X` (tolerant), and a trailing lone `\` is
kept. Decoding does not invent CR or `;`/`,` handling: only these escapes.

Escaping is canonical and idempotent in the sense that
`vcf_unescape(vcf_escape(s)) == s` for every `s`, and
`vcf_escape(vcf_unescape(e))` is the canonical form of `e` for canonical `e`.

## 7. Folding and writing

- `vcf_write` emits `BEGIN:VCARD`, `VERSION:<version>`, every stored
  property in order, and `END:VCARD`.
- A property line is `[group "."] NAME [";" params] ":" value`; the name is
  written as stored (uppercase after parsing); the parameter text is
  re-emitted verbatim.
- Values are re-escaped: properties named `N` and `ADR` use
  `vcf_escape_component` (their `;` bytes stay structural), every other
  property uses `vcf_escape`.
- Every physical line ends with CRLF. A logical line longer than 75 bytes is
  split into physical lines: the first carries up to 75 bytes and each
  continuation starts with one SPACE and carries up to 74 content bytes, so
  no physical line exceeds 75 bytes. Folding is byte-based and may split a
  multi-byte UTF-8 sequence.
- `vcf_write_stream` concatenates `vcf_write` for every card with no
  separator.
- Parse -> write -> parse is model-preserving: version, property count,
  names, groups, parameter text and decoded values are identical (proved by
  t24).

## 8. Building

```xi
pub fn vcf_build_n(family: Str, given: Str, additional: Str, prefix: Str, suffix: Str) -> Str
pub fn vcf_build_adr(pobox: Str, ext: Str, street: Str, locality: Str, region: Str, code: Str, country: Str) -> Str
pub fn vcf_build_card(version: Str, formatted_name: Str, n: Str, org: Str, tel: Str, email: Str, adr: Str) -> Result[Str, Str]
```

- `vcf_build_n` / `vcf_build_adr` escape each component with
  `vcf_escape_component` and join the components with `;` (always the full
  five / seven components, including empty trailing ones).
- `vcf_build_card` emits, in order, `BEGIN:VCARD`, `VERSION:<version>`,
  `FN:<vcf_escape(formatted_name)>`, then `N`, `ORG`, `TEL`, `EMAIL`, `ADR`
  for every argument that is non-empty, then `END:VCARD`, all CRLF and
  folded at 75 bytes. `FN`, `ORG`, `TEL` and `EMAIL` are decoded text values
  and are escaped with `vcf_escape`. `N` and `ADR` must already be escaped
  structured values and are emitted verbatim -- build them with
  `vcf_build_n` / `vcf_build_adr`.
- `Err("vcf: unsupported version: <version>")` when version is not `3.0` or
  `4.0`; `Err("vcf: FN is required")` when `formatted_name` is empty.

## 9. API signatures

```xi
pub fn vcf_escape(value: Str) -> Str
pub fn vcf_escape_component(value: Str) -> Str
pub fn vcf_unescape(value: Str) -> Str
pub fn vcf_parse_card(text: Str) -> Result[VCard, Str]
pub fn vcf_parse_stream(text: Str) -> Result[VCardStream, Str]
pub fn vcf_property_count(v: &VCard) -> Int
pub fn vcf_property(v: &VCard, i: Int) -> VcfProperty
pub fn vcf_prop_index(v: &VCard, name: Str) -> Int
pub fn vcf_prop_value(v: &VCard, name: Str) -> Option[Str]
pub fn vcf_props_all(v: &VCard, name: Str) -> Vec[Str]
pub fn vcf_param_value(v: &VCard, i: Int, pname: Str) -> Option[Str]
pub fn vcf_stream_count(s: &VCardStream) -> Int
pub fn vcf_stream_version(s: &VCardStream, i: Int) -> Str
pub fn vcf_stream_property_count(s: &VCardStream, i: Int) -> Int
pub fn vcf_stream_property(s: &VCardStream, card: Int, idx: Int) -> VcfProperty
pub fn vcf_build_n(family: Str, given: Str, additional: Str, prefix: Str, suffix: Str) -> Str
pub fn vcf_build_adr(pobox: Str, ext: Str, street: Str, locality: Str, region: Str, code: Str, country: Str) -> Str
pub fn vcf_build_card(version: Str, formatted_name: Str, n: Str, org: Str, tel: Str, email: Str, adr: Str) -> Result[Str, Str]
pub fn vcf_write(v: &VCard) -> Str
pub fn vcf_write_stream(s: &VCardStream) -> Str
```

Complexity: parsing and writing are O(input length); accessor functions are
O(1) except lookup by name (`vcf_prop_index`, `vcf_prop_value`,
`vcf_props_all`) which is O(property count).

## 10. Error catalog

Parse failures are `Err(msg)` with `msg` starting with `"vcf: "`:

| Message | Trigger |
|---|---|
| `vcf: empty input` | no non-blank logical line at all |
| `vcf: malformed content line: <line>` | line fails the content-line grammar: empty name, empty name after a dot, a non-token byte before the value colon, no value colon, or unbalanced parameter quotes |
| `vcf: expected BEGIN:VCARD, got: <line>` | a well-formed property line appears outside any card and is not `BEGIN:VCARD` |
| `vcf: nested BEGIN:VCARD` | `BEGIN:VCARD` while a card is open |
| `vcf: missing END:VCARD` | end of input while a card is open |
| `vcf: missing VERSION` | the first stored property of a card is not `VERSION`, or the card closes with no version |
| `vcf: unsupported version: <v>` | VERSION value is not `3.0` or `4.0` (e.g. `2.1`) |
| `vcf: duplicate VERSION` | a second `VERSION` in one card |
| `vcf: unexpected content after END:VCARD: <line>` | `vcf_parse_card` only: non-blank content after the single card |

Build failures (`vcf_build_card`) are `Err(msg)` with `msg` starting with
`"vcf: "`:

| Message | Trigger |
|---|---|
| `vcf: unsupported version: <v>` | version argument is not `3.0` or `4.0` |
| `vcf: FN is required` | `formatted_name` is empty |

The error text includes the offending line where applicable, but no line or
column numbers. Every message is produced verbatim by the code, so tests can
pin exact prefixes.

## 11. Test plan

`tests/test_conformance.xi` (module `vcf_tests`) runs 24 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | minimal cards | 3.0 and 4.0 envelopes; surrounding blank lines ignored |
| t2 | full card | all six fields, document order, case-insensitive lookup |
| t3 | groups/parameters | group capture, raw parameter text, first list value |
| t4 | quoted parameters | `:`/`;` inside quotes; second parameter after quotes |
| t5 | value unescaping | `\,` `\;` `\\` `\n` and `\N` decode |
| t6 | escaping | round-trip incl. non-ASCII; CRLF/CR -> `\n` |
| t7 | folding | space/tab/multi-line continuation; trailing space preserved |
| t8 | line endings | LF, lone CR and mixed terminators |
| t9 | stream | three cards, versions, per-card counts/indices, bounds |
| t10 | stream round-trip | write -> parse keeps cards and properties |
| t11 | structure errors | empty/junk input, missing END, nested BEGIN, expected BEGIN |
| t12 | VERSION rules | missing, before-property, 3.0/4.0 only, duplicate |
| t13 | line errors | malformed lines; `parse_card` vs `parse_stream` on two cards |
| t14 | build_card | all six fields; CRLF-only; reparse equality |
| t15 | build errors | unsupported versions; empty FN |
| t16 | build omissions/folding | empty fields omitted; 200-byte FN folds <=75 and reparses |
| t17 | builders | `build_n` / `build_adr` component escaping and composition |
| t18 | empty values | `X:`, empty parameter section, whitespace value preserved |
| t19 | colons in values | NOTE/URL values keep later colons |
| t20 | tolerant unescaping | unknown escape, trailing backslash, `\N` |
| t21 | accessors | first/all values, missing lookups, out-of-range properties |
| t22 | BOM | leading `EF BB BF` ignored |
| t23 | write folding | `vcf_write` <=75-byte CRLF lines; reparse equality |
| t24 | model round-trip | parse -> write -> parse keeps version/names/groups/params/values |

All `Str` equality goes through `xiom.string.compare.str_compare` (BUG 17:
`==` on `Str` values read from `Vec[Str]` elements lowers to a pointer
comparison); `Vec[Str]` elements are read into explicitly typed locals first.

## 12. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-codec
idioms as `xiom.eml`/`xiom.csv` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the card/stream models are flat
  parallel vectors (section 3).
- `Ok`/`Err` for every `Result` are constructed only in the leaf helpers
  `_vcf_ok_*` / `_vcf_err_*`.
- Str equality between `Vec[Str]` elements goes through
  `str_compare`/`str_compare_ignore_case`; values are read into typed locals
  before use.
- All byte reads are widened once: `(string.byte_at(s, i) as Int) & 0xFF`,
  so no `UInt8` value is compared against an integer literal.
- Tests dispatch directly (`t1()` ... `t24()`); no `Vec[fn]` indexed calls,
  no inline lambdas, no match pattern binds `mut`, and every `match` is
  exhaustive.
- Free functions only; no self methods. The public API borrows `&VCard` /
  `&VCardStream` for reads; parsing works on locals and returns fresh
  structs.

## 13. Known limitations

- Property values are opaque text: no component decomposition (N, ADR, ORG,
  GEO), no property-specific validation, no date/URI/phone parsing.
- No binary or transfer-encoded payload handling; PHOTO et al. are strings.
- No charset handling; non-ASCII bytes pass through.
- Parameter values keep their raw escapes apart from having outer quotes
  removed; RFC 6868 caret-decoding is not implemented.
- Escaping is canonical: parse decodes, write re-encodes, so byte-exact
  round-tripping is not preserved (model-level round-tripping is).
- Fold points are byte positions; a multi-byte UTF-8 sequence may be split.
- `vcf_parse_card` rejects multi-card input; use `vcf_parse_stream`.
- Errors carry the offending line text but no line/column positions.
