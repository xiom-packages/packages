// XIOM -- xiom.bmp conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module bmp_tests
use xiom.io; use xiom.test; use xiom.bmp;

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn pix(data: &Vec[UInt8], x: Int, y: Int) -> Int {
  match bmp_pixel_rgb(data, x, y) {
    Ok(v) => { return v; },
    Err(e) => { return -1; },
  }
}

fn bad_pixel(data: &Vec[UInt8], x: Int, y: Int) -> Bool {
  match bmp_pixel_rgb(data, x, y) {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn bad_info(r: Result[BmpInfo, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn bad_bytes(r: Result[Vec[UInt8], Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn rgb3(r: Int, g: Int, b: Int) -> Int {
  return r * 65536 + g * 256 + b;
}

// top-down 2x2: TL red, TR green, BL blue, BR white
fn make_rgb2x2() -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  v.push(255 as UInt8); v.push(0 as UInt8); v.push(0 as UInt8);
  v.push(0 as UInt8); v.push(255 as UInt8); v.push(0 as UInt8);
  v.push(0 as UInt8); v.push(0 as UInt8); v.push(255 as UInt8);
  v.push(255 as UInt8); v.push(255 as UInt8); v.push(255 as UInt8);
  return v;
}

// hand-built 1x1 32-bit BMP: B=10 G=20 R=30 A=255
fn mk32() -> Vec[UInt8] {
  let out = Vec[UInt8].new();
  out.push(66 as UInt8); out.push(77 as UInt8);
  out.push(58 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(54 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(40 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(1 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(1 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(1 as UInt8); out.push(0 as UInt8);
  out.push(32 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(4 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8); out.push(0 as UInt8);
  out.push(10 as UInt8); out.push(20 as UInt8); out.push(30 as UInt8); out.push(255 as UInt8);
  return out;
}

fn t1() -> TestResult {
  if (bmp_row_bytes(1, 24) != 4) { return assert(false, "row_bytes(1,24) is 4"); }
  if (bmp_row_bytes(2, 24) != 8) { return assert(false, "row_bytes(2,24) is 8"); }
  if (bmp_row_bytes(3, 24) != 12) { return assert(false, "row_bytes(3,24) is 12"); }
  if (bmp_row_bytes(4, 24) != 12) { return assert(false, "row_bytes(4,24) is 12"); }
  if (bmp_row_bytes(5, 24) != 16) { return assert(false, "row_bytes(5,24) is 16"); }
  if (bmp_row_bytes(1, 32) != 4) { return assert(false, "row_bytes(1,32) is 4"); }
  return assert(true, "row_bytes pads rows to 4 bytes");
}

fn t2() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  if (data.len() != 70) { return assert(false, "2x2 24-bit size is 70"); }
  match bmp_parse_header(data) {
    Ok(info) => {
      if (info.width != 2) { return assert(false, "parsed width 2"); }
      if (info.height != 2) { return assert(false, "parsed height 2"); }
      if (info.bits != 24) { return assert(false, "parsed bits 24"); }
      if (info.data_offset != 54) { return assert(false, "parsed offset 54"); }
      if (info.row_bytes != 8) { return assert(false, "parsed row_bytes 8"); }
      return assert(true, "built 2x2 header parses");
    },
    Err(e) => { return assert(false, "built header failed to parse"); },
  }
}

fn t3() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  if (pix(data, 0, 0) != rgb3(255, 0, 0)) { return assert(false, "TL is red"); }
  if (pix(data, 1, 0) != rgb3(0, 255, 0)) { return assert(false, "TR is green"); }
  if (pix(data, 0, 1) != rgb3(0, 0, 255)) { return assert(false, "BL is blue"); }
  if (pix(data, 1, 1) != rgb3(255, 255, 255)) { return assert(false, "BR is white"); }
  return assert(true, "2x2 pixel round-trip uses top-left origin");
}

fn t4() -> TestResult {
  let v = Vec[UInt8].new();
  v.push(1 as UInt8); v.push(2 as UInt8); v.push(3 as UInt8);
  v.push(4 as UInt8); v.push(5 as UInt8); v.push(6 as UInt8);
  v.push(7 as UInt8); v.push(8 as UInt8); v.push(9 as UInt8);
  let data = ok_bytes(bmp_build_24(v, 3, 1));
  if (data.len() != 66) { return assert(false, "3x1 size is 54 + 12"); }
  if (pix(data, 0, 0) != rgb3(1, 2, 3)) { return assert(false, "3x1 pixel 0"); }
  if (pix(data, 1, 0) != rgb3(4, 5, 6)) { return assert(false, "3x1 pixel 1"); }
  if (pix(data, 2, 0) != rgb3(7, 8, 9)) { return assert(false, "3x1 pixel 2"); }
  return assert(true, "3x1 padded row round-trips");
}

fn t5() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  let b0: Int = (data[54] as Int) & 0xFF;
  let b2: Int = (data[56] as Int) & 0xFF;
  let pad1: Int = (data[61] as Int) & 0xFF;
  let t0: Int = (data[62] as Int) & 0xFF;
  let t2: Int = (data[64] as Int) & 0xFF;
  if (b0 != 255) { return assert(false, "file row 0 starts with blue B"); }
  if (b2 != 0) { return assert(false, "file row 0 blue R is 0"); }
  if (pad1 != 0) { return assert(false, "row padding byte is 0"); }
  if (t0 != 0) { return assert(false, "file row 1 starts with red B=0"); }
  if (t2 != 255) { return assert(false, "file row 1 red R is 255"); }
  return assert(true, "storage is bottom-up with zero padding");
}

fn t6() -> TestResult {
  let data = mk32();
  match bmp_parse_header(data) {
    Ok(info) => {
      if (info.bits != 32) { return assert(false, "32-bit header bits"); }
      if (info.row_bytes != 4) { return assert(false, "32-bit row_bytes 4"); }
      if (pix(data, 0, 0) != rgb3(30, 20, 10)) { return assert(false, "BGRA reads as RGB"); }
      return assert(true, "32-bit BMP parses and reads RGB");
    },
    Err(e) => { return assert(false, "32-bit header failed"); },
  }
}

fn t7() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  if (!bad_pixel(data, -1, 0)) { return assert(false, "x=-1 is Err"); }
  if (!bad_pixel(data, 0, -1)) { return assert(false, "y=-1 is Err"); }
  if (!bad_pixel(data, 2, 0)) { return assert(false, "x=width is Err"); }
  if (!bad_pixel(data, 0, 2)) { return assert(false, "y=height is Err"); }
  return assert(true, "out-of-range pixels are Err");
}

fn t8() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[0] = 88 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "bad magic is Err"); }
  return assert(true, "bad magic is rejected");
}

fn t9() -> TestResult {
  let t = Vec[UInt8].new();
  t.push(66 as UInt8); t.push(77 as UInt8);
  if (!bad_info(bmp_parse_header(t))) { return assert(false, "short buffer is Err"); }
  return assert(true, "truncated header is rejected");
}

fn t10() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[28] = 8 as UInt8;
  data[29] = 0 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "8-bit is Err"); }
  return assert(true, "unsupported bit depth is rejected");
}

fn t11() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[30] = 1 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "compression is Err"); }
  return assert(true, "non-zero compression is rejected");
}

fn t12() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[26] = 2 as UInt8;
  data[27] = 0 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "planes=2 is Err"); }
  return assert(true, "planes must be 1");
}

fn t13() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[18] = 160 as UInt8; data[19] = 134 as UInt8; data[20] = 1 as UInt8; data[21] = 0 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "oversized width is Err"); }
  return assert(true, "pixel data beyond the buffer is rejected");
}

fn t14() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[22] = 255 as UInt8; data[23] = 255 as UInt8; data[24] = 255 as UInt8; data[25] = 255 as UInt8;
  if (pix(data, 0, 0) != rgb3(0, 0, 255)) { return assert(false, "top-down row 0 is the blue row"); }
  if (!bad_pixel(data, 0, 1)) { return assert(false, "top-down height is 1"); }
  return assert(true, "negative height means top-down rows");
}

fn t15() -> TestResult {
  let v = Vec[UInt8].new();
  v.push(1 as UInt8);
  if (!bad_bytes(bmp_build_24(v, 2, 2))) { return assert(false, "size mismatch is Err"); }
  return assert(true, "pixel buffer size must match dimensions");
}

fn t16() -> TestResult {
  let v = Vec[UInt8].new();
  if (!bad_bytes(bmp_build_24(v, 0, 0))) { return assert(false, "zero dims are Err"); }
  if (!bad_bytes(bmp_build_24(v, 1, 0))) { return assert(false, "zero height is Err"); }
  return assert(true, "non-positive dimensions are rejected");
}

fn t17() -> TestResult {
  let v = Vec[UInt8].new();
  var y = 0;
  while (y < 7) {
    var x = 0;
    while (x < 5) {
      v.push((x * 30) as UInt8);
      v.push((y * 20) as UInt8);
      v.push(((x + y) * 10) as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  let data = ok_bytes(bmp_build_24(v, 5, 7));
  if (data.len() != 54 + 112) { return assert(false, "5x7 size is 54 + 7*16"); }
  var yy = 0;
  while (yy < 7) {
    var xx = 0;
    while (xx < 5) {
      if (pix(data, xx, yy) != rgb3(xx * 30, yy * 20, (xx + yy) * 10)) {
        return assert(false, "5x7 pixel mismatch");
      }
      xx = xx + 1;
    }
    yy = yy + 1;
  }
  return assert(true, "5x7 all-pixel round-trip");
}

fn t18() -> TestResult {
  let data = ok_bytes(bmp_build_24(make_rgb2x2(), 2, 2));
  data[14] = 12 as UInt8;
  data[15] = 0 as UInt8; data[16] = 0 as UInt8; data[17] = 0 as UInt8;
  if (!bad_info(bmp_parse_header(data))) { return assert(false, "DIB 12 is Err"); }
  return assert(true, "DIB header must be at least 40 bytes");
}

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

  if failed == 0 {
    io.println("xiom.bmp: all tests passed");
  } else {
    io.println("xiom.bmp: tests failed");
  }
  return failed;
}
