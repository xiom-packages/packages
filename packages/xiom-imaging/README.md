# xiom.imaging

> **Status:** `incubating` -- conformance-tested (22/22); not yet published on the XIOM registry.
> **Scope:** one dependency-free module of deterministic, integer-only
> grayscale image kernels over an 8-bit pixel buffer with width/height/stride
> records: 3x3 box blur, separable 1-2-1 Gaussian blur, Sobel magnitude,
> binary and Otsu threshold, nearest and integer bilinear resize,
> flips/rotations, histogram and percentile, integral image with box-sum
> queries and an alpha-free overlay copy.
> **Deps:** none for the library module (it imports nothing); the tests use
> `xiom.test` and `xiom.io` from `xiom.std`.

## What it is

`xiom.imaging` is the pure-integer core of raster image processing. Every
public function is a pure function of its arguments: no floats, no FFI, no
I/O, no global state, no randomness. Samples are 8-bit grayscale values
(0 = black, 255 = white) stored row-major in a `Vec[UInt8]`; each row begins
at `y * stride` and only the first `width` bytes are data, so callers can
carry padded or borrowed layouts without copies.

The module provides the classical, hand-checkable kernels:

- **smoothing:** 3x3 box blur and a separable 1-2-1 Gaussian blur;
- **edges:** Sobel gradient magnitude (L1 norm, saturated);
- **segmentation:** strict binary threshold plus an automatic Otsu level
  computed from the 256-bin histogram;
- **statistics:** histogram and nearest-rank percentile;
- **resampling:** nearest-neighbor and integer bilinear resize;
- **geometry:** horizontal/vertical flip, rotate 90 clockwise, rotate 180;
- **queries:** summed-area integral image and half-open box sums;
- **compositing:** alpha-free overlay copy with clipping.

All neighbor reads replicate the edge, all rounding is documented integer
rounding, and every write into a `UInt8` buffer passes a saturation guard.
See `SPEC.md` for the exact kernels, rounding rules, bounds and error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `imaging_max_value()` | `Int` | Largest sample value (255). |
| `imaging_new(width, height, fill)` | `Result[GrayImage, Str]` | Allocate a filled image. |
| `imaging_from_pixels(width, height, stride, pixels)` | `Result[GrayImage, Str]` | Adopt a validated buffer. |
| `imaging_width(img)` / `imaging_height(img)` / `imaging_stride(img)` | `Int` | Layout accessors. |
| `imaging_pixel(img, x, y)` | `Int` | Sample 0..255, or -1 out of range. |
| `imaging_copy(img)` | `GrayImage` | Deep copy, compacted stride. |
| `imaging_box_blur(img)` | `GrayImage` | 3x3 average, `(sum + 4) / 9`. |
| `imaging_gaussian_blur(img)` | `GrayImage` | Separable `[1,2,1]/4` passes. |
| `imaging_sobel(img)` | `GrayImage` | `|gx| + |gy|`, saturated. |
| `imaging_threshold(img, t)` | `Result[GrayImage, Str]` | `v > t` -> 255 else 0. |
| `imaging_histogram(img)` | `Vec[Int]` | 256 bins, padding excluded. |
| `imaging_otsu_threshold(img)` | `Int` | Between-class variance maximizer. |
| `imaging_percentile(img, p)` | `Result[Int, Str]` | Nearest-rank percentile. |
| `imaging_resize_nearest(img, w, h)` | `Result[GrayImage, Str]` | Block replication. |
| `imaging_resize_bilinear(img, w, h)` | `Result[GrayImage, Str]` | 16-bit fixed weights. |
| `imaging_flip_horizontal(img)` / `imaging_flip_vertical(img)` | `GrayImage` | Mirrors. |
| `imaging_rotate90(img)` / `imaging_rotate180(img)` | `GrayImage` | Clockwise / half turn. |
| `imaging_integral(img)` | `Vec[Int]` | Summed-area table, zero border. |
| `imaging_box_sum(img, x0, y0, x1, y1)` | `Result[Int, Str]` | Half-open box sum. |
| `imaging_overlay_copy(dst, src, dx, dy)` | `GrayImage` | Opaque overwrite copy. |

```xi
use xiom.imaging;

let blurred = imaging_box_blur(img);        // img: GrayImage
let edges = imaging_sobel(blurred);
io.println(imaging_pixel(edges, 1, 1));     // sample 0..255, or -1 if outside
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: twenty-two `[PASS]` lines, then `xiom.imaging: all tests passed`,
exit 0.

## Install / publish

```
xiom pkg install xiom.imaging@0.1.0     # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
