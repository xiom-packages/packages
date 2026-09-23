# xiom.geo

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** geohash encoding/decoding for WGS84 coordinates, plus
> latitude/longitude clamping and inclusive bounding-box containment.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.str_slice`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## Scope

`xiom.geo` is a small, dependency-free geohash module. It encodes a
latitude/longitude pair into the standard base32 geohash string and decodes a
geohash back to the center of the cell it names. It also exposes two
coordinate helpers (`geo_clamp_lat`, `geo_clamp_lon`) and inclusive
bounding-box containment that can cross the antimeridian.

The base32 alphabet is `"0123456789bcdefghjkmnpqrstuvwxyz"` (lowercase; the
letters `a`, `i`, `l`, `o` are not used). Precision is limited to 1..12
characters. The canonical example in this module's tests is the Wikipedia
pair `57.64911, 10.40744`; the well-known 11-character geohash is
`u4pruydqqvj`, and the 12-character extension is `u4pruydqqvj8`.

Everything is computed with `Float64` interval bisection; the module contains
no FFI, no allocation tricks, and no platform-specific code.

## API

| Function | Returns | Description |
|---|---|---|
| `geo_clamp_lat(lat)` | `Float64` | Clamp a latitude into `[-90, 90]`. |
| `geo_clamp_lon(lon)` | `Float64` | Clamp a longitude into `[-180, 180]` (clamps, never wraps). |
| `geo_geohash_encode(lat, lon, precision)` | `Result[Str, Str]` | Encode a validated coordinate as a `precision`-character geohash (1..12). |
| `geo_geohash_decode(hash)` | `Result[GeoPoint, Str]` | Decode a 1..12 character geohash to the latitude/longitude of its cell **center**. |
| `geo_geohash_neighbors(hash)` | `Vec[Str]` | The 8 neighboring cells in N, NE, E, SE, S, SW, W, NW order (empty for an invalid hash). |
| `geo_geo_bbox_contains(min_lat, min_lon, max_lat, max_lon, lat, lon)` | `Bool` | Inclusive box containment; `min_lon > max_lon` means the box crosses the antimeridian. |

Type: `GeoPoint = { lat: Float64; lon: Float64; }` -- decimal degrees on the
WGS84 datum.

## Usage

```xi
use xiom.geo;
use xiom.io;

fn main() -> Int {
  let h = geo_geohash_encode(57.64911, 10.40744, 11);
  if h.is_ok { io.println(h.value); }        // u4pruydqqvj

  let p = geo_geohash_decode("u4pruydqqvj");
  if p.is_ok { io.println("decoded to the cell center"); }

  let ns = geo_geohash_neighbors("u4pruydqqvj");
  io.println(ns[0]);                         // u4pruydqqvm (N)

  if geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, 175.0) {
    io.println("inside the antimeridian box");
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.geo
```

Expected tail: 21 `[PASS]` lines, `xiom.geo: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

The suite (`tests/test_conformance.xi`) pins the known vector, precision
lengths, decode centers and round trips, the full error catalog, the exact
8-neighborhood of `u4pruydqqvj`, antimeridian and inclusive bounding boxes,
and clamping. See `SPEC.md` for the test-to-semantics map.

## Limitations

- **Geohash only.** GeoJSON, KML, GPX, shapefiles, MGRS, UTM and projections
  from the placeholder inventory are not implemented.
- **Cell-center decode.** `geo_geohash_decode` returns the center of the cell,
  not the original input; the accuracy is bounded by the cell size
  (about 1.7e-7 degrees latitude at precision 12) and the caller must not
  treat the result as the exact coordinate.
- **Precision <= 12.** Encoded hashes have at most 12 characters; decoding
  rejects anything longer with `Err("geo: geohash too long")`.
- **Lowercase alphabet.** Uppercase letters are rejected as invalid
  characters (no case folding).
- **Neighborhood edge cases.** Latitude is clamped at the poles, so a polar
  cell's north/south neighbor can repeat the cell or another neighbor, and
  the 8 entries are not guaranteed distinct there. Longitude wraps at the
  antimeridian.
- **Boxes.** `min_lat <= max_lat` is required (no enforcement); `NaN`
  coordinates are not validated and propagate comparison results.
- No typed conversion to/from other coordinate encodings, no distance or
  area functions, no streaming API.

See `SPEC.md` for the algorithm, the error catalog and the test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
