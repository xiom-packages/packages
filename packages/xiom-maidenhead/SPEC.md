# xiom.maidenhead -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.maidenhead` (`src/maidenhead.xi`). Pure XIOM, no FFI.

## 1. Scope

An integer-only Maidenhead (QTH grid) locator codec over integer-microdegree
coordinates:

- encode a validated coordinate to a canonical uppercase locator of 2, 4, 6
  or 8 characters (`maidenhead_encode`),
- decode a locator to its exact integer-microdegree bounding box and center
  (`maidenhead_decode`),
- normalize a locator to its canonical uppercase spelling and validate it
  (`maidenhead_normalize`),
- read the validated length and the field/square/subsquare/extended-square
  parts of a locator (`maidenhead_locator_length`, `maidenhead_field`,
  `maidenhead_square`, `maidenhead_subsquare`, `maidenhead_ext_square`),
- read box length/bounds, test inclusive containment
  (`maidenhead_box_length`, `maidenhead_box_min_lat`, `maidenhead_box_min_lon`,
  `maidenhead_box_max_lat`, `maidenhead_box_max_lon`,
  `maidenhead_box_contains`).

All arithmetic is exact integer arithmetic; no `Float64` and no `Vec` appear
in the module.

## 2. Non-goals

- No distance, bearing or great-circle math; no neighboring/adjacent-cell
  computation and no area or polygon geometry.
- No map projections or other coordinate systems (MGRS, UTM, GeoJSON, KML,
  GPX, shapefiles).
- No sub-microdegree input: floating-point degrees are the caller's concern.
- No configurable levels or alphabets, no arbitrary precision beyond length 8,
  no streaming APIs; every call is a pure function over its arguments.
- No FFI, file I/O, or registry integration.

## 3. Units and domain

- 1 degree = 1,000,000 microdegrees (`ud`); the module's suffix `_ud` uses
  this unit exclusively.
- Latitude domain: `[-90_000_000, 90_000_000]`, inclusive.
- Longitude domain: `[-180_000_000, 180_000_000]`, inclusive.
- Locator lengths: `2`, `4`, `6` or `8` characters (1 to 4 level pairs).
- `Int` is 64-bit in XIOM; the widest intermediate product in this module is
  `43_200 * 25_000 = 1.08e9`, far inside the range.

## 4. Levels, characters and geometry

### 4.1 Levels

A locator is a sequence of (longitude, latitude) character pairs, longitude
first, following the standard Maidenhead scheme:

| Level | Pair index | Longitude part | Latitude part | Cell (lon x lat) |
|---|---|---|---|---|
| field | 1 | letters `A`-`R` (18) | letters `A`-`R` (18) | 20 deg x 10 deg |
| square | 2 | digits `0`-`9` | digits `0`-`9` | 2 deg x 1 deg |
| subsquare | 3 | letters `A`-`X` (24) | letters `A`-`X` (24) | 5' x 2.5' |
| extended square | 4 | digits `0`-`9` | digits `0`-`9` | 0.5' x 0.25' |

Accepted lengths are exactly `2`, `4`, `6`, `8`. Canonical output is
uppercase; ASCII letters in input are case-insensitive and are folded to
uppercase before validation, so `"jo22ki"` and `"Jo22kI"` both decode as
`"JO22KI"`. Digits are unaffected by case folding.

### 4.2 Exact integer index on the 1/240-degree grid

A longitude cell at the finest level is `2 deg / 240 = 1/120 deg = 25_000/3
ud` and a latitude cell is `1 deg / 240 = 1/240 deg = 25_000/6 ud`. The codec
therefore indexes both axes over the whole sphere with 43_200 cells
(`18 * 10 * 24 * 10`) and exact integer arithmetic:

```
nl = floor((lon_ud + 180_000_000) * 3 / 25_000)    # longitude, 0..43_199
ml = floor((lat_ud + 90_000_000)  * 6 / 25_000)    # latitude,  0..43_199
```

(the numerators are cells per microdegree: `120 / 1_000_000 = 3/25_000` for
longitude, `240 / 1_000_000 = 6/25_000` for latitude). The four locator parts
are the base-2400/240/10/1 digits of the index:

```
field         = k / 2400
square        = (k / 240) % 10
subsquare     = (k / 10) % 24
extended sq.  = k % 10
```

Longitude and latitude are indexed independently; each level's pair is
(longitude part, latitude part). The emitted character is uppercase
`A` + index for letters and `0` + index for digits. No `Float64` is used, so
every result is exact and platform-independent.

### 4.3 Boundary behavior

- A point exactly on a cell edge selects the **upper** (east/north) cell:
  the cells of a level are half-open `[lower, upper)` in both axes.
- The inclusive upper bounds `lon_ud = 180_000_000` and `lat_ud =
  90_000_000` are *not* inside a half-open cell; they fold into the
  northernmost/easternmost cell (index 43_199) because the index formula
  saturates at 43_200. Hence `"RR99XX99"` is the maximum locator and is
  produced both by the exact top corner and by `(89_999_999, 179_999_999)`.
- The inclusive lower bounds `lon_ud = -180_000_000` and `lat_ud =
  -90_000_000` are the lower edges of the first cell `"AA00AA00"`.

Worked edge examples (length 8):

| Point (lat_ud, lon_ud) | Locator | Reason |
|---|---|---|
| `(-90_000_000, -180_000_000)` | `AA00AA00` | domain minimum |
| `(-1, 0)` | `JI09AX09` | last latitude cell below 0 deg |
| `(0, -1)` | `IJ90XA90` | last longitude cell below 0 deg |
| `(0, 0)` | `JJ00AA00` | edges select the upper cell |
| `(0, 1)` / `(1, 0)` | `JJ00AA00` | first cell east/north of 0 deg |
| `(89_999_999, 179_999_999)` | `RR99XX99` | last interior point |
| `(90_000_000, 180_000_000)` | `RR99XX99` | top edge clamps |

### 4.4 Worked examples

Decimal-degree inputs are shown for readability; the module takes the exact
integer microdegree values (for example `51.5007` = `51_500_700` ud).

| Point | 2 | 4 | 6 | 8 |
|---|---|---|---|---|
| `51.5007 N, 0.1278 W` (London) | `IO` | `IO91` | `IO91WM` | `IO91WM40` |
| `52.370216 N, 4.895168 E` (Amsterdam) | `JO` | `JO22` | `JO22KI` | `JO22KI78` |
| `33.8688 S, 151.2093 E` (Sydney) | `QF` | `QF56` | `QF56OD` | `QF56OD51` |
| `40.7128 N, 74.0060 W` (New York) | `FN` | `FN20` | `FN20XR` | `FN20XR91` |
| `60.1699 N, 24.9384 E` (Helsinki) | `KP` | `KP20` | `KP20LE` | `KP20LE20` |
| `(0, 0)` | `JJ` | `JJ00` | `JJ00AA` | `JJ00AA00` |
| `(90 N, 180 E)` | `RR` | `RR99` | `RR99XX` | `RR99XX99` |

All vectors were cross-checked against an independent exact-rational
reference implementation of the classic subdivision algorithm; a 30k-point
encode sweep and a 73k-locator decode sweep agreed on every value.

## 5. Precision table

| Length | Levels included | Latitude cell | Longitude cell |
|---|---|---|---|
| 2 | field | 10 deg = 600' = 36,000" = 10,000,000 ud | 20 deg = 1,200' = 72,000" = 20,000,000 ud |
| 4 | + square | 1 deg = 60' = 3,600" = 1,000,000 ud | 2 deg = 120' = 7,200" = 2,000,000 ud |
| 6 | + subsquare | 1/24 deg = 2.5' = 150" = 41,666.67 ud | 1/12 deg = 5' = 300" = 83,333.33 ud |
| 8 | + extended square | 1/240 deg = 0.25' = 15" = 4,166.67 ud | 1/120 deg = 0.5' = 30" = 8,333.33 ud |

The non-integer microdegree figures are exact fractions (41,666 + 2/3 ud,
83,333 + 1/3 ud, 4,166 + 2/3 ud, 8,333 + 1/3 ud); they are rounded above for
display and are exact in the integer index arithmetic of section 4.2. The
suite pins the spans of decoded square and subsquare boxes, which is
equivalent to this table's degree/minute/second figures.

Every cell at every level is wider than one microdegree on both axes, so
every valid locator decodes to a non-empty box (contrast with geohash, whose
finest cells can be sub-microdegree).

## 6. Decoding and box semantics

Decoding rebuilds the full-grid index from the parts:

```
k = field*2400 + square*240 + subsquare*10 + ext       # per axis
w = 2400, 240, 10 or 1                                 # by length 2, 4, 6, 8
```

and converts the half-open cell `[k, k + w)` (in 1/240-degree units) to the
inclusive integer-microdegree range whose points all re-encode to it. With
`den = 3` for longitude and `den = 6` for latitude:

```
min = ceil((k * 25_000 - 540_000_000) / den)
max = ceil(((k + w) * 25_000 - 540_000_000) / den) - 1      (k + w < 43_200)
max = 180_000_000 (lon) or 90_000_000 (lat)                 (k + w = 43_200)
center_lat = (min_lat + max_lat) / 2
center_lon = (min_lon + max_lon) / 2
```

Properties (all pinned by the suite):

- `min <= center <= max` on both axes; the center and all four box corners
  re-encode to the source locator at the same length.
- The box contains exactly the integer-microdegree points that encode to the
  locator; `maidenhead_box_contains` is inclusive on all four bounds.
- For the top cell the reported maximum is the inclusive domain maximum
  (`180_000_000` / `90_000_000`), because encoding folds those bounds into the
  top cell (section 4.3).
- The center uses truncating integer division (LLVM `sdiv`, toward zero), so
  for a box whose endpoints sum negative the center is the truncation, not
  the floor; e.g. `"AA00AA00"` centers at `(-89_997_917, -179_995_833)`.
- Longitude `+180_000_000` and `-180_000_000` are distinct cells; no
  antimeridian wrapping occurs anywhere in the module.

## 7. API signatures

```xi
pub type MaidenheadBox = {
  length: Int;
  min_lat_ud: Int;
  min_lon_ud: Int;
  max_lat_ud: Int;
  max_lon_ud: Int;
  center_lat_ud: Int;
  center_lon_ud: Int;
}

pub fn maidenhead_encode(lat_ud: Int, lon_ud: Int, length: Int) -> Result[Str, Str]
pub fn maidenhead_decode(locator: Str) -> Result[MaidenheadBox, Str]
pub fn maidenhead_normalize(locator: Str) -> Result[Str, Str]
pub fn maidenhead_locator_length(locator: Str) -> Result[Int, Str]
pub fn maidenhead_field(locator: Str) -> Result[Str, Str]
pub fn maidenhead_square(locator: Str) -> Result[Str, Str]
pub fn maidenhead_subsquare(locator: Str) -> Result[Str, Str]
pub fn maidenhead_ext_square(locator: Str) -> Result[Str, Str]
pub fn maidenhead_box_length(b: MaidenheadBox) -> Int
pub fn maidenhead_box_min_lat(b: MaidenheadBox) -> Int
pub fn maidenhead_box_min_lon(b: MaidenheadBox) -> Int
pub fn maidenhead_box_max_lat(b: MaidenheadBox) -> Int
pub fn maidenhead_box_max_lon(b: MaidenheadBox) -> Int
pub fn maidenhead_box_contains(b: MaidenheadBox, lat_ud: Int, lon_ud: Int) -> Bool
```

Encode is `O(1)`; decode/normalize and the locator accessors are
`O(len(locator))`; the box accessors are `O(1)`.

## 8. Error catalog

All messages are returned as the `Err` payload and are pinned verbatim by the
suite.

| Condition | Message |
|---|---|
| `length` not 2, 4, 6 or 8 in `maidenhead_encode` | `maidenhead: invalid length` |
| `lat_ud < -90_000_000` or `lat_ud > 90_000_000` | `maidenhead: latitude out of range` |
| `lon_ud < -180_000_000` or `lon_ud > 180_000_000` | `maidenhead: longitude out of range` |
| `locator.len() == 0` | `maidenhead: empty locator` |
| length not 2, 4, 6 or 8 (including odd lengths) | `maidenhead: invalid locator length` |
| position 0 or 1 outside `A`-`R` after case folding | `maidenhead: invalid field letter` |
| position 2 or 3 outside `0`-`9` | `maidenhead: invalid square digit` |
| position 4 or 5 outside `A`-`X` after case folding | `maidenhead: invalid subsquare letter` |
| position 6 or 7 outside `0`-`9` | `maidenhead: invalid extended square digit` |
| `maidenhead_square` on a length-2 locator | `maidenhead: square part missing` |
| `maidenhead_subsquare` on a length-2 or length-4 locator | `maidenhead: subsquare part missing` |
| `maidenhead_ext_square` on a locator shorter than 8 | `maidenhead: extended square part missing` |

Validation order in `maidenhead_encode` is length, latitude, longitude. For
locators, empty length is checked first, then the 2/4/6/8 length rule, then
the characters position by position in locator order (field, square,
subsquare, extended square). The part accessors apply the same locator
validation before their own missing-part check. Bounds are inclusive on both
ends.

## 9. Test plan

`tests/test_conformance.xi` (module `maidenhead_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected locators, boxes and centers were produced
by an independent exact-rational reference implementation of the classic
subdivision algorithm.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | London vector | `(51_500_700, -127_800)` -> `IO`, `IO91`, `IO91WM`, `IO91WM40` |
| t2 | city vectors | Amsterdam `JO22KI`, Sydney `QF56OD51`, New York `FN20XR`, Helsinki `KP20LE` |
| t3 | null island | `(0, 0)` -> `JJ00AA00`; box `[0, 4166] x [0, 8333]`, center `(2083, 4166)`, exact containment edges |
| t4 | range corners | `AA00AA00`, `RR99XX99`, `AR09AX09`, `RA90XA90`; north-east prefixes `RR`, `RR99`, `RR99XX` |
| t5 | edge selection | `(0,-1)` -> `IJ90XA90`; `(-1,0)` -> `JI09AX09`; `(0,0)`/`(0,1)`/`(1,0)` -> `JJ00AA00`; last interior point -> `RR99XX99` |
| t6 | invalid encode length | 0, 1, 3, 5, 7, 9, 10, -2 -> exact message; length checked before coordinates |
| t7 | invalid latitude | `+/-90_000_001` -> exact message; `+/-90_000_000` accepted |
| t8 | invalid longitude | `+/-180_000_001` -> exact message; `+/-180_000_000` accepted |
| t9 | known-vector box | `JO22KI` exact bounds, center `(52_354_166, 4_875_000)`, length, accessors, inclusive containment and two rejections |
| t10 | field/square boxes | `JO` and `IO91` exact bounds and centers |
| t11 | corner boxes | `AA00AA00`, `RR99XX99`, `AR09AX09`, `RA90XA90` bounds; top maxima clamp; negative centers truncate toward zero |
| t12 | length errors | `""`, lengths 1, 3, 5, 7, 10 and an 11-byte non-locator -> exact messages (length before characters) |
| t13 | invalid field | `S`, `1`, `!` and lowercase out-of-range letters at positions 0/1 -> exact message |
| t14 | invalid square | letters, space and `-` at positions 2/3 -> exact message |
| t15 | invalid subsquare | `Y` (24), digits and `!` at positions 4/5 -> exact message |
| t16 | invalid extended square | letters and `!` at positions 6/7 -> exact message |
| t17 | case folding | `jo22ki` decodes field-for-field like `JO22KI`; `normalize` uppercases mixed case |
| t18 | normalize | idempotent uppercase; shares the decode catalog (empty, length, square, subsquare, extended square) |
| t19 | part accessors | `jo22ki78` -> `JO`/`22`/`KI`/`78`; length 2/4/6/8; missing-part errors for short locators; validation error propagates |
| t20 | round trips | Denmark, null island and all six pole/antimeridian edges at every length 2/4/6/8: box non-empty, contains the point, center and four corners re-encode to the locator |
| t21 | nesting and spans | each length's locator is a prefix of the next; decoded spans pin the precision table (square `999_999 x 1_999_999` ud interior, subsquare `41_665 x 83_332`) |

Every `Str` comparison goes through `xiom.string.compare`'s `str_compare`,
never `==` (BUG 17 family), and the suite uses no `Vec` at all (no `Vec[fn]`
dispatch; the 21 test functions are called directly from `main`).

## 10. Known limitations

- **No neighbors.** Adjacent-cell, distance, bearing and area computations
  are explicitly out of scope.
- **Length cap 8.** Longer locators are rejected; the extended square is the
  finest standard level.
- **Microdegree grid.** Sub-microdegree input must be rounded by the caller.
- **No antimeridian wrapping.** `+180` and `-180` are distinct edge cells.
- No configurable levels, no non-standard alphabets, no streaming APIs.

## 11. Compiler / stdlib notes

The module follows the v0.61.3 idioms proven by the sibling ports:

- Free functions only; no `self` methods, no lambdas, no `Vec[Float64]`, and
  in fact no `Vec` at all.
- `Ok`/`Err` payloads are constructed only in the leaf helpers
  `_ok_str`/`_err_str`/`_ok_box`/`_err_box`/`_ok_int`/`_err_int`.
- Every `xiom.string.byte_at` result is widened as `(x as Int) & 0xFF`
  before comparison; all accepted bytes are ASCII < 128.
- No string equality is performed in the module (the suite routes every
  comparison through `str_compare`).
- Case folding uses `xiom.string.str_upper` (ASCII `a`-`z`), then validates
  the folded bytes, so lowercase input is accepted without a second lookup
  table.
- `Int` division truncates toward zero (LLVM `sdiv`). The decode helpers use
  `_div_ceil(a, b)` implemented with pure division and remainder
  (`q = a / b; r = a % b; r > 0 ? q + 1 : q`), which is exact for negative
  numerators; the center formula and the suite pin the truncating behavior,
  including negative sums.
- The only build output is advisory: passing `MaidenheadBox` by value to the
  box accessors and helpers emits `warning[E001] use of moved value` under
  the current borrow checker. The warnings are benign (struct values are
  copied) and the suite is green: `port.ps1` ends
  `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.
