// XIOM -- xiom.imaging: pure deterministic grayscale image processing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Integer-only, allocation-explicit image kernels over an 8-bit grayscale
// buffer. No floats, no FFI, no I/O, no randomness: every public function is
// a pure function of its arguments and every result is bit-for-bit
// reproducible.
//
// Representation: GrayImage is a dense record of width, height, stride and a
// row-major Vec[UInt8] of samples. A row starts at y * stride; only the first
// width bytes of each row are image data (stride >= width, padding bytes are
// never read or written by any kernel). Constructors (imaging_new,
// imaging_from_pixels) enforce the invariants; every derived image returned by
// this module has stride == width (compacted) unless it is a direct copy of an
// input's layout (none: every constructor and producer compacts).
//
// Rounding: XIOM lowers `/` to truncation toward zero. Every kernel here works
// on non-negative integers only, so division and modulo are the plain
// truncating operators and the documented rounding is exact:
//   * box blur      (sum + 4) / 9     -- nearest, ties away from zero (up)
//   * Gaussian 1D   (sum + 2) / 4     -- nearest, ties up, applied per pass
//   * Gaussian 2D   equal to weights 1 2 1 / 2 4 2 / 1 2 1 over 16 with
//                   per-pass rounding instead of one /16 division
//   * bilinear      (sum + 32768) / 65536 -- nearest on 16-bit fixed weights
//   * division      truncation toward zero, only on non-negative values
//
// Saturation: every sample written back into a UInt8 buffer passes through a
// 0..255 guard (_img_clamp255). Sobel magnitudes are |gx| + |gy| (L1 norm),
// so an edge can exceed 255 and saturates. Blur outputs are convex
// combinations and threshold outputs are 0/255; the guard is defensive there.
//
// Bounds: every kernel clamps neighbor coordinates to the image rectangle
// (edge replication), so borders need no special cases. Public readers
// (imaging_pixel) return -1 out of range; public writers/constructors reject
// invalid sizes and payloads through Result. All loops are counted while
// loops whose counters strictly increase, so every loop terminates.
//
// v0.62.2 notes that shaped this module: no vectors of strings, no methods,
// no lambdas, no vectors of structs, no mutable scalar-reference parameters;
// vector elements are always read into typed locals; Ok/Err construction is
// confined to the leaf helpers at the bottom. See SPEC.md for the kernel
// tables, rounding rules, bounds and the error catalog.

module xiom.imaging

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// 8-bit grayscale image.
///
/// `pixels` holds `height` rows of `stride` bytes each, row-major; the first
/// `width` bytes of every row are samples (0 = black, 255 = white), the
/// remaining `stride - width` bytes are padding that no kernel reads or
/// writes. `width` and `height` are >= 1 and `stride` is >= `width`; both
/// constructors enforce this. Fields are public for inspection; producers in
/// this module always return `stride == width`.
pub type GrayImage = {
  width: Int;
  height: Int;
  stride: Int;
  pixels: Vec[UInt8];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Largest sample value (white).
/// Complexity: O(1).
pub fn imaging_max_value() -> Int {
  return 255;
}

// --------------------------------------------------
//  Scalar and coordinate helpers (private)
// --------------------------------------------------

// Smaller of a and b.
fn _img_imin(a: Int, b: Int) -> Int {
  if (a < b) { return a; }
  return b;
}

// v clamped to [lo, hi]; callers guarantee lo <= hi.
fn _img_clamp(v: Int, lo: Int, hi: Int) -> Int {
  if (v < lo) { return lo; }
  if (v > hi) { return hi; }
  return v;
}

// v clamped to the 0..255 sample range.
fn _img_clamp255(v: Int) -> Int {
  return _img_clamp(v, 0, 255);
}

// Nearest-integer division (sum + div / 2) / div for sum >= 0, div > 0;
// exact halves round up (away from zero).
fn _img_div_round(sum: Int, div: Int) -> Int {
  return (sum + div / 2) / div;
}

// Clamped column coordinate: x outside [0, width-1] replicates the border.
fn _img_cx(img: &GrayImage, x: Int) -> Int {
  return _img_clamp(x, 0, img.width - 1);
}

// Clamped row coordinate: y outside [0, height-1] replicates the border.
fn _img_cy(img: &GrayImage, y: Int) -> Int {
  return _img_clamp(y, 0, img.height - 1);
}

// Row-major offset of in-bounds (x, y): y * stride + x.
fn _img_at(img: &GrayImage, x: Int, y: Int) -> Int {
  return y * img.stride + x;
}

// Sample (x, y), caller guarantees 0 <= x < width, 0 <= y < height.
// Returns 0..255.
fn _img_raw(img: &GrayImage, x: Int, y: Int) -> Int {
  let v: Int = (img.pixels[_img_at(img, x, y)] as Int) & 0xFF;
  return v;
}

// Sample at (x, y) with both coordinates edge-clamped to the image
// rectangle. Returns 0..255.
fn _img_px(img: &GrayImage, x: Int, y: Int) -> Int {
  return _img_raw(img, _img_cx(img, x), _img_cy(img, y));
}

// Sample of a compact auxiliary buffer (stride == width) with a clamped row.
fn _img_tp(buf: &Vec[UInt8], w: Int, x: Int, y: Int) -> Int {
  let v: Int = (buf[y * w + x] as Int) & 0xFF;
  return v;
}

// Fixed-point source coordinate for integer bilinear resize, 8 fraction bits:
// q = (i * (src_n - 1) * 256) / (dst_n - 1). Returns 0 when either side has
// a single sample (no interpolation is possible or needed). The fractional
// part is q % 256 and the base index and its clamped successor are q / 256
// and min(q / 256 + 1, src_n - 1).
fn _img_coord_q(i: Int, src_n: Int, dst_n: Int) -> Int {
  if (src_n <= 1 || dst_n <= 1) { return 0; }
  return (i * (src_n - 1) * 256) / (dst_n - 1);
}

// Sum over the 256 histogram bins of level * count (the raw sample total).
fn _img_hist_total(hist: &Vec[Int]) -> Int {
  var s = 0;
  var i = 0;
  while (i < 256) {
    let c: Int = hist[i];
    s = s + i * c;
    i = i + 1;
  }
  return s;
}

// --------------------------------------------------
//  Constructors and accessors
// --------------------------------------------------

/// Allocate a width x height image filled with `fill` (0..255), stride ==
/// width. Errors: "imaging: invalid width" / "imaging: invalid height" for
/// non-positive dimensions, "imaging: fill out of range" for fill outside
/// 0..255. Complexity: O(width * height).
pub fn imaging_new(width: Int, height: Int, fill: Int) -> Result[GrayImage, Str] {
  if (width <= 0) { return _img_err_img("imaging: invalid width"); }
  if (height <= 0) { return _img_err_img("imaging: invalid height"); }
  if (fill < 0 || fill > 255) { return _img_err_img("imaging: fill out of range"); }
  let out = Vec[UInt8].new();
  let n = width * height;
  var i = 0;
  while (i < n) {
    out.push(fill as UInt8);
    i = i + 1;
  }
  let img = GrayImage{ width: width; height: height; stride: width; pixels: out; };
  return _img_ok_img(img);
}

/// Adopt an existing pixel buffer. Requires width >= 1, height >= 1,
/// stride >= width and exactly stride * height bytes of payload; padding
/// bytes inside a row are preserved and never read by kernels (except through
/// this exact layout). Errors: "imaging: invalid width", "imaging: invalid
/// height", "imaging: invalid stride", "imaging: pixel buffer size mismatch".
/// Complexity: O(1).
pub fn imaging_from_pixels(width: Int, height: Int, stride: Int, pixels: Vec[UInt8]) -> Result[GrayImage, Str] {
  if (width <= 0) { return _img_err_img("imaging: invalid width"); }
  if (height <= 0) { return _img_err_img("imaging: invalid height"); }
  if (stride < width) { return _img_err_img("imaging: invalid stride"); }
  if (pixels.len() != stride * height) { return _img_err_img("imaging: pixel buffer size mismatch"); }
  let img = GrayImage{ width: width; height: height; stride: stride; pixels: pixels; };
  return _img_ok_img(img);
}

/// Image width in samples (>= 1).
/// Complexity: O(1).
pub fn imaging_width(img: &GrayImage) -> Int {
  return img.width;
}

/// Image height in samples (>= 1).
/// Complexity: O(1).
pub fn imaging_height(img: &GrayImage) -> Int {
  return img.height;
}

/// Row stride in bytes (>= width).
/// Complexity: O(1).
pub fn imaging_stride(img: &GrayImage) -> Int {
  return img.stride;
}

/// Sample at (x, y) as 0..255, or -1 when the coordinate is outside the
/// image. Complexity: O(1).
pub fn imaging_pixel(img: &GrayImage, x: Int, y: Int) -> Int {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) { return -1; }
  return _img_raw(img, x, y);
}

/// Deep copy with the same width and height, compacted to stride == width.
/// Complexity: O(width * height).
pub fn imaging_copy(img: &GrayImage) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      out.push(_img_raw(img, x, y) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

// --------------------------------------------------
//  Smoothing kernels
// --------------------------------------------------

/// 3x3 box blur: each sample becomes the average of its 3x3 neighborhood with
/// edge replication, rounded to nearest by (sum + 4) / 9. The result has the
/// same dimensions, compacted to stride == width. Constant images are exact
/// fixed points (sum = 9v -> v). Complexity: O(width * height).
pub fn imaging_box_blur(img: &GrayImage) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      var sum = 0;
      var dy = -1;
      while (dy <= 1) {
        var dx = -1;
        while (dx <= 1) {
          sum = sum + _img_px(img, x + dx, y + dy);
          dx = dx + 1;
        }
        dy = dy + 1;
      }
      out.push(_img_div_round(sum, 9) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

/// Separable Gaussian-ish blur with the integer kernel [1, 2, 1] / 4 applied
/// horizontally then vertically, each pass rounded by (sum + 2) / 4 with edge
/// replication. The effective 2D weights are
///   1 2 1
///   2 4 2
///   1 2 1
/// over 16, except that rounding happens per pass (not once at /16), which is
/// documented and deterministic. Constant images are exact fixed points.
/// Result dimensions match the input. Complexity: O(width * height).
pub fn imaging_gaussian_blur(img: &GrayImage) -> GrayImage {
  let w = img.width;
  let tmp = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let s = _img_px(img, x - 1, y) + 2 * _img_px(img, x, y) + _img_px(img, x + 1, y);
      tmp.push(_img_div_round(s, 4) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let out = Vec[UInt8].new();
  var y2 = 0;
  while (y2 < img.height) {
    let ym = _img_cy(img, y2 - 1);
    let yp = _img_cy(img, y2 + 1);
    var x2 = 0;
    while (x2 < w) {
      let s2 = _img_tp(tmp, w, x2, ym) + 2 * _img_tp(tmp, w, x2, y2) + _img_tp(tmp, w, x2, yp);
      out.push(_img_div_round(s2, 4) as UInt8);
      x2 = x2 + 1;
    }
    y2 = y2 + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

/// Sobel gradient magnitude with edge replication:
///   gx = (p(x+1,y-1) + 2p(x+1,y) + p(x+1,y+1)) - (p(x-1,y-1) + 2p(x-1,y) + p(x-1,y+1))
///   gy = (p(x-1,y+1) + 2p(x,y+1) + p(x+1,y+1)) - (p(x-1,y-1) + 2p(x,y-1) + p(x+1,y-1))
/// The magnitude is the L1 norm |gx| + |gy| (no square root), saturated to
/// 255. Flat images map to 0 everywhere. Complexity: O(width * height).
pub fn imaging_sobel(img: &GrayImage) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let gx = (_img_px(img, x + 1, y - 1) + 2 * _img_px(img, x + 1, y) + _img_px(img, x + 1, y + 1))
             - (_img_px(img, x - 1, y - 1) + 2 * _img_px(img, x - 1, y) + _img_px(img, x - 1, y + 1));
      let gy = (_img_px(img, x - 1, y + 1) + 2 * _img_px(img, x, y + 1) + _img_px(img, x + 1, y + 1))
             - (_img_px(img, x - 1, y - 1) + 2 * _img_px(img, x, y - 1) + _img_px(img, x + 1, y - 1));
      var ax = gx;
      if (ax < 0) { ax = 0 - ax; }
      var ay = gy;
      if (ay < 0) { ay = 0 - ay; }
      out.push(_img_clamp255(ax + ay) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

// --------------------------------------------------
//  Thresholding, histogram and percentile
// --------------------------------------------------

/// Binary threshold: every sample strictly greater than `t` becomes 255,
/// every other sample becomes 0. `t` must be in 0..255, otherwise
/// "imaging: threshold out of range". The strict comparison means
/// threshold(img, t) recovers the two Otsu classes whenever
/// imaging_otsu_threshold returns t. Complexity: O(width * height).
pub fn imaging_threshold(img: &GrayImage, t: Int) -> Result[GrayImage, Str] {
  if (t < 0 || t > 255) { return _img_err_img("imaging: threshold out of range"); }
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let v = _img_raw(img, x, y);
      if (v > t) {
        out.push(255 as UInt8);
      } else {
        out.push(0 as UInt8);
      }
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return _img_ok_img(res);
}

/// 256-bin histogram of the image samples (padding bytes excluded); bin i
/// counts samples equal to i, and the counts sum to width * height.
/// Complexity: O(width * height).
pub fn imaging_histogram(img: &GrayImage) -> Vec[Int] {
  let hist = Vec[Int].new();
  var i = 0;
  while (i < 256) {
    hist.push(0);
    i = i + 1;
  }
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      let v = _img_raw(img, x, y);
      let c: Int = hist[v];
      hist[v] = c + 1;
      x = x + 1;
    }
    y = y + 1;
  }
  return hist;
}

/// Otsu threshold: the level t in 0..254 maximizing the between-class
/// variance of the two groups {v <= t} and {v > t}. Class means are
/// computed with truncating integer division and the score is
/// w0 * w1 * (mean0 - mean1)^2, evaluated for every t with both classes
/// non-empty; ties keep the smallest t. A single-level image (no valid
/// split) returns its only level, an empty image returns 0.
/// Complexity: O(width * height + 256).
pub fn imaging_otsu_threshold(img: &GrayImage) -> Int {
  let hist = imaging_histogram(img);
  let n = img.width * img.height;
  if (n <= 0) { return 0; }
  let total = _img_hist_total(&hist);
  var best_t = 0;
  var best_v = -1;
  var w0 = 0;
  var s0 = 0;
  var t = 0;
  while (t <= 254) {
    let c: Int = hist[t];
    w0 = w0 + c;
    s0 = s0 + t * c;
    let w1 = n - w0;
    if (w0 > 0 && w1 > 0) {
      let m0 = s0 / w0;
      let m1 = (total - s0) / w1;
      let d = m0 - m1;
      let between = w0 * w1 * d * d;
      if (between > best_v) {
        best_v = between;
        best_t = t;
      }
    }
    t = t + 1;
  }
  if (best_v < 0) {
    var i = 0;
    while (i < 256) {
      let c: Int = hist[i];
      if (c > 0) { return i; }
      i = i + 1;
    }
    return 0;
  }
  return best_t;
}

/// Nearest-rank percentile of the sample values: k = ceil(p * n / 100) with
/// p in 0..100 goes through (p * n + 99) / 100, is clamped to 1..n, and the
/// k-th smallest sample is returned. p = 0 yields the minimum, p = 100 the
/// maximum. Errors: "imaging: percentile out of range" for p outside 0..100,
/// "imaging: empty image" when width * height is 0.
/// Complexity: O(width * height + 256).
pub fn imaging_percentile(img: &GrayImage, p: Int) -> Result[Int, Str] {
  if (p < 0 || p > 100) { return _img_err_int("imaging: percentile out of range"); }
  let n = img.width * img.height;
  if (n <= 0) { return _img_err_int("imaging: empty image"); }
  let hist = imaging_histogram(img);
  var k = (p * n + 99) / 100;
  if (k < 1) { k = 1; }
  if (k > n) { k = n; }
  var cum = 0;
  var i = 0;
  while (i < 256) {
    let c: Int = hist[i];
    cum = cum + c;
    if (cum >= k) { return _img_ok_int(i); }
    i = i + 1;
  }
  return _img_ok_int(255);
}

// --------------------------------------------------
//  Resampling
// --------------------------------------------------

/// Nearest-neighbor resize to new_w x new_h. Target (x, y) samples source
/// (x * width / new_w, y * height / new_h) with truncating division, so
/// integer upscales replicate blocks and a same-size resize is an exact
/// copy. Errors: "imaging: invalid width" / "imaging: invalid height" for
/// non-positive targets. Result stride == new_w. Complexity: O(new_w * new_h).
pub fn imaging_resize_nearest(img: &GrayImage, new_w: Int, new_h: Int) -> Result[GrayImage, Str] {
  if (new_w <= 0) { return _img_err_img("imaging: invalid width"); }
  if (new_h <= 0) { return _img_err_img("imaging: invalid height"); }
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < new_h) {
    let sy = (y * img.height) / new_h;
    var x = 0;
    while (x < new_w) {
      let sx = (x * img.width) / new_w;
      out.push(_img_raw(img, sx, sy) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: new_w; height: new_h; stride: new_w; pixels: out; };
  return _img_ok_img(res);
}

/// Integer bilinear resize to new_w x new_h. Source coordinates are 16-bit
/// fixed point: q = (i * (src_n - 1) * 256) / (dst_n - 1) (0 when either side
/// has one sample), split into base ix = q / 256 and fraction fx = q % 256;
/// the second sample is min(ix + 1, src_n - 1). With
/// w00 = (256-fx)(256-fy), w10 = fx(256-fy), w01 = (256-fx)fy, w11 = fx*fy
/// the result is (v00*w00 + v10*w10 + v01*w01 + v11*w11 + 32768) / 65536
/// (nearest on 16-bit weights), clamped to 0..255 defensively. A same-size
/// resize is an exact copy and constant images stay constant (the weights
/// sum to 65536). Errors: "imaging: invalid width" / "imaging: invalid
/// height". Complexity: O(new_w * new_h).
pub fn imaging_resize_bilinear(img: &GrayImage, new_w: Int, new_h: Int) -> Result[GrayImage, Str] {
  if (new_w <= 0) { return _img_err_img("imaging: invalid width"); }
  if (new_h <= 0) { return _img_err_img("imaging: invalid height"); }
  let w = img.width;
  let h = img.height;
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < new_h) {
    let qy = _img_coord_q(y, h, new_h);
    let iy = qy / 256;
    let fy = qy % 256;
    let y0 = _img_imin(iy, h - 1);
    let y1 = _img_imin(iy + 1, h - 1);
    var x = 0;
    while (x < new_w) {
      let qx = _img_coord_q(x, w, new_w);
      let ix = qx / 256;
      let fx = qx % 256;
      let x0 = _img_imin(ix, w - 1);
      let x1 = _img_imin(ix + 1, w - 1);
      let v00 = _img_raw(img, x0, y0);
      let v10 = _img_raw(img, x1, y0);
      let v01 = _img_raw(img, x0, y1);
      let v11 = _img_raw(img, x1, y1);
      let w00 = (256 - fx) * (256 - fy);
      let w10 = fx * (256 - fy);
      let w01 = (256 - fx) * fy;
      let w11 = fx * fy;
      let s = v00 * w00 + v10 * w10 + v01 * w01 + v11 * w11;
      out.push(_img_clamp255((s + 32768) / 65536) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: new_w; height: new_h; stride: new_w; pixels: out; };
  return _img_ok_img(res);
}

// --------------------------------------------------
//  Geometry
// --------------------------------------------------

/// Mirror left/right: (x, y) -> (width - 1 - x, y). Complexity: O(width * height).
pub fn imaging_flip_horizontal(img: &GrayImage) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      out.push(_img_raw(img, img.width - 1 - x, y) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

/// Mirror top/bottom: (x, y) -> (x, height - 1 - y). Complexity: O(width * height).
pub fn imaging_flip_vertical(img: &GrayImage) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < img.height) {
    var x = 0;
    while (x < img.width) {
      out.push(_img_raw(img, x, img.height - 1 - y) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: img.width; height: img.height; stride: img.width; pixels: out; };
  return res;
}

/// Rotate 90 degrees clockwise: a width x height image becomes height x width
/// with out(nx, ny) = in(ny, height - 1 - nx). Complexity: O(width * height).
pub fn imaging_rotate90(img: &GrayImage) -> GrayImage {
  let new_w = img.height;
  let new_h = img.width;
  let out = Vec[UInt8].new();
  var ny = 0;
  while (ny < new_h) {
    var nx = 0;
    while (nx < new_w) {
      let ox = ny;
      let oy = img.height - 1 - nx;
      out.push(_img_raw(img, ox, oy) as UInt8);
      nx = nx + 1;
    }
    ny = ny + 1;
  }
  let res = GrayImage{ width: new_w; height: new_h; stride: new_w; pixels: out; };
  return res;
}

/// Rotate 180 degrees: (x, y) -> (width - 1 - x, height - 1 - y), equivalent
/// to a horizontal flip followed by a vertical flip.
/// Complexity: O(width * height).
pub fn imaging_rotate180(img: &GrayImage) -> GrayImage {
  return imaging_flip_vertical(imaging_flip_horizontal(img));
}

// --------------------------------------------------
//  Integral image
// --------------------------------------------------

/// Summed-area table with a zero border: a (width + 1) x (height + 1)
/// row-major Vec[Int] where I(0, y) = I(x, 0) = 0 and
/// I(x + 1, y + 1) = p(x, y) + I(x, y + 1) + I(x + 1, y) - I(x, y).
/// Entry (x, y) lives at y * (width + 1) + x. Complexity: O(width * height).
pub fn imaging_integral(img: &GrayImage) -> Vec[Int] {
  let w = img.width;
  let h = img.height;
  let iw = w + 1;
  let out = Vec[Int].new();
  let n = iw * (h + 1);
  var i = 0;
  while (i < n) {
    out.push(0);
    i = i + 1;
  }
  var y = 0;
  while (y < h) {
    var x = 0;
    while (x < w) {
      let v = _img_raw(img, x, y);
      let above: Int = out[y * iw + (x + 1)];
      let left: Int = out[(y + 1) * iw + x];
      let diag: Int = out[y * iw + x];
      out[(y + 1) * iw + (x + 1)] = v + above + left - diag;
      x = x + 1;
    }
    y = y + 1;
  }
  return out;
}

/// Sum of the half-open box [x0, x1) x [y0, y1) via the integral image.
/// An empty box (x0 == x1 or y0 == y1) is 0. Errors: "imaging: box out of
/// bounds" when any coordinate is negative or beyond width/height, and
/// "imaging: invalid box" when x0 > x1 or y0 > y1.
/// Complexity: O(width * height + 1).
pub fn imaging_box_sum(img: &GrayImage, x0: Int, y0: Int, x1: Int, y1: Int) -> Result[Int, Str] {
  if (x0 < 0 || y0 < 0 || x1 < 0 || y1 < 0) { return _img_err_int("imaging: box out of bounds"); }
  if (x1 > img.width || y1 > img.height) { return _img_err_int("imaging: box out of bounds"); }
  if (x0 > x1 || y0 > y1) { return _img_err_int("imaging: invalid box"); }
  let integ = imaging_integral(img);
  let iw = img.width + 1;
  let a: Int = integ[y0 * iw + x0];
  let b: Int = integ[y0 * iw + x1];
  let c: Int = integ[y1 * iw + x0];
  let d: Int = integ[y1 * iw + x1];
  return _img_ok_int(d - b - c + a);
}

// --------------------------------------------------
//  Compositing
// --------------------------------------------------

/// Alpha-free overlay: returns a copy of `dst` (same dimensions, compacted)
/// with every sample of `src` copied verbatim at offset (dx, dy) --
/// destination (dx + sx, dy + sy) receives src(sx, sy) when that coordinate
/// is inside dst. No blending and no alpha: this is an opaque overwrite copy.
/// Source samples whose target falls outside dst are skipped; negative
/// offsets clip the source's top/left. Complexity: O(width * height).
pub fn imaging_overlay_copy(dst: &GrayImage, src: &GrayImage, dx: Int, dy: Int) -> GrayImage {
  let out = Vec[UInt8].new();
  var y = 0;
  while (y < dst.height) {
    var x = 0;
    while (x < dst.width) {
      let sx = x - dx;
      let sy = y - dy;
      var v = _img_raw(dst, x, y);
      if (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) {
        v = _img_raw(src, sx, sy);
      }
      out.push(v as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let res = GrayImage{ width: dst.width; height: dst.height; stride: dst.width; pixels: out; };
  return res;
}

// --------------------------------------------------
//  Leaf Result constructors (v0.62.2: Ok/Err construction is confined to
//  tiny helpers that return a Result directly)
// --------------------------------------------------

fn _img_ok_img(v: GrayImage) -> Result[GrayImage, Str] {
  return Ok(v);
}

fn _img_err_img(m: Str) -> Result[GrayImage, Str] {
  return Err(m);
}

fn _img_ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _img_err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}
