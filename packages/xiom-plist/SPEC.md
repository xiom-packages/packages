# xiom.plist -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.plist`, version `0.1.0`).
Module: `src/plist.xi` (`module xiom.plist`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`, `xiom.convert`).

## 1. Scope

A pure-XIOM (no FFI) codec for the XML form of Apple property lists, for the
documented subset below:

- `plist_parse` builds a flat node model (`PlistDoc`) from a whole `Str`,
  skipping the optional `<?xml ... ?>` declaration and `<!DOCTYPE ...>`
  prolog and skipping comments / processing instructions between elements;
- values: `<dict>` (alternating `<key>` then a value), `<array>`, `<string>`,
  `<integer>`, `<real>`, `<true/>`, `<false/>`, `<data>`, `<date>`;
- entity decoding for text and attribute values: `&amp; &lt; &gt; &quot;
  &apos;`, `&#NN;` and `&#xNN;` / `&#XNN;` (strict: an unknown or malformed
  reference is an error);
- accessors: root/kind/parent/text, dict count/key/get, array count/get,
  typed scalar getters;
- `plist_emit` writes a canonical document back with deterministic tab
  indentation; parse -> emit -> parse is stable;
- a deterministic `Err("plist: ...")` catalog for malformed input.

## 2. Non-goals

- Binary plists (`bplist00`), OpenStep/NeXTSTEP plists, GNUstep extensions.
- NSKeyedArchiver / `$archiver` / `$objects` semantics.
- Full XML: namespaces and prefixes, CDATA, entity declarations, DTD
  internal subsets, attribute types, `xml:space` / `xml:lang`, BOM and
  UTF-16 input, Unicode normalization.
- Preserving comments or processing instructions (they are skipped).
- Decoding `<data>` base64 to bytes, converting `<real>` to `Float64`, or
  converting `<date>` to a timestamp.
- Streaming / SAX-style callbacks, file I/O, or registry integration.
- Duplicate-key detection (duplicates are accepted; lookup returns the
  first entry).
- Recursion depth limiting (deeply nested documents recurse).

## 3. Supported grammar

Informal EBNF over bytes; `WS` is space, tab, CR or LF:

```
document = prolog? "<plist" version ">" WS? value WS? "</plist>" trailing? EOF
prolog   = ( WS | comment | pi | doctype )*
comment  = "<!--" ... "-->"                       (non-nested, skipped)
pi       = "<?" ... "?>"                          (skipped)
doctype  = "<!DOCTYPE" ... ">"                    (first '>' ends it)
version  = WS "version" WS? "=" WS? ( '"1.0"' | "'1.0'" )
value    = dict | array | string | integer | real | true | false | data | date
dict     = "<dict/>" | "<dict>" ( WS? key WS? value )* WS? "</dict>"
key      = "<key/>" | "<key>" text "</key>"
array    = "<array/>" | "<array>" ( WS? value )* WS? "</array>"
string   = "<string/>" | "<string>" text "</string>"
integer  = "<integer>" text "</integer>"
real     = "<real>" text "</real>"
data     = "<data/>" | "<data>" text "</data>"
date     = "<date>" text "</date>"
true     = "<true/>"
false    = "<false/>"
text     = *( [^<&] | entity ), terminated by the matching end tag
entity   = "&amp;" | "&lt;" | "&gt;" | "&quot;" | "&apos;"
         | "&#" 1*digit ";" | "&#x" 1*hexdigit ";" | "&#X" 1*hexdigit ";"
trailing = WS | comment | pi | doctype
```

Decisions (each covered by the conformance suite):

1. **Prolog.** The declaration and DOCTYPE are skipped wherever `misc` is
   accepted (`_skip_misc`). A DOCTYPE ends at the first `>`; internal
   subsets are therefore not supported. An unclosed comment, PI or DOCTYPE
   is `plist: premature EOF`.
2. **Root.** The only accepted top-level element is `<plist>`. `version` is
   required, must be quoted, must be named `version`, and must equal `1.0`;
   other attributes are rejected. Self-closing `<plist/>` has no value.
3. **Whitespace.** ASCII whitespace (space, tab, CR, LF) is insignificant
   between elements and inside tags (around `=` and before `>`), but it is
   never stripped from `<string>` text (which is preserved byte-exact).
4. **Tags.** Tag names must start with an ASCII letter and end at
   whitespace, `=`, `/`, `>` or `<`. Closing tags must match the open
   element exactly and may have trailing whitespace before `>`.
5. **Self-closing forms.** `<dict/>`, `<array/>`, `<string/>`, `<data/>` are
   valid zero-length values. `<key/>` is a valid empty key. `<integer/>`,
   `<real/>` and `<date/>` fail their token validation. `<true>` and
   `<false>` must be written self-closing (`<true></true>` is
   `plist: malformed tag`).
6. **Dicts.** Entries are key/value pairs; a value without a key, a key
   without a value, two consecutive keys, and `</dict>` where a value is
   expected are all `plist: odd dict element count`. A `<key>` element in
   any other position (root value, array item, ...) is
   `plist: key outside dict`. Duplicate keys are accepted and
   `plist_dict_get` returns the first match.
7. **Arrays.** Items are value elements; non-whitespace text between items
   is an error.
8. **Text.** Raw text is legal only inside text leaf elements
   (`string`/`integer`/`real`/`data`/`date`/`key`). Anywhere else it is
   `plist: text outside elements`. Text runs end at the next `<`, so a
   comment inside a string is not part of the text.
9. **Entities.** Strict decoding: `&`, `&name;` with an unknown name,
   missing `;`, `&#;`, `&#x;`, `&#0;` and code points above U+10FFFF are
   all `plist: bad entity`. Numeric references encode as UTF-8; raw NUL
   bytes are rejected (`plist: NUL byte in text`).
10. **Strings.** Stored verbatim after entity decoding (leading/trailing
    whitespace included). The emitter escapes `&`, `<` and `>`.
11. **Integers.** Optional `-`, then one or more ASCII digits; parsed to
    `Int` with 64-bit bounds checking (`-9223372036854775808` ..
    `9223372036854775807`); stored canonically via
    `xiom.convert.int_to_string`, so `007` reads back `7` and `-0` reads
    back `0`. `+5`, `1.0`, `1 2`, `0x10`, empty and out-of-range values are
    `plist: bad integer`.
12. **Reals.** Validated text tokens: optional `-`, digits, optional
    `.` + digits, optional `e`/`E` + optional sign + digits (e.g. `3.14`,
    `-2.5e10`, `1E-3`, `42`), stored trimmed and verbatim. `.5`, `1.`,
    `1e`, `+1.5`, `1.2.3` and interior whitespace are `plist: bad real`.
    No `Vec[Float64]` and no rounding.
13. **Data.** All ASCII whitespace is removed; the remaining bytes must be
    base64 alphabet bytes with any `=` forming a trailing run. The text is
    stored as-is (`AAECAw==`, also across multiple indented lines) and is
    never decoded; bad bytes or an interior `=` are `plist: bad data`.
14. **Dates.** Exactly `YYYY-MM-DDThh:mm:ssZ` with digit components, `T`
    and `Z` uppercase, and ranges month 1..12, day 1..31, hour 0..23,
    minute/second 0..59; stored trimmed and verbatim. Any other shape is
    `plist: bad date`.
15. **Document structure.** One root value exactly: none is
    `plist: missing root value`, a second one is
    `plist: multiple root values`; anything but whitespace/misc after
    `</plist>` is `plist: content after document root`.
16. **Encoding.** `Str` is an opaque UTF-8 byte buffer: scanning is
    byte-wise, multi-byte sequences pass through untouched, and the input
    is not UTF-8-validated.

## 4. Data model

```xi
pub type PlistDoc = {
  kinds: Vec[Int];          // PLIST_KIND_* per node; node 0 is PLIST_KIND_DOC
  texts: Vec[Str];          // scalar payload ("" for containers and node 0)
  keys: Vec[Str];           // dict key when the parent is a dict ("" otherwise)
  parents: Vec[Int];        // owning node (-1 only for node 0)
  child_starts: Vec[Int];   // node i owns children[start .. start + length)
  child_lengths: Vec[Int];
  children: Vec[Int];       // flat concatenation of every child list
}
```

Kind constants: `PLIST_KIND_DICT` 0, `PLIST_KIND_ARRAY` 1,
`PLIST_KIND_STRING` 2, `PLIST_KIND_INTEGER` 3, `PLIST_KIND_REAL` 4,
`PLIST_KIND_BOOL` 5, `PLIST_KIND_DATA` 6, `PLIST_KIND_DATE` 7,
`PLIST_KIND_DOC` 8 (node 0).

Invariants: `kinds`, `texts`, `keys`, `parents`, `child_starts` and
`child_lengths` all have the same length; every non-root node appears in
`children` exactly once; for each node `0 <= child_starts[i]` and
`child_starts[i] + child_lengths[i] <= children.len()`. Node 0 is the
synthetic document node with parent `-1`; the root value is its only child
(node 1 for every document produced by `plist_parse`). Children are stored
in document order, so a dict's children are its values (keys are carried in
`keys[]`), and array item order is preserved.

`Vec[StructType]` is not usable in this compiler, so the model is
deliberately flat with one index vector plus ranges instead of a tree of
structs.

## 5. API contract

```xi
pub fn plist_parse(text: Str) -> Result[PlistDoc, Str]
pub fn plist_emit(d: &PlistDoc) -> Str
pub fn plist_root(d: &PlistDoc) -> Int
pub fn plist_root_kind(d: &PlistDoc) -> Int
pub fn plist_node_count(d: &PlistDoc) -> Int
pub fn plist_kind(d: &PlistDoc, node: Int) -> Int
pub fn plist_parent(d: &PlistDoc, node: Int) -> Option[Int]
pub fn plist_text(d: &PlistDoc, node: Int) -> Str
pub fn plist_int_value(d: &PlistDoc, node: Int) -> Option[Int]
pub fn plist_bool_value(d: &PlistDoc, node: Int) -> Option[Bool]
pub fn plist_dict_count(d: &PlistDoc, node: Int) -> Int
pub fn plist_dict_key(d: &PlistDoc, node: Int, index: Int) -> Option[Str]
pub fn plist_dict_get(d: &PlistDoc, node: Int, key: Str) -> Option[Int]
pub fn plist_array_count(d: &PlistDoc, node: Int) -> Int
pub fn plist_array_get(d: &PlistDoc, node: Int, index: Int) -> Option[Int]
```

- `plist_parse`: `Ok(doc)` on success; `Err(msg)` for the first malformed
  construct, with `msg` from the catalog below.
- `plist_root`: `-1` for a document with no root value (only possible
  through a hand-built empty `PlistDoc`; `plist_parse` never returns one).
- `plist_kind`: `-1` when `node < 0` or out of range; `plist_text` returns
  `""` in the same cases (and for containers).
- `plist_parent`: `Some(parent)`, `Some(-1)` only for node 0, `None` out of
  range.
- `plist_int_value` / `plist_bool_value`: `Some` only for a node of that
  kind whose stored text is canonical (guaranteed after `plist_parse`);
  `None` otherwise.
- `plist_dict_get`: byte-exact key comparison (case-sensitive), first match
  wins (duplicates allowed); `None` for a non-dict node, an absent key or
  an out-of-range node.
- `plist_dict_key`: `Some(key)` for `0 <= index < plist_dict_count` (keys
  may be `""`); `None` otherwise.
- `plist_array_get`: `Some(item)` for `0 <= index < plist_array_count`;
  `None` otherwise.
- `plist_emit`: exact canonical output (declaration, Apple DOCTYPE,
  `<plist version="1.0">`, depth-first values with one tab per depth level,
  LF line endings, trailing newline, empty containers as `<dict/>` /
  `<array/>`, `&`/`<`/`>` escaped in string text and keys). Returns `""`
  when the document has no root value or its parallel vectors disagree.
- All accessors are total: they never panic and never index outside the
  vectors (the child ranges are checked before use).

Complexity: `plist_parse` is O(n) over the document bytes plus O(nodes) for
the child-range build; `plist_emit` is O(nodes + text bytes); scalar and
child-count accessors are O(1) (dict lookup is O(entries); integer getters
re-parse O(digits)).

## 6. Error string catalog

All errors are `Err("plist: ...")`, deterministic and reported at the first
failure.

| Error text | Trigger |
|---|---|
| `plist: premature EOF` | input ends inside a tag, in text, in a comment/PI/DOCTYPE, or before `</plist>` |
| `plist: malformed tag` | empty/non-letter tag name, junk before `>` in a close tag, `/` not followed by `>`, bare attribute name, `<` inside a tag, `<true>` / `<false>` not self-closing |
| `plist: unknown tag` | element not in the supported set, or a non-`plist` element at the document position |
| `plist: mismatched tag` | closing tag does not match the open element |
| `plist: key outside dict` | `<key>` used as a root value or an array item |
| `plist: odd dict element count` | value without key, key without value, consecutive keys, or `</dict>` where a value is expected |
| `plist: bad integer` | non-decimal/empty/out-of-64-bit-range integer token (including `<integer/>`) |
| `plist: bad real` | invalid real token (including `.5`, `1.`, `1e`, `+1.5`, `<real/>`) |
| `plist: bad data` | non-base64 byte, or `=` not forming a trailing run |
| `plist: bad date` | token not `YYYY-MM-DDThh:mm:ssZ` or out of range |
| `plist: bad entity` | unknown name, missing `;`, empty/hex-less numeric body, `&#0;`, code point > U+10FFFF |
| `plist: NUL byte in text` | raw 0x00 byte in text or an attribute value |
| `plist: unquoted attribute` | attribute value not in `"..."` or `'...'` |
| `plist: unknown attribute` | attribute other than `version` on `<plist>`, or a second attribute |
| `plist: missing version attribute` | `<plist>` with no attribute |
| `plist: unsupported version` | `version` present but not `1.0` |
| `plist: text outside elements` | non-whitespace text at document level or inside dict/array |
| `plist: missing root value` | `<plist .../>` or `<plist ...></plist>` |
| `plist: multiple root values` | a second value where `</plist>` is expected |
| `plist: content after document root` | non-whitespace, non-misc bytes after `</plist>` |

## 7. Test plan

`tests/test_conformance.xi` (`module plist_tests`, 22 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check, a summary line, and
returns the failure count). Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | root string + prolog | declaration/DOCTYPE skipped; node 0 kind; root, text, parent |
| t2 | dict | lookup, key order, count, missing key, non-dict node |
| t3 | nested array + empty dict | child ranges, array get bounds, parents |
| t4 | booleans | kinds, `plist_bool_value` true/false, text, wrong-kind None |
| t5 | integer boundaries | 0, `-42`, i64 max, i64 min, `007` -> `7`, `-0` -> `0` |
| t6 | bad integers | `12x`, empty, i64 max+1, i64 min-1, `+5`, `1.0`, `1 2`, `0x10`, `<integer/>` |
| t7 | reals | verbatim `3.14`, `-2.5e10`, `1E-3`, `42`; rejects `.5`, `1.`, `1e`, `+1.5`, `1.2.3`, empty, `1 2` |
| t8 | data | `AAECAw==`, multi-line body -> compact, `<data/>` -> "", rejects junk, `AA=A`, `%%%` |
| t9 | dates | verbatim valid token; rejects month 13/00, space separator, missing `Z`, hour 24, short month, empty |
| t10 | entities (valid) | named, `&#65;`, `&#x42;`, `&#X43;`, `&#233;` (>=128 -> 2 UTF-8 bytes) in text and keys |
| t11 | entities (bad) | unknown, bare `&`, `&#;`, `&#x;`, `&#0;`, `>&#x110000;`, `&#xZZ;`, missing `;`, `a & b` |
| t12 | mismatched tags | string vs array, nested dict, root, array close |
| t13 | unknown tags | root value, array item, dict element, top-level non-plist |
| t14 | key placement / parity | key outside dict; key-only, value-only, key/key, key/value/key dicts |
| t15 | premature EOF | empty, blank, tag cut, text cut, missing `</plist>`, unclosed comment, unclosed dict |
| t16 | text outside elements | before root, at plist level, inside array, after root value, between dict key and value |
| t17 | version attribute | unquoted, unknown, second attribute, missing, `2.0`; single quotes + spaces accepted |
| t18 | canonical emitter | exact output: header, tabs, key/value lines, escapes, empty forms |
| t19 | round-trip | `parse -> emit -> parse` emission-stable and node counts equal; values survive |
| t20 | out-of-range accessors | kind `-1`, text `""`, None getters, kind-strict getters |
| t21 | empty values / strict bool | `<array/>`, `<dict/>`, `<string/>`, `<data/>`, `<true></true>` rejected, both bool roots |
| t22 | document structure | missing root value (empty + self-closing plist), multiple roots, trailing tag/text |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Tests call `t1()` ... `t22()` directly (no `Vec[fn]`
dispatch).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.plist
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## 8. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.xml`
pure-parser idioms (byte-wise scanning with `xiom.string.byte_at`,
`Vec[UInt8]` accumulation with `xiom.string.builder.sb_to_str`,
`&mut` parser state) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is parallel homogeneous
  vectors plus one flat child index vector with ranges -- children are not
  contiguous in parse order, hence the counting-sort build in `_build_doc`.
- `Ok`/`Err` for `Result[PlistDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc` (constructing Results directly inside other
  functions miscompiles in this compiler). Token validators return
  `Result[Int, Str]` / `Result[Str, Str]` directly.
- Str equality between `Vec[Str]` elements goes through `str_compare`
  (BUG 17); every element read is bound to a typed local, and
  `Vec[Int]` element reads are bound before comparison.
- `UInt8` widening masks the byte (`(b as Int) & 0xFF`) before arithmetic,
  including constants >= 128.
- The parser mirrors all four parallel node vectors on every push
  (`_push_node`); accessors and the emitter check the child ranges first.
- Tests dispatch directly (`t1()` ... `t22()`); `Vec[fn]` indexed calls are
  not used, and match patterns bind no `mut`.
- `<real>` stays a text token because `Vec[Float64]` is unsupported; there
  is no rounding anywhere in the module.

## 9. Known limitations

- No binary/OpenStep plists, no NSKeyedArchiver semantics.
- No namespaces, CDATA, DTD internal subsets, `xml:space`, BOM/UTF-16
  handling or input UTF-8 validation; comments/PIs are skipped, not
  preserved, and cannot appear inside text leaves.
- Duplicate dict keys are accepted (first match wins); no depth limit.
- Real values are unvalidated beyond the token shape (no range/NaN checks);
  base64 is validated by alphabet and trailing padding only and is not
  decoded; dates accept day 31 in every month.
- One root value; no file I/O, streaming or registry integration.
