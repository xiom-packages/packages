# xiom.gpx -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.gpx` (`src/gpx.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free GPX 1.1 **subset** codec for in-memory `Str`
documents. It parses the documented subset into a flat `GpxDoc`, exposes
accessors for the tree and its child text elements, and serializes documents
back to canonical GPX text:

- `gpx_parse` -- document -> `Result[GpxDoc, Str]`,
- `gpx_build` -- document -> canonical `Str`,
- `gpx_new` / `gpx_add_*` / `gpx_set_field` -- from-scratch construction,
- `gpx_node_count` / `gpx_kind` / `gpx_parent` / `gpx_children` /
  `gpx_nodes_of_kind` -- structure access,
- `gpx_version` / `gpx_creator` -- root attributes,
- `gpx_lat_udeg` / `gpx_lon_udeg` -- coordinates in microdegrees,
- `gpx_field` / `gpx_has_field` / `gpx_field_count` -- child text elements,
- `gpx_coord_parse` / `gpx_coord_text` -- coordinate literal helpers.

Coordinates are fixed-point integer microdegrees (1e-6 degree); the module
never uses `Float64` and never performs geo math.

## 2. Non-goals

- Full XML: namespaces, CDATA, comments, DOCTYPE/DTD, processing instructions
  other than a leading `<?xml ...?>`, character encoding conversion.
- Full GPX: `<rtept>` route points, `<extensions>`, `<link>`, `<src>`,
  `<cmt>`, `<fix>`, `<sat>`, `<hdop>`/`<vdop>`/`<pdop>`, schema validation,
  GPX 1.0 compatibility rules.
- Geo math (distances, projections, elevation handling) and file I/O.
- A nested object model (`Vec[StructType]` trees); the document is flat.
- Rich error positions (line/column); errors carry the offending name or text
  where useful.
- Any FFI.

## 3. Supported grammar

```
document      = ws* [ declaration ] ws* element ws* EOF
declaration   = "<?xml" ( ws | "?" ) *any-byte-until "?>"
element       = start-tag content end-tag | empty-element
start-tag     = "<" name attribute* ws* ">"
empty-element = "<" name attribute* ws* "/>"
end-tag       = "</" name ws* ">"
attribute     = ws+ name ws* "=" ws* quoted
quoted        = '"' *any-byte-except-'"'-and-"<" '"'
              | "'" *any-byte-except-"'"-and-"<" "'"
name          = 1*( byte except ws / "<" / ">" / "/" / "=" )
content       = *( ws | element | text )
ws            = SP | TAB | CR | LF
```

Element set: `gpx`, `wpt`, `rte`, `trk`, `trkseg`, `trkpt`, `name`, `desc`,
`sym`, `type`, `ele`, `time`. The placement tree is:

```
gpx    -> wpt | rte | trk
wpt    -> name | desc | sym | type | ele | time
rte    -> name | desc | sym | type | ele | time
trk    -> name | desc | sym | type | ele | time | trkseg
trkseg -> trkpt
trkpt  -> name | desc | sym | type | ele | time
```

The child elements `name`..`time` are leaves: they hold at most one text run
and never contain elements. Routes in this subset carry metadata only;
`<rtept>` is an unknown element.

## 4. Semantics and decisions

Each decision is covered by the conformance suite (`section 9`).

1. **Declaration.** A leading `<?xml ...?>` is skipped verbatim; it is not
   validated beyond the `<?xml` prefix (followed by whitespace or `?`) and the
   presence of a closing `?>`. A document may omit it. Any other leading
   `<?...` is `Err("gpx: malformed declaration")`; any `<?` or `<!` after the
   document start is `Err("gpx: unsupported markup")`. Comments are therefore
   not supported.
2. **Root.** The first element must be `<gpx>`; otherwise
   `Err("gpx: wrong root element: <name>")`. A second top-level element is
   `Err("gpx: multiple root elements")`. Text outside elements must be
   whitespace, else `Err("gpx: text outside elements")`.
3. **Elements.** Names outside the element set are
   `Err("gpx: unknown element: <name>")`; known elements in the wrong place
   are `Err("gpx: element not allowed here: <name>")`.
4. **Attributes.** Values must be quoted with `"` or `'`; an unquoted value is
   `Err("gpx: unquoted attribute value: <name>")`, a missing `=` or a raw `<`
   in a value is `Err("gpx: malformed attribute")`. `<gpx>` accepts optional
   `version` and `creator` (stored as `""` when absent; entities decoded);
   `<wpt>` and `<trkpt>` require both `lat` and `lon`. Any other attribute,
   including attributes on `rte`, `trk`, `trkseg` or leaf elements, is
   `Err("gpx: unexpected attribute: <name>")`; a repeated attribute is
   `Err("gpx: duplicate attribute: <name>")`.
5. **Coordinates.** A coordinate literal is an optional `+`/`-`, one or more
   ASCII digits, and an optional `.`-fraction with at least one digit;
   whitespace, exponents, lone signs and two dots are malformed
   (`Err("gpx: malformed latitude/longitude: <text>")`). The value is scaled
   to microdegrees; fraction digits beyond the sixth are rounded half away
   from zero. Latitude must be in [-90, 90] and longitude in [-180, 180]
   (`Err("gpx: latitude/longitude out of range: <text>")`); an integer part
   longer than six digits is out of range. Both bounds are accepted.
   `gpx_coord_parse` applies the widest range (-180..180) and returns `None`
   for malformed or out-of-range text; `gpx_coord_text` emits the shortest
   exact form with at least one fraction digit and never a negative zero.
6. **Child elements.** At most one field of each kind per parent node; a
   second one is `Err("gpx: duplicate element: <name>")`. Leaf text is
   preserved byte-for-byte including surrounding whitespace; an empty or
   self-closing leaf yields `Some("")` (presence is kept, content is empty).
   Non-leaf elements must contain only whitespace and allowed children; other
   text is `Err("gpx: unexpected text in <name>")`.
7. **Entities.** `&amp;` `&lt;` `&gt;` `&quot;` `&apos;`, decimal `&#NN;` and
   hexadecimal `&#xHH;` are decoded in text and attribute values. An unknown
   name, an empty or non-numeric body, trailing junk, `&#0;`, surrogates
   (U+D800..U+DFFF) and values above U+10FFFF are
   `Err("gpx: bad entity: &<body>;")`; a reference without a terminating `;`
   is `Err("gpx: unterminated entity")`. Numeric references are encoded to
   UTF-8.
8. **Closing tags.** A closing tag must match the open element:
   `Err("gpx: mismatched closing tag: expected </a>, found </b>")`; a closing
   tag with nothing open is `Err("gpx: unexpected closing tag: </a>")`.
   Attributes are not allowed on closing tags and tags must be well formed
   (`Err("gpx: malformed tag")`).
9. **End of input.** EOF inside a tag, attribute or open element, or a
   document with no root, is `Err("gpx: premature end of input")`.
10. **Errors.** Parsing stops at the first problem and returns
    `Err("gpx: ...")`; messages are deterministic and include the offending
    name or literal where listed above.
11. **Canonical serialization.** `gpx_build` emits the declaration line
    `<?xml version="1.0" encoding="UTF-8"?>`, then the tree with two-space
    indentation per depth, double-quoted attributes, escaped text, a trailing
    newline, and self-closed empty elements. Field elements are emitted before
    child elements, in kind order name, desc, sym, type, ele, time. Node order
    follows the document's node order. Text escapes `&`, `<` and `>`; attribute
    values additionally escape `"`. `gpx_build` of a document with no root node
    returns `""`.
12. **Encoding.** Scanning is byte-wise; non-ASCII bytes pass through
    unchanged (only numeric entities are transcoded), so UTF-8 content
    round-trips byte-exactly.

## 5. Data model

```xi
pub type GpxDoc = {
  kinds: Vec[Int];         // node kind: 0 gpx 1 wpt 2 rte 3 trk 4 trkseg 5 trkpt
  parents: Vec[Int];       // parent node index (-1 for the root)
  lat_udeg: Vec[Int];      // latitude in microdegrees (wpt/trkpt; 0 elsewhere)
  lon_udeg: Vec[Int];      // longitude in microdegrees (wpt/trkpt; 0 elsewhere)
  field_owners: Vec[Int];  // field association list: owning node
  field_kinds: Vec[Int];   // 0 name 1 desc 2 sym 3 type 4 ele 5 time
  field_values: Vec[Str];  // entity-decoded field text
  version: Str;            // <gpx version="...">, "" when absent
  creator: Str;            // <gpx creator="...">, "" when absent
}
```

Invariants:

- node 0 exists and has kind 0 and `parents[0] == -1`; every other node has a
  parent index `>= 0` smaller than its own index (preorder layout);
- `kinds`, `parents`, `lat_udeg` and `lon_udeg` always have the same length;
- `field_owners`, `field_kinds` and `field_values` always have the same
  length, and at most one field exists per `(owner, kind)` pair;
- a wpt/trkpt node always has both coordinates within range; other nodes store
  0/0;
- the accessors in section 6 are safe for any index.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat instead of a tree of structs.

## 6. API signatures

```xi
pub fn gpx_parse(text: Str) -> Result[GpxDoc, Str]
pub fn gpx_build(d: &GpxDoc) -> Str
pub fn gpx_new(version: Str, creator: Str) -> GpxDoc
pub fn gpx_add_waypoint(d: &mut GpxDoc, lat_udeg: Int, lon_udeg: Int) -> Int
pub fn gpx_add_route(d: &mut GpxDoc) -> Int
pub fn gpx_add_track(d: &mut GpxDoc) -> Int
pub fn gpx_add_segment(d: &mut GpxDoc, track: Int) -> Int
pub fn gpx_add_trackpoint(d: &mut GpxDoc, segment: Int, lat_udeg: Int, lon_udeg: Int) -> Int
pub fn gpx_set_field(d: &mut GpxDoc, node: Int, field: Int, value: Str) -> Bool
pub fn gpx_node_count(d: &GpxDoc) -> Int
pub fn gpx_kind(d: &GpxDoc, node: Int) -> Int
pub fn gpx_parent(d: &GpxDoc, node: Int) -> Int
pub fn gpx_version(d: &GpxDoc) -> Str
pub fn gpx_creator(d: &GpxDoc) -> Str
pub fn gpx_lat_udeg(d: &GpxDoc, node: Int) -> Option[Int]
pub fn gpx_lon_udeg(d: &GpxDoc, node: Int) -> Option[Int]
pub fn gpx_field(d: &GpxDoc, node: Int, field: Int) -> Option[Str]
pub fn gpx_has_field(d: &GpxDoc, node: Int, field: Int) -> Bool
pub fn gpx_field_count(d: &GpxDoc, node: Int) -> Int
pub fn gpx_nodes_of_kind(d: &GpxDoc, kind: Int) -> Vec[Int]
pub fn gpx_children(d: &GpxDoc, node: Int) -> Vec[Int]
pub fn gpx_coord_parse(text: Str) -> Option[Int]
pub fn gpx_coord_text(udeg: Int) -> Str
```

Complexity: parsing, building and the coordinate helpers are
O(input length) / O(nodes + fields + text bytes); `gpx_field`, `gpx_children`
and `gpx_nodes_of_kind` scan the flat vectors, so they are O(nodes) or
O(fields) per call.

Builder return values: `-1` from an `add_*` function means an invalid parent
node or an out-of-range coordinate; `false` from `gpx_set_field` means an
invalid node or field kind; neither panics nor mutates on failure.
`gpx_set_field` replaces the value when the field already exists.

## 7. Error catalog

Every parse failure is `Err(msg)` with `msg` starting with `"gpx: "`:

| Message | Trigger |
|---|---|
| `gpx: malformed declaration` | leading `<?...` that is not `<?xml` + ws/`?`, or no `?>` |
| `gpx: unsupported markup` | `<?` or `<!` after the document start (comments, DOCTYPE/PI) |
| `gpx: unknown element: <name>` | element outside the supported set (including `<rtept>` and prefixed names) |
| `gpx: wrong root element: <name>` | first element is not `<gpx>` |
| `gpx: multiple root elements` | a second top-level element |
| `gpx: element not allowed here: <name>` | known element in the wrong container |
| `gpx: duplicate element: <name>` | two child text elements of the same kind on one parent |
| `gpx: unexpected attribute: <name>` | attribute not allowed on that element |
| `gpx: duplicate attribute: <name>` | repeated `version`/`creator`/`lat`/`lon` |
| `gpx: unquoted attribute value: <name>` | value not starting with `"` or `'` |
| `gpx: malformed attribute` | missing `=`, empty attribute name or raw `<` in a value |
| `gpx: malformed tag` | stray `<`, empty tag name or junk before `>` |
| `gpx: missing latitude attribute` | wpt/trkpt without `lat` |
| `gpx: missing longitude attribute` | wpt/trkpt without `lon` |
| `gpx: malformed latitude: <text>` | latitude not a decimal-degree literal |
| `gpx: malformed longitude: <text>` | longitude not a decimal-degree literal |
| `gpx: latitude out of range: <text>` | scaled latitude outside [-90, 90] |
| `gpx: longitude out of range: <text>` | scaled longitude outside [-180, 180] |
| `gpx: bad entity: &<body>;` | unknown name, malformed numeric body, NUL, surrogate or > U+10FFFF |
| `gpx: unterminated entity` | `&` without a terminating `;` |
| `gpx: mismatched closing tag: expected </a>, found </b>` | closing tag does not match the open element |
| `gpx: unexpected closing tag: </a>` | closing tag with no open element |
| `gpx: unexpected text in <name>` | non-whitespace text in a container element |
| `gpx: text outside elements` | non-whitespace text at document level |
| `gpx: premature end of input` | EOF inside a tag/attribute/root or missing root |

## 8. Canonical output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="demo">
  <wpt lat="37.5" lon="-122.4">
    <name>Start &amp; Go</name>
    <ele>12.5</ele>
  </wpt>
  <rte>
    <name>R1</name>
  </rte>
  <trk>
    <name>T1</name>
    <trkseg>
      <trkpt lat="0.0" lon="0.0"/>
      <trkpt lat="-90.0" lon="180.0">
        <time>2026-01-01T00:00:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
```

Rules: `version`/`creator` are always emitted (possibly empty); coordinates
use the shortest exact microdegree text; field order is name, desc, sym, type,
ele, time; empty elements self-close; the file ends with a newline.
`gpx_build(gpx_parse(x))` is the canonicalization of `x`, and re-parsing that
output reproduces the same document (`same_doc` in the test suite).

## 9. Test plan

`tests/test_conformance.xi` (module `gpx_tests`) runs 29 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | root with version/creator | node 0 is gpx, parent -1, attributes, no fields |
| t2 | waypoint | coordinates, name, presence/count queries, children, `nodes_of_kind` |
| t3 | coordinate boundaries | ±90 / ±180 accepted, 7th digit rounding, leading `+` |
| t4 | coordinate helpers | text formatting, parse/none for malformed and out-of-range |
| t5 | entities | five predefined, decimal/hex numeric, UTF-8 encoding, re-escape, re-parse |
| t6 | route metadata | rte kind, name/desc/sym/type fields, absent ele, no coordinates |
| t7 | track structure | trk/trkseg/trkpt parents, two segments, point fields, empty segment |
| t8 | empty elements | self-closed wpt/trkseg/name, `Some("")` for empty leaf |
| t9 | declaration/whitespace | leading PI, multiline start tag, single quotes, text kept verbatim |
| t10 | build waypoint | canonical output and text/attribute escaping |
| t11 | field order | name, ele, time emitted in kind order regardless of set order |
| t12 | build track | nested indentation, self-closed empty segment, returned indices |
| t13 | builder validation | `-1`/`false` on invalid parents, ranges and fields; replace semantics |
| t14 | accessor bounds | `-1`/`-2`/`None`/empty for out-of-range indices |
| t15 | canonical round-trip | exact canonical text and build idempotence |
| t16 | semantic round-trip | parse/build/parse equality via `same_doc` |
| t17 | closing tags | mismatched, unexpected, case-sensitive names |
| t18 | unknown elements | foreign name, prefixed name, `rtept` |
| t19 | placement | trkpt at top level, wpt in trk, nested trkseg, trk in wpt, field on gpx |
| t20 | attributes | unquoted value, malformed attribute, unexpected attribute, wrong root |
| t21 | lat/lon requirements | missing lat/lon, duplicate attributes, unexpected coordinate attr |
| t22 | coordinate ranges | lat ±90.000001, lon ±180.000001, 7-digit integer part |
| t23 | malformed coordinates | letters, exponent, empty, `1.`, `.5`, spaces, `--1` |
| t24 | entities errors | unknown, `&#;`, `&#0;`, `&#x110000;`, surrogate, unterminated, in attributes |
| t25 | premature EOF | empty input, unclosed tag/attribute/element |
| t26 | text placement | outside elements, inside gpx/wpt, whitespace-only documents |
| t27 | duplicates/roots | duplicate field, multiple roots, comment, PI |
| t28 | declaration errors | unterminated declaration, `<?pi?>`, `<?xmlversion...`, declaration-only doc |
| t29 | build edge | empty version/creator attributes, rootless document -> `""` |

Element comparisons use `xiom.string.compare.str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.xml` /
`xiom.toml` pure-parser idioms (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`, `&mut` parser state) and documents these
compiler-driven choices:

- `Vec[StructType]` is unsupported, so `GpxDoc` is nine parallel fields and
  child elements are a flat `(owner, kind, value)` association list.
- `Ok`/`Err` for `Result[GpxDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare`, and Vec element reads bind typed locals
  first (`let x: Int = v[i];`, `let s: Str = v[j];`).
- `gpx_build` precomputes first-child/next-sibling links in O(nodes) and emits
  recursively (depth <= 4), so serialization is linear instead of rescanning
  parents per node.
- Tests dispatch directly (`t1()` ... `t29()`); no `Vec[fn]` indexed calls and
  no `mut` bindings in match patterns.

## 11. Known limitations

- The subset is closed: no `<rtept>`, `<link>`, `<extensions>`, comments,
  CDATA, namespaces, DOCTYPE or non-`xml` processing instructions.
- Coordinates cap at six decimal places (microdegrees); finer input is
  rounded half away from zero and precision beyond that is lost by design.
- `lat`/`lon` must be plain decimal literals: no exponent notation, no
  whitespace padding, no `+`/`-` other than the leading sign.
- Leaf text cannot span markup (one text run per leaf); entity references are
  the only way to embed `&` or `<` in text and the only way to embed `"` in an
  attribute value.
- Root `version`/`creator` are not required and not validated; GPX schema
  requirements are not enforced.
- Errors carry no line/column position.
- No file I/O, no streaming parser, no geo math.
