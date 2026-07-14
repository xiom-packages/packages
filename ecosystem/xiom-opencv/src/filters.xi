module xiom.opencv.filters

use xiom.opencv.types;

fn get_pixel(img: &Image, x: Int, y: Int, c: Int) -> Int {
  var idx = (y * img.width + x) * img.channels + c;
  return img.data[idx];
}

fn set_pixel(img: &mut Image, x: Int, y: Int, c: Int, val: Int) {
  var idx = (y * img.width + x) * img.channels + c;
  img.data[idx] = val;
}

fn clamp_byte(v: Int) -> Int {
  var r = v;
  if r < 0 { r = 0; };
  if r > 255 { r = 255; };
  return r;
}

pub fn blur(img: &Image, kernel_size: Int) -> Image
  requires: kernel_size > 0
  requires: kernel_size % 2 == 1
{
  var half = kernel_size / 2;
  var out = image_new(img.width, img.height, img.channels);
  var y = 0;
  while y < img.height {
    var x = 0;
    while x < img.width {
      var ch = 0;
      while ch < img.channels {
        var sum = 0;
        var count = 0;
        var ky = -half;
        while ky <= half {
          var kx = -half;
          while kx <= half {
            var sx = x + kx;
            var sy = y + ky;
            if sx >= 0 && sx < img.width && sy >= 0 && sy < img.height {
              sum = sum + get_pixel(img, sx, sy, ch);
              count = count + 1;
            };
            kx = kx + 1;
          };
          ky = ky + 1;
        };
        set_pixel(&mut out, x, y, ch, sum / count);
        ch = ch + 1;
      };
      x = x + 1;
    };
    y = y + 1;
  };
  return out;
}

pub fn grayscale(img: &Image) -> Image
  requires: img.channels >= 3
{
  var out = image_new(img.width, img.height, 1);
  var y = 0;
  while y < img.height {
    var x = 0;
    while x < img.width {
      var r = get_pixel(img, x, y, 0);
      var g = get_pixel(img, x, y, 1);
      var b = get_pixel(img, x, y, 2);
      var gray = (r * 77 + g * 150 + b * 29) / 256;
      set_pixel(&mut out, x, y, 0, clamp_byte(gray));
      x = x + 1;
    };
    y = y + 1;
  };
  return out;
}

pub fn threshold(img: &Image, thresh: Int, max_val: Int) -> Image
  requires: thresh >= 0
  requires: max_val >= 0
{
  var out = image_new(img.width, img.height, img.channels);
  var i = 0;
  var total = img.width * img.height * img.channels;
  while i < total {
    if img.data[i] > thresh {
      out.data[i] = max_val;
    } else {
      out.data[i] = 0;
    };
    i = i + 1;
  };
  return out;
}

pub fn sobel_edges(img: &Image) -> Image
  requires: img.channels == 1
{
  var out = image_new(img.width, img.height, 1);
  var gx = [ -1, 0, 1, -2, 0, 2, -1, 0, 1 ];
  var gy = [ -1, -2, -1, 0, 0, 0, 1, 2, 1 ];
  var y = 1;
  while y < img.height - 1 {
    var x = 1;
    while x < img.width - 1 {
      var sum_x = 0;
      var sum_y = 0;
      var ki = 0;
      var ky = -1;
      while ky <= 1 {
        var kx = -1;
        while kx <= 1 {
          var p = get_pixel(img, x + kx, y + ky, 0);
          sum_x = sum_x + p * gx[ki];
          sum_y = sum_y + p * gy[ki];
          ki = ki + 1;
          kx = kx + 1;
        };
        ky = ky + 1;
      };
      var mag = sum_x * sum_x + sum_y * sum_y;
      var i = 0;
      var approx = 0;
      while approx * approx < mag && i < 1000 {
        approx = approx + 1;
        i = i + 1;
      };
      if approx > 255 { approx = 255; };
      set_pixel(&mut out, x, y, 0, approx);
      x = x + 1;
    };
    y = y + 1;
  };
  return out;
}

pub fn resize_nearest(img: &Image, w: Int, h: Int) -> Image
  requires: w > 0
  requires: h > 0
{
  var out = image_new(w, h, img.channels);
  var y = 0;
  while y < h {
    var x = 0;
    while x < w {
      var sx = (x * img.width) / w;
      var sy = (y * img.height) / h;
      var ch = 0;
      while ch < img.channels {
        var val = get_pixel(img, sx, sy, ch);
        set_pixel(&mut out, x, y, ch, val);
        ch = ch + 1;
      };
      x = x + 1;
    };
    y = y + 1;
  };
  return out;
}
