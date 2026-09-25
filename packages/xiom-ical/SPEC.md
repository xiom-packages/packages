# xiom.ical -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ical` (`src/ical.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for an RFC 5545 **subset** of iCalendar held in
memory as a `Str`. It provides four groups of operations:

- **Stream text**: `ical_unfold` (remove line folding), `ical_escape_text` and
  `ical_unescape_text` (TEXT value escaping).
- **Parsing**: `ical_parse` -- stream -> `Result[Ical, Str]`, building a flat
  component tree with properties and parameters.
- **Inspection**: component navigation (`ical_root*`, `ical_child*`,
  `ical_find_child`, `ical_component_*`), property access
  (`ical_prop_*`, `ical_find_prop`, `ical_get`, `ical_get_text`) and parameter
  access (`ical_prop_param_*`).
- **Building and writing**: `ical_new`, `ical_add_component`, `ical_add_prop`,
  `ical_add_text_prop`, `ical_build_event`, `ical_serialize`,
  `ical_serialize_folded`.

The codec reproduces text: values are never typed. It answers "what content
lines and components does this stream contain?" and "what does it look like as
text?" and nothing more.

## 2. Non-goals

- No RRULE/RDATE/EXDATE expansion and no recurrence sets.
- No VTIMEZONE processing and no TZID arithmetic; TZID is an opaque
  parameter value.
- No date/time parsing to epoch or to any numeric type; DATE, DATE-TIME,
  DURATION, PERIOD and UTC-OFFSET values stay `Str`.
- No calendar semantics: required/optional property validation, UID
  uniqueness, SEQUENCE/STATUS interpretation, METHOD handling, scheduling.
- No MIME/content transfer decoding (base64, quoted-printable) and no
  charset conversion; only TEXT backslash escapes are decoded.
- No RFC 6868 parameter caret-encoding, no parameter unquoting, no
  property-group syntax (`group.NAME`), no X-parameter interpretation.
- No streaming parser and no error line/column positions.
- No `Vec[StructType]` component-node tree; the model is deliberately flat
  (see section 4).
- Any FFI.

## 3. Supported grammar

```
stream       = *( contentline / blank )
contentline  = name *( ";" param ) ":" value
name         = 1*( ALPHA / DIGIT / "-" )
param        = param-name "=" param-value
param-name   = 1*( byte except ";" / ":" / "=" )
param-value  = *( byte except ";" / ":" ) / DQUOTE *( byte except DQUOTE ) DQUOTE
value        = *( byte except CR / LF )
blank        = *( SP / TAB )
line-break   = CRLF / LF / CR
unfolded     = remove( *( line-break ( SP / TAB ) ) )
```

Parsing decisions (each is covered by the conformance suite):

1. **Unfolding first.** `ical_parse` starts with `ical_unfold`: each line
   break immediately followed by one space or tab is removed together with
   that single whitespace byte. Remaining line breaks terminate lines.
2. **Line endings.** CRLF, LF and lone CR all terminate lines, in any mix.
   A final line without a terminator is still a line. Output always uses
   CRLF.
3. **Blank lines.** Empty and whitespace-only lines are skipped anywhere.
   A whitespace-only line that follows a break keeps all but one byte of its
   whitespace (the first byte was eaten as a fold), and is then skipped.
4. **Content-line split.** The structural `:` is the first colon outside a
   double-quoted parameter value. Everything before it is the name, followed
   by `;`-separated parameters; everything after it is the raw value. A line
   with no structural colon -- including one with an unbalanced `"` -- is
   malformed.
5. **Names.** Property, component and parameter names are ASCII
   `ALPHA / DIGIT / "-"` for properties and components; parameter names only
   have to be non-empty. All stored names are lowercased byte-wise; lookups
   are case-insensitive.
6. **Parameters.** `param-name=param-value`; the value is stored verbatim,
   so a quoted-string parameter keeps its double quotes. A quoted value may
   contain `;` and `:`. A parameter with no `=` (or an empty name) is
   malformed; parameter names are otherwise not validated (no character
   class). Parameters on `BEGIN`/`END` lines are ignored entirely -- not
   validated, not stored, not re-emitted -- because only BEGIN/END pairing
   matters for those lines.
7. **Components.** `BEGIN:NAME` opens a component nested in the currently
   open one (or at the top level), `END:NAME` closes it; names must match
   case-insensitively. Unpaired or mismatched ends, names that are not
   `ALPHA / DIGIT / "-"`, and end-of-input with an open component are
   `Err("ical: ...")`. Any component name is accepted; `VCALENDAR`,
   `VEVENT` and `VALARM` get no special treatment.
8. **Properties.** A content line that is not `BEGIN`/`END` before any
   `BEGIN` is `Err("ical: property outside component: <name>")`. A property
   belongs to the innermost open component; it is stored raw
   (escapes preserved) in document order. Duplicates are preserved.
9. **Lookups.** `ical_get` / `ical_find_prop` scan a component's **direct**
   properties in document order and return the first match; children are
   never searched. `ical_get_text` additionally decodes TEXT escapes.
10. **Escaping.** A TEXT value escapes `\` -> `\\`, `;` -> `\;`, `,` -> `\,`
    and LF -> `\n`; CR and CRLF are also written as `\n` (the CR is dropped).
    Unescaping decodes `\\`, `\;`, `\,`, `\n` and `\N`; an unknown escape
    (`\q`) or a trailing lone `\` is preserved byte-for-byte.
11. **Serialization order.** A component is written as `BEGIN:NAME`, its
    direct properties in document order, its children in component order,
    then `END:NAME`. Names and parameter names are uppercased, values and
    parameter values are written verbatim. Nothing is folded.
12. **Folding on output.** `ical_serialize_folded` folds a content line into
    chunks of at most 75 octets for the first physical line and 74 octets for
    each continuation (whose leading space counts toward the 75), inserting
    CRLF + one space. A boundary is moved back over UTF-8 continuation bytes
    (0x80..0xBF) so multi-byte sequences are never split; a pathological
    chunk that starts with a continuation byte advances by one byte to
    guarantee progress. `ical_unfold` of the folded output equals
    `ical_serialize`.
13. **Multiple roots.** A stream may contain several top-level components
    (for example a VTIMEZONE followed by a VCALENDAR); they are all kept.
14. **Empty input.** An empty or blank-only stream parses as an empty
    `Ical` and serializes back to `""`.

## 4. Data model

```xi
pub type Ical = {
  comp_names: Vec[Str];        // lowercased component names
  comp_parents: Vec[Int];      // parent index, -1 for top level
  prop_comps: Vec[Int];        // owning component of each property
  prop_names: Vec[Str];        // lowercased property names
  prop_values: Vec[Str];       // raw values (escapes preserved)
  prop_param_starts: Vec[Int]; // parameter slice start per property
  prop_param_lengths: Vec[Int];// parameter slice length per property
  param_names: Vec[Str];       // lowercased parameter names
  param_values: Vec[Str];      // verbatim parameter values
}
```

Invariants: `comp_names.len() == comp_parents.len()`; for every component
`i`, `comp_parents[i] < i` or `comp_parents[i] == -1` (parents always precede
children, so the tree is acyclic); `prop_comps[k]` is a valid component
index; the five property vectors are index-aligned; and for every property
`k`, `prop_param_starts[k] + prop_param_lengths[k] <= param_names.len()`.

`Vec[StructType]` is not usable in this compiler, so the tree is a set of
flat parallel vectors instead of a vector of component nodes. A property's
parameters are always contiguous in the shared pools because the only
parser or builder path that appends parameters appends them together with
their property.

## 5. API signatures

```xi
pub fn ical_parse(text: Str) -> Result[Ical, Str]
pub fn ical_unfold(text: Str) -> Str
pub fn ical_escape_text(s: Str) -> Str
pub fn ical_unescape_text(s: Str) -> Str

pub fn ical_component_count(c: &Ical) -> Int
pub fn ical_root_count(c: &Ical) -> Int
pub fn ical_root(c: &Ical, i: Int) -> Int
pub fn ical_component_name(c: &Ical, comp: Int) -> Str
pub fn ical_component_parent(c: &Ical, comp: Int) -> Int
pub fn ical_child_count(c: &Ical, comp: Int) -> Int
pub fn ical_child(c: &Ical, comp: Int, i: Int) -> Int
pub fn ical_find_child(c: &Ical, comp: Int, name: Str) -> Int

pub fn ical_prop_count(c: &Ical, comp: Int) -> Int
pub fn ical_prop_name(c: &Ical, comp: Int, i: Int) -> Str
pub fn ical_prop_value(c: &Ical, comp: Int, i: Int) -> Str
pub fn ical_prop_value_text(c: &Ical, comp: Int, i: Int) -> Str
pub fn ical_find_prop(c: &Ical, comp: Int, name: Str) -> Int
pub fn ical_get(c: &Ical, comp: Int, name: Str) -> Option[Str]
pub fn ical_get_text(c: &Ical, comp: Int, name: Str) -> Option[Str]
pub fn ical_prop_param_count(c: &Ical, comp: Int, i: Int) -> Int
pub fn ical_prop_param_name(c: &Ical, comp: Int, i: Int, j: Int) -> Str
pub fn ical_prop_param_value(c: &Ical, comp: Int, i: Int, j: Int) -> Str

pub fn ical_new() -> Ical
pub fn ical_add_component(c: &mut Ical, parent: Int, name: Str) -> Int
pub fn ical_add_prop(c: &mut Ical, comp: Int, name: Str, value: Str) -> Bool
pub fn ical_add_text_prop(c: &mut Ical, comp: Int, name: Str, text: Str) -> Bool
pub fn ical_build_event(uid: Str, dtstamp: Str, dtstart: Str, dtend: Str, summary: Str, description: Str, location: Str) -> Ical

pub fn ical_serialize(c: &Ical) -> Str
pub fn ical_serialize_folded(c: &Ical) -> Str
```

Complexity: parsing is O(total input length); serialization is O(output
length); every navigation and lookup operation scans the flat vectors and is
therefore O(components) or O(properties) with small constants.

Out-of-range behavior is total and documented: index getters return `-1`
(`ical_root`, `ical_child`, `ical_find_child`, `ical_find_prop`), an empty
string (name/value getters and `ical_component_name`), `-2`
(`ical_component_parent`), `0` (`ical_prop_param_count`), `None`
(`ical_get`, `ical_get_text`). `ical_add_component` returns `-1` and
`ical_add_prop`/`ical_add_text_prop` return `false` without mutating the
stream when their arguments are invalid.

## 6. Error strings

All parse failures are `Err(msg)` where `msg` starts with `"ical: "`:

| Message | Trigger |
|---|---|
| `ical: malformed content line: <line>` | a non-blank line with no structural `:` (including unbalanced quotes) |
| `ical: invalid property name: <name>` | name empty or not `ALPHA / DIGIT / "-"` |
| `ical: malformed parameter: <line>` | parameter segment without `=`, empty parameter name, or a trailing `;` before the `:` |
| `ical: unterminated quoted parameter: <line>` | defensive guard only; not reachable through `ical_parse`, because a quoted value that never closes hides the structural `:` and is reported as a malformed content line |
| `ical: invalid component name: <value>` | `BEGIN`/`END` value empty or not `ALPHA / DIGIT / "-"` |
| `ical: unexpected END: <value>` | `END` with no open component |
| `ical: END:<value> does not match BEGIN:<open>` | `END` name differs from the innermost open component |
| `ical: unterminated component: <name>` | end of input with the innermost component still open |
| `ical: property outside component: <name>` | content line before the first `BEGIN` |

Error messages embed raw input text (`<line>`, `<name>`, `<value>`) and carry
no line/column positions.

## 7. Test plan

`tests/test_conformance.xi` (module `ical_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | calendar parses | component count, roots, names, parents, children, property counts, raw values, out-of-range -1/-2/"" |
| t2 | case-insensitive lookup | lowercased storage, first-match wins, `None`/`-1` for absent, ordinal bounds |
| t3 | unfolding | space, tab, multi-line and double-space continuations; unfold preserves plain breaks |
| t4 | TEXT escapes | exact `\;` `\,` `\n` `\\` output and decode, `\N`, unknown escape kept, trailing `\` kept, CRLF -> `\n` |
| t5 | parameters | two parameters, names lowercased, values verbatim, quoted `":"`, out-of-range params |
| t6 | malformed lines | no colon, space in name, `_` in name, empty name |
| t7 | BEGIN/END pairing | unexpected END, mismatch message, unterminated component, case-insensitive close |
| t8 | outside component | property before any BEGIN; empty components |
| t9 | nesting and roots | VEVENT + VALARM + second VEVENT, child order, multiple roots, child lookup |
| t10 | round-trip | `ical_serialize(ical_parse(x))` equals canonical CRLF input byte-for-byte |
| t11 | folded output | lines <= 75 octets, more physical lines, unfolds to the plain form, reparses |
| t12 | build_event | VERSION/PRODID + seven VEVENT properties, escapes, parse-back of summary/description/dtstart |
| t13 | empty input | `""`, blank-only stream, `ical_new` serialize to `""` |
| t14 | line endings | LF-only, CR-only, mixed CRLF/LF, folded LF |
| t15 | raw vs text | `ical_get`/`ical_prop_value` keep escapes; `ical_get_text`/`ical_prop_value_text` decode |
| t16 | per-component lookup | child properties invisible to the parent and vice versa |
| t17 | parameter splitting | unquoted `;` terminators, quoted `p;q`, quoted TZID, unquoted DATE-TIME |
| t18 | bad parameters | missing `=`, empty name, unbalanced quote, trailing `;` |
| t19 | component names | invalid name, empty name, unterminated stream, no trailing newline |
| t20 | builder | serialize order, invalid name/parent rejected, CR/LF value rejected, text escaping, no partial mutation |
| t21 | fold boundaries | 75 octets stays one line, 76 folds, UTF-8 multi-byte not split, unfold/reparse identity |
| t22 | parameter round-trip | `ATTENDEE;CN="Doe: John";ROLE=...` survives parse -> serialize |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Backslash literals are assembled with a `bs()` helper so
no expectation depends on compiler escape corner cases.

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the just-landed
`xiom.eml` / `xiom.toml` pure-parser idioms (byte-wise scanning with
`xiom.string.byte_at` and `xiom.string.str_slice`, `Vec[UInt8]` accumulation
with `xiom.string.builder.sb_to_str`) and documents these compiler-driven
choices:

- `Vec[StructType]` is unsupported, so the component tree is a set of flat
  vectors with parent indices; the component vector is never nested.
- `Err(Str)` is constructed only by the leaf helpers `_ok_ical`/`_err_ical`;
  no `Ok`/`Err` is built inside a struct-returning function.
- Str equality between `Vec[Str]` elements goes through `str_compare`
  (BUG 17); every `Vec[Int]` element read is bound to a typed `Int` local.
- `_emit_comp` is recursive over the flat tree and appends bytes through a
  `&mut Vec[UInt8]` out-parameter, the pattern used by
  `xiom.collect.rbtree` walkers.
- Tests dispatch directly (`t1()` ... `t22()`); indexed `Vec[fn]` calls are
  not used, and match patterns bind no `mut`.

## 9. Known limitations

- No RFC 6868 caret encoding; parameter values keep their quotes and the
  module never decodes RFC 2231 continuations.
- Values are strings: no date/time/duration/period numeric interpretation.
- Blank-line and line-ending handling is more permissive than RFC 5545.
- A `:` inside an unquoted parameter value terminates the structural part of
  the line; quote the value to protect it.
- Unknown TEXT escapes are preserved rather than rejected; `\r` is not
  defined and is emitted as `\n` (the CR is dropped) by the escaper.
- The event builder emits parameter-free properties and assumes DATE-TIME
  arguments contain no CR/LF (violations are dropped, not escaped).
- No serializer for anything but the parsed/built model (no pretty printer,
  no property sorting) and no file I/O.
- Errors carry no line/column position.
