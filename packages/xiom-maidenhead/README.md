# xiom.maidenhead

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), green under the
> repo harness. **NOT published** to the XIOM registry.
> **Scope:** an integer-only Maidenhead (QTH grid) locator codec: encode
> integer-microdegree coordinates to canonical uppercase locators of 2, 4, 6
> or 8 characters and decode them back to exact integer-microdegree bounding
> boxes and centers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_upper`,
> `xiom.string.str_slice` and `xiom.string.byte_at`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.maidenhead` is a small, dependency-free codec for the standard
Maidenhead locator system used by radio amateurs. A locator is a sequence of
(longitude, latitude) pairs, longitude first:

| Level | Length pair | Longitude part | Latitude part | Cell (lon x lat) |
|---|---|---|---|---|
| field | 1 | letters `A`-`R` | letters `A`-`R` | 20 deg x 10 deg |
| square | 2 | digits `0`-`9` | digits `0`-`9` | 2 deg x 1 deg |
| subsquare | 3 | letters `A`-`X` | letters `A`-`X` | 5' x 2.5' |
| extended square | 4 | digits `0`-`9` | digits `0`-`9` | 0.5' x 0.25' |

Accepted lengths are therefore **2, 4, 6 or 8** characters; canonical output
is **uppercase**. Input is case-insensitive (`"jo22ki"` and `"JO22KI"` decode
identically).

Coordinates are carried as **integer microdegrees** (`ud`): 1 degree is
1,000,000 ud, latitude runs over `[-90_000_000, 90_000_000]` and longitude
over `[-180_000_000, 180_000_000]`, both inclusive. The codec uses integer
arithmetic exclusively -- no `Float64`, no platform-dependent rounding -- so
the same input always produces the same locator on every platform.

Boundary behavior is fixed and documented: a point exactly on a cell edge
selects the upper (east/north) cell, and the inclusive upper bounds
`lat = 90_000_000` / `lon = 180_000_000` fold into the northernmost /
easternmost cell, so `"AA00AA00"` is the minimum locator and `"RR99XX99"` the
maximum. For example `(0, 0)` is `"JJ00AA00"` and `(0, -1 ud)` is
`"IJ90XA90"`.

A decoded `MaidenheadBox` is the inclusive integer-microdegree range whose
points all re-encode to the same locator, plus the box center (truncating
integer division `(min + max) / 2`). Every valid locator decodes to a
non-empty box: the smallest cell (extended square) is 83,333.33 ud x
41,666.67 ud, wider than one microdegree on both axes. The center and all
four box corners re-encode to the source locator.

## Precision table

| Length | Levels included | Latitude cell | Longitude cell |
|---|---|---|---|
| 2 | field | 10 deg = 600' = 36,000" (10,000,000 ud) | 20 deg = 1,200' = 72,000" (20,000,000 ud) |
| 4 | + square | 1 deg = 60' = 3,600" (1,000,000 ud) | 2 deg = 120' = 7,200" (2,000,000 ud) |
| 6 | + subsquare | 1/24 deg = 2.5' = 150" (41,666.67 ud) | 1/12 deg = 5' = 300" (83,333.33 ud) |
| 8 | + extended square | 1/240 deg = 0.25' = 15" (4,166.67 ud) | 1/120 deg = 0.5' = 30" (8,333.33 ud) |

The fractions of a microdegree are exact rational cells (the microdegree
figures are rounded for display); the spec's derivatives are pinned by the
suite through decoded box spans.

## Quick start

```xi
use xiom.maidenhead;
use xiom.io;

fn main() -> Int {
  let loc = maidenhead_encode(51500700, -127800, 6);  // 51.5007N 0.1278W
  if loc.is_ok { io.println(loc.value); }             // IO91WM

  let d = maidenhead_decode("jo22ki");                // lowercase is accepted
  if d.is_ok {
    let box = d.value;                                // box.length == 6
    // box.min_lat_ud, box.max_lat_ud, box.min_lon_ud, box.max_lon_ud
    // box.center_lat_ud, box.center_lon_ud
  }

  let n = maidenhead_normalize("jo22ki");
  if n.is_ok { io.println(n.value); }                 // JO22KI
  return 0;
}
```

## Install

```
xiom pkg install xiom.maidenhead@0.1.0   # consumer
xiom pkg publish                          # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## API

| Function | Returns | Description |
|---|---|---|
| `maidenhead_encode(lat_ud, lon_ud, length)` | `Result[Str, Str]` | Encode integer-microdegree coordinates as a `length`-character uppercase locator (length 2, 4, 6 or 8). |
| `maidenhead_decode(locator)` | `Result[MaidenheadBox, Str]` | Decode a 2/4/6/8 character locator (case-insensitive) to its box and center. |
| `maidenhead_normalize(locator)` | `Result[Str, Str]` | Validate a locator and return its canonical uppercase spelling. |
| `maidenhead_locator_length(locator)` | `Result[Int, Str]` | Validated length: 2, 4, 6 or 8. |
| `maidenhead_field(locator)` | `Result[Str, Str]` | Field part (level 0): two letters A-R. |
| `maidenhead_square(locator)` | `Result[Str, Str]` | Square part (level 1): two digits, requires length >= 4. |
| `maidenhead_subsquare(locator)` | `Result[Str, Str]` | Subsquare part (level 2): two letters A-X, requires length >= 6. |
| `maidenhead_ext_square(locator)` | `Result[Str, Str]` | Extended square part (level 3): two digits, requires length 8. |
| `maidenhead_box_length(b)` | `Int` | Character count of the source locator. |
| `maidenhead_box_min_lat(b)` | `Int` | Lower latitude bound in microdegrees. |
| `maidenhead_box_min_lon(b)` | `Int` | Lower longitude bound in microdegrees. |
| `maidenhead_box_max_lat(b)` | `Int` | Upper latitude bound in microdegrees. |
| `maidenhead_box_max_lon(b)` | `Int` | Upper longitude bound in microdegrees. |
| `maidenhead_box_contains(b, lat_ud, lon_ud)` | `Bool` | Inclusive containment of a point in the box. |

Type:

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
```

Complexity is `O(1)` for encode, `O(1)` for the accessors and
`O(len(locator))` for decode/normalize.

## Error model

All failures are `Err(Str)` with deterministic messages; nothing panics and
no silent fallback exists.

| Condition | Message |
|---|---|
| `length` not 2, 4, 6 or 8 in encode | `maidenhead: invalid length` |
| `lat_ud < -90_000_000` or `lat_ud > 90_000_000` | `maidenhead: latitude out of range` |
| `lon_ud < -180_000_000` or `lon_ud > 180_000_000` | `maidenhead: longitude out of range` |
| locator is `""` | `maidenhead: empty locator` |
| locator length not 2, 4, 6 or 8 (including odd) | `maidenhead: invalid locator length` |
| position 0 or 1 is not a letter `A`-`R` after case folding | `maidenhead: invalid field letter` |
| position 2 or 3 is not a digit `0`-`9` | `maidenhead: invalid square digit` |
| position 4 or 5 is not a letter `A`-`X` after case folding | `maidenhead: invalid subsquare letter` |
| position 6 or 7 is not a digit `0`-`9` | `maidenhead: invalid extended square digit` |
| `maidenhead_square` on a length-2 locator | `maidenhead: square part missing` |
| `maidenhead_subsquare` on a length-2/4 locator | `maidenhead: subsquare part missing` |
| `maidenhead_ext_square` on a shorter locator | `maidenhead: extended square part missing` |

Validation order in encode is length, then latitude, then longitude. For
locators, length (empty, then invalid) is checked before any character, and
positions are checked in locator order: field pair, square pair, subsquare
pair, extended square pair. Bounds are inclusive on both ends.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.maidenhead
```

Expected tail: 21 `[PASS]` lines, `xiom.maidenhead: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

The suite (`tests/test_conformance.xi`) pins known city vectors at lengths
2/4/6/8, the four range corners, boundary and top-edge behavior, exact boxes
and centers from field to extended-square level, the full error catalog,
uppercase folding, the part accessors, and round trips at every length
including the poles and the antimeridian. Expected values were cross-checked
against an independent exact-rational reference implementation of the classic
Maidenhead subdivision algorithm (30k-point encode and 73k-locator decode
sweeps). See `SPEC.md` for the algorithm, the precision table and the
test-to-semantics map.

## Limitations

- **No neighbors, distance or bearings.** Adjacent-cell computation,
  great-circle conversions and map projections are out of scope.
- **Length cap 8.** Longer locators are rejected with
  `maidenhead: invalid locator length`; the extended square is the finest
  standard level.
- **Integer grid only.** Sub-microdegree input is not representable; callers
  must round before calling the codec.
- **No antimeridian wrapping.** Longitude `+180_000_000` and
  `-180_000_000` are distinct edge cells; the codec never wraps a coordinate
  from one to the other. Latitude/longitude cells at the top edge include the
  boundary value (see boundary behavior above).
- No configurable levels or alphabets, no streaming APIs.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
