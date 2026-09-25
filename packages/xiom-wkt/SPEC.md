# xiom.wkt -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.wkt` (`src/wkt.xi`). Pure XIOM, no FFI.
Tests: `tests/test_conformance.xi` (module `wkt_tests`, 27 checks).

## 1. Scope

A small, dependency-free Well-Known Text (WKT) geometry codec for a documented
subset:

- parse one WKT geometry document (`wkt_parse`) into a flat element table
  (`WktDoc`) with child, ring and coordinate spans;
- canonically re-emit a parsed document (`wkt_write`), normalizing all
  whitespace to single spaces and type keywords to uppercase;
- parse + emit in one call (`wkt_normalize`);
- inspect the table: element type/marker/arity/EMPTY flag, parents, direct
  children, coordinate and per-ring spans, and the coordinate text tokens.

Coordinate numbers are **validated lexically but never converted**: each
ordinate is kept as the exact decimal text token from the input (`"1.50"`,
`"+1e3"`, `"-0"` stay byte-identical), so the codec is lossless and there is no
Float64 dependency or rounding anywhere. Callers that want numbers convert
the tokens themselves (for example with `xiom.string.str_to_float`).

The accepted geometry types are POINT, LINESTRING, POLYGON, MULTIPOINT,
MULTILINESTRING, MULTIPOLYGON and GEOMETRYCOLLECTION, each with an EMPTY form,
plus optional Z/M/ZM ordinate markers (pass-through).

## 2. Non-goals

- **No SRID / EWKT.** A leading `SRID=4326;` is rejected as an unknown
  geometry type.
- **No WKB, GeoJSON, GML, PROJ or coordinate transforms.**
- **No geometry math.** Ring closure, minimum vertex counts, self
  intersection, simplicity, area, length and spatial predicates are not
  checked or computed. The codec validates syntax only.
- **No numeric conversion** (see above).
- **No streaming / incremental parsing.** The whole `Str` is consumed in
  memory and the whole table is built before `wkt_parse` returns.
- **No fused markers.** `POINTZ (1 2 3)` is rejected; the marker must be
  space-separated: `POINT Z (1 2 3)`.
- **No unparenthesized MULTIPOINT.** `MULTIPOINT (1 2, 3 4)` is rejected;
  each point must be parenthesized: `MULTIPOINT ((1 2), (3 4))`.
- **No other WKT types** (TIN, POLYHEDRALSURFACE, CIRCULARSTRING, CURVEPOLYGON,
  TRIANGLE, ...).
- **No trailing junk after the root geometry** and no multiple documents per
  string.
- No `EMPTY` combined with a coordinate list (`POINT EMPTY (1 2)` is a
  trailing-tokens error).

## 3. Grammar

```
wkt        = ws geometry ws EOF
geometry   = type [ ws marker ] ws ( "EMPTY" | body )
type       = POINT | LINESTRING | POLYGON | MULTIPOINT
           | MULTILINESTRING | MULTIPOLYGON | GEOMETRYCOLLECTION
marker     = Z | M | ZM
body       = point_body | linestring_body | polygon_body | multipoint_body
           | multilinestring_body | multipolygon_body | collection_body
point_body            = "(" tuple ")"
linestring_body       = "(" tuple *( "," tuple ) ")"
polygon_body          = "(" ring *( "," ring ) ")"
ring                  = "(" tuple *( "," tuple ) ")"
multipoint_body       = "(" point_item *( "," point_item ) ")"
point_item            = "(" tuple ")"
multilinestring_body  = "(" line_item *( "," line_item ) ")"
line_item             = "(" tuple *( "," tuple ) ")"
multipolygon_body     = "(" poly_item *( "," poly_item ) ")"
poly_item             = "(" ring *( "," ring ) ")"
collection_body       = "(" geometry *( "," geometry ) ")"
tuple      = number 1*( ws number )              -- exactly arity numbers
number     = [ "+" | "-" ] digit+ [ "." digit+ ]
             [ ( "e" | "E" ) [ "+" | "-" ] digit+ ]
ws         = *( space | TAB | LF | CR )
```

Everything is matched **case-insensitively** (`point`, `Point`, `POINT` all
parse); `wkt_write` always emits the canonical uppercase form. `EMPTY`,
`Z`, `M` and `ZM` are case-insensitive too.

Semantics, one rule per numbered item:

1. **Element table.** Elements are numbered in pre-order; the root is element
   0. A POINT has one coordinate, a LINESTRING has its vertices, a POLYGON
   has its rings, a MULTIPOINT has one POINT child per parenthesized item, a
   MULTILINESTRING one LINESTRING child per item, a MULTIPOLYGON one POLYGON
   child per item, and a GEOMETRYCOLLECTION one child per member geometry.
2. **Child ranges.** `child_starts`/`child_ends` are `[start, end)` spans into
   the flat `child_ids` table. The list holds the **direct** children in
   input order. Sibling element indices are not contiguous when a sibling has
   descendants, which is why the ids are listed explicitly.
3. **Ring and coordinate ranges.** `ring_starts`/`ring_ends` and
   `point_starts`/`point_ends` are `[start, end)` subtree spans: for a
   MULTIPOLYGON they cover all rings of all its polygons, and for a
   GEOMETRYCOLLECTION all descendant rings/coordinates. Rings are global:
   `wkt_ring_parent` maps a ring to its owning POLYGON element (rings of the
   polygons below a MULTIPOLYGON belong to those child polygons).
4. **Coordinates.** A tuple has exactly `arity` numbers separated by
   whitespace; `arity = 2 + dims(marker)` where Z adds 1, M adds 1 and ZM
   adds 2. The ordinates are stored as text in `xs`, `ys`, `zs`, `ms`; for an
   M-only tuple the third token is stored in `ms` and `zs` is `""`.
5. **Number shape.** `[+-]? digits [. digits]? ([eE] [+-]? digits)?`.
   `.5`, `5.`, `1e`, `1e+`, `--1` and any other shape are errors. Leading
   zeros, a leading `+` and exponents are accepted and kept verbatim.
6. **EMPTY.** The keyword `EMPTY` is the only empty spelling; an empty
   parenthesized list (`POINT ()`, `LINESTRING (  )`, `POLYGON (())`,
   `GEOMETRYCOLLECTION ()`, ...) is an error. `POINT Z EMPTY` is legal: the
   marker is recorded (and re-emitted) although there are no coordinates.
7. **Ordinate markers.** A marker is declared per element and emitted
   uppercase. A child that declares no marker inherits the enclosing element's
   effective marker and arity; a child that declares a **different** marker
   than one already in force is a conflict error. A geometry collection with
   no marker may contain children that declare their own markers.
8. **Rings are not validated geometrically.** A POLYGON ring may have any
   number of vertices and need not be closed; `POLYGON ((0 0, 1 1, 2 2))`
   parses. This is deliberate (see non-goals).
9. **Whitespace.** Any whitespace runs (space, TAB, LF, CR) may appear
   between tokens; leading and trailing whitespace around the document is
   allowed. The canonical emitter collapses every gap to one space and never
   emits whitespace at the start or end.
10. **Canonical text.** `wkt_write` emits `TYPE`, the declared marker with a
    leading space when present, one space before the body, `", "` between
    list items, single spaces between ordinates, and `EMPTY` with no body.
    Coordinate tokens are emitted verbatim.
11. **Round trip.** For every accepted document `d`:
    `wkt_parse(wkt_write(d)) == d` (structurally) and
    `wkt_write(wkt_parse(wkt_write(d))) == wkt_write(d)`. For any accepted
    text `t`, `wkt_write(parse(t))` is the canonical form of `t`.
12. **Error reporting.** Parsing fails on the first problem scanning left to
    right. Every error is a `Str` of the exact form
    `"wkt: <detail> at <byte-offset>"`; offsets are byte offsets into the
    input (not character offsets). See section 5.
13. **Empty table.** `wkt_write` on a hand-built `WktDoc` with zero elements
    returns `""`; `wkt_parse` never produces such a table.

## 4. API contract

```xi
pub type WktDoc = {
  kinds: Vec[Int];             // 0 POINT .. 6 GEOMETRYCOLLECTION
  markers: Vec[Int];           // declared marker: 0 none, 1 Z, 2 M, 3 ZM
  arities: Vec[Int];           // effective ordinates per tuple (2..4)
  empties: Vec[Bool];          // EMPTY flag
  parents: Vec[Int];           // -1 for the root
  child_starts: Vec[Int];      // [start, end) into child_ids
  child_ends: Vec[Int];
  child_ids: Vec[Int];         // direct child element ids, in order
  ring_starts: Vec[Int];       // [start, end) rings in the subtree
  ring_ends: Vec[Int];
  point_starts: Vec[Int];      // [start, end) coordinates in the subtree
  point_ends: Vec[Int];
  ring_parents: Vec[Int];      // owning polygon per ring
  ring_point_starts: Vec[Int]; // [start, end) coordinates per ring
  ring_point_ends: Vec[Int];
  xs: Vec[Str];                // ordinate texts, verbatim
  ys: Vec[Str];
  zs: Vec[Str];
  ms: Vec[Str];
}
```

```xi
pub fn wkt_parse(text: Str) -> Result[WktDoc, Str]
pub fn wkt_write(doc: &WktDoc) -> Str
pub fn wkt_normalize(text: Str) -> Result[Str, Str]

pub fn wkt_geometry_count(doc: &WktDoc) -> Int
pub fn wkt_type(doc: &WktDoc, i: Int) -> Str
pub fn wkt_marker(doc: &WktDoc, i: Int) -> Int
pub fn wkt_coord_arity(doc: &WktDoc, i: Int) -> Int
pub fn wkt_is_empty(doc: &WktDoc, i: Int) -> Bool
pub fn wkt_parent(doc: &WktDoc, i: Int) -> Int
pub fn wkt_child_count(doc: &WktDoc, i: Int) -> Int
pub fn wkt_child(doc: &WktDoc, i: Int, k: Int) -> Int
pub fn wkt_point_start(doc: &WktDoc, i: Int) -> Int
pub fn wkt_point_end(doc: &WktDoc, i: Int) -> Int
pub fn wkt_point_count(doc: &WktDoc, i: Int) -> Int
pub fn wkt_ring_count(doc: &WktDoc, i: Int) -> Int
pub fn wkt_ring_parent(doc: &WktDoc, r: Int) -> Int
pub fn wkt_ring_point_start(doc: &WktDoc, r: Int) -> Int
pub fn wkt_ring_point_end(doc: &WktDoc, r: Int) -> Int
pub fn wkt_ring_point_count(doc: &WktDoc, r: Int) -> Int
pub fn wkt_coord_count(doc: &WktDoc) -> Int
pub fn wkt_x(doc: &WktDoc, p: Int) -> Str
pub fn wkt_y(doc: &WktDoc, p: Int) -> Str
pub fn wkt_z(doc: &WktDoc, p: Int) -> Str
pub fn wkt_m(doc: &WktDoc, p: Int) -> Str
```

Out-of-range defaults (never an error channel; all accessors are total):

| Accessor | Out-of-range result |
|---|---|
| `wkt_type` | `""` |
| `wkt_marker` | `-1` |
| `wkt_coord_arity` | `-1` |
| `wkt_is_empty` | `true` |
| `wkt_parent` | `-1` |
| `wkt_child_count` | `0` |
| `wkt_child` | `-1` |
| `wkt_point_start`, `wkt_point_end`, `wkt_ring_parent`, `wkt_ring_point_start`, `wkt_ring_point_end` | `-1` |
| `wkt_point_count`, `wkt_ring_count`, `wkt_ring_point_count`, `wkt_coord_count`, `wkt_geometry_count` | `0` |
| `wkt_x`, `wkt_y`, `wkt_z`, `wkt_m` | `""` |

None of the accessors may be called with a negative or too-large index and
returned data: they clamp to the documented defaults, so `wkt_type(doc, -1)`
is `""` and not a crash.

`wkt_type` returns `"POINT"`, `"LINESTRING"`, `"POLYGON"`, `"MULTIPOINT"`,
`"MULTILINESTRING"`, `"MULTIPOLYGON"` or `"GEOMETRYCOLLECTION"`.
`wkt_marker` reports the **declared** marker; `wkt_coord_arity` reports the
**effective** arity (inherited when the element declares none).
`wkt_point_count` counts coordinates in the whole subtree, `wkt_ring_count`
counts rings in the whole subtree, `wkt_child_count` counts direct children.

Complexity: `wkt_parse`, `wkt_write` and `wkt_normalize` are O(n) over the
input (the emitter uses `xiom.string.builder`, one allocation); every accessor
is O(1). Recursion depth is the nesting depth of collections.

## 5. Error catalog

Every message is exactly `"wkt: <detail> at <offset>"` (ASCII, no trailing
period). The first problem in byte order wins.

| Detail | Meaning | Example input | Message |
|---|---|---|---|
| `unknown geometry type` | the first keyword is not one of the seven types (`EMPTY` alone included) | `CIRCLE (1 2)`, `""` | `wkt: unknown geometry type at 0` |
| `unknown ordinate marker` | a keyword after the type is not `Z`, `M`, `ZM` or `EMPTY`; also a fused form such as `POINTZ` fails as an unknown type | `POINT X (1 2)` | `wkt: unknown ordinate marker at 6` |
| `expected "("` | a geometry body or list item must start with `(` | `POINT 1 2`, `MULTIPOINT (1 2)` | `wkt: expected "(" at 6` |
| `expected ")"` | a POINT tuple is followed by something other than `)` | `POINT (1 2, 3 4)` | `wkt: expected ")" at 10` |
| `unbalanced parentheses` | the input ended while a `(` was open; the offset is the unclosed `(` | `POINT (1 2` | `wkt: unbalanced parentheses at 6` |
| `invalid number` | a coordinate token that starts no valid number, or garbage where a number was expected | `POINT (1.)`, `POINT (abc 1)` | `wkt: invalid number at 7` |
| `expected N ordinates` | a tuple has fewer or more numbers than the effective arity; the offset is the tuple start | `POINT (1 2 3)` | `wkt: expected 2 ordinates at 7` |
| `missing ","` | a comma-separated list has two items with no comma between them | `MULTIPOINT ((1 2) (3 4))` | `wkt: missing "," at 18` |
| `empty coordinate list` | `(`, optional whitespace and `)` with nothing in between; use `EMPTY` | `POINT ()` | `wkt: empty coordinate list at 7` |
| `trailing tokens` | input remains after the root geometry | `POINT (1 2) x` | `wkt: trailing tokens at 12` |
| `conflicting ordinate markers` | a child declares a marker different from one already in force in an ancestor | `GEOMETRYCOLLECTION Z (POINT M (1 2 3))` | `wkt: conflicting ordinate markers at 28` |

`wkt_normalize` returns the same errors unchanged. `wkt_parse` never panics and
never returns a partial document.

## 6. Test matrix

`tests/test_conformance.xi` runs 27 named checks through
`assert(cond, "name")`, one `fn` per check; `main` calls them directly and
returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | point | element, arity, coordinate text, absent z/m |
| t2 | case + whitespace | case-insensitive keywords, canonical spacing |
| t3 | verbatim tokens | leading `+`, exponents, leading zeros, no conversion |
| t4 | linestring | vertices, counts, spacing |
| t5 | EMPTY variants | all seven types, flag, empty spans, emit |
| t6 | polygon | rings, per-ring spans, ownership, access |
| t7 | multipoint | parenthesized items become POINT children |
| t8 | multilinestring | children, subtree counts, parents |
| t9 | multipolygon | polygons, rings, ring ownership |
| t10 | geometrycollection | mixed members, direct children, subtree total |
| t11 | Z/M/ZM | markers, arities, ordinate slots, `POINT Z EMPTY` |
| t12 | marker inheritance | children inherit; explicit child markers |
| t13 | unknown type | error and offset |
| t14 | unbalanced parens | error reports the unclosed `(` |
| t15 | invalid numbers | `.5`, `5.`, `1e`, `1e+`, `abc` rejected |
| t16 | ordinate count | too few / too many vs effective arity |
| t17 | empty lists | `()`, `(  )`, `(())` rejected |
| t18 | missing comma | between points, rings, collection members |
| t19 | trailing tokens | after all EMPTY and non-EMPTY roots |
| t20 | markers | unknown marker, fused type, cross-level conflict |
| t21 | list shapes | MULTIPOINT needs inner parens; POINT closes with `)` |
| t22 | round trip | canonical emit re-parses to the same text |
| t23 | accessor bounds | every out-of-range default |
| t24 | wkt_normalize | canonical text or exact error |
| t25 | nested collections | element order, direct children, subtree totals |
| t26 | EMPTY in collections | structure preserved, round trip |
| t27 | ZM in collections | inheritance through MULTIPOLYGON to polygons |

All Str comparisons in the suite go through `xiom.string.compare`'s
`str_compare` (BUG 17: `==` on `Str` values read from `Vec[Str]` elements
lowers to a pointer comparison).

## 7. Known limitations

- No SRID/EPSG (`SRID=...;`), no WKB, no CRS, no geometry math (section 2).
- Coordinate tokens are text; the module does not convert, so `1.0` and `1`
  are different tokens and round-trip verbatim. `wkt_normalize` therefore
  normalizes whitespace and casing but **not** number spelling.
- Ring closure and minimum vertex counts are not validated; a "polygon" with
  two vertices parses.
- Deeply nested GEOMETRYCOLLECTIONs recurse once per nesting level; extremely
  deep input is bounded by the process stack (documented, not guarded).
- Only one geometry per document.
- `MULTIPOINT` items must be parenthesized; the older unparenthesized syntax
  is rejected.
- Fused marker spellings (`POINTZ`, `POINTZM`) are rejected.
- No comments, no `SRID` prefix, no whitespace inside a number token.
- The `Str` is treated as a UTF-8 byte buffer; scanning is byte-wise but
  multi-byte sequences are only ever split at token boundaries, so non-ASCII
  (invalid inside WKT anyway) cannot corrupt the table.

## 8. Compiler / stdlib notes

The implementation follows the XIOM v0.61.3 workarounds used across this
repository:

- `Str` equality goes through `xiom.string.compare`; Vec element reads are
  bound to typed locals before use (BUG 17 and the untyped `Vec[Int]` read).
- `Ok`/`Err` are constructed only in the leaf helpers
  (`_ok_doc`/`_err_doc`, `_ok_at`/`_err_at`, `_ok_str`/`_err_str`).
- Emission uses `xiom.string.builder` (`sb_new`/`sb_push_str`/`sb_to_str`)
  with explicit `&mut` at call sites.
- Direct-child ids are appended in post-order bursts (`_append_kids`) so that
  nested containers cannot interleave the flat `child_ids` table.
- The test suite calls each `fn tN()` directly (no `Vec[fn]` dispatch).
- `src/wkt.xi` must stay **BOM-free**: with a UTF-8 BOM the compiler's module
  resolver does not find `module xiom.wkt`, and importing the module fails
  with "undefined variable" errors while the file still type-checks stand
  alone.
