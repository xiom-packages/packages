// XIOM -- xiom.bmp: uncompressed BMP parsing and building (24-bit and 32-bit)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.bmp

pub type BmpInfo = {
  width: Int;
  height: Int;      // > 0 = bottom-up rows, < 0 = top-down rows
  bits: Int;
  data_offset: Int;
  row_bytes: Int;
}

fn _err_info(m: Str) -> Result[BmpInfo, Str] { return Err(m); }
fn _ok_info(i: BmpInfo) -> Result[BmpInfo, Str] { return Ok(i); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  let b0: Int = (data[off] as Int) & 0xFF;
  let b1: Int = (data[off + 1] as Int) & 0xFF;
  return b0 + b1 * 256;
}

fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  let b0: Int = (data[off] as Int) & 0xFF;
  let b1: Int = (data[off + 1] as Int) & 0xFF;
  let b2: Int = (data[off + 2] as Int) & 0xFF;
  let b3: Int = (data[off + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn _s32(data: &Vec[UInt8], off: Int) -> Int {
  let v = _le32(data, off);
  if (v >= 2147483648) { return v - 4294967296; }
  return v;
}

fn _p16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn _p32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

pub fn bmp_row_bytes(width: Int, bits: Int) -> Int {
  return ((width * bits + 31) / 32) * 4;
}

pub fn bmp_parse_header(data: &Vec[UInt8]) -> Result[BmpInfo, Str] {
  let n = data.len();
  if (n < 54) { return _err_info("bmp: truncated header"); }
  let m0: Int = (data[0] as Int) & 0xFF;
  let m1: Int = (data[1] as Int) & 0xFF;
  if (m0 != 66) { return _err_info("bmp: bad magic"); }
  if (m1 != 77) { return _err_info("bmp: bad magic"); }
  let dib = _le32(data, 14);
  if (dib < 40) { return _err_info("bmp: unsupported DIB header"); }
  let width = _le32(data, 18);
  if (width <= 0) { return _err_info("bmp: invalid width"); }
  if (width > 1000000) { return _err_info("bmp: invalid width"); }
  let height = _s32(data, 22);
  if (height == 0) { return _err_info("bmp: invalid height"); }
  if (height > 1000000) { return _err_info("bmp: invalid height"); }
  if (height < -1000000) { return _err_info("bmp: invalid height"); }
  let planes = _le16(data, 26);
  if (planes != 1) { return _err_info("bmp: invalid planes"); }
  let bits = _le16(data, 28);
  if (bits != 24) {
    if (bits != 32) { return _err_info("bmp: unsupported bit depth"); }
  }
  let comp = _le32(data, 30);
  if (comp != 0) { return _err_info("bmp: unsupported compression"); }
  let offset = _le32(data, 10);
  let rb = bmp_row_bytes(width, bits);
  var abs_h = height;
  if (abs_h < 0) { abs_h = 0 - abs_h; }
  let need = offset + rb * abs_h;
  if (need > n) { return _err_info("bmp: pixel data out of bounds"); }
  let info = BmpInfo{ width: width, height: height, bits: bits, data_offset: offset, row_bytes: rb };
  return _ok_info(info);
}

pub fn bmp_pixel_rgb(data: &Vec[UInt8], x: Int, y: Int) -> Result[Int, Str] {
  let parsed = bmp_parse_header(data);
  match parsed {
    Ok(info) => {
      let w = info.width;
      var abs_h = info.height;
      if (abs_h < 0) { abs_h = 0 - abs_h; }
      if (x < 0) { return _err_int("bmp: pixel out of range"); }
      if (y < 0) { return _err_int("bmp: pixel out of range"); }
      if (x >= w) { return _err_int("bmp: pixel out of range"); }
      if (y >= abs_h) { return _err_int("bmp: pixel out of range"); }
      var row = y;
      if (info.height > 0) { row = abs_h - 1 - y; }
      let pos = info.data_offset + row * info.row_bytes + x * (info.bits / 8);
      let bl: Int = (data[pos] as Int) & 0xFF;
      let gl: Int = (data[pos + 1] as Int) & 0xFF;
      let rl: Int = (data[pos + 2] as Int) & 0xFF;
      return _ok_int(rl * 65536 + gl * 256 + bl);
    },
    Err(e) => { return _err_int(e); },
  }
}

pub fn bmp_build_24(rgb: &Vec[UInt8], width: Int, height: Int) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("bmp: invalid width"); }
  if (height <= 0) { return _err_bytes("bmp: invalid height"); }
  let need = width * height * 3;
  if (rgb.len() != need) { return _err_bytes("bmp: pixel buffer size mismatch"); }
  let rb = bmp_row_bytes(width, 24);
  let data_size = rb * height;
  let total = 54 + data_size;
  let out = Vec[UInt8].new();
  out.push(66 as UInt8);
  out.push(77 as UInt8);
  _p32(&mut out, total);
  _p16(&mut out, 0);
  _p16(&mut out, 0);
  _p32(&mut out, 54);
  _p32(&mut out, 40);
  _p32(&mut out, width);
  _p32(&mut out, height);
  _p16(&mut out, 1);
  _p16(&mut out, 24);
  _p32(&mut out, 0);
  _p32(&mut out, data_size);
  _p32(&mut out, 2835);
  _p32(&mut out, 2835);
  _p32(&mut out, 0);
  _p32(&mut out, 0);
  var yrow = 0;
  while (yrow < height) {
    let src = height - 1 - yrow;
    var x = 0;
    while (x < width) {
      let base = (src * width + x) * 3;
      let r: Int = (rgb[base] as Int) & 0xFF;
      let g: Int = (rgb[base + 1] as Int) & 0xFF;
      let b: Int = (rgb[base + 2] as Int) & 0xFF;
      out.push(b as UInt8);
      out.push(g as UInt8);
      out.push(r as UInt8);
      x = x + 1;
    }
    let pad = rb - width * 3;
    var p = 0;
    while (p < pad) {
      out.push(0 as UInt8);
      p = p + 1;
    }
    yrow = yrow + 1;
  }
  return _ok_bytes(out);
}
