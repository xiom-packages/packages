# xiom.expat -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.expat` (`src/expat.xi`). Pure XIOM, no FFI.
Reference: XML 1.0 (Fifth Edition), W3C Recommendation 26 November 2008 --
implemented as the subset below, not as a validating/complete XML processor.

## 1. Scope

An event-based XML parser over one `Str`:

- `expat_parse` -- whole document -> `Result[ExpatState, Str]`: the complete
  event stream in document order.
- `expat_open` + `expat_next_event` -- the same parser as an incremental event
  source over the in-memory text (no cross-buffer streaming).
- One-shot helpers over a parsed state: element count/name/depth, attribute
  access by index or by name, concatenated text content, document metadata
  (encoding, version, standalone, entity table).

Encoding pipeline (applied by `expat_open` before any event):

1. A UTF-8 BOM (`EF BB BF`) is detected and stripped.
2. `UTF-16LE` (`FF FE`) and `UTF-16BE` (`FE FF`) BOMs are detected and
   **rejected**: `expat: UTF-16LE input unsupported at 0` /
   `... UTF-16BE ...`. XIOM `Str` is NUL-terminated, so UTF-16 bytes (whose
   ASCII code units contain NUL bytes) cannot exist in a `Str`; detection is
   the honest maximum supportable here.
3. Otherwise a leading `<?xml ...?>` declaration is peeked for its `encoding`
   pseudo-attribute. `utf-8`/`utf8` spellings parse as UTF-8; `iso-8859-1`,
   `iso8859-1`, `latin-1` and `latin1` (case-insensitive) select the Latin-1
   fallback, which re-encodes bytes `0x80-0xFF` as `U+0080-U+00FF` in UTF-8.
   Any other declared label is `expat: unsupported encoding at <pos>` where
   `<pos>` is the offset of the `encoding` keyword.
4. The (remaining) text is validated as strict UTF-8 (RFC 3629): stray
   continuation bytes, truncated sequences, overlong forms, UTF-8-encoded
   surrogates and values above `U+10FFFF` are
   `expat: invalid UTF-8 byte at <pos>`. A NUL byte (only reachable via a
   Latin-1 declaration, since `Str` cannot otherwise carry one) is
   `expat: NUL byte at <pos>`.

All offsets in a parsed state are byte offsets into the decoded text (BOM
stripped; Latin-1 re-encoded). Line/column counters are 1-based; CR, LF and
CRLF each count as one line end, and columns count code points (UTF-8
continuation bytes do not advance the column).

## 2. Non-goals

- DTD validation of any kind; `<!ELEMENT>`, `<!ATTLIST>`, `<!NOTATION>` and
  friends are preserved raw in the DOCTYPE event and otherwise ignored.
- External entities, parameter entities (an `<!ENTITY % ...>` declaration is
  an error), external subsets, conditional sections.
- Namespace URI resolution; prefixed names and `xmlns` attributes are recorded
  verbatim. `expat_prefix_of`/`expat_local_of` split on the first `:` only.
- The full Unicode name ranges: ASCII `NameStartChar`/`NameChar` are enforced
  exactly; bytes `>= 0x80` (already validated as UTF-8) pass through, as
  documented in section 4.
- Attribute types/`#FIXED` defaults from a DTD (only CDATA-style
  normalization is applied), entity value normalization rules for external
  entities, conditional/default attribute injection.
- XML line-end normalization: raw CR/LF are preserved in text, comment, PI and
  CDATA payloads. Attribute values ARE normalized (tab/LF/CR -> space).
- Error recovery, resumable states after `Err`, cross-buffer streaming.
- Text declarations (the `<?xml ...?>` form allowed in external entities) and
  the `version="1.1"` code-point additions: `version` must match `1.[0-9]+`,
  and any character outside the XML 1.0 `Char` production is rejected where
  checked (character references, raw controls).

## 3. Grammar subset

Productions not listed keep their XML 1.0 meaning within the stated limits.
`S` is one or more XML whitespace bytes (space, tab, LF, CR).

```
document      = decl? misc* (doctype misc*)? element misc*        (see notes)
decl          = '<?xml' S VersionInfo EncodingDecl? SDDecl? S? '?>'
VersionInfo   = S 'version' Eq ('"' VersionNum '"' | "'" VersionNum "'")
EncodingDecl  = S 'encoding' Eq ('"' EncName '"' | "'" EncName "'")
SDDecl        = S 'standalone' Eq (("'" ('yes'|'no') "'") | ('"' ('yes'|'no') '"'))
misc          = comment | PI | S
doctype       = '<!DOCTYPE' S Name (S ExternalID)? S? ('[' intSubset ']' S?)? '>'
ExternalID    = 'SYSTEM' S SystemLiteral
              | 'PUBLIC' S PubidLiteral S SystemLiteral
intSubset     = raw text, bracket-balanced; scanned only for ENTITY declarations
entityDecl    = '<!ENTITY' S Name S EntityValue S? '>'
EntityValue   = '"' ([^%&"] | Reference)* '"' | "'" ([^%&'] | Reference)* "'"
element       = '<' Name (S attribute)* S? '>' content '</' Name S? '>'
              | '<' Name (S attribute)* S? '/>'
attribute     = Name Eq AttValue
AttValue      = '"' ([^<&"] | Reference)* '"' | "'" ([^<&'] | Reference)* "'"
content       = (text | element | Reference | CDATA | comment | PI)*
text          = any run of Chars up to the next '<' (see notes)
comment       = '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
PI            = '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
CDATA         = '<![CDATA[' (Char* - (Char* ']]>' Char*)) ']]>'
Reference     = EntityRef | CharRef
EntityRef     = '&' Name ';'          (predefined or internal subset entity)
CharRef       = '&#[0-9]+;' | '&#x[0-9A-Fa-f]+;'
Name          = NameStartChar NameChar*
```

Decisions, each pinned by the conformance suite:

1. **Declaration placement.** `<?xml ...?>` is accepted only at offset 0 of the
   decoded text; a `[Xx][Mm][Ll]` PI target anywhere else is
   `reserved PI target`. Declaration pseudo-attributes must appear in the
   order version, encoding?, standalone?; duplicates, reordering, missing
   version and shape violations are `bad XML declaration`. The declared
   encoding must be UTF-8 or Latin-1 (`unsupported encoding`).
2. **DOCTYPE placement.** At most one DOCTYPE, only before the root element
   starts (`duplicate DOCTYPE`, `DOCTYPE after root element`). The name is
   required; `SYSTEM` takes one quoted literal, `PUBLIC` two. The subset is
   bracket-balanced (quotes and comments inside are skipped) and preserved raw
   in the event data. Missing pieces are `unterminated DOCTYPE` /
   `unterminated DOCTYPE literal`.
3. **Entities.** The five predefined entities always resolve. Character
   references decode decimal or hex (at most 8 digits) and must name an XML 1.0
   `Char`; otherwise `bad character reference`. Named references resolve in the
   internal entity table: an unknown name is `unknown entity`, a malformed
   reference (`&;`, missing `;`, non-name) is `malformed entity reference`, all
   reported at the offset of the `&`. Internal entity values are literal text:
   references inside them expand recursively, with a nesting cap of 16
   (`entity nesting too deep`) and an expansion cap of 65536 bytes per
   text/attribute run (`entity expansion too large`). `<!ENTITY lt ...>`
   redefinitions are `reserved entity redeclared`, repeated names are
   `duplicate entity`, and parameter entities are `parameter entity not
   supported`.
4. **Names.** `NameStartChar` = `[A-Za-z_:]` or any byte `>= 0x80`;
   `NameChar` = start plus `[0-9.-]`, `0xB7`, or any byte `>= 0x80`. The input
   is already validated UTF-8, so non-ASCII bytes form well-formed sequences;
   they are not checked against the Unicode name ranges (non-goal).
   Whitespace is required between attributes
   (`missing whitespace between attributes`).
5. **Attributes.** Values must be single- or double-quoted (no entity form:
   `unterminated attribute value` when a quote is missing/absent). Raw `<` is
   `'<' in attribute value`. Raw tab/LF/CR become one space each; references
   expand (and are NOT re-normalized); raw control bytes below 0x20 (other
   than tab/LF/CR) are `control character`. Duplicate names on the same start
   tag are `duplicate attribute`. The quote style is recorded (0 double,
   1 single).
6. **Comments.** The body is stored raw. A `--` that is not immediately
   followed by `>` is `double dash in comment`; an unterminated comment is
   `unterminated comment` at the opening `<!--`.
7. **PI.** The target is a Name that must not be `[Xx][Mm][Ll]` (except the
   declaration at offset 0); leading whitespace after the target is consumed
   and the data runs to the first `?>` (`unterminated PI` otherwise).
8. **CDATA.** Only inside the root element (`CDATA outside root element`); the
   body is raw up to the first `]]>` (`unterminated CDATA` otherwise); no
   reference expansion happens inside.
9. **Text.** A run of characters up to the next `<`. References expand.
   A raw `]]>` is `']]>' in text` (entity-produced `]]>` is exempt, as XML
   requires). Raw controls are `control character`. Whitespace-only runs are
   preserved as text events. At depth 0 only whitespace is allowed:
   non-whitespace before the root is `text before root element`, after it is
   `junk after root element`.
10. **Elements.** End tags must match the innermost open element
    (`mismatched end tag` at the `</`), an end tag with no open element is
    `unexpected end tag`, open depth is capped at 256 (`element nesting too
    deep`). `<` not followed by a valid markup start or NameStartChar is
    `invalid markup`. After the last event, a non-empty stack is
    `unclosed element` (reported at the outermost unclosed start offset) and a
    missing root is `no root element` (reported at end of input).
11. **Empty elements.** `<a/>` produces a start event consuming the whole
    `<a/>` markup, immediately followed by an end event with the same
    offset/line/column and `consumed == 0`; `expat_element_count` counts it
    once.
12. **Determinism.** The same input always yields the same state or the same
    first error; messages are fixed strings plus a byte offset; the input is
    never mutated.

## 4. API contract

```xi
pub type ExpatState = { /* parallel Vec fields + cursor + metadata */ }

pub fn expat_open(text: Str) -> Result[ExpatState, Str]
pub fn expat_parse(text: Str) -> Result[ExpatState, Str]
pub fn expat_next_event(st: &mut ExpatState) -> Result[Int, Str]   // Ok(-1) at end

// document metadata
pub fn expat_encoding(st: &ExpatState) -> Str
pub fn expat_version(st: &ExpatState) -> Str
pub fn expat_standalone(st: &ExpatState) -> Int      // 1 yes, 0 no, -1 absent
pub fn expat_has_decl(st: &ExpatState) -> Bool
pub fn expat_has_doctype(st: &ExpatState) -> Bool
pub fn expat_depth(st: &ExpatState) -> Int
pub fn expat_entity_count(st: &ExpatState) -> Int
pub fn expat_entity_name(st: &ExpatState, i: Int) -> Str
pub fn expat_entity_value(st: &ExpatState, i: Int) -> Str

// events
pub fn expat_event_count(st: &ExpatState) -> Int
pub fn expat_event_kind(st: &ExpatState, i: Int) -> Int            // -1 when OOR
pub fn expat_event_kind_name(kind: Int) -> Str
pub fn expat_event_name(st: &ExpatState, i: Int) -> Str
pub fn expat_event_data(st: &ExpatState, i: Int) -> Str
pub fn expat_event_system_id(st: &ExpatState, i: Int) -> Str
pub fn expat_event_public_id(st: &ExpatState, i: Int) -> Str
pub fn expat_event_standalone(st: &ExpatState, i: Int) -> Int
pub fn expat_event_offset(st: &ExpatState, i: Int) -> Int
pub fn expat_event_line(st: &ExpatState, i: Int) -> Int
pub fn expat_event_column(st: &ExpatState, i: Int) -> Int
pub fn expat_event_consumed(st: &ExpatState, i: Int) -> Int
pub fn expat_event_attr_count(st: &ExpatState, i: Int) -> Int
pub fn expat_event_attr_name(st: &ExpatState, i: Int, k: Int) -> Str
pub fn expat_event_attr_value(st: &ExpatState, i: Int, k: Int) -> Str
pub fn expat_event_attr_quote(st: &ExpatState, i: Int, k: Int) -> Int

// elements and content
pub fn expat_element_count(st: &ExpatState) -> Int
pub fn expat_element_event(st: &ExpatState, i: Int) -> Int         // -1 when OOR
pub fn expat_element_name(st: &ExpatState, i: Int) -> Str
pub fn expat_element_depth(st: &ExpatState, i: Int) -> Int
pub fn expat_element_attr_count(st: &ExpatState, i: Int) -> Int
pub fn expat_element_attr_name(st: &ExpatState, i: Int, k: Int) -> Str
pub fn expat_element_attr_value(st: &ExpatState, i: Int, k: Int) -> Str
pub fn expat_extract_attribute(st: &ExpatState, i: Int, name: Str) -> Str
pub fn expat_text_content(st: &ExpatState, i: Int) -> Str

// qualified names (recorded, never resolved)
pub fn expat_prefix_of(name: Str) -> Str
pub fn expat_local_of(name: Str) -> Str
```

Event kinds: `0 decl`, `1 doctype`, `2 comment`, `3 pi`, `4 cdata`,
`5 start`, `6 end`, `7 text`. Out-of-range reads return `""` / `-1` / `false`
rather than failing. Element indices are the ordinals of start events (so an
empty element has exactly one element index). `expat_text_content` walks from
the element's start event to its matching end event, concatenating text and
CDATA payloads at any descendant depth; comment/PI payloads are excluded and
relative nesting deeper than 1024 contributes nothing.

## 5. Limits

| Limit | Value | Error when exceeded |
|---|---|---|
| open-element depth | 256 | `element nesting too deep` |
| entity nesting depth | 16 | `entity nesting too deep` |
| expansion per text/attribute run | 65536 bytes | `entity expansion too large` |
| `expat_text_content` relative depth | 1024 | deeper text is skipped |
| character reference digits | 8 | `bad character reference` |

## 6. Error catalog

Every error is the string `"expat: " + <text> + " at " + <decimal byte
offset>` (`xiom.convert.int_to_string`); parsing stops at the first error.

| # | Message text | Condition |
|---|---|---|
| 1 | `invalid UTF-8 byte` | ill-formed UTF-8; pos = first problem byte |
| 2 | `NUL byte` | a U+0000 byte (reachable via a Latin-1 declaration) |
| 3 | `UTF-16LE input unsupported` / `UTF-16BE input unsupported` | UTF-16 BOM detected; pos = 0 |
| 4 | `unsupported encoding` | declared encoding is neither UTF-8 nor Latin-1; pos = the `encoding` keyword |
| 5 | `bad XML declaration` | declaration shape/order/value violation; pos = the offending byte/quote |
| 6 | `unterminated XML declaration` | no `?>` before end of input; pos = declaration start |
| 7 | `duplicate XML declaration` | a second declaration at offset 0 (unreachable in one parse) |
| 8 | `reserved PI target` | `[Xx][Mm][Ll]` target outside offset 0; pos = `<?` |
| 9 | `invalid PI target` | PI name scan failed; pos = target start |
| 10 | `unterminated PI` | no `?>`; pos = `<?` |
| 11 | `double dash in comment` | `--` not followed by `>`; pos = first `-` |
| 12 | `unterminated comment` | no `-->`; pos = `<!--` |
| 13 | `unterminated CDATA` | no `]]>`; pos = `<![CDATA[` |
| 14 | `CDATA outside root element` | CDATA at depth 0; pos = `<![CDATA[` |
| 15 | `control character` | raw byte < 0x20 other than tab/LF/CR; pos = byte |
| 16 | `']]>' in text` | raw `]]>` in character data; pos = `>` |
| 17 | `bad DOCTYPE` | `<!DOCTYPE` not followed by whitespace; pos = byte |
| 18 | `invalid DOCTYPE name` | DOCTYPE name scan failed; pos = name start |
| 19 | `unterminated DOCTYPE` | subset bracket or `>` never closed; pos = `[` / `<!DOCTYPE` |
| 20 | `unterminated DOCTYPE literal` | quoted SYSTEM/PUBLIC literal not closed; pos = quote |
| 21 | `duplicate DOCTYPE` | second DOCTYPE; pos = second `<!DOCTYPE` |
| 22 | `DOCTYPE after root element` | DOCTYPE after the root started; pos = `<!DOCTYPE` |
| 23 | `unterminated entity declaration` | ENTITY declaration cut short; pos = problem byte |
| 24 | `unterminated entity literal` | entity value quote not closed; pos = quote |
| 25 | `invalid entity name` | ENTITY name scan failed; pos = name start |
| 26 | `reserved entity redeclared` | `lt/gt/amp/apos/quot` declared; pos = name |
| 27 | `duplicate entity` | same entity name declared twice; pos = second name |
| 28 | `parameter entity not supported` | `%` in an ENTITY declaration or entity value; pos = `%` |
| 29 | `unknown entity` | named reference not predefined/declared; pos = `&` |
| 30 | `malformed entity reference` | `&;`, non-name, or missing `;`; pos = `&` |
| 31 | `bad character reference` | bad digits/length, non-`Char`, NUL; pos = `&` |
| 32 | `entity nesting too deep` | expansion depth >= 16; pos = outer `&` |
| 33 | `entity expansion too large` | a run exceeded 64 KiB; pos = outer `&` |
| 34 | `invalid markup` | `<` not followed by a valid declaration/comment/PI/CDATA/end/name start; pos = `<` |
| 35 | `invalid element name` | element name scan failed (defensive) |
| 36 | `invalid attribute name` | attribute name scan failed; pos = name start |
| 37 | `missing '=' in attribute` | attribute name not followed by `=`; pos = byte |
| 38 | `unterminated attribute value` | missing/unquoted/closing quote absent; pos = value start |
| 39 | `'<' in attribute value` | raw `<` inside a quoted value; pos = `<` |
| 40 | `duplicate attribute` | same name twice on one tag; pos = second name |
| 41 | `missing whitespace between attributes` | attributes not separated by whitespace; pos = byte |
| 42 | `unterminated start tag` | no `>`/`/>`; pos = `<` (or stray `/`) |
| 43 | `invalid end tag name` | end-tag name scan failed; pos = name start |
| 44 | `unterminated end tag` | end tag not closed by `>`; pos = `</` |
| 45 | `unexpected end tag` | end tag at depth 0; pos = `</` |
| 46 | `mismatched end tag` | end name != innermost open name; pos = `</` |
| 47 | `element nesting too deep` | depth would exceed 256; pos = `<` |
| 48 | `multiple root elements` | a second root start; pos = `<` |
| 49 | `text before root element` | non-whitespace text at depth 0 before the root; pos = run start |
| 50 | `junk after root element` | non-whitespace text at depth 0 after the root; pos = run start |
| 51 | `unclosed element` | end of document with a non-empty stack; pos = outermost unclosed start |
| 52 | `no root element` | end of document with no root start; pos = end of text |

`expat_open` can only report catalog entries 1-4 (encoding-level). Messages in
rows 2, 7 and 35 are defensive branches that the public API cannot reach:
XIOM `Str` cannot carry a NUL byte, a declaration is parsed only once at
offset 0, and the dispatcher already guarantees a name-start byte before
entering the start-tag parser. All other messages are reachable and covered by
the suite.

## 7. Test matrix

`tests/test_conformance.xi` (module `expat_tests`) runs 25 named checks, one
`fn` per check, through `assert(cond, "name")`; `main` returns the failure
count (0 = green). Every comparison uses `str_compare` (BUG 17) and raw bytes
are built with `Vec[UInt8]`.

| # | Check | Pins |
|---|---|---|
| t1 | start/text/end events | names, two quote styles, offsets, line/column, consumed, attribute reads (decisions 5, 9, 10) |
| t2 | empty elements, depths, text_content | start+end pair for `<a/>`, consumed 0, aggregation (decision 11, section 4) |
| t3 | XML declaration | version/encoding/standalone recorded, offsets (decision 1) |
| t4 | Latin-1 fallback | declared `ISO-8859-1`, `0xE9` -> `U+00E9` (section 1.3) |
| t5 | UTF-8 BOM | detected, stripped, offsets are BOM-stripped (section 1.1) |
| t6 | UTF-16 BOMs | detected and rejected with distinct messages (section 1.2) |
| t7 | comments | raw body, `--` rejection, empty comment (decision 6) |
| t8 | PIs | target/data, reserved `xml` target (decision 7) |
| t9 | CDATA | raw body, no expansion, text_content (decision 8) |
| t10 | DOCTYPE | name, SYSTEM/PUBLIC, raw subset, duplicate/order errors (decision 2) |
| t11 | entities | values, chains, unknown/malformed/recursive/reserved/parameter/duplicate (decision 3) |
| t12 | references | predefined, decimal/hex, in text and attributes, bad refs (decision 3) |
| t13 | attributes | normalization, quote flags, duplicates, missing `=`/quotes, raw `<` (decision 5) |
| t14 | well-formedness | mismatch, unclosed, no/junk root, whitespace tail (decisions 9, 10) |
| t15 | invalid markup | `<` variants, `]]>` in text (decisions 9, 10) |
| t16 | malformed input | bad UTF-8 shapes and raw controls (section 1.4) |
| t17 | names/prefixes | non-ASCII pass-through, `ns:tag`, prefix/local split, name errors (decision 4) |
| t18 | declaration errors | order, shapes, unsupported encodings, placement (decision 1) |
| t19 | one-shot helpers | element index, attribute extraction, text content, out-of-range reads (section 4) |
| t20 | streaming | `expat_open` + `expat_next_event`, `Ok(-1)` idempotence (section 4) |
| t21 | mixed content | text_content across elements/CDATA/comments/PIs (section 4) |
| t22 | subset scan | non-ENTITY declarations skipped, entity in attribute (decision 2) |
| t23 | positions | whitespace runs, line/column across `\n` (section 1) |
| t24 | reference scope | no expansion in PI/comment/CDATA (decision 3) |
| t25 | expansion cap | 70000-byte payload rejected (decision 3) |

## 8. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the sibling ported packages):

- Free functions only; the event stream and every table are parallel `Vec`
  fields (`Vec[StructType]` is unsupported).
- The parser cursor lives in `ExpatState`: scanners are pure
  `(text, pos) -> Result[Int, Str]` functions because `&mut Int`
  out-parameters miscompile; only `&mut ExpatState` / `&mut Vec[UInt8]` are
  passed by reference (with explicit `&mut` at every call site).
- `Ok`/`Err` are constructed only in the leaf helpers
  `_ok_int`/`_err_int`, `_ok_str`/`_err_str`, `_ok_state`/`_err_state`.
- `Str` values read from `Vec[Str]` elements are compared with
  `str_compare` (BUG 17) and bound to typed locals first; `Vec[Int]` reads do
  the same.
- Byte comparisons widen and mask once (`(string.byte_at.. as Int) & 0xFF`),
  so all scanner constants are plain `Int` and sign-safe for bytes >= 128.
- Event emission is centralized in `_emit_event`, which pushes every parallel
  event vector together (they cannot drift).
- `expat_text_content` counts relative open depth from 0 (a plain
  `d > base` scheme misclassifies empty children, which close back to the base
  depth immediately).
- Output buffers are materialized with `Str::from_utf8` /
  `builder.sb_to_str`; NUL can never reach them (character references reject
  U+0000, and `Str` itself is NUL-terminated).
