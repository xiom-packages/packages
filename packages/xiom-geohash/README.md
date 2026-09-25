# xiom.geohash

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), green under the
> repo harness. **NOT published** to the XIOM registry.
> **Scope:** an integer-only geohash codec: encode integer-microdegree
> coordinates to canonical lowercase base32 geohashes and decode them back to
> exact integer-microdegree cell boxes and centers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_lower`,
> `xiom.string.str_slice` and `xiom.string.byte_at`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.geohash` is a small, dependency-free codec for the standard geohash
base32 alphabet `"0123456789bcdefghjkmnpqrstuvwxyz"` (lowercase; the letters
`a`, `i`, `l`, `o` are not used). Precision is 1..12 characters.

Coordinates are carried as **integer microdegrees** (`ud`): 1 degree is
1,000,000 ud, latitude runs over `[-90_000_000, 90_000_000]` and longitude
over `[-180_000_000, 180_000_000]`, both inclusive. The codec uses integer
arithmetic exclusively -- no `Float64`, no platform-dependent rounding -- so
the same input always produces the same hash on every platform. Encoding is
exact integer bisection (bit-by-bit long division), which matches the classic
float bisector on every documented vector.

`geohash_encode` is canonical: it always emits lowercase. `geohash_decode`
and `geohash_normalize` accept uppercase ASCII input and fold it to
lowercase, so `"U4PRUYDQQVJ"` decodes exactly like `"u4pruydqqvj"`.

A decoded `GeoBox` is the inclusive integer-microdegree range whose points all
re-encode to the same hash, plus the box center. At precision 12 an axis cell
can be thinner than one microdegree, so a hash whose cell contains no integer
point decodes to an empty box (`min > max`, reported by
`geohash_box_is_empty`); such hashes are never produced by `geohash_encode`
from integer input. Precisions 1..11 always yield non-empty boxes.

## Quick start

```xi
use xiom.geohash;
use xiom.io;

fn main() -> Int {
  let h = geohash_encode(57649110, 10407440, 11);   // 57.64911N 10.40744E
  if h.is_ok { io.println(h.value); }               // u4pruydqqvj

  let d = geohash_decode("U4PRUYDQQVJ");            // uppercase is accepted
  if d.is_ok {
    let box = d.value;
    io.println("precision is 11");                  // box.precision == 11
    // box.min_lat_ud, box.max_lat_ud, box.min_lon_ud, box.max_lon_ud
    // box.center_lat_ud, box.center_lon_ud
  }

  let n = geohash_normalize("U4PRUYDQQVJ");
  if n.is_ok { io.println(n.value); }               // u4pruydqqvj
  return 0;
}
```

## Install

```
xiom pkg install xiom.geohash@0.1.0     # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## API

| Function | Returns | Description |
|---|---|---|
| `geohash_encode(lat_ud, lon_ud, precision)` | `Result[Str, Str]` | Encode integer-microdegree coordinates as a `precision`-character canonical lowercase geohash (precision 1..12). |
| `geohash_decode(hash)` | `Result[GeoBox, Str]` | Decode a 1..12 character hash (lowercase or uppercase ASCII) to its cell box and center. |
| `geohash_normalize(hash)` | `Result[Str, Str]` | Validate a hash and return its canonical lowercase spelling. |
| `geohash_box_precision(b)` | `Int` | Precision (character count) of the source hash. |
| `geohash_box_min_lat(b)` | `Int` | Lower latitude bound in microdegrees. |
| `geohash_box_min_lon(b)` | `Int` | Lower longitude bound in microdegrees. |
| `geohash_box_max_lat(b)` | `Int` | Upper latitude bound in microdegrees. |
| `geohash_box_max_lon(b)` | `Int` | Upper longitude bound in microdegrees. |
| `geohash_box_is_empty(b)` | `Bool` | True when the box contains no integer-microdegree point. |
| `geohash_box_contains(b, lat_ud, lon_ud)` | `Bool` | Inclusive containment of a point in the box. |

Type:

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
```

The center is the truncating integer division `(min + max) / 2`; inside a
non-empty box it re-encodes to the same hash, and so do all four box corners.
Complexity is `O(precision)` for encode/decode/normalize and `O(1)` for the
accessors.

## Error model

All failures are `Err(Str)` with deterministic messages; nothing panics and
no silent fallback exists.

| Condition | Message |
|---|---|
| `precision < 1` or `precision > 12` | `geohash: invalid precision` |
| `lat_ud < -90_000_000` or `lat_ud > 90_000_000` | `geohash: latitude out of range` |
| `lon_ud < -180_000_000` or `lon_ud > 180_000_000` | `geohash: longitude out of range` |
| `hash` is `""` | `geohash: empty geohash` |
| `hash.len() > 12` | `geohash: geohash too long` |
| a byte outside the alphabet after case folding (including `a`, `i`, `l`, `o`) | `geohash: invalid geohash character` |

Validation order in encode is precision, then latitude, then longitude;
decode and normalize check length (empty, too long) before characters, so
`"u4pruydqqvj8x"` reports `geohash: geohash too long` even though every byte
is a valid symbol. Bounds are inclusive: `lat = +/-90_000_000`,
`lon = +/-180_000_000`, `precision = 1` and `precision = 12` are all valid.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.geohash
```

Expected tail: 20 `[PASS]` lines, `xiom.geohash: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

The suite (`tests/test_conformance.xi`) pins the canonical vectors, the four
range corners, precision lengths 1..12, exact boxes and centers at precisions
1, 11 and 12, empty precision-12 boxes, the full error catalog, uppercase
folding, containment, and round trips at every precision. See `SPEC.md` for
the algorithm, the precision table and the test-to-semantics map.

## Limitations

- **No neighbors.** Adjacent-cell computation, distance, bearing, area,
  polygons and projections are out of scope.
- **Precision <= 12.** Encoded hashes have at most 12 characters; decoding
  rejects longer input with `Err("geohash: geohash too long")`.
- **Empty precision-12 boxes.** An axis cell at precision 12 is about
  0.17 ud (latitude) / 0.34 ud (longitude), so a hash whose cell contains no
  integer point decodes to a box with `min > max`; the center then falls up
  to one microdegree outside the true cell. Check `geohash_box_is_empty`.
- **Integer grid only.** Sub-microdegree input is not representable; callers
  must round before calling the codec.
- **No antimeridian wrapping.** Longitude `+180_000_000` and
  `-180_000_000` are distinct edge cells (`"x"` and `"8"` at precision 1);
  the codec never wraps a coordinate from one to the other.
- No configurable alphabet, no arbitrary precision, no streaming API.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
