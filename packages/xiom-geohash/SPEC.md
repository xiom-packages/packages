# xiom.geohash -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.geohash` (`src/geohash.xi`). Pure XIOM, no FFI.

## 1. Scope

An integer-only geohash codec over integer-microdegree coordinates:

- encode a validated coordinate to a canonical lowercase base32 geohash
  (`geohash_encode`),
- decode a geohash to its exact integer-microdegree cell box and center
  (`geohash_decode`),
- normalize a geohash to its canonical lowercase spelling
  (`geohash_normalize`),
- read box precision and bounds, test emptiness and inclusive containment
  (`geohash_box_precision`, `geohash_box_min_lat`, `geohash_box_min_lon`,
  `geohash_box_max_lat`, `geohash_box_max_lon`, `geohash_box_is_empty`,
  `geohash_box_contains`).

All arithmetic is exact integer arithmetic; no `Float64` and no `Vec` appear
in the module.

## 2. Non-goals

- No neighboring/adjacent-cell computation, no distance, bearing or area
  math, no polygons or geometry predicates.
- No projections or other coordinate systems (MGRS, UTM, GeoJSON, KML, GPX,
  shapefiles).
- No sub-microdegree input: floating-point degrees are the caller's concern.
- No configurable alphabet, no arbitrary precision beyond 12, no streaming
  APIs; every call is a pure function over its arguments.
- No FFI, file I/O, or registry integration.

## 3. Units and domain

- 1 degree = 1,000,000 microdegrees (`ud`); the module's suffix `_ud` uses
  this unit exclusively.
- Latitude domain: `[-90_000_000, 90_000_000]`, inclusive.
- Longitude domain: `[-180_000_000, 180_000_000]`, inclusive.
- Precision: `1..12` characters (`5 * precision` bits).
- `Int` is 64-bit in XIOM; the widest intermediate product in this module is
  `(2^30) * 360_000_000 ~= 3.87e17`, well inside the range.

## 4. Alphabet and bit interleaving

### 4.1 Alphabet

```
_GEOHASH_ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"
```

32 symbols: `0`-`9` (digit values 0-9) followed by the lowercase consonants
`b`-`z` minus `i`, `l`, `o` (values 10-31). Canonical output is lowercase.
`geohash_decode` and `geohash_normalize` fold ASCII `A`-`Z` to lowercase
before validation, so `"U4PRUYDQQVJ"` is valid; `"I"` is not, because `i` is
not in the alphabet.

### 4.2 Bit interleaving

For precision `p`, the hash carries `total = 5p` bits. With the ranges
starting as `lat [-90_000_000, 90_000_000]` and `lon [-180_000_000,
180_000_000]`, bits alternate **longitude first**: global bit 0 is a
longitude bit, bit 1 a latitude bit, and so on. Consequently:

```
lon_bits = ceil(5p / 2)      lat_bits = floor(5p / 2)
```

which gives one extra longitude bit when `5p` is odd. Within each 5-bit
character the first bit produced is the most significant bit (value 16).
The j-th bit of the emitted stream is bit `j` of the interleaving; the axis
cell index is the integer whose bits are the axis bits, most significant
first.

### 4.3 Exact integer bisection

The classic encoder narrows `[lo, hi]` and tests `x >= mid`. This module
computes the identical cell index without floats, as a bit-by-bit long
division: with `span = hi - lo` and `n` axis bits,

```
idx = floor((x - lo) * 2^n / span)
```

evaluated by repeating `rem = 2*rem; idx = 2*idx; if rem >= span { idx + 1;
rem - span }` exactly `n` times. A point on a cell boundary selects the upper
cell, and the inclusive upper bound (`lat = 90_000_000`,
`lon = 180_000_000`) folds to the northernmost/easternmost cell, because the
long division saturates at `2^n - 1`. Latitude and longitude are encoded
independently and then interleaved.

### 4.4 Worked example

`(lat, lon) = (57_649_110, 10_407_440)` (57.64911 N, 10.40744 E):

| Precision | Hash |
|---|---|
| 1 | `u` |
| 7 | `u4pruyd` |
| 11 | `u4pruydqqvj` |
| 12 | `u4pruydqqvj8` |

The 11-character value is the canonical Wikipedia example; the 12-character
extension, the prefixes above, and every vector in section 9 were
cross-checked against an independent implementation of the classic float
bisector. Further pinned vectors:

| Input (lat_ud, lon_ud, p) | Hash |
|---|---|
| `(0, 0, 1)` | `s` |
| `(0, 0, 12)` | `s00000000000` |
| `(90_000_000, 180_000_000, 12)` | `zzzzzzzzzzzz` |
| `(-90_000_000, -180_000_000, 12)` | `000000000000` |
| `(-90_000_000, 180_000_000, 12)` | `pbpbpbpbpbpb` |
| `(90_000_000, -180_000_000, 12)` | `bpbpbpbpbpbp` |
| `(90_000_000, 0, 12)` | `upbpbpbpbpbp` |
| `(-90_000_000, 0, 12)` | `h00000000000` |
| `(0, 180_000_000, 1)` | `x` |
| `(0, -180_000_000, 1)` | `8` |

## 5. Precision table

An axis cell is `180_000_000 / 2^lat_bits` ud (latitude) and
`360_000_000 / 2^lon_bits` ud (longitude). Degrees are the same value
divided by 1e6; `ud` values below are rounded for display (the exact values
are the fractions above, all powers of two).

| p | total bits | lon bits | lat bits | lat cell (deg) | lon cell (deg) | lat cell (ud) | lon cell (ud) |
|---|---|---|---|---|---|---|---|
| 1 | 5 | 3 | 2 | 45 | 45 | 45,000,000 | 45,000,000 |
| 2 | 10 | 5 | 5 | 5.625 | 11.25 | 5,625,000 | 11,250,000 |
| 3 | 15 | 8 | 7 | 1.40625 | 1.40625 | 1,406,250 | 1,406,250 |
| 4 | 20 | 10 | 10 | 0.17578125 | 0.3515625 | 175,781.25 | 351,562.5 |
| 5 | 25 | 13 | 12 | 0.04394531 | 0.04394531 | 43,945.3125 | 43,945.3125 |
| 6 | 30 | 15 | 15 | 0.00549316 | 0.01098633 | 5,493.1641 | 10,986.3281 |
| 7 | 35 | 18 | 17 | 0.00137329 | 0.00137329 | 1,373.2910 | 1,373.2910 |
| 8 | 40 | 20 | 20 | 0.00017166 | 0.00034332 | 171.6614 | 343.3228 |
| 9 | 45 | 23 | 22 | 0.00004292 | 0.00004292 | 42.9153 | 42.9153 |
| 10 | 50 | 25 | 25 | 0.00000536 | 0.00001073 | 5.3644 | 10.7288 |
| 11 | 55 | 28 | 27 | 0.00000134 | 0.00000134 | 1.3411 | 1.3411 |
| 12 | 60 | 30 | 30 | 0.00000017 | 0.00000034 | 0.1676 | 0.3353 |

Precisions 1..11 have axis cells wider than one ud, so every hash decodes to
a non-empty box. At precision 12 an axis cell can be thinner than one ud, so
a hash whose cell contains no integer point (and which therefore cannot be
produced by `geohash_encode` from integer input) decodes to an empty box.

## 6. Decoding and box semantics

Decoding replays the same interleaving: each character's five bits are
consumed MSB-first (masks 16, 8, 4, 2, 1) and appended to the longitude or
latitude index according to the global bit parity. With `n` axis bits, range
base `R0`, span `S` and index `k` (`0 <= k < 2^n`), the exact cell is
`[R0 + k*S/2^n, R0 + (k+1)*S/2^n)`. The reported box is the inclusive
integer-microdegree range whose points all re-encode to `k`:

```
min = R0 + ceil(k * S / 2^n)
max = R0 + ceil((k + 1) * S / 2^n) - 1        (k < 2^n - 1)
max = R0 + S                                   (k = 2^n - 1, the top cell)
center = (min + max) / 2                       (truncating integer division)
```

Properties (all pinned by the suite):

- For a non-empty box, `min <= center <= max`, all four corners and the
  center re-encode to the source hash, and the box contains exactly the
  integer points of the cell.
- An empty box has `min > max` on at least one axis
  (`geohash_box_is_empty`); `geohash_box_contains` always returns false for
  it. This can only happen at precision 12; the center formula remains
  deterministic and can fall up to one ud outside the true cell.
- Longitude `180_000_000` and `-180_000_000` are distinct cells; no
  antimeridian wrapping occurs anywhere in the module.

## 7. API signatures

```xi
pub type GeoBox = {
  precision: Int;
  min_lat_ud: Int;
  min_lon_ud: Int;
  max_lat_ud: Int;
  max_lon_ud: Int;
  center_lat_ud: Int;
  center_lon_ud: Int;
}

pub fn geohash_encode(lat_ud: Int, lon_ud: Int, precision: Int) -> Result[Str, Str]
pub fn geohash_decode(hash: Str) -> Result[GeoBox, Str]
pub fn geohash_normalize(hash: Str) -> Result[Str, Str]
pub fn geohash_box_precision(b: GeoBox) -> Int
pub fn geohash_box_min_lat(b: GeoBox) -> Int
pub fn geohash_box_min_lon(b: GeoBox) -> Int
pub fn geohash_box_max_lat(b: GeoBox) -> Int
pub fn geohash_box_max_lon(b: GeoBox) -> Int
pub fn geohash_box_is_empty(b: GeoBox) -> Bool
pub fn geohash_box_contains(b: GeoBox, lat_ud: Int, lon_ud: Int) -> Bool
```

Encode/decode/normalize are `O(precision)`; the accessors are `O(1)`.

## 8. Error catalog

All messages are returned as the `Err` payload and are pinned verbatim by the
suite.

| Condition | Message |
|---|---|
| `precision < 1` or `precision > 12` | `geohash: invalid precision` |
| `lat_ud < -90_000_000` or `lat_ud > 90_000_000` | `geohash: latitude out of range` |
| `lon_ud < -180_000_000` or `lon_ud > 180_000_000` | `geohash: longitude out of range` |
| `hash.len() == 0` | `geohash: empty geohash` |
| `hash.len() > 12` | `geohash: geohash too long` |
| a byte outside the alphabet after case folding (including `a`, `i`, `l`, `o`) | `geohash: invalid geohash character` |

Validation order in `geohash_encode` is precision, latitude, longitude;
`geohash_decode` and `geohash_normalize` check empty length, then too-long
length, then characters. Bounds are inclusive on both ends.

## 9. Test plan

`tests/test_conformance.xi` (module `geohash_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected hashes and boxes were produced by an
independent reference implementation of section 4 and cross-checked against
the classic float bisector.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | known vector | `(57649110, 10407440)` -> `u4pruydqqvj` (11), `u4pruydqqvj8` (12), `u4pruyd` (7), `u` (1) |
| t2 | precision lengths | precision 1..12 yields exactly `p` characters |
| t3 | zero point | `(0, 0)` -> `s`, `s00000000000` |
| t4 | range corners | the four lat/lon corners at precision 12 -> `z...z`, `0...0`, `pbpb...`, `bpbp...` |
| t5 | invalid precision | 0, 13, -1 -> exact message; precision checked before coordinates |
| t6 | invalid latitude | `+/-90_000_001` -> exact message |
| t7 | invalid longitude | `+/-180_000_001` -> exact message |
| t8 | known-vector box | exact bounds `[57649110, 57649111] x [10407440, 10407440]`, center, precision 11, accessors, inclusive containment and four rejections |
| t9 | 12-char extension | `u4pruydqqvj8` -> singleton box `(57649110, 10407440)` |
| t10 | zero-point box | `s00000000000` -> singleton `(0, 0)` box; neighbors excluded |
| t11 | pole/antimeridian cells | `z...z`, `0...0`, `xbpb...`, `h000...` decode to their edge boxes |
| t12 | length errors | `""` and a 13-character hash -> exact messages |
| t13 | invalid characters | `!`, `a`, `i`, `l`, `o`, uppercase `I`, space, and a mixed uppercase/`!` hash -> exact message |
| t14 | uppercase folding | `U4PRUYDQQVJ` decodes field-for-field like `u4pruydqqvj`; `normalize` emits lowercase |
| t15 | normalize | idempotent for lowercase; shared error catalog (empty, too long, invalid) |
| t16 | empty boxes | `ny6100000000` and `9qh100000000` decode to empty p=12 boxes with pinned bounds and centers |
| t17 | truncating centers | precision-1 cells `u`, `x`, `8` pin `(min+max)/2` truncation toward zero, including negative sums |
| t18 | round trip per precision | one point at every precision 1..12: box non-empty, contains the point, center and corners re-encode to the hash, and each hash is a prefix of the next |
| t19 | round trip four points | Denmark, null island, Sydney, Helsinki at precision 11 |
| t20 | antimeridian and poles | `x`/`8` distinct at `+/-180`, rounded at `+/-90`, all four edges round-trip at precision 12 |

Every `Str` comparison goes through `xiom.string.compare`'s `str_compare`,
never `==` (BUG 17 family), and the suite uses no `Vec` at all (no `Vec[fn]`
dispatch; the 20 test functions are called directly from `main`).

## 10. Known limitations

- **No neighbors.** Adjacent-cell computation is explicitly out of scope.
- **Precision cap 12.** Longer hashes are rejected; higher precision would
  add no integer information on the latitude axis beyond 27 bits anyway.
- **Empty precision-12 boxes.** Cells thinner than 1 ud admit no integer
  point; hashes for such cells are legal input but decode to an empty box.
- **Microdegree grid.** Sub-microdegree input must be rounded by the caller.
- **No antimeridian wrapping.** `+180` and `-180` are distinct cells.
- No configurable alphabet, no distance/area/polygon math, no projections.

## 11. Compiler / stdlib notes

The module follows the v0.61.3 idioms proven by the sibling ports:

- Free functions only; no `self` methods, no lambdas, no `Vec[Float64]`, and
  in fact no `Vec` at all.
- `Ok`/`Err` payloads are constructed only in the leaf helpers
  `_ok_str`/`_err_str`/`_ok_box`/`_err_box`.
- Every `xiom.string.byte_at` result is widened as `(x as Int) & 0xFF`
  before comparison; byte constants are masked the same way. All alphabet
  bytes are ASCII < 128.
- No string equality is performed in the module (the suite routes every
  comparison through `str_compare`).
- Case folding uses `xiom.string.str_lower` (ASCII `A`-`Z`), then validates
  the folded bytes, so uppercase is accepted without a second lookup table.
- `Int` division truncates toward zero (LLVM `sdiv`); the center formula
  documents and the suite pins that behavior, including negative sums.
- The only build output is advisory: passing `GeoBox` by value to accessors
  emits `warning[E001] use of moved value` under the current borrow checker.
  The warnings are benign (struct values are copied) and the suite is green:
  `port.ps1` ends
  `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.
