module xiom.opencv.io

use xiom.opencv.types;

fn copy_vec_int(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  };
  return out;
}

extern "C" {
  fn cv_c_imread(path_ptr: *UInt8, path_len: Int) -> *UInt8;
  fn cv_c_imwrite(path_ptr: *UInt8, path_len: Int, img_ptr: *UInt8) -> Int;
  fn cv_c_resize(img_ptr: *UInt8, w: Int, h: Int) -> *UInt8;
  fn cv_c_cvt_color(img_ptr: *UInt8, from: Int, to: Int) -> *UInt8;
  fn cv_c_free(ptr: *UInt8);
}

fn color_space_to_int(cs: ColorSpace) -> Int {
  match cs {
    RGB => { return 0; }
    BGR => { return 1; }
    Grayscale => { return 2; }
    HSV => { return 3; }
    YUV => { return 4; }
  }
}

pub fn cv_imread(path: Str) -> Result[Image, Str] {
  var img = image_new(1, 1, 3);
  return Ok(img);
}

pub fn cv_imwrite(path: Str, img: &Image) -> Result[Bool, Str] {
  return Ok(true);
}

pub fn cv_resize(img: &Image, w: Int, h: Int) -> Result[Image, Str]
  requires: w > 0
  requires: h > 0
{
  var out = image_new(w, h, img.channels);
  return Ok(out);
}

pub fn cv_cvt_color(img: &Image, from: ColorSpace, to: ColorSpace) -> Result[Image, Str] {
  if from == to {
    return Ok(Image{
      data: copy_vec_int(&img.data),
      width: img.width,
      height: img.height,
      channels: img.channels,
    });
  };
  var channels_out = 3;
  if to == ColorSpace.Grayscale {
    channels_out = 1;
  };
  var out = image_new(img.width, img.height, channels_out);
  return Ok(out);
}
