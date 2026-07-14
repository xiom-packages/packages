module xiom.opencv.types

pub type Image = {
  data: Vec[Int];
  width: Int;
  height: Int;
  channels: Int;
}

pub enum ColorSpace {
  RGB,
  BGR,
  Grayscale,
  HSV,
  YUV,
}

pub type Rect = {
  x: Int;
  y: Int;
  w: Int;
  h: Int;
}

pub type Point2i = {
  x: Int;
  y: Int;
}

pub type Size2i = {
  w: Int;
  h: Int;
}

pub type KeyPoint = {
  pt: Point2i;
  size: Float32;
  angle: Float32;
  response: Float32;
  octave: Int;
}

pub type MatchedPoints = {
  query: Vec[Point2i];
  train: Vec[Point2i];
  distances: Vec[Float32];
}

pub fn image_new(width: Int, height: Int, channels: Int) -> Image
  requires: width > 0
  requires: height > 0
  requires: channels > 0
{
  var total = width * height * channels;
  var data = Vec[Int].new();
  var i = 0;
  while i < total {
    data.push(0);
    i = i + 1;
  };
  return Image{
    data: data,
    width: width,
    height: height,
    channels: channels,
  };
}

pub fn image_from_vec(data: Vec[Int], w: Int, h: Int, c: Int) -> Image
  requires: data.len() > 0
  requires: w > 0
  requires: h > 0
  requires: c > 0
  ensures: result.data.len() == data.len()
{
  return Image{
    data: data,
    width: w,
    height: h,
    channels: c,
  };
}

pub fn image_region(img: &Image, roi: &Rect) -> Image
  requires: roi.x + roi.w <= img.width
  requires: roi.y + roi.h <= img.height
{
  var out = image_new(roi.w, roi.h, img.channels);
  var row = 0;
  while row < roi.h {
    var col = 0;
    while col < roi.w {
      var ch = 0;
      while ch < img.channels {
        var src_idx = ((roi.y + row) * img.width + (roi.x + col)) * img.channels + ch;
        var dst_idx = (row * roi.w + col) * img.channels + ch;
        out.data[dst_idx] = img.data[src_idx];
        ch = ch + 1;
      };
      col = col + 1;
    };
    row = row + 1;
  };
  return out;
}

pub fn image_size(img: &Image) -> Size2i {
  return Size2i{ w: img.width, h: img.height };
}

pub fn rect_new(x: Int, y: Int, w: Int, h: Int) -> Rect {
  return Rect{ x: x, y: y, w: w, h: h };
}

pub fn point2i_new(x: Int, y: Int) -> Point2i {
  return Point2i{ x: x, y: y };
}

pub fn size2i_new(w: Int, h: Int) -> Size2i {
  return Size2i{ w: w, h: h };
}
