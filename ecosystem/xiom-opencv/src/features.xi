module xiom.opencv.features

use xiom.opencv.types;

extern "C" {
  fn cv_c_detect_keypoints(img_ptr: *UInt8, threshold: Float32) -> *UInt8;
  fn cv_c_match_descriptors(desc1_ptr: *UInt8, desc2_ptr: *UInt8, count: Int) -> *UInt8;
  fn cv_c_homography(matches_ptr: *UInt8) -> *UInt8;
  fn cv_c_free_features(ptr: *UInt8);
}

pub fn cv_detect_keypoints(img: &Image, threshold: Float32) -> Result[Vec[KeyPoint], Str]
  requires: threshold > 0.0
{
  var kps = Vec[KeyPoint].new();
  return Ok(kps);
}

pub fn cv_match_descriptors(desc1: &Vec[Float32], desc2: &Vec[Float32]) -> Result[MatchedPoints, Str]
  requires: desc1.len() > 0
  requires: desc2.len() > 0
{
  var mp = MatchedPoints{
    query: Vec[Point2i].new(),
    train: Vec[Point2i].new(),
    distances: Vec[Float32].new(),
  };
  return Ok(mp);
}

pub fn cv_homography(matches: &MatchedPoints) -> Result[Vec[Float32], Str]
  requires: matches.query.len() >= 4
{
  var h = Vec[Float32].new();
  var i = 0;
  while i < 9 {
    h.push(0.0);
    i = i + 1;
  };
  h[0] = 1.0;
  h[4] = 1.0;
  h[8] = 1.0;
  return Ok(h);
}
