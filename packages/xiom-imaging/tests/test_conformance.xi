// XIOM -- xiom.imaging conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven, direct calls only: hand-computed 3x3 kernels, a Sobel edge,
// an Otsu bimodal split, resize exactness and integral-image box sums.

module imaging_tests
use xiom.io; use xiom.test; use xiom.imaging;

// --------------------------------------------------
//  Result extraction helpers
// --------------------------------------------------

fn extract_img(r: Result[GrayImage, Str]) -> GrayImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_img(); },
  }
}

fn extract_int(r: Result[Int, Str]) -> Int {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return -1; },
  }
}

fn empty_img() -> GrayImage {
  return GrayImage{ width: 0; height: 0; stride: 0; pixels: Vec[UInt8].new(); };
}

fn is_bad_img(r: Result[GrayImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn is_bad_int(r: Result[Int, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

// Integral table entry (x, y) of a width-w image: y * (w + 1) + x.
fn integ_at(v: &Vec[Int], w: Int, x: Int, y: Int) -> Int {
  let z: Int = v[y * (w + 1) + x];
  return z;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// 3x3 with rows 1 2 3 / 4 5 6 / 7 8 9.
fn seq3() -> GrayImage {
  let p = Vec[UInt8].new();
  var i = 1;
  while (i <= 9) {
    p.push(i as UInt8);
    i = i + 1;
  }
  return GrayImage{ width: 3; height: 3; stride: 3; pixels: p; };
}

// h x w constant image.
fn flat(w: Int, h: Int, v: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  var i = 0;
  while (i < w * h) {
    p.push(v as UInt8);
    i = i + 1;
  }
  return GrayImage{ width: w; height: h; stride: w; pixels: p; };
}

// 1x8 with four 10s then four 200s.
fn bimodal() -> GrayImage {
  let p = Vec[UInt8].new();
  var i = 0;
  while (i < 4) {
    p.push(10 as UInt8);
    i = i + 1;
  }
  i = 0;
  while (i < 4) {
    p.push(200 as UInt8);
    i = i + 1;
  }
  return GrayImage{ width: 8; height: 1; stride: 8; pixels: p; };
}

fn two_by_two(a: Int, b: Int, c: Int, d: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  p.push(a as UInt8);
  p.push(b as UInt8);
  p.push(c as UInt8);
  p.push(d as UInt8);
  return GrayImage{ width: 2; height: 2; stride: 2; pixels: p; };
}

fn two_by_one(a: Int, b: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  p.push(a as UInt8);
  p.push(b as UInt8);
  return GrayImage{ width: 2; height: 1; stride: 2; pixels: p; };
}

fn one_by_three(a: Int, b: Int, c: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  p.push(a as UInt8);
  p.push(b as UInt8);
  p.push(c as UInt8);
  return GrayImage{ width: 3; height: 1; stride: 3; pixels: p; };
}

fn two_by_three(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  p.push(a as UInt8);
  p.push(b as UInt8);
  p.push(c as UInt8);
  p.push(d as UInt8);
  p.push(e as UInt8);
  p.push(f as UInt8);
  return GrayImage{ width: 2; height: 3; stride: 2; pixels: p; };
}

fn three_by_three(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int, i: Int) -> GrayImage {
  let p = Vec[UInt8].new();
  p.push(a as UInt8);
  p.push(b as UInt8);
  p.push(c as UInt8);
  p.push(d as UInt8);
  p.push(e as UInt8);
  p.push(f as UInt8);
  p.push(g as UInt8);
  p.push(h as UInt8);
  p.push(i as UInt8);
  return GrayImage{ width: 3; height: 3; stride: 3; pixels: p; };
}

// 2x2 image with stride 3: rows 1 2 pad / 3 4 pad (pad = 90, 91).
fn strided_2x2_bytes() -> Vec[UInt8] {
  let p = Vec[UInt8].new();
  p.push(1 as UInt8);
  p.push(2 as UInt8);
  p.push(90 as UInt8);
  p.push(3 as UInt8);
  p.push(4 as UInt8);
  p.push(91 as UInt8);
  return p;
}

fn strided_2x2() -> GrayImage {
  return extract_img(imaging_from_pixels(2, 2, 3, strided_2x2_bytes()));
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let a = extract_img(imaging_new(2, 3, 7));
  if (imaging_width(a) != 2) { return assert(false, "new width is 2"); }
  if (imaging_height(a) != 3) { return assert(false, "new height is 3"); }
  if (imaging_stride(a) != 2) { return assert(false, "new stride is compacted"); }
  if (imaging_pixel(a, 0, 0) != 7) { return assert(false, "new fills first sample"); }
  if (imaging_pixel(a, 1, 2) != 7) { return assert(false, "new fills last sample"); }
  if (imaging_pixel(a, -1, 0) != -1) { return assert(false, "read x=-1 is -1"); }
  if (imaging_pixel(a, 2, 0) != -1) { return assert(false, "read x=width is -1"); }
  if (imaging_pixel(a, 0, 3) != -1) { return assert(false, "read y=height is -1"); }
  if (imaging_max_value() != 255) { return assert(false, "max value is 255"); }
  if (!is_bad_img(imaging_new(0, 1, 0))) { return assert(false, "width 0 rejected"); }
  if (!is_bad_img(imaging_new(1, 0, 0))) { return assert(false, "height 0 rejected"); }
  if (!is_bad_img(imaging_new(1, 1, 256))) { return assert(false, "fill 256 rejected"); }
  return assert(true, "constructor, accessors and bounds-checked reads");
}

fn t2() -> TestResult {
  let a = extract_img(imaging_from_pixels(2, 2, 3, strided_2x2_bytes()));
  if (imaging_stride(a) != 3) { return assert(false, "from_pixels keeps stride 3"); }
  if (imaging_pixel(a, 0, 0) != 1) { return assert(false, "strided (0,0) is 1"); }
  if (imaging_pixel(a, 1, 0) != 2) { return assert(false, "strided (1,0) is 2"); }
  if (imaging_pixel(a, 0, 1) != 3) { return assert(false, "strided (0,1) is 3"); }
  if (imaging_pixel(a, 1, 1) != 4) { return assert(false, "strided (1,1) is 4"); }
  let h = imaging_histogram(a);
  if (h.len() != 256) { return assert(false, "histogram has 256 bins"); }
  if (h[90] != 0 || h[91] != 0) { return assert(false, "padding bytes are ignored"); }
  if (!is_bad_img(imaging_from_pixels(2, 2, 1, strided_2x2_bytes()))) { return assert(false, "stride < width rejected"); }
  let short = Vec[UInt8].new();
  short.push(1 as UInt8);
  if (!is_bad_img(imaging_from_pixels(2, 2, 3, short))) { return assert(false, "short payload rejected"); }
  let none = Vec[UInt8].new();
  if (!is_bad_img(imaging_from_pixels(0, 2, 0, none))) { return assert(false, "width 0 rejected"); }
  return assert(true, "from_pixels validates layout and padding is invisible");
}

fn t3() -> TestResult {
  let b = imaging_box_blur(seq3());
  if (imaging_width(b) != 3 || imaging_height(b) != 3) { return assert(false, "box blur keeps 3x3"); }
  if (imaging_stride(b) != 3) { return assert(false, "box blur compacts stride"); }
  if (imaging_pixel(b, 1, 1) != 5) { return assert(false, "box blur center of 1..9 is 5"); }
  if (imaging_pixel(b, 0, 0) != 2) { return assert(false, "box blur corner clamps to 2"); }
  if (imaging_pixel(b, 2, 0) != 4) { return assert(false, "box blur top-right is 4"); }
  if (imaging_pixel(b, 2, 2) != 8) { return assert(false, "box blur corner clamps to 8"); }
  return assert(true, "3x3 box blur hand-computed center and corners");
}

fn t4() -> TestResult {
  let c = flat(4, 2, 42);
  let b = imaging_box_blur(c);
  if (imaging_pixel(b, 0, 0) != 42) { return assert(false, "constant box blur fixed point"); }
  if (imaging_pixel(b, 3, 1) != 42) { return assert(false, "constant box blur last sample"); }
  let down = imaging_box_blur(three_by_three(0, 0, 0, 0, 4, 0, 0, 0, 0));
  if (imaging_pixel(down, 1, 1) != 0) { return assert(false, "4/9 rounds down to 0"); }
  let up = imaging_box_blur(three_by_three(0, 0, 0, 0, 5, 0, 0, 0, 0));
  if (imaging_pixel(up, 1, 1) != 1) { return assert(false, "5/9 rounds up to 1"); }
  return assert(true, "box blur preserves constants and rounds to nearest");
}

fn t5() -> TestResult {
  let g = imaging_gaussian_blur(seq3());
  if (imaging_pixel(g, 1, 1) != 5) { return assert(false, "gaussian center of 1..9 is 5"); }
  if (imaging_pixel(g, 0, 0) != 2) { return assert(false, "gaussian corner clamps to 2"); }
  let c = imaging_gaussian_blur(flat(3, 3, 42));
  if (imaging_pixel(c, 1, 1) != 42) { return assert(false, "gaussian constant fixed point"); }
  let k = imaging_gaussian_blur(one_by_three(0, 4, 0));
  if (imaging_pixel(k, 0, 0) != 1) { return assert(false, "1-2-1 profile left is 1"); }
  if (imaging_pixel(k, 1, 0) != 2) { return assert(false, "1-2-1 profile peak is 2"); }
  if (imaging_pixel(k, 2, 0) != 1) { return assert(false, "1-2-1 profile right is 1"); }
  return assert(true, "separable 1-2-1 gaussian weights and rounding");
}

fn t6() -> TestResult {
  let s = imaging_sobel(flat(3, 3, 42));
  var y = 0;
  while (y < 3) {
    var x = 0;
    while (x < 3) {
      if (imaging_pixel(s, x, y) != 0) { return assert(false, "flat sobel is zero"); }
      x = x + 1;
    }
    y = y + 1;
  }
  return assert(true, "sobel of a flat image is all zero");
}

fn t7() -> TestResult {
  let edge = three_by_three(0, 0, 255, 0, 0, 255, 0, 0, 255);
  let s = imaging_sobel(edge);
  if (imaging_pixel(s, 1, 1) != 255) { return assert(false, "sobel edge saturates at 255"); }
  if (imaging_pixel(s, 1, 0) != 255) { return assert(false, "sobel edge saturates on top row"); }
  if (imaging_pixel(s, 0, 1) != 0) { return assert(false, "flat left column is 0"); }
  if (imaging_pixel(s, 2, 1) != 255) { return assert(false, "clamped right column saturates"); }
  return assert(true, "sobel on a vertical edge saturates");
}

fn t8() -> TestResult {
  let ramp = three_by_three(0, 10, 20, 0, 10, 20, 0, 10, 20);
  let s = imaging_sobel(ramp);
  if (imaging_pixel(s, 1, 1) != 80) { return assert(false, "ramp sobel |gx| is 80"); }
  if (imaging_pixel(s, 0, 0) != 40) { return assert(false, "ramp sobel corner is 40"); }
  if (imaging_pixel(s, 2, 1) != 40) { return assert(false, "ramp sobel right is 40"); }
  return assert(true, "sobel L1 magnitude exact on an integer ramp");
}

fn t9() -> TestResult {
  let t = extract_img(imaging_threshold(seq3(), 5));
  if (imaging_pixel(t, 0, 0) != 0) { return assert(false, "1 <= 5 is black"); }
  if (imaging_pixel(t, 1, 1) != 0) { return assert(false, "5 > 5 is false"); }
  if (imaging_pixel(t, 2, 0) != 0) { return assert(false, "3 <= 5 is black"); }
  if (imaging_pixel(t, 0, 2) != 255) { return assert(false, "7 > 5 is white"); }
  if (imaging_pixel(t, 2, 2) != 255) { return assert(false, "9 > 5 is white"); }
  if (!is_bad_img(imaging_threshold(seq3(), -1))) { return assert(false, "t=-1 rejected"); }
  if (!is_bad_img(imaging_threshold(seq3(), 256))) { return assert(false, "t=256 rejected"); }
  return assert(true, "binary threshold is strict and range-checked");
}

fn t10() -> TestResult {
  let b = bimodal();
  let otsu = imaging_otsu_threshold(b);
  if (otsu != 10) { return assert(false, "otsu picks the smallest maximizer 10"); }
  let t = extract_img(imaging_threshold(b, otsu));
  var i = 0;
  while (i < 4) {
    if (imaging_pixel(t, i, 0) != 0) { return assert(false, "low class is black"); }
    if (imaging_pixel(t, i + 4, 0) != 255) { return assert(false, "high class is white"); }
    i = i + 1;
  }
  let f = flat(8, 1, 77);
  if (imaging_otsu_threshold(f) != 77) { return assert(false, "single-level otsu returns the level"); }
  return assert(true, "otsu threshold splits a bimodal histogram");
}

fn t11() -> TestResult {
  let h = imaging_histogram(seq3());
  if (h.len() != 256) { return assert(false, "256 bins"); }
  if (h[0] != 0) { return assert(false, "bin 0 empty"); }
  if (h[1] != 1) { return assert(false, "bin 1 has one"); }
  if (h[5] != 1) { return assert(false, "bin 5 has one"); }
  if (h[9] != 1) { return assert(false, "bin 9 has one"); }
  if (h[10] != 0) { return assert(false, "bin 10 empty"); }
  var sum = 0;
  var i = 0;
  while (i < 256) {
    let c: Int = h[i];
    sum = sum + c;
    i = i + 1;
  }
  if (sum != 9) { return assert(false, "counts sum to 9"); }
  let hb = imaging_histogram(bimodal());
  if (hb[10] != 4 || hb[200] != 4) { return assert(false, "bimodal bins are 4 and 4"); }
  return assert(true, "histogram bins, size and total counts");
}

fn t12() -> TestResult {
  let q = two_by_two(1, 2, 2, 3);
  if (extract_int(imaging_percentile(q, 0)) != 1) { return assert(false, "p0 is the minimum"); }
  if (extract_int(imaging_percentile(q, 25)) != 1) { return assert(false, "p25 is 1"); }
  if (extract_int(imaging_percentile(q, 50)) != 2) { return assert(false, "p50 is 2"); }
  if (extract_int(imaging_percentile(q, 75)) != 2) { return assert(false, "p75 is 2"); }
  if (extract_int(imaging_percentile(q, 100)) != 3) { return assert(false, "p100 is the maximum"); }
  if (!is_bad_int(imaging_percentile(q, -1))) { return assert(false, "p=-1 rejected"); }
  if (!is_bad_int(imaging_percentile(q, 101))) { return assert(false, "p=101 rejected"); }
  return assert(true, "nearest-rank percentile and range checks");
}

fn t13() -> TestResult {
  let integ = imaging_integral(seq3());
  if (integ.len() != 16) { return assert(false, "integral has (3+1)^2 entries"); }
  if (integ_at(integ, 3, 0, 0) != 0) { return assert(false, "integral origin is 0"); }
  if (integ_at(integ, 3, 1, 1) != 1) { return assert(false, "I(1,1)=1"); }
  if (integ_at(integ, 3, 2, 1) != 3) { return assert(false, "I(2,1)=3"); }
  if (integ_at(integ, 3, 1, 2) != 5) { return assert(false, "I(1,2)=5"); }
  if (integ_at(integ, 3, 2, 2) != 12) { return assert(false, "I(2,2)=12"); }
  if (integ_at(integ, 3, 3, 2) != 21) { return assert(false, "I(3,2)=21"); }
  if (integ_at(integ, 3, 3, 3) != 45) { return assert(false, "I(3,3)=45"); }
  return assert(true, "integral image matches hand-computed prefix sums");
}

fn t14() -> TestResult {
  let s = seq3();
  if (extract_int(imaging_box_sum(s, 0, 0, 2, 2)) != 12) { return assert(false, "top-left 2x2 sum is 12"); }
  if (extract_int(imaging_box_sum(s, 1, 1, 3, 3)) != 28) { return assert(false, "bottom-right 2x2 sum is 28"); }
  if (extract_int(imaging_box_sum(s, 0, 0, 3, 3)) != 45) { return assert(false, "full image sum is 45"); }
  if (extract_int(imaging_box_sum(s, 1, 2, 3, 3)) != 17) { return assert(false, "bottom row tail is 17"); }
  if (extract_int(imaging_box_sum(s, 0, 0, 0, 3)) != 0) { return assert(false, "empty box is 0"); }
  if (!is_bad_int(imaging_box_sum(s, 0, 0, 4, 3))) { return assert(false, "x1 > width rejected"); }
  if (!is_bad_int(imaging_box_sum(s, -1, 0, 1, 1))) { return assert(false, "negative x0 rejected"); }
  if (!is_bad_int(imaging_box_sum(s, 2, 0, 1, 1))) { return assert(false, "x0 > x1 rejected"); }
  return assert(true, "integral-image box sums and box errors");
}

fn t15() -> TestResult {
  let r = extract_img(imaging_resize_nearest(two_by_two(1, 2, 3, 4), 4, 4));
  if (imaging_width(r) != 4 || imaging_height(r) != 4) { return assert(false, "4x4 target"); }
  if (imaging_pixel(r, 0, 0) != 1) { return assert(false, "block (0,0) is 1"); }
  if (imaging_pixel(r, 1, 0) != 1) { return assert(false, "block (1,0) is 1"); }
  if (imaging_pixel(r, 2, 0) != 2) { return assert(false, "block (2,0) is 2"); }
  if (imaging_pixel(r, 3, 0) != 2) { return assert(false, "block (3,0) is 2"); }
  if (imaging_pixel(r, 0, 2) != 3) { return assert(false, "block (0,2) is 3"); }
  if (imaging_pixel(r, 3, 3) != 4) { return assert(false, "block (3,3) is 4"); }
  return assert(true, "nearest resize replicates 2x2 blocks exactly");
}

fn t16() -> TestResult {
  let s = seq3();
  let r = extract_img(imaging_resize_nearest(s, 3, 3));
  if (imaging_pixel(r, 0, 0) != 1) { return assert(false, "identity keeps (0,0)"); }
  if (imaging_pixel(r, 1, 1) != 5) { return assert(false, "identity keeps center"); }
  if (imaging_pixel(r, 2, 2) != 9) { return assert(false, "identity keeps (2,2)"); }
  if (imaging_pixel(r, 0, 2) != 7) { return assert(false, "identity keeps (0,2)"); }
  let one = extract_img(imaging_resize_nearest(s, 1, 1));
  if (imaging_pixel(one, 0, 0) != 1) { return assert(false, "1x1 samples the origin"); }
  if (!is_bad_img(imaging_resize_nearest(s, 0, 3))) { return assert(false, "new width 0 rejected"); }
  if (!is_bad_img(imaging_resize_nearest(s, 3, 0))) { return assert(false, "new height 0 rejected"); }
  return assert(true, "nearest identity resize and target validation");
}

fn t17() -> TestResult {
  let r = extract_img(imaging_resize_bilinear(two_by_one(0, 100), 3, 1));
  if (imaging_width(r) != 3 || imaging_height(r) != 1) { return assert(false, "3x1 target"); }
  if (imaging_pixel(r, 0, 0) != 0) { return assert(false, "bilinear left endpoint is 0"); }
  if (imaging_pixel(r, 1, 0) != 50) { return assert(false, "bilinear midpoint is 50"); }
  if (imaging_pixel(r, 2, 0) != 100) { return assert(false, "bilinear right endpoint is 100"); }
  return assert(true, "integer bilinear 2x1 -> 3x1 is exactly 0, 50, 100");
}

fn t18() -> TestResult {
  let s = seq3();
  let r = extract_img(imaging_resize_bilinear(s, 3, 3));
  if (imaging_pixel(r, 0, 0) != 1) { return assert(false, "bilinear identity keeps (0,0)"); }
  if (imaging_pixel(r, 1, 1) != 5) { return assert(false, "bilinear identity keeps center"); }
  if (imaging_pixel(r, 2, 2) != 9) { return assert(false, "bilinear identity keeps (2,2)"); }
  if (imaging_pixel(r, 2, 0) != 3) { return assert(false, "bilinear identity keeps (2,0)"); }
  let c = extract_img(imaging_resize_bilinear(flat(2, 2, 42), 3, 3));
  var y = 0;
  while (y < 3) {
    var x = 0;
    while (x < 3) {
      if (imaging_pixel(c, x, y) != 42) { return assert(false, "constant stays 42"); }
      x = x + 1;
    }
    y = y + 1;
  }
  return assert(true, "bilinear identity is exact and constants survive");
}

fn t19() -> TestResult {
  let s = two_by_three(1, 2, 3, 4, 5, 6);
  let h = imaging_flip_horizontal(s);
  if (imaging_pixel(h, 0, 0) != 2) { return assert(false, "h-flip (0,0) is 2"); }
  if (imaging_pixel(h, 1, 0) != 1) { return assert(false, "h-flip (1,0) is 1"); }
  if (imaging_pixel(h, 0, 1) != 4) { return assert(false, "h-flip (0,1) is 4"); }
  if (imaging_pixel(h, 0, 2) != 6) { return assert(false, "h-flip (0,2) is 6"); }
  if (imaging_pixel(h, 1, 2) != 5) { return assert(false, "h-flip (1,2) is 5"); }
  let v = imaging_flip_vertical(s);
  if (imaging_pixel(v, 0, 0) != 5) { return assert(false, "v-flip (0,0) is 5"); }
  if (imaging_pixel(v, 1, 0) != 6) { return assert(false, "v-flip (1,0) is 6"); }
  if (imaging_pixel(v, 0, 2) != 1) { return assert(false, "v-flip (0,2) is 1"); }
  return assert(true, "horizontal and vertical flips are exact");
}

fn t20() -> TestResult {
  let a = two_by_two(1, 2, 3, 4);
  let r = imaging_rotate90(a);
  if (imaging_pixel(r, 0, 0) != 3) { return assert(false, "cw (0,0) is 3"); }
  if (imaging_pixel(r, 1, 0) != 1) { return assert(false, "cw (1,0) is 1"); }
  if (imaging_pixel(r, 0, 1) != 4) { return assert(false, "cw (0,1) is 4"); }
  if (imaging_pixel(r, 1, 1) != 2) { return assert(false, "cw (1,1) is 2"); }
  let ns = imaging_rotate90(two_by_three(1, 2, 3, 4, 5, 6));
  if (imaging_width(ns) != 3 || imaging_height(ns) != 2) { return assert(false, "2x3 rotates to 3x2"); }
  if (imaging_pixel(ns, 0, 0) != 5) { return assert(false, "cw 2x3 (0,0) is 5"); }
  if (imaging_pixel(ns, 1, 0) != 3) { return assert(false, "cw 2x3 (1,0) is 3"); }
  if (imaging_pixel(ns, 2, 0) != 1) { return assert(false, "cw 2x3 (2,0) is 1"); }
  if (imaging_pixel(ns, 0, 1) != 6) { return assert(false, "cw 2x3 (0,1) is 6"); }
  if (imaging_pixel(ns, 2, 1) != 2) { return assert(false, "cw 2x3 (2,1) is 2"); }
  let r180 = imaging_rotate180(a);
  if (imaging_pixel(r180, 0, 0) != 4) { return assert(false, "180 (0,0) is 4"); }
  if (imaging_pixel(r180, 1, 0) != 3) { return assert(false, "180 (1,0) is 3"); }
  if (imaging_pixel(r180, 0, 1) != 2) { return assert(false, "180 (0,1) is 2"); }
  if (imaging_pixel(r180, 1, 1) != 1) { return assert(false, "180 (1,1) is 1"); }
  return assert(true, "rotate 90 clockwise and rotate 180 are exact");
}

fn t21() -> TestResult {
  let dst = flat(3, 3, 0);
  let r = imaging_overlay_copy(dst, two_by_one(7, 8), 1, 1);
  if (imaging_pixel(r, 1, 1) != 7) { return assert(false, "overlay (1,1) is 7"); }
  if (imaging_pixel(r, 2, 1) != 8) { return assert(false, "overlay (2,1) is 8"); }
  if (imaging_pixel(r, 0, 1) != 0) { return assert(false, "overlay leaves (0,1)"); }
  if (imaging_pixel(r, 1, 0) != 0) { return assert(false, "overlay leaves (1,0)"); }
  let clip = imaging_overlay_copy(dst, two_by_two(7, 8, 9, 10), 2, 2);
  if (imaging_pixel(clip, 2, 2) != 7) { return assert(false, "clip copies only (2,2)"); }
  if (imaging_pixel(clip, 2, 1) != 0) { return assert(false, "clip leaves (2,1)"); }
  if (imaging_pixel(clip, 1, 2) != 0) { return assert(false, "clip leaves (1,2)"); }
  let neg = imaging_overlay_copy(dst, two_by_one(9, 8), -1, 0);
  if (imaging_pixel(neg, 0, 0) != 8) { return assert(false, "negative offset clips left"); }
  if (imaging_pixel(neg, 1, 0) != 0) { return assert(false, "negative offset leaves (1,0)"); }
  let none = imaging_overlay_copy(dst, flat(1, 1, 9), -1, -1);
  if (imaging_pixel(none, 0, 0) != 0) { return assert(false, "fully outside overlay copies nothing"); }
  return assert(true, "alpha-free overlay copy, clipping and negative offsets");
}

fn t22() -> TestResult {
  let s = strided_2x2();
  let c = imaging_copy(s);
  if (imaging_stride(c) != 2) { return assert(false, "copy compacts stride to width"); }
  if (imaging_pixel(c, 0, 0) != 1) { return assert(false, "copy (0,0) is 1"); }
  if (imaging_pixel(c, 1, 0) != 2) { return assert(false, "copy (1,0) is 2"); }
  if (imaging_pixel(c, 0, 1) != 3) { return assert(false, "copy (0,1) is 3"); }
  if (imaging_pixel(c, 1, 1) != 4) { return assert(false, "copy (1,1) is 4"); }
  let h = imaging_histogram(c);
  if (h[90] != 0 || h[91] != 0) { return assert(false, "copy drops padding bytes"); }
  return assert(true, "copy compacts a strided source without padding");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  var failed = 0;

  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }

  if failed == 0 {
    io.println("xiom.imaging: all tests passed");
  } else {
    io.println("xiom.imaging: tests failed");
  }
  return failed;
}
