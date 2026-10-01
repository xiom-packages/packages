# xiom.imaging SPEC

## Scope

Pure-XIOM, integer-only grayscale image processing over an 8-bit pixel
buffer. One module (`src/imaging.xi`, `module xiom.imaging`) implements
smoothing, edge detection, thresholding, statistics, resampling, geometry,
integral queries and alpha-free compositing. No floats, no FFI, no I/O, no
randomness; every function is a pure function of its arguments.

## Non-goals

Color and alpha channels, 16-bit or float samples, gamma/color management,
JPEG/PNG/TIFF containers (see `xiom.png`/`xiom.bmp`), filters beyond the
listed kernels, morphological operators, FFT, connected components,
anti-aliased rotation, and any stateful pipeline object.

## Representation

```xiom
pub type GrayImage = {
  width: Int;    // >= 1, samples per row (image columns)
  height: Int;   // >= 1, number of rows
  stride: Int;   // >= width, bytes per stored row
  pixels: Vec[UInt8];  // row-major, height * stride bytes
}
```

Sample `(x, y)` lives at `y * stride + x`. The `stride - width` trailing
bytes of each row are padding: no kernel reads or writes them, histogram and
statistics ignore them. Constructors enforce `width >= 1`, `height >= 1`,
`stride >= width`, `pixels.len() == stride * height`. Every image returned by
a kernel has `stride == width` (compacted); `imaging_copy` and every
`Result`-returning producer preserve only dimensions.

## Public API

```xiom
pub fn imaging_max_value() -> Int
pub fn imaging_new(width: Int, height: Int, fill: Int) -> Result[GrayImage, Str]
pub fn imaging_from_pixels(width: Int, height: Int, stride: Int, pixels: Vec[UInt8]) -> Result[GrayImage, Str]
pub fn imaging_width(img: &GrayImage) -> Int
pub fn imaging_height(img: &GrayImage) -> Int
pub fn imaging_stride(img: &GrayImage) -> Int
pub fn imaging_pixel(img: &GrayImage, x: Int, y: Int) -> Int
pub fn imaging_copy(img: &GrayImage) -> GrayImage
pub fn imaging_box_blur(img: &GrayImage) -> GrayImage
pub fn imaging_gaussian_blur(img: &GrayImage) -> GrayImage
pub fn imaging_sobel(img: &GrayImage) -> GrayImage
pub fn imaging_threshold(img: &GrayImage, t: Int) -> Result[GrayImage, Str]
pub fn imaging_histogram(img: &GrayImage) -> Vec[Int]
pub fn imaging_otsu_threshold(img: &GrayImage) -> Int
pub fn imaging_percentile(img: &GrayImage, p: Int) -> Result[Int, Str]
pub fn imaging_resize_nearest(img: &GrayImage, new_w: Int, new_h: Int) -> Result[GrayImage, Str]
pub fn imaging_resize_bilinear(img: &GrayImage, new_w: Int, new_h: Int) -> Result[GrayImage, Str]
pub fn imaging_flip_horizontal(img: &GrayImage) -> GrayImage
pub fn imaging_flip_vertical(img: &GrayImage) -> GrayImage
pub fn imaging_rotate90(img: &GrayImage) -> GrayImage
pub fn imaging_rotate180(img: &GrayImage) -> GrayImage
pub fn imaging_integral(img: &GrayImage) -> Vec[Int]
pub fn imaging_box_sum(img: &GrayImage, x0: Int, y0: Int, x1: Int, y1: Int) -> Result[Int, Str]
pub fn imaging_overlay_copy(dst: &GrayImage, src: &GrayImage, dx: Int, dy: Int) -> GrayImage
```

## Rounding and saturation

XIOM `/` truncates toward zero. All values here are non-negative, so
division and modulo are plain truncating operators. Rounding is
nearest-integer with exact halves rounding up:

| Kernel | Rule |
|---|---|
| box blur | `(sum + 4) / 9` over the 9-neighborhood |
| Gaussian, horizontal | `(s + 2) / 4`, `s = p(x-1) + 2p(x) + p(x+1)` |
| Gaussian, vertical | `(s + 2) / 4` on the horizontal-pass result |
| bilinear | `(sum + 32768) / 65536` on 16-bit fixed weights |
| threshold | exact, no rounding (`v > t` -> 255 else 0) |
| Otsu class means | truncating `sum / count` |

Every value written to a `UInt8` passes the 0..255 guard; blur outputs are
convex combinations that cannot leave the input range, threshold outputs are
0/255, and the Sobel L1 magnitude (`|gx| + |gy|`, no square root) can exceed
255 and saturates.

## Kernels

Box blur (per sample, edge-replicated coordinates):

```
       p(x-1,y-1) p(x,y-1) p(x+1,y-1)
sum =  p(x-1,y)   p(x,y)   p(x+1,y)
       p(x-1,y+1) p(x,y+1) p(x+1,y+1)
out = (sum + 4) / 9
```

Gaussian blur: separable integer kernel `[1, 2, 1] / 4` applied
horizontally, then vertically, with `(s + 2) / 4` rounding per pass. The
effective 2D weights are:

```
1 2 1
2 4 2      / 16, with per-pass (not single /16) rounding
1 2 1
```

Sobel (edge replication at borders):

```
gx = (p(x+1,y-1) + 2p(x+1,y) + p(x+1,y+1)) - (p(x-1,y-1) + 2p(x-1,y) + p(x-1,y+1))
gy = (p(x-1,y+1) + 2p(x,y+1) + p(x+1,y+1)) - (p(x-1,y-1) + 2p(x,y-1) + p(x+1,y-1))
out = min(255, |gx| + |gy|)
```

A flat image maps to 0 everywhere. For a horizontal ramp `0, 10, 20` (three
identical rows) the center gradient is `|80| + 0 = 80`; for a vertical step
`0 0 255` per row the step column saturates at 255.

## Thresholding and statistics

- `imaging_threshold(img, t)` requires `t` in 0..255 and emits 255 exactly
  where `v > t` (strict). `threshold(img, imaging_otsu_threshold(img))`
  therefore splits the two Otsu classes.
- `imaging_histogram(img)` returns 256 `Int` bins; bin `i` counts samples
  equal to `i`; counts sum to `width * height`.
- `imaging_otsu_threshold(img)` maximizes `w0 * w1 * (mean0 - mean1)^2` over
  `t` in 0..254 with both classes non-empty, means truncated by integer
  division; ties keep the smallest `t`. A single-level image returns its only
  level; an empty image returns 0.
- `imaging_percentile(img, p)` (p in 0..100) is nearest-rank:
  `k = (p * n + 99) / 100` clamped to 1..n, then the k-th smallest sample.
  p=0 is the minimum, p=100 the maximum.

## Resampling

Nearest: target `(x, y)` samples source `(x * width / new_w, y * height / new_h)`
with truncating division. Same-size resize is an exact copy; integer
upscales replicate blocks.

Bilinear: source coordinates use 16-bit fixed point,
`q = (i * (src_n - 1) * 256) / (dst_n - 1)` (0 when either side has one
sample), split into `ix = q / 256`, `fx = q % 256`; the second sample is
`min(ix + 1, src_n - 1)`. With
`w00 = (256-fx)(256-fy)`, `w10 = fx(256-fy)`, `w01 = (256-fx)fy`,
`w11 = fx*fy`:

```
out = (v00*w00 + v10*w10 + v01*w01 + v11*w11 + 32768) / 65536
```

The weights sum to 65536, so constant images stay constant and a same-size
resize is an exact copy. Example (hand-checked): `[0, 100]` (2x1) resized to
3x1 gives `[0, 50, 100]`.

## Geometry

- `flip_horizontal`: `(x, y) -> (width - 1 - x, y)`.
- `flip_vertical`: `(x, y) -> (x, height - 1 - y)`.
- `rotate90` (clockwise): output is `height x width` with
  `out(nx, ny) = in(ny, height - 1 - nx)`.
- `rotate180`: horizontal flip then vertical flip.

## Integral image and box queries

`imaging_integral` returns a `(width + 1) x (height + 1)` row-major
`Vec[Int]` with zero first row/column and

```
I(x+1, y+1) = p(x, y) + I(x, y+1) + I(x+1, y) - I(x, y)
```

Entry `(x, y)` is at `y * (width + 1) + x`.

`imaging_box_sum(img, x0, y0, x1, y1)` sums the half-open box
`[x0, x1) x [y0, y1)`:

```
sum = I(x1, y1) - I(x0, y1) - I(x1, y0) + I(x0, y0)
```

An empty box is 0; negative or beyond-image coordinates are errors, as is
`x0 > x1` or `y0 > y1`.

## Compositing

`imaging_overlay_copy(dst, src, dx, dy)` returns a copy of `dst` with
`src(sx, sy)` written to `(dx + sx, dy + sy)` whenever that target is inside
`dst`; other samples keep their `dst` value. There is no blending and no
alpha channel: this is an opaque overwrite copy. Negative offsets clip the
source's top/left; oversize sources clip at the right/bottom; a source that
misses `dst` entirely copies nothing. The result is always `dst`-sized.

## Bounds and error catalog

- Neighbor reads in blur/Sobel always clamp coordinates to
  `[0, width-1] x [0, height-1]` (edge replication); borders need no special
  cases.
- `imaging_pixel` returns -1 outside the image instead of reading.
- Every loop is a counted `while` with a strictly increasing counter, so all
  kernels terminate; the suite finishes in seconds on tiny fixtures and all
  kernels are `O(width * height)` (`O(width * height + 256)` for
  histogram/Otsu/percentile, `O(width * height + 1)` for box sums).

| Condition | Message |
|---|---|
| `imaging_new` width <= 0 | `imaging: invalid width` |
| `imaging_new` height <= 0 | `imaging: invalid height` |
| `imaging_new` fill outside 0..255 | `imaging: fill out of range` |
| `imaging_from_pixels` width/height <= 0 | `imaging: invalid width` / `imaging: invalid height` |
| `imaging_from_pixels` stride < width | `imaging: invalid stride` |
| `imaging_from_pixels` payload length != stride * height | `imaging: pixel buffer size mismatch` |
| `imaging_threshold` t outside 0..255 | `imaging: threshold out of range` |
| `imaging_percentile` p outside 0..100 | `imaging: percentile out of range` |
| `imaging_percentile` width * height == 0 | `imaging: empty image` |
| resize target <= 0 | `imaging: invalid width` / `imaging: invalid height` |
| box coordinate negative or beyond image | `imaging: box out of bounds` |
| box with x0 > x1 or y0 > y1 | `imaging: invalid box` |

## Test plan

`tests/test_conformance.xi`, 22 checks: constructor/accessor/bounds reads;
strided `from_pixels` validation and padding invisibility; box blur
hand-computed center/corners plus rounding (4/9 -> 0, 5/9 -> 1) and constant
fixed point; Gaussian weights on `1..9`, constant fixed point and the
`[1,2,1]` profile; Sobel flat-zero, saturated vertical edge and exact integer
ramp (80/40); strict binary threshold and range errors; Otsu on a bimodal
`10/200` image (level 10, class split) and the single-level edge case;
histogram bins/size/total; nearest-rank percentiles and range errors;
integral prefix sums; box sums including empty and error boxes; nearest
2x2 -> 4x4 block exactness, identity and target validation; bilinear
`[0, 100] -> [0, 50, 100]`, identity and constant preservation; flips;
rotate 90 clockwise (square and 2x3 -> 3x2) and rotate 180; overlay copy,
clipping, negative offset and full miss; stride-compacting copy.

## Known limitations

- Only 8-bit grayscale samples; no color/alpha/16-bit/float paths.
- Bilinear resize interpolates at image centers via the `(src-1)/(dst-1)`
  mapping; no half-pixel/area-averaging variant.
- Otsu is global; no local/adaptive thresholding.
- Rotations are exact 90-degree multiples; no arbitrary-angle resampling.
- Kernels allocate a fresh output image per call; there is no in-place or
  streaming variant.
- Very large boxes are limited by `Int` range, not checked.
