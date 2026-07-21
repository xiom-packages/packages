module xiom.opencv.tests.conformance

use xiom.opencv.types;
use xiom.opencv.io;
use xiom.opencv.features;
use xiom.opencv.filters;

fn check_eq_int(a: Int, b: Int) -> Bool {
  return a == b;
}

fn check_eq_bool(a: Bool, b: Bool) -> Bool {
  return a == b;
}

fn check_ok_int(a: Result[Int, Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

fn check_ok_image(a: Result[Image, Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

fn check_ok_bool(a: Result[Bool, Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

fn check_ok_keypoints(a: Result[Vec[KeyPoint], Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

fn check_ok_matches(a: Result[MatchedPoints, Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

fn check_ok_homography(a: Result[Vec[Float32], Str]) -> Bool {
  match a {
    Ok(v) => { return true; }
    _ => { return false; }
  }
}

pub fn run_all() -> Int {
  var passed = 0;
  var failed = 0;
  var total = 0;

  passed = passed + test_types();
  total = total + 7;

  passed = passed + test_io();
  total = total + 4;

  passed = passed + test_features();
  total = total + 3;

  passed = passed + test_filters();
  total = total + 5;

  failed = total - passed;
  if failed == 0 {
    return 0;
  };
  return 1;
}

fn test_types() -> Int {
  var p = 0;

  var img = image_new(64, 64, 3);
  if check_eq_int(img.width, 64) && check_eq_int(img.height, 64) && check_eq_int(img.channels, 3) {
    p = p + 1;
  };

  var pixels = Vec[Int].new();
  var k = 0;
  while k < 12 {
    pixels.push(100);
    k = k + 1;
  };
  var from_vec = image_from_vec(pixels, 3, 2, 2);
  if check_eq_int(from_vec.data.len(), 12) && check_eq_int(from_vec.width, 3) {
    p = p + 1;
  };

  var roi = rect_new(2, 2, 4, 4);
  var crop = image_region(&img, &roi);
  if check_eq_int(crop.width, 4) && check_eq_int(crop.height, 4) {
    p = p + 1;
  };

  var sz = image_size(&img);
  if check_eq_int(sz.w, img.width) && check_eq_int(sz.h, img.height) {
    p = p + 1;
  };

  var r = rect_new(0, 0, 10, 20);
  if check_eq_int(r.x, 0) && check_eq_int(r.y, 0) && check_eq_int(r.w, 10) && check_eq_int(r.h, 20) {
    p = p + 1;
  };

  var pt = point2i_new(5, 7);
  if check_eq_int(pt.x, 5) && check_eq_int(pt.y, 7) {
    p = p + 1;
  };

  var sz2 = size2i_new(100, 200);
  if check_eq_int(sz2.w, 100) && check_eq_int(sz2.h, 200) {
    p = p + 1;
  };

  return p;
}

fn test_io() -> Int {
  var p = 0;

  var r = cv_imread("test.jpg");
  if check_ok_image(r) {
    var img = match r { Ok(v) => { v } };
    if check_eq_int(img.width, 1) && check_eq_int(img.height, 1) {
      p = p + 1;
    };
  };

  var img = image_new(8, 8, 3);
  var w = cv_imwrite("out.jpg", &img);
  if check_ok_bool(w) {
    var ok = match w { Ok(v) => { v } };
    if ok {
      p = p + 1;
    };
  };

  var rs = cv_resize(&img, 16, 16);
  if check_ok_image(rs) {
    var resized = match rs { Ok(v) => { v } };
    if check_eq_int(resized.width, 16) && check_eq_int(resized.height, 16) {
      p = p + 1;
    };
  };

  var cv = cv_cvt_color(&img, ColorSpace.RGB, ColorSpace.Grayscale);
  if check_ok_image(cv) {
    var gray = match cv { Ok(v) => { v } };
    if check_eq_int(gray.channels, 1) {
      p = p + 1;
    };
  };

  return p;
}

fn test_features() -> Int {
  var p = 0;

  var img = image_new(64, 64, 1);
  var kps = cv_detect_keypoints(&img, 0.01);
  if check_ok_keypoints(kps) {
    var pts = match kps { Ok(v) => { v } };
    if check_eq_int(pts.len(), 0) {
      p = p + 1;
    };
  };

  var d1 = Vec[Float32].new();
  d1.push(1.0);
  var d2 = Vec[Float32].new();
  d2.push(2.0);
  var mp = cv_match_descriptors(&d1, &d2);
  if check_ok_matches(mp) {
    var m = match mp { Ok(v) => { v } };
    if check_eq_int(m.query.len(), 0) && check_eq_int(m.train.len(), 0) {
      p = p + 1;
    };
  };

  var q = Vec[Point2i].new();
  var i = 0;
  while i < 4 {
    q.push(point2i_new(i, i));
    i = i + 1;
  };
  var t = Vec[Point2i].new();
  var j = 0;
  while j < 4 {
    t.push(point2i_new(j, j));
    j = j + 1;
  };
  var dists = Vec[Float32].new();
  var d = 0;
  while d < 4 {
    dists.push(0.0);
    d = d + 1;
  };
  var match_data = MatchedPoints{ query: q, train: t, distances: dists };
  var h = cv_homography(&match_data);
  if check_ok_homography(h) {
    var mat = match h { Ok(v) => { v } };
    if check_eq_int(mat.len(), 9) {
      p = p + 1;
    };
  };

  return p;
}

fn test_filters() -> Int {
  var p = 0;

  var img = image_new(16, 16, 3);

  var b = blur(&img, 3);
  if check_eq_int(b.width, 16) && check_eq_int(b.height, 16) && check_eq_int(b.channels, 3) {
    p = p + 1;
  };

  var gray = grayscale(&img);
  if check_eq_int(gray.width, 16) && check_eq_int(gray.height, 16) && check_eq_int(gray.channels, 1) {
    p = p + 1;
  };

  var th = threshold(&img, 100, 255);
  if check_eq_int(th.width, 16) && check_eq_int(th.height, 16) && check_eq_int(th.channels, 3) {
    p = p + 1;
  };

  var single = image_new(16, 16, 1);
  var edges = sobel_edges(&single);
  if check_eq_int(edges.width, 16) && check_eq_int(edges.height, 16) && check_eq_int(edges.channels, 1) {
    p = p + 1;
  };

  var rn = resize_nearest(&img, 32, 32);
  if check_eq_int(rn.width, 32) && check_eq_int(rn.height, 32) && check_eq_int(rn.channels, 3) {
    p = p + 1;
  };

  return p;
}
