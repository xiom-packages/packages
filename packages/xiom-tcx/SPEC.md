# xiom.tcx -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.tcx` (`src/tcx.xi`). Pure XIOM, no FFI.
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`).

## 1. Scope

A small, dependency-free Garmin TCX (Training Center XML) **subset** codec
for in-memory `Str` documents. It parses the documented subset into a flat
`TcxDoc`, exposes accessors for activities, laps and trackpoints, and
serializes documents back to canonical TCX text:

- `tcx_parse` -- document -> `Result[TcxDoc, Str]`,
- `tcx_build` -- document -> canonical `Str`,
- `tcx_new` -- empty document,
- activity accessors: count, `Sport` attribute, `Id` text, lap count,
  owning-activity lookup,
- lap accessors: `StartTime`, `TotalTimeSeconds`, `DistanceMeters`,
  `MaximumSpeed`, `Calories`, `AverageHeartRateBpm`/`Value`, trackpoint count
  and Track presence,
- trackpoint accessors: `Time`, `LatitudeDegrees`, `LongitudeDegrees`,
  Position presence, `AltitudeMeters`, `DistanceMeters`,
  `HeartRateBpm`/`Value`, `Cadence`, `SensorState`, owning-lap lookup.

Numeric values are kept as **validated text tokens**, never as numbers:
`TotalTimeSeconds`, `DistanceMeters`, `MaximumSpeed`, `AltitudeMeters` and
the latitude/longitude degrees are validated decimal literals; `Calories`,
`Cadence` and the heart-rate `Value` are unsigned decimal integers;
`SensorState` is `Present` or `Absent`. The module never uses `Float64` or
`Vec[Float64]`, performs no unit conversion and no GPS math.

## 2. Non-goals

- Full XML: namespaces semantics, CDATA, comments, DOCTYPE/DTD, processing
  instructions other than a leading `<?xml ...?>`, character encoding
  conversion, BOM handling.
- Full TCX: `<Courses>`, `<Workouts>`, `<Extensions>`, `<Creator>`,
  `<Author>`, `<Training>`, `<Notes>`, activity-type payload elements
  (`<Biking>`, `<Running>`, ...), schema validation and TCX version rules.
- Unknown attributes (namespace declarations included) are accepted and
  ignored, not reproduced.
- Numeric semantics: no parsing to numbers, no ranges, no unit conversion,
  no arithmetic (including calories/heart-rate/cadence ranges).
- Timestamps (`Id`, `Time`, `StartTime`) are opaque text; no date parsing.
- A nested object model (`Vec[StructType]` trees); the document is flat.
- Rich error positions (line/column); errors carry the offending name or text
  where useful.
- File I/O, streaming parsing, and any FFI.

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

Element set and placement tree (each `->` line lists the allowed children;
`*` = one or more, `?` = zero or one):

```
TrainingCenterDatabase -> Activities
Activities             -> Activity*
Activity               -> Id, Lap*
Lap                    -> TotalTimeSeconds, DistanceMeters, MaximumSpeed?,
                          Calories, AverageHeartRateBpm?, Track?
AverageHeartRateBpm    -> Value
Track                  -> Trackpoint*
Trackpoint             -> Time, Position?, AltitudeMeters?, DistanceMeters?,
                          HeartRateBpm?, Cadence?, SensorState?
Position               -> LatitudeDegrees, LongitudeDegrees
HeartRateBpm           -> Value
```

Leaf elements hold at most one text run and never contain elements.
`DistanceMeters` appears under both `Lap` (required) and `Trackpoint`
(optional); `Value` appears under both `AverageHeartRateBpm` and
`HeartRateBpm` (both required). Both are stored per record.

## 4. Semantics and decisions

Each decision is covered by the conformance suite (section 9).

1. **Declaration.** A leading `<?xml ...?>` is skipped verbatim; it is not
   validated beyond the `<?xml` prefix (followed by whitespace or `?`) and the
   presence of a closing `?>`. A document may omit it. Any other leading
   `<?...` is `Err("tcx: malformed declaration")`; any `<?` or `<!` after the
   document start is `Err("tcx: unsupported markup")`. Comments are therefore
   not supported.
2. **Root.** The first element must be `<TrainingCenterDatabase>`; a known
   element in root position that is not the root is
   `Err("tcx: wrong root element: <name>")` (a name outside the subset is
   `Err("tcx: unknown element: <name>")` first). A second top-level element is
   `Err("tcx: multiple root elements")`. Text outside elements must be
   whitespace, else `Err("tcx: text outside elements")`. `<TrainingCenterDatabase>`
   requires exactly one `<Activities>`.
3. **Elements.** Names outside the element set are
   `Err("tcx: unknown element: <name>")`; known elements in the wrong place
   are `Err("tcx: element not allowed here: <name>")`.
4. **Attributes.** Values must be quoted with `"` or `'`; an unquoted value is
   `Err("tcx: unquoted attribute value: <name>")`, a missing `=` or a raw `<`
   in a value is `Err("tcx: malformed attribute")`. `<Activity>` requires a
   non-empty `Sport` attribute and `<Lap>` requires a non-empty `StartTime`
   attribute; absent is `Err("tcx: missing required attribute: <name>")` and
   present-but-empty is `Err("tcx: empty attribute: <name>")`. A repeated
   `Sport`/`StartTime` is `Err("tcx: duplicate attribute: <name>")`. Every
   other attribute on any element (including `xmlns` declarations) is
   accepted and ignored.
5. **Text and trimming.** Attribute values and leaf text are entity-decoded
   and then trimmed of leading/trailing XML whitespace; the trimmed token is
   stored verbatim (no case folding, no concatenation of multiple runs).
   Whitespace-only character data between elements is ignored; other text
   where elements are expected is `Err("tcx: unexpected text in <name>")`
   (containers) or `Err("tcx: text outside elements")` (document level).
6. **Numeric tokens.** A decimal token is an optional `+`/`-`, one or more
   ASCII digits, and an optional `.`-fraction with at least one digit
   (no exponent, no embedded whitespace, no lone `.`/sign). It is required
   for `TotalTimeSeconds`, `DistanceMeters`, `MaximumSpeed`, `AltitudeMeters`,
   `LatitudeDegrees` and `LongitudeDegrees`. An unsigned-integer token is one
   or more ASCII digits; it is required for `Calories`, `Cadence` and both
   `Value` elements. `SensorState` must be exactly `Present` or `Absent`.
   A present leaf whose trimmed text is empty is
   `Err("tcx: empty element: <name>")`; a non-empty invalid token is
   `Err("tcx: malformed <name>: <text>")`. Valid tokens are stored as text
   and emitted unchanged.
7. **Entities.** `&amp;` `&lt;` `&gt;` `&quot;` `&apos;`, decimal `&#NN;` and
   hexadecimal `&#xHH;` are decoded in text and attribute values. An unknown
   name, an empty or non-numeric body, trailing junk, `&#0;`, surrogates
   (U+D800..U+DFFF) and values above U+10FFFF are
   `Err("tcx: bad entity: &<body>;")`; a reference without a terminating `;`
   is `Err("tcx: unterminated entity")`. Numeric references are encoded to
   UTF-8.
8. **Closing tags.** A closing tag must match the open element:
   `Err("tcx: mismatched closing tag: expected </a>, found </b>")`; a closing
   tag with nothing open is `Err("tcx: unexpected closing tag: </a>")`.
   Attributes are not allowed on closing tags and tags must be well formed
   (`Err("tcx: malformed tag")`).
9. **Cardinality.** `TrainingCenterDatabase` requires one `Activities`;
   `Activities` requires at least one `Activity`; `Activity` requires one
   `Id` and at least one `Lap`; `Lap` requires `TotalTimeSeconds`,
   `DistanceMeters` and `Calories`; `Track` requires at least one
   `Trackpoint`; `Trackpoint` requires `Time`; `Position` requires both
   coordinates; `AverageHeartRateBpm`/`HeartRateBpm` require `Value`. A
   missing child is `Err("tcx: missing required element: <name>")`, checked
   when the parent ends (closing tag or self-close). A second
   single-instance child of one parent is `Err("tcx: duplicate element: <name>")`.
10. **End of input.** EOF inside a tag, attribute or open element, or a
    document with no root, is `Err("tcx: premature end of input")`.
11. **Errors.** Parsing stops at the first problem and returns
    `Err("tcx: ...")`; messages are deterministic and include the offending
    name or literal where listed above.
12. **Canonical serialization.** `tcx_build` emits the declaration line
    `<?xml version="1.0" encoding="UTF-8"?>`, then `TrainingCenterDatabase` >
    `Activities` > `Activity` > `Lap` > `Track` > `Trackpoint` with two-space
    indentation per depth, double-quoted attributes in fixed order (`Sport`,
    then `StartTime`), escaped text, a trailing newline, and optional
    elements omitted when empty. Children are emitted in the grammar order of
    section 3 (input order is not preserved for reordered fields).
    `tcx_build` of a document with no activities emits a self-closed
    `<Activities/>`; `tcx_build(tcx_parse(x))` is the canonicalization of `x`,
    and re-parsing that output reproduces the same document (`same_doc` in
    the test suite).
13. **Encoding.** Scanning is byte-wise; non-ASCII bytes pass through
    unchanged (only numeric entities are transcoded), so UTF-8 content
    round-trips byte-exactly.

## 5. Data model

```xi
pub type TcxDoc = {
  act_sport: Vec[Str];       // <Activity Sport="..."> text
  act_id: Vec[Str];          // <Id> text (required, non-empty)
  act_lap_start: Vec[Int];   // first lap index of each activity
  lap_start_time: Vec[Str];  // <Lap StartTime="..."> attribute
  lap_total_time: Vec[Str];  // <TotalTimeSeconds> token (required)
  lap_distance: Vec[Str];    // <DistanceMeters> token (required)
  lap_max_speed: Vec[Str];   // <MaximumSpeed> token ("" when absent)
  lap_calories: Vec[Str];    // <Calories> token (required)
  lap_avg_hr: Vec[Str];      // AverageHeartRateBpm/Value ("" when absent)
  lap_tp_start: Vec[Int];    // first trackpoint index of each lap
  tp_time: Vec[Str];         // <Time> text (required, non-empty)
  tp_lat: Vec[Str];          // LatitudeDegrees ("" when no Position)
  tp_lon: Vec[Str];          // LongitudeDegrees ("" when no Position)
  tp_alt: Vec[Str];          // AltitudeMeters ("" when absent)
  tp_distance: Vec[Str];     // Trackpoint DistanceMeters ("" when absent)
  tp_hr: Vec[Str];           // HeartRateBpm/Value ("" when absent)
  tp_cadence: Vec[Str];      // Cadence ("" when absent)
  tp_sensor: Vec[Str];       // SensorState ("" when absent)
}
```

Invariants:

- Activities are `0..act_sport.len()`; activity `a` owns the laps in
  `[act_lap_start[a], act_lap_start[a+1])`, and the last activity owns up to
  `lap_start_time.len()`. Lap `l` owns the trackpoints in
  `[lap_tp_start[l], lap_tp_start[l+1])`, the last lap up to `tp_time.len()`.
- Every per-activity push group (`act_sport`, `act_id`, `act_lap_start`),
  per-lap push group (six vectors plus `lap_tp_start`) and per-trackpoint
  push group (eight vectors) advances together, so the vectors cannot drift
  during parsing.
- `_lap_start`/`_lap_end`/`_tp_start`/`_tp_end` clamp every stored range to
  the vector lengths, and all accessors guard their indices, so hand-built
  documents cannot read out of bounds.
- Required text fields (`act_id`, `lap_total_time`, `lap_distance`,
  `lap_calories`, `tp_time`, both coordinates) are non-empty in any document
  returned by `tcx_parse`; optional fields use `""` as the absence marker.
- A Parsed Position always has both coordinates; the emitter omits a Position
  whose latitude or longitude is empty.

`Vec[StructType]` is not usable in this compiler, so the model is
deliberately flat instead of a tree of structs.

## 6. API signatures

```xi
pub type TcxDoc = { ... }
pub fn tcx_new() -> TcxDoc
pub fn tcx_parse(text: Str) -> Result[TcxDoc, Str]
pub fn tcx_build(d: &TcxDoc) -> Str
pub fn tcx_activity_count(d: &TcxDoc) -> Int
pub fn tcx_lap_count(d: &TcxDoc) -> Int
pub fn tcx_trackpoint_count(d: &TcxDoc) -> Int
pub fn tcx_activity_sport(d: &TcxDoc, a: Int) -> Str
pub fn tcx_activity_id(d: &TcxDoc, a: Int) -> Str
pub fn tcx_activity_lap_count(d: &TcxDoc, a: Int) -> Int
pub fn tcx_lap_activity(d: &TcxDoc, l: Int) -> Int
pub fn tcx_lap_start_time(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_total_time(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_distance(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_max_speed(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_calories(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_avg_hr(d: &TcxDoc, l: Int) -> Str
pub fn tcx_lap_trackpoint_count(d: &TcxDoc, l: Int) -> Int
pub fn tcx_lap_has_track(d: &TcxDoc, l: Int) -> Bool
pub fn tcx_trackpoint_lap(d: &TcxDoc, t: Int) -> Int
pub fn tcx_trackpoint_time(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_lat(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_lon(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_has_position(d: &TcxDoc, t: Int) -> Bool
pub fn tcx_trackpoint_alt(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_distance(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_hr(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_cadence(d: &TcxDoc, t: Int) -> Str
pub fn tcx_trackpoint_sensor(d: &TcxDoc, t: Int) -> Str
```

Complexity: parsing and building are O(input length) / O(records + tokens);
scalar accessors are O(1) except `tcx_lap_activity` and `tcx_trackpoint_lap`,
which scan the ranges (O(activities) / O(laps)).

Accessor conventions: out-of-range `Str` accessors return `""`;
`tcx_lap_activity`/`tcx_trackpoint_lap` return `-1`;
`tcx_activity_lap_count`/`tcx_lap_trackpoint_count` return `0`;
`tcx_lap_has_track`/`tcx_trackpoint_has_position` return `false`. None of
them panics.

## 7. Error catalog

Every parse failure is `Err(msg)` with `msg` starting with `"tcx: "`:

| Message | Trigger |
|---|---|
| `tcx: malformed declaration` | leading `<?...` that is not `<?xml` + ws/`?`, or no `?>` |
| `tcx: unsupported markup` | `<?` or `<!` after the document start (comments, DOCTYPE/PI) |
| `tcx: unknown element: <name>` | element outside the supported set |
| `tcx: wrong root element: <name>` | first element is a known element other than `<TrainingCenterDatabase>` |
| `tcx: multiple root elements` | a second top-level element |
| `tcx: element not allowed here: <name>` | known element in the wrong container |
| `tcx: duplicate element: <name>` | second single-instance child of one parent (`Id`, `TotalTimeSeconds`, `DistanceMeters`, `MaximumSpeed`, `Calories`, `AverageHeartRateBpm`, `Track`, `Time`, `Position`, `LatitudeDegrees`, `LongitudeDegrees`, `AltitudeMeters`, `HeartRateBpm`, `Value`, `Cadence`, `SensorState`, `Activities`) |
| `tcx: missing required element: <name>` | parent ended without `Activities`, `Activity`, `Id`, `Lap`, `TotalTimeSeconds`, `DistanceMeters`, `Calories`, `Trackpoint`, `Time`, `Position` coordinate or `Value` |
| `tcx: missing required attribute: <name>` | `Activity` without `Sport`, `Lap` without `StartTime` |
| `tcx: empty attribute: <name>` | `Sport=""` or `StartTime=""` (after trimming) |
| `tcx: empty element: <name>` | present leaf with empty trimmed text, including `<X/>` |
| `tcx: duplicate attribute: <name>` | repeated `Sport` or `StartTime` |
| `tcx: unquoted attribute value: <name>` | value not starting with `"` or `'` |
| `tcx: malformed attribute` | missing `=`, empty attribute name or raw `<` in a value |
| `tcx: malformed tag` | stray `<`, empty tag name, junk after `/` or a closing-tag name |
| `tcx: malformed <name>: <text>` | non-empty token failing its numeric/enum rule |
| `tcx: bad entity: &<body>;` | unknown name, malformed numeric body, NUL, surrogate or > U+10FFFF |
| `tcx: unterminated entity` | `&` without a terminating `;` |
| `tcx: mismatched closing tag: expected </a>, found </b>` | closing tag does not match the open element |
| `tcx: unexpected closing tag: </a>` | closing tag with no open element |
| `tcx: unexpected text in <name>` | non-whitespace text in a container element |
| `tcx: text outside elements` | non-whitespace text at document level |
| `tcx: premature end of input` | EOF inside a tag/attribute/root element or missing root |

## 8. Canonical output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase>
  <Activities>
    <Activity Sport="Running">
      <Id>2026-01-01T00:00:00Z</Id>
      <Lap StartTime="2026-01-01T00:00:00Z">
        <TotalTimeSeconds>2400.0</TotalTimeSeconds>
        <DistanceMeters>10000.0</DistanceMeters>
        <MaximumSpeed>5.5</MaximumSpeed>
        <Calories>700</Calories>
        <AverageHeartRateBpm>
          <Value>140</Value>
        </AverageHeartRateBpm>
        <Track>
          <Trackpoint>
            <Time>2026-01-01T00:00:01Z</Time>
            <Position>
              <LatitudeDegrees>37.5</LatitudeDegrees>
              <LongitudeDegrees>-122.4</LongitudeDegrees>
            </Position>
            <AltitudeMeters>12.5</AltitudeMeters>
            <DistanceMeters>1.0</DistanceMeters>
            <HeartRateBpm>
              <Value>141</Value>
            </HeartRateBpm>
            <Cadence>90</Cadence>
            <SensorState>Present</SensorState>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>
```

Rules: attribute order `Sport`, `StartTime`; child order as in section 3;
required tokens always emitted, optional elements only when non-empty;
`Position` only when both coordinates are non-empty; text escapes `&`, `<`
and `>`; attribute values additionally escape `"`; every element ends with a
LF; the file ends with a LF after `</TrainingCenterDatabase>`; ignored
attributes are dropped; numeric tokens are emitted exactly as stored.

## 9. Test plan

`tests/test_conformance.xi` (module `tcx_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full document model | counts, sport/Id, lap fields, trackpoint fields, ranges |
| t2 | canonical build | exact bytes of the full document, build stability |
| t3 | multi activity/lap/trackpoint | counts, owners and ranges of three laps / two activities |
| t4 | optional elements absent | `MaximumSpeed`/`AverageHeartRateBpm`/`Track` and tp optionals |
| t5 | valid tokens | signed/fraction decimals, integer `0`/`255`, `Absent`, trim |
| t6 | entities | five predefined, decimal/hex numeric, UTF-8, re-escape, round-trip |
| t7 | whitespace and quotes | declaration, single quotes, pretty-printing, trimming |
| t8 | canonical skeleton | `tcx_new` output, minimal document output |
| t9 | semantic round-trip | parse/build/parse equality via `same_doc` |
| t10 | accessor bounds | `""`/`-1`/`0`/`false` out of range |
| t11 | missing required elements | Id, Lap, Activity, Activities, Trackpoint, coordinates, Value |
| t12 | missing required tokens | `TotalTimeSeconds`, lap `DistanceMeters`, `Calories`, `Time` |
| t13 | attributes | missing/empty `Sport` and `StartTime` |
| t14 | placement | unknown, misplaced, leaves with children |
| t15 | closing tags | mismatched, unexpected, case-sensitive, junk after name |
| t16 | duplicates | `Id`, `TotalTimeSeconds`, `Track`, `Position`, `Value`, `Time` |
| t17 | malformed tokens | letters, exponent, two dots, `1.`, `12.5` integer, `-1`, enum |
| t18 | empty elements | `<Id/>`, empty/whitespace tokens, `<Value/>` |
| t19 | attribute syntax | unquoted, missing `=`, raw `<`, duplicate, ignored extra |
| t20 | entity errors | unknown, unterminated, `&#;`, `&#0;`, out of range, surrogate |
| t21 | premature EOF | empty input, open tag/attribute/element |
| t22 | root and text | wrong root, multiple roots, text placement, comment/PI |
| t23 | declaration | unterminated, `<?xmlversion...`, accepted `<?xml?>` |

Element comparisons use `xiom.string.compare.str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the `xiom.gpx`
pure-parser idioms (byte-wise scanning with `xiom.string.byte_at`,
`Vec[UInt8]` accumulation with `xiom.string.builder.sb_to_str`, `&mut`
parser state) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so `TcxDoc` is eighteen parallel vectors
  with per-record start indices, and every push group is mirrored so the
  vectors cannot drift on a parse error.
- `Ok`/`Err` for `Result[TcxDoc, Str]` are constructed only in the leaf
  helpers `_ok_doc`/`_err_doc`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare`, and Vec element reads bind typed locals
  first (`let x: Int = v[i];`, `let s: Str = v[j];`).
- Bytes widened to `Int` are masked (`(b as Int) & 0xFF`); byte constants are
  `UInt8` literals.
- The leaf storage target (which vector a leaf writes to) is computed at
  start-tag time from the parent kind and carried on the open stack, so
  `DistanceMeters` and `Value` are disambiguated without rescanning.
- `tcx_build` is iterative: nested loops over activities, laps and
  trackpoints, with fixed canonical child order, so serialization is linear.
- Tests dispatch directly (`t1()` ... `t23()`); no `Vec[fn]` indexed calls
  and no `mut` bindings in match patterns.

## 11. Known limitations

- The subset is closed: no courses, workouts, extensions, creator/author
  blocks, activity-type payload elements, comments, CDATA or DOCTYPE; a
  closing tag is required for every element.
- Unknown attributes are ignored and not reproduced by `tcx_build`, so
  canonical output is not a byte-copy of the input.
- Numeric tokens are stored as text: leading zeros/`+` and fractional forms
  (`+1.5`, `-0.0`) are preserved verbatim; no range or unit validation.
- Timestamps are opaque text; `Id`/`Time`/`StartTime` are never parsed or
  normalized.
- `Activities` requires at least one `Activity` and every `Activity` at
  least one `Lap`; the emitter cannot produce an empty-`Activities` document
  that re-parses, by design.
- Leaf text cannot span markup (one text run per leaf); entity references are
  the only way to embed `&` or `<` in text and the only way to embed `"` in an
  attribute value. A raw `<` inside an attribute value is rejected.
- Leaf text and attribute values are trimmed; a leaf's internal whitespace is
  preserved as written.
- Errors carry no line/column position. No file I/O, no streaming parser, no
  GPS math.
