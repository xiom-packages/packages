# xiom.geo -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.geo` (`src/geo.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free geohash module for WGS84 coordinates:

- encode a latitude/longitude pair to a base32 geohash string
  (`geo_geohash_encode`),
- decode a geohash to the center of its cell (`geo_geohash_decode`),
- compute the 8 neighboring cells of a geohash (`geo_geohash_neighbors`),
- inclusive bounding-box containment, including antimeridian-crossing boxes
  (`geo_geo_bbox_contains`),
- clamp latitudes/longitudes (`geo_clamp_lat`, `geo_clamp_lon`).

All arithmetic is `Float64` interval bisection over the WGS84 ranges
latitude `[-90, 90]` and longitude `[-180, 180]`. No `Vec[Float64]` is used;
only scalar `Float64` locals and two `GeoPoint` fields.

## 2. Non-goals

- Other geospatial formats (GeoJSON, KML, GPX, shapefiles) and coordinate
  systems (MGRS, UTM, projections).
- Distance, bearing, area, or polygon operations.
- Configurable alphabets, uppercase folding, arbitrary precision (> 12).
- Streaming APIs; every call is a pure function over its arguments.
- Any FFI, file I/O, or registry integration.

## 3. Geohash algorithm

### 3.1 Alphabet

```
_GEO_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
```

32 symbols: `0`-`9` (digit values 0-9) followed by the lowercase consonants
`b`-`z` minus `i`, `l`, `o` (values 10-31). Standard geohash; lowercase only.

### 3.2 Bit interleaving

The WGS84 ranges start as `lat [-90, 90]`, `lon [-180, 180]`. Bits alternate
**longitude first**: bit 0 of a hash is a longitude bit, bit 1 a latitude bit,
and so on. Within each 5-bit character the first bit produced is the most
significant bit (value 16).

For a longitude bit: `mid = (lon_lo + lon_hi) / 2`; the bit is 1 when
`lon >= mid` (interval becomes `[mid, lon_hi]`), else 0 (interval becomes
`[lon_lo, mid]`). Latitude bits use the same rule. At the inclusive upper
bound `lon = 180` or `lat = 90` every bit is 1, selecting the easternmost /
northernmost cell.

A character is emitted after every 5 bits (bit indexes `4, 9, 14, ...`); its
digit value indexes `_GEO_BASE32` through `xiom.string.str_slice`. A hash of
`precision` characters therefore carries `5 * precision` bits:
`lon_bits = ceil(5p / 2)`, `lat_bits = floor(5p / 2)`.

### 3.3 Worked example

`(lat, lon) = (57.64911, 10.40744)`:

| Precision | Hash |
|---|---|
| 1 | `u` |
| 7 | `u4pruyd` |
| 11 | `u4pruydqqvj` (well-known example) |
| 12 | `u4pruydqqvj8` |

The 11-character value is the canonical Wikipedia example (the vector string
itself is 11 characters); `xiom.geo` additionally pins the 12-character
extension `u4pruydqqvj8` and `(0, 0) -> s00000000000`. All values in this
table were cross-checked against an independent reference implementation.

### 3.4 Decoding

Decoding replays the same bisection per character: bit value `v` (0..31) is
decomposed MSB-first with masks `16, 8, 4, 2, 1`; each set bit narrows the
matching interval upward. After the last character the result is the cell
center `((lat_lo + lat_hi) / 2, (lon_lo + lon_hi) / 2)`. Because encoding uses
`>=` against the midpoint, a decoded center always re-encodes to its own cell.

## 4. Neighbor derivation

`geo_geohash_neighbors(hash)` first decodes the cell center, then computes the
cell span from the hash length:

```
total_bits = 5 * precision
lon_bits   = ceil(total_bits / 2)
lat_bits   = floor(total_bits / 2)
height     = 180 / 2^lat_bits     (degrees of latitude)
width      = 360 / 2^lon_bits     (degrees of longitude)
```

Moving half a span from the center reaches the center of the adjacent cell:

```
north_lat = clamp(center.lat + height)     east_lon = wrap(center.lon + width)
south_lat = clamp(center.lat - height)     west_lon = wrap(center.lon - width)
```

Each neighbor is re-encoded with the internal raw encoder at the same
precision. The order is fixed and documented:

| # | Direction | lat | lon |
|---|---|---|---|
| 0 | N | `north_lat` | `center.lon` |
| 1 | NE | `north_lat` | `east_lon` |
| 2 | E | `center.lat` | `east_lon` |
| 3 | SE | `south_lat` | `east_lon` |
| 4 | S | `south_lat` | `center.lon` |
| 5 | SW | `south_lat` | `west_lon` |
| 6 | W | `center.lat` | `west_lon` |
| 7 | NW | `north_lat` | `west_lon` |

Reference set for `u4pruydqqvj` (11 characters; independently verified):
`["u4pruydqqvm", "u4pruydqqvq", "u4pruydqqvn", "u4pruydqquy", "u4pruydqquv",
"u4pruydqquu", "u4pruydqqvh", "u4pruydqqvk"]`.

Boundary semantics: `clamp` pins latitude at `[-90, 90]` and `wrap` moves
longitude into `[-180, 180]` by +/-360. On a polar cell the out-of-range
neighbor therefore collapses onto the pole cell (a duplicate entry is
possible); on an antimeridian cell the column wraps to the opposite edge. An
invalid hash yields an empty `Vec[Str]`.

## 5. Bounding boxes

`geo_geo_bbox_contains(min_lat, min_lon, max_lat, max_lon, lat, lon)`:

1. `lat < min_lat || lat > max_lat` => false.
2. When `min_lon <= max_lon`: true iff `lon >= min_lon && lon <= max_lon`.
3. When `min_lon > max_lon` (antimeridian-crossing box): true iff
   `lon >= min_lon || lon <= max_lon`, i.e. the box covers
   `[min_lon, 180]` together with `[-180, max_lon]`.

All six bounds are inclusive. `min_lat <= max_lat` is assumed; a degenerate
box `min == max` on both axes contains exactly that point.

## 6. API signatures

```xi
pub type GeoPoint = { lat: Float64; lon: Float64; }

pub fn geo_clamp_lat(lat: Float64) -> Float64
pub fn geo_clamp_lon(lon: Float64) -> Float64
pub fn geo_geohash_encode(lat: Float64, lon: Float64, precision: Int) -> Result[Str, Str]
pub fn geo_geohash_decode(hash: Str) -> Result[GeoPoint, Str]
pub fn geo_geohash_neighbors(hash: Str) -> Vec[Str]
pub fn geo_geo_bbox_contains(min_lat: Float64, min_lon: Float64, max_lat: Float64, max_lon: Float64, lat: Float64, lon: Float64) -> Bool
```

Complexity: encode/decode/neighbors are `O(precision)`; clamp and bbox are
`O(1)`.

## 7. Error catalog

All messages are returned as the `Err` payload and are pinned verbatim by the
suite.

| Condition | Message |
|---|---|
| `precision < 1` or `precision > 12` | `geo: invalid precision` |
| `lat < -90` or `lat > 90` | `geo: latitude out of range` |
| `lon < -180` or `lon > 180` | `geo: longitude out of range` |
| `hash.len() == 0` | `geo: empty geohash` |
| `hash.len() > 12` | `geo: geohash too long` |
| a byte outside the base32 alphabet (including uppercase) | `geo: invalid geohash character` |

Validation order in encode: precision, then latitude, then longitude.
Decode checks length before characters, so `"u4pruydqqvj8x"` reports
`geo: geohash too long` even though every byte is a valid symbol. Bounds are
inclusive: `lat = +/-90`, `lon = +/-180` and `precision = 1` / `12` are valid.
`NaN` is not rejected by the range comparisons (it fails every `<`/`>` test)
and is outside the supported contract.

## 8. Test plan

`tests/test_conformance.xi` (module `geo_tests`) runs 21 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | known vector | `encode(57.64911, 10.40744, 11) == "u4pruydqqvj"` and `...12 == "u4pruydqqvj8"` |
| t2 | known vector shape | 12 characters, prefixes `u4pruyd` and `u4pruydqqvj` |
| t3 | precision lengths | precision 1..12 yields exactly `p` characters |
| t4 | zero point | `(0, 0)` -> `s` and `s00000000000` |
| t5 | decode center | `decode("u4pruydqqvj")` within 1e-4 of the input on both axes |
| t6 | round trips | 4 points (Denmark, null island, Sydney, Helsinki) encode/decode within 1e-4 |
| t7 | invalid precision | 0, 13, -1 -> exact message |
| t8 | invalid range | +/-90.5 and +/-180.5 -> exact messages |
| t9 | inclusive bounds | `(-90, -180)` and `(90, 180)` encode Ok |
| t10 | empty hash | `""` -> exact message |
| t11 | invalid characters | `!`, `a`, uppercase `U` -> exact message |
| t12 | too long | 13 characters -> exact message (length asserted via `str_len`) |
| t13 | precision 1 cell | `encode(..., 1) == "u"`; `decode("u")` center inside its 45-degree cell |
| t14 | neighbor set | exact N, NE, E, SE, S, SW, W, NW hashes of `u4pruydqqvj`, all decodable |
| t15 | neighbor distinctness | 8 distinct hashes, none equal to the center |
| t16 | cardinal signs | decoded N/E/S/W neighbors differ in the expected sign on the moved axis (within 1e-9 on the fixed axis) |
| t17 | bbox inside/outside | interior true; lat and lon outside false |
| t18 | bbox edges | corners inclusive |
| t19 | degenerate box | point box contains exactly itself |
| t20 | antimeridian box | `min_lon 170 > max_lon -170`: 175, -175, 170, -170 true; 0 false |
| t21 | clamp | lat +/-100, lon +/-200 clamp to the bounds; in-range values pass through |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Known limitations

- Geohash only; the other placeholder inventory entries are unimplemented.
- Decode returns the cell center, not the original coordinate; precision 12
  bounds the error at roughly 1.7e-7 degrees latitude.
- Precision is capped at 12 characters.
- Lowercase alphabet only; no case folding.
- Polar neighbors are latitude-clamped and may duplicate; 8 distinct
  neighbors are not guaranteed at the poles.
- `NaN` coordinates are not validated.
- No antimeridian wrap in `geo_clamp_lon` (it clamps: 200 -> 180).

## 10. Compiler / stdlib notes

The module follows the v0.61.3 idioms proven by the sibling ports:

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`,
  no `Vec[Float64]`.
- `Ok`/`Err` for `Result[Str, Str]` and `Result[GeoPoint, Str]` are
  constructed only in the leaf helpers `_ok_str`/`_err_str`/`_ok_point`/
  `_err_point` (constructing Results directly inside other functions
  miscompiles in this compiler).
- Byte-wise alphabet lookup uses `xiom.string.byte_at` against a `Str`
  constant whose bytes are all ASCII < 128, so the `UInt8` comparison is
  safe.
- The suite avoids reading `Str.len()` / `string.str_len()` on `Vec[Str]`
  elements (BUG 17 family: the length of an element read back from a
  `Vec[Str]` is unreliable). Element lengths are pinned by exact literal
  comparison instead; hard-coded `Str` literals and `Result` payloads do
  report correct lengths.
- No compiler workarounds beyond the above; `port.ps1` ends
  `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.
