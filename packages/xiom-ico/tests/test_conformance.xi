// XIOM -- xiom.ico conformance tests (16 checks)
// Port task: prove the pure-XIOM xiom.ico ICO/CUR container codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ico_tests
use xiom.io; use xiom.test; use xiom.ico;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on a Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so every expected
// error message is compared with this helper.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Unsigned byte `i` of `data` equals `want` (0..255).
fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// Byte-wise equality of two vectors.
fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if (x != y) { return false; }
    i = i + 1;
  }
  return true;
}

fn ok_info(r: Result[IcoInfo, Str]) -> IcoInfo {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return IcoInfo{ kind: 0; count: 0; dir_bytes: 0 }; },
  }
}

fn bad_info(r: Result[IcoInfo, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn info_err_is(r: Result[IcoInfo, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_entry(r: Result[IcoEntry, Str]) -> IcoEntry {
  match r {
    Ok(v) => { return v; },
    Err(e) => {
      return IcoEntry{ width: 0; height: 0; color_count: 0; planes: 0;
        bits: 0; bytes: 0; offset: 0 };
    },
  }
}

fn entry_err_is(r: Result[IcoEntry, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_builder(r: Result[IcoBuilder, Str]) -> IcoBuilder {
  match r {
    Ok(v) => { return v; },
    Err(e) => {
      return IcoBuilder{ kind: 0; widths: Vec[Int].new();
        heights: Vec[Int].new(); color_counts: Vec[Int].new();
        planes: Vec[Int].new(); bits: Vec[Int].new(); sizes: Vec[Int].new();
        payload: Vec[UInt8].new() };
    },
  }
}

fn bad_builder(r: Result[IcoBuilder, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

// Append one raw 16-byte directory entry; the values are the exact on-disk
// numbers (`wraw`/`hraw` are stored bytes, 0 meaning 256).
fn push_entry(out: &mut Vec[UInt8], wraw: Int, hraw: Int, cc: Int, planes: Int, bits: Int, size: Int, off: Int) {
  out.push(wraw as UInt8);
  out.push(hraw as UInt8);
  out.push(cc as UInt8);
  out.push(0 as UInt8);
  out.push((planes % 256) as UInt8);
  out.push(((planes / 256) % 256) as UInt8);
  out.push((bits % 256) as UInt8);
  out.push(((bits / 256) % 256) as UInt8);
  out.push((size % 256) as UInt8);
  out.push(((size / 256) % 256) as UInt8);
  out.push(((size / 65536) % 256) as UInt8);
  out.push(((size / 16777216) % 256) as UInt8);
  out.push((off % 256) as UInt8);
  out.push(((off / 256) % 256) as UInt8);
  out.push(((off / 65536) % 256) as UInt8);
  out.push(((off / 16777216) % 256) as UInt8);
}

// 2-image ICO: 16x16 32-bit (4 bytes at 38), then 256x256 32-bit
// (6 bytes at 42). Total 48 bytes.
fn mk_ico2() -> Vec[UInt8] {
  let d = Vec[UInt8].new();
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(1 as UInt8); d.push(0 as UInt8);
  d.push(2 as UInt8); d.push(0 as UInt8);
  push_entry(&mut d, 16, 16, 0, 1, 32, 4, 38);
  push_entry(&mut d, 0, 0, 0, 1, 32, 6, 42);
  d.push(170 as UInt8); d.push(187 as UInt8);
  d.push(204 as UInt8); d.push(221 as UInt8);
  d.push(1 as UInt8); d.push(2 as UInt8); d.push(3 as UInt8);
  d.push(4 as UInt8); d.push(5 as UInt8); d.push(6 as UInt8);
  return d;
}

// 1-image ICO: 48x32 8-bit 7-color, 4-byte payload at 22. Total 26 bytes.
fn mk_ico1() -> Vec[UInt8] {
  let d = Vec[UInt8].new();
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(1 as UInt8); d.push(0 as UInt8);
  d.push(1 as UInt8); d.push(0 as UInt8);
  push_entry(&mut d, 48, 32, 7, 1, 8, 4, 22);
  d.push(9 as UInt8); d.push(8 as UInt8);
  d.push(7 as UInt8); d.push(6 as UInt8);
  return d;
}

// 1-image CUR: 32x32 with hotspot (5, 7) and an 8-byte payload at 22.
// Total 30 bytes.
fn mk_cur1() -> Vec[UInt8] {
  let d = Vec[UInt8].new();
  d.push(0 as UInt8); d.push(0 as UInt8);
  d.push(2 as UInt8); d.push(0 as UInt8);
  d.push(1 as UInt8); d.push(0 as UInt8);
  push_entry(&mut d, 32, 32, 0, 5, 7, 8, 22);
  var i = 0;
  while (i < 8) {
    d.push((i + 10) as UInt8);
    i = i + 1;
  }
  return d;
}

// Deterministic payload of `n` bytes derived from `seed`.
fn make_payload(n: Int, seed: Int) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(((seed + i * 7) % 251) as UInt8);
    i = i + 1;
  }
  return v;
}

fn t1() -> TestResult {
  if (ico_dir_bytes(0) != 6) { return assert(false, "dir_bytes(0) is 6"); }
  if (ico_dir_bytes(1) != 22) { return assert(false, "dir_bytes(1) is 22"); }
  if (ico_dir_bytes(2) != 38) { return assert(false, "dir_bytes(2) is 38"); }
  if (ico_dir_bytes(65535) != 1048566) {
    return assert(false, "dir_bytes(65535) is 6 + 16 * 65535");
  }
  let d = mk_ico2();
  if (d.len() != 48) { return assert(false, "2-image fixture is 48 bytes"); }
  if (!byte_is(d, 0, 0)) { return assert(false, "header reserved byte 0"); }
  if (!byte_is(d, 1, 0)) { return assert(false, "header reserved byte 1"); }
  if (!byte_is(d, 2, 1)) { return assert(false, "header type low byte is 1"); }
  if (!byte_is(d, 3, 0)) { return assert(false, "header type high byte is 0"); }
  if (!byte_is(d, 4, 2)) { return assert(false, "header count low byte is 2"); }
  if (!byte_is(d, 5, 0)) { return assert(false, "header count high byte is 0"); }
  let info = ok_info(ico_parse_header(d));
  if (info.kind != 1) { return assert(false, "parsed kind is icon"); }
  if (info.count != 2) { return assert(false, "parsed count is 2"); }
  if (info.dir_bytes != 38) { return assert(false, "parsed dir_bytes is 38"); }
  return assert(true, "header decodes and the directory size table is exact");
}

fn t2() -> TestResult {
  let d = mk_ico2();
  let e0 = ok_entry(ico_entry(d, 0));
  if (e0.width != 16) { return assert(false, "entry 0 width 16"); }
  if (e0.height != 16) { return assert(false, "entry 0 height 16"); }
  if (e0.color_count != 0) { return assert(false, "entry 0 color count 0"); }
  if (e0.planes != 1) { return assert(false, "entry 0 planes 1"); }
  if (e0.bits != 32) { return assert(false, "entry 0 bits 32"); }
  if (e0.bytes != 4) { return assert(false, "entry 0 size 4"); }
  if (e0.offset != 38) { return assert(false, "entry 0 offset 38"); }
  let e1 = ok_entry(ico_entry(d, 1));
  if (e1.width != 256) { return assert(false, "entry 1 width sentinel is 256"); }
  if (e1.height != 256) { return assert(false, "entry 1 height sentinel is 256"); }
  if (e1.planes != 1) { return assert(false, "entry 1 planes 1"); }
  if (e1.bits != 32) { return assert(false, "entry 1 bits 32"); }
  if (e1.bytes != 6) { return assert(false, "entry 1 size 6"); }
  if (e1.offset != 42) { return assert(false, "entry 1 offset 42"); }
  return assert(true, "entries decode every field and the 0-as-256 sentinel");
}

fn t3() -> TestResult {
  let d = mk_ico2();
  let p0 = ok_bytes(ico_image_data(d, 0));
  if (p0.len() != 4) { return assert(false, "payload 0 is 4 bytes"); }
  if (!byte_is(p0, 0, 170)) { return assert(false, "payload 0 byte 0"); }
  if (!byte_is(p0, 1, 187)) { return assert(false, "payload 0 byte 1"); }
  if (!byte_is(p0, 2, 204)) { return assert(false, "payload 0 byte 2"); }
  if (!byte_is(p0, 3, 221)) { return assert(false, "payload 0 byte 3"); }
  let p1 = ok_bytes(ico_image_data(d, 1));
  if (p1.len() != 6) { return assert(false, "payload 1 is 6 bytes"); }
  var i = 0;
  while (i < 6) {
    if (!byte_is(p1, i, i + 1)) {
      return assert(false, "payload 1 byte matches the source");
    }
    i = i + 1;
  }
  return assert(true, "payload slices copy exactly the declared spans");
}

fn t4() -> TestResult {
  let d = mk_cur1();
  if (d.len() != 30) { return assert(false, "CUR fixture is 30 bytes"); }
  let info = ok_info(ico_parse(d));
  if (info.kind != 2) { return assert(false, "CUR kind is cursor"); }
  if (info.count != 1) { return assert(false, "CUR count is 1"); }
  if (info.dir_bytes != 22) { return assert(false, "CUR dir_bytes is 22"); }
  let e = ok_entry(ico_entry(d, 0));
  if (e.width != 32) { return assert(false, "cursor width 32"); }
  if (e.height != 32) { return assert(false, "cursor height 32"); }
  if (e.planes != 5) { return assert(false, "cursor hotspot x is 5"); }
  if (e.bits != 7) { return assert(false, "cursor hotspot y is 7"); }
  let p = ok_bytes(ico_image_data(d, 0));
  if (p.len() != 8) { return assert(false, "cursor payload is 8 bytes"); }
  if (!byte_is(p, 0, 10)) { return assert(false, "cursor payload first byte"); }
  if (!byte_is(p, 7, 17)) { return assert(false, "cursor payload last byte"); }
  if (!ico_is_cur(d)) { return assert(false, "is_cur is true for CUR"); }
  if (ico_is_ico(d)) { return assert(false, "is_ico is false for CUR"); }
  return assert(true, "CUR hotspots decode from the planes/bit-count words");
}

fn t5() -> TestResult {
  if (!bad_builder(ico_builder_new(0))) { return assert(false, "kind 0 is Err"); }
  if (!bad_builder(ico_builder_new(3))) { return assert(false, "kind 3 is Err"); }
  if (!bad_builder(ico_builder_new(255))) {
    return assert(false, "kind 255 is Err");
  }
  if (!bad_builder(ico_builder_new(-1))) {
    return assert(false, "negative kind is Err");
  }
  let i = ok_builder(ico_builder_new(1));
  if (ico_builder_kind(i) != 1) { return assert(false, "icon builder kind 1"); }
  if (ico_builder_count(i) != 0) {
    return assert(false, "new builder is empty");
  }
  let c = ok_builder(ico_builder_new(2));
  if (ico_builder_kind(c) != 2) { return assert(false, "cursor builder kind 2"); }
  return assert(true, "builder creation validates the resource type");
}

fn t6() -> TestResult {
  let b = ok_builder(ico_builder_new(1));
  let img0 = Vec[UInt8].new();
  img0.push(1 as UInt8); img0.push(2 as UInt8);
  img0.push(3 as UInt8); img0.push(4 as UInt8);
  let img1 = Vec[UInt8].new();
  var i = 0;
  while (i < 6) {
    img1.push((i + 1) as UInt8);
    i = i + 1;
  }
  let r0 = ico_builder_add(&mut b, img0, 16, 16, 0, 1, 32);
  if (!r0.is_ok) { return assert(false, "add image 0 is Ok"); }
  let n0: Int = r0.value;
  if (n0 != 1) { return assert(false, "add image 0 returns 1"); }
  let r1 = ico_builder_add(&mut b, img1, 256, 256, 0, 1, 32);
  if (!r1.is_ok) { return assert(false, "add image 1 is Ok"); }
  let n1: Int = r1.value;
  if (n1 != 2) { return assert(false, "add image 1 returns 2"); }
  if (ico_builder_count(b) != 2) { return assert(false, "builder count is 2"); }
  let out = ok_bytes(ico_builder_emit(b));
  if (out.len() != 48) {
    return assert(false, "emitted file is 6 + 32 + 10 bytes");
  }
  if (!byte_is(out, 0, 0)) { return assert(false, "emitted reserved low byte"); }
  if (!byte_is(out, 1, 0)) { return assert(false, "emitted reserved high byte"); }
  if (!byte_is(out, 2, 1)) { return assert(false, "emitted type low byte 1"); }
  if (!byte_is(out, 4, 2)) { return assert(false, "emitted count low byte 2"); }
  if (!byte_is(out, 6, 16)) { return assert(false, "entry 0 width byte 16"); }
  if (!byte_is(out, 9, 0)) { return assert(false, "entry 0 reserved byte 0"); }
  if (!byte_is(out, 18, 38)) {
    return assert(false, "entry 0 offset low byte 38");
  }
  if (!byte_is(out, 19, 0)) { return assert(false, "entry 0 offset high byte"); }
  if (!byte_is(out, 22, 0)) {
    return assert(false, "entry 1 width is the 256 sentinel");
  }
  if (!byte_is(out, 34, 42)) {
    return assert(false, "entry 1 offset low byte 42");
  }
  if (!byte_is(out, 38, 1)) { return assert(false, "payload 0 first byte"); }
  if (!byte_is(out, 47, 6)) { return assert(false, "payload 1 last byte"); }
  let info = ok_info(ico_parse(out));
  if (info.count != 2) { return assert(false, "emitted file parses count 2"); }
  let e1 = ok_entry(ico_entry(out, 1));
  if (e1.width != 256) { return assert(false, "emitted 256 round-trips"); }
  if (e1.offset != 42) { return assert(false, "emitted offset 42 round-trips"); }
  let back = ok_bytes(ico_image_data(out, 0));
  if (!vec_eq(back, img0)) { return assert(false, "payload 0 round-trips"); }
  return assert(true, "builder emits a canonical directory with recomputed offsets");
}

fn t7() -> TestResult {
  let b = ok_builder(ico_builder_new(1));
  let img = Vec[UInt8].new();
  img.push(77 as UInt8);
  let r = ico_builder_add(&mut b, img, 256, 256, 0, 0, 0);
  if (!r.is_ok) { return assert(false, "256x256 image is accepted"); }
  let out = ok_bytes(ico_builder_emit(b));
  if (out.len() != 23) { return assert(false, "single-image emit is 23 bytes"); }
  if (!byte_is(out, 6, 0)) {
    return assert(false, "width 256 writes the 0 sentinel");
  }
  if (!byte_is(out, 7, 0)) {
    return assert(false, "height 256 writes the 0 sentinel");
  }
  let e = ok_entry(ico_entry(out, 0));
  if (e.width != 256) { return assert(false, "sentinel reads back as 256"); }
  if (e.height != 256) { return assert(false, "height sentinel reads 256"); }
  let b2 = ok_builder(ico_builder_new(1));
  let r2 = ico_builder_add(&mut b2, img, 1, 1, 0, 0, 0);
  if (!r2.is_ok) { return assert(false, "1x1 image is accepted"); }
  let out2 = ok_bytes(ico_builder_emit(b2));
  if (!byte_is(out2, 6, 1)) {
    return assert(false, "width 1 is stored verbatim");
  }
  if (!byte_is(out2, 7, 1)) {
    return assert(false, "height 1 is stored verbatim");
  }
  return assert(true, "the 256-pixel sentinel round-trips and 1 is verbatim");
}

fn t8() -> TestResult {
  let b = ok_builder(ico_builder_new(1));
  let img = Vec[UInt8].new();
  img.push(3 as UInt8);
  let empty = Vec[UInt8].new();
  if (!int_err_is(ico_builder_add(&mut b, img, 0, 16, 0, 1, 32), "ico: invalid width")) {
    return assert(false, "width 0 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 257, 16, 0, 1, 32), "ico: invalid width")) {
    return assert(false, "width 257 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, -1, 16, 0, 1, 32), "ico: invalid width")) {
    return assert(false, "width -1 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 0, 0, 1, 32), "ico: invalid height")) {
    return assert(false, "height 0 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 257, 0, 1, 32), "ico: invalid height")) {
    return assert(false, "height 257 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, -1, 1, 32), "ico: invalid color count")) {
    return assert(false, "color count -1 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, 256, 1, 32), "ico: invalid color count")) {
    return assert(false, "color count 256 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, 0, -1, 32), "ico: invalid planes or hotspot x")) {
    return assert(false, "planes -1 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, 0, 65536, 32), "ico: invalid planes or hotspot x")) {
    return assert(false, "planes 65536 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, 0, 1, -1), "ico: invalid bit count or hotspot y")) {
    return assert(false, "bit count -1 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, img, 16, 16, 0, 1, 65536), "ico: invalid bit count or hotspot y")) {
    return assert(false, "bit count 65536 is Err");
  }
  if (!int_err_is(ico_builder_add(&mut b, empty, 16, 16, 0, 1, 32), "ico: empty image resource")) {
    return assert(false, "empty payload is Err");
  }
  if (ico_builder_count(b) != 0) {
    return assert(false, "failed adds leave the builder empty");
  }
  let okr = ico_builder_add(&mut b, img, 256, 1, 255, 65535, 65535);
  if (!okr.is_ok) { return assert(false, "boundary maxima are accepted"); }
  return assert(true, "builder field ranges are enforced without partial appends");
}

fn t9() -> TestResult {
  let c = ok_builder(ico_builder_new(2));
  let img = Vec[UInt8].new();
  img.push(9 as UInt8); img.push(8 as UInt8); img.push(7 as UInt8);
  let r = ico_builder_add_cursor(&mut c, img, 32, 32, 16, 5, 7);
  if (!r.is_ok) { return assert(false, "cursor add is Ok"); }
  let n: Int = r.value;
  if (n != 1) { return assert(false, "cursor add returns 1"); }
  if (!int_err_is(ico_builder_add(&mut c, img, 32, 32, 16, 0, 0), "ico: not an icon builder")) {
    return assert(false, "add on a cursor builder is rejected");
  }
  let i = ok_builder(ico_builder_new(1));
  if (!int_err_is(ico_builder_add_cursor(&mut i, img, 32, 32, 16, 0, 0), "ico: not a cursor builder")) {
    return assert(false, "add_cursor on an icon builder is rejected");
  }
  let out = ok_bytes(ico_builder_emit(c));
  if (out.len() != 25) { return assert(false, "cursor emit is 22 + 3 bytes"); }
  if (!byte_is(out, 2, 2)) { return assert(false, "cursor type byte is 2"); }
  if (!byte_is(out, 10, 5)) { return assert(false, "hotspot x low byte is 5"); }
  if (!byte_is(out, 12, 7)) { return assert(false, "hotspot y low byte is 7"); }
  let info = ok_info(ico_parse(out));
  if (info.kind != 2) { return assert(false, "emitted cursor parses as CUR"); }
  let e = ok_entry(ico_entry(out, 0));
  if (e.planes != 5) { return assert(false, "hotspot x round-trips"); }
  if (e.bits != 7) { return assert(false, "hotspot y round-trips"); }
  let back = ok_bytes(ico_image_data(out, 0));
  if (!vec_eq(back, img)) { return assert(false, "cursor payload round-trips"); }
  return assert(true, "cursor builder stores hotspots and guards builder kinds");
}

fn t10() -> TestResult {
  let b = ok_builder(ico_builder_new(1));
  let mini = Vec[UInt8].new();
  mini.push(1 as UInt8);
  var i = 0;
  while (i < 65535) {
    let r = ico_builder_add(&mut b, mini, 1, 1, 0, 0, 0);
    if (!r.is_ok) {
      return assert(false, "the first 65535 adds are Ok");
    }
    i = i + 1;
  }
  if (ico_builder_count(b) != 65535) {
    return assert(false, "the count reaches 65535");
  }
  let over = ico_builder_add(&mut b, mini, 1, 1, 0, 0, 0);
  if (!int_err_is(over, "ico: too many images")) {
    return assert(false, "the 65536th add is rejected");
  }
  if (ico_builder_count(b) != 65535) {
    return assert(false, "a rejected add leaves the count unchanged");
  }
  return assert(true, "the 16-bit on-disk count caps the builder at 65535");
}

fn t11() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!info_err_is(ico_parse_header(empty), "ico: truncated header")) {
    return assert(false, "empty buffer is a truncated header");
  }
  let five = Vec[UInt8].new();
  var i = 0;
  while (i < 5) {
    five.push(0 as UInt8);
    i = i + 1;
  }
  if (!info_err_is(ico_parse_header(five), "ico: truncated header")) {
    return assert(false, "5-byte buffer is a truncated header");
  }
  let r = mk_ico2();
  r[1] = 1 as UInt8;
  if (!info_err_is(ico_parse_header(r), "ico: invalid reserved field")) {
    return assert(false, "non-zero reserved word is Err");
  }
  let t0 = mk_ico2();
  t0[2] = 0 as UInt8;
  if (!info_err_is(ico_parse_header(t0), "ico: unknown resource type")) {
    return assert(false, "type 0 is Err");
  }
  let t3 = mk_ico2();
  t3[2] = 3 as UInt8;
  if (!info_err_is(ico_parse_header(t3), "ico: unknown resource type")) {
    return assert(false, "type 3 is Err");
  }
  let t255 = mk_ico2();
  t255[2] = 255 as UInt8;
  if (!info_err_is(ico_parse_header(t255), "ico: unknown resource type")) {
    return assert(false, "type 255 is Err");
  }
  let z = mk_ico2();
  z[4] = 0 as UInt8;
  z[5] = 0 as UInt8;
  if (!info_err_is(ico_parse_header(z), "ico: zero image count")) {
    return assert(false, "count 0 is Err");
  }
  let h = Vec[UInt8].new();
  h.push(0 as UInt8); h.push(0 as UInt8);
  h.push(1 as UInt8); h.push(0 as UInt8);
  h.push(255 as UInt8); h.push(255 as UInt8);
  if (!info_err_is(ico_parse_header(h), "ico: directory out of bounds")) {
    return assert(false, "huge count is Err");
  }
  let one = Vec[UInt8].new();
  one.push(0 as UInt8); one.push(0 as UInt8);
  one.push(1 as UInt8); one.push(0 as UInt8);
  one.push(1 as UInt8); one.push(0 as UInt8);
  i = 0;
  while (i < 15) {
    one.push(0 as UInt8);
    i = i + 1;
  }
  if (!info_err_is(ico_parse_header(one), "ico: directory out of bounds")) {
    return assert(false, "count 1 in a 21-byte buffer is Err");
  }
  return assert(true, "header validation covers truncation, reserved, type, count, directory");
}

fn t12() -> TestResult {
  let a = mk_ico1();
  a[9] = 1 as UInt8;
  if (!info_err_is(ico_parse(a), "ico: invalid entry reserved field")) {
    return assert(false, "entry reserved is Err");
  }
  let b = mk_ico1();
  b[14] = 0 as UInt8; b[15] = 0 as UInt8;
  b[16] = 0 as UInt8; b[17] = 0 as UInt8;
  if (!info_err_is(ico_parse(b), "ico: empty image resource")) {
    return assert(false, "size 0 is Err");
  }
  let c = mk_ico1();
  c[14] = 100 as UInt8;
  if (!info_err_is(ico_parse(c), "ico: entry size out of bounds")) {
    return assert(false, "size above the buffer is Err");
  }
  let o = mk_ico1();
  o[18] = 0 as UInt8; o[19] = 0 as UInt8;
  o[20] = 0 as UInt8; o[21] = 0 as UInt8;
  if (!info_err_is(ico_parse(o), "ico: image data overlaps directory")) {
    return assert(false, "offset inside the directory is Err");
  }
  let p = mk_ico1();
  p[18] = 24 as UInt8;
  if (!info_err_is(ico_parse(p), "ico: image data out of bounds")) {
    return assert(false, "offset + size past the buffer is Err");
  }
  let good = mk_ico1();
  if (bad_info(ico_parse(good))) {
    return assert(false, "the untouched fixture is Ok");
  }
  return assert(true, "entry validation covers reserved, empty, oversize, overlap, overrun");
}

fn t13() -> TestResult {
  let d = mk_ico2();
  if (!entry_err_is(ico_entry(d, -1), "ico: entry index out of range")) {
    return assert(false, "index -1 is Err");
  }
  if (!entry_err_is(ico_entry(d, 2), "ico: entry index out of range")) {
    return assert(false, "index == count is Err");
  }
  if (!entry_err_is(ico_entry(d, 99), "ico: entry index out of range")) {
    return assert(false, "index far above count is Err");
  }
  if (!bytes_err_is(ico_image_data(d, 2), "ico: entry index out of range")) {
    return assert(false, "payload index == count is Err");
  }
  let e1 = ok_entry(ico_entry(d, 1));
  if (e1.width != 256) { return assert(false, "index 1 is Ok"); }
  if (e1.bytes != 6) { return assert(false, "index 1 payload size is 6"); }
  if (e1.offset != 42) { return assert(false, "index 1 offset is 42"); }
  let short = Vec[UInt8].new();
  short.push(0 as UInt8); short.push(0 as UInt8); short.push(1 as UInt8);
  if (!entry_err_is(ico_entry(short, 0), "ico: truncated header")) {
    return assert(false, "entry accessor forwards header errors");
  }
  if (!bytes_err_is(ico_image_data(short, 0), "ico: truncated header")) {
    return assert(false, "payload accessor forwards header errors");
  }
  return assert(true, "index bounds are checked and parse errors are forwarded");
}

fn t14() -> TestResult {
  let i = mk_ico2();
  if (!ico_is_ico(i)) { return assert(false, "is_ico is true for ICO"); }
  if (ico_is_cur(i)) { return assert(false, "is_cur is false for ICO"); }
  let c = mk_cur1();
  if (ico_is_ico(c)) { return assert(false, "is_ico is false for CUR"); }
  if (!ico_is_cur(c)) { return assert(false, "is_cur is true for CUR"); }
  let short = Vec[UInt8].new();
  short.push(0 as UInt8); short.push(0 as UInt8); short.push(1 as UInt8);
  if (ico_is_ico(short)) { return assert(false, "short buffer is not ICO"); }
  if (ico_is_cur(short)) { return assert(false, "short buffer is not CUR"); }
  let z = mk_ico2();
  z[4] = 0 as UInt8;
  z[5] = 0 as UInt8;
  if (ico_is_ico(z)) { return assert(false, "zero-count buffer is not ICO"); }
  return assert(true, "ico_is_ico and ico_is_cur classify valid headers only");
}

fn t15() -> TestResult {
  let b = ok_builder(ico_builder_new(1));
  let i0 = make_payload(3, 5);
  let i1 = make_payload(5, 60);
  let i2 = make_payload(7, 130);
  let r0 = ico_builder_add(&mut b, i0, 16, 16, 2, 1, 8);
  if (!r0.is_ok) { return assert(false, "add image 0"); }
  let r1 = ico_builder_add(&mut b, i1, 256, 32, 0, 1, 32);
  if (!r1.is_ok) { return assert(false, "add image 1"); }
  let r2 = ico_builder_add(&mut b, i2, 48, 64, 255, 0, 4);
  if (!r2.is_ok) { return assert(false, "add image 2"); }
  let o1 = ok_bytes(ico_builder_emit(b));
  let o2 = ok_bytes(ico_builder_emit(b));
  if (o1.len() != 6 + 48 + 15) {
    return assert(false, "3-image emit is 6 + 48 + 15 bytes");
  }
  if (!vec_eq(o1, o2)) { return assert(false, "emit is deterministic"); }
  let info = ok_info(ico_parse(o1));
  if (info.count != 3) { return assert(false, "round-trip count 3"); }
  let e0 = ok_entry(ico_entry(o1, 0));
  let e1 = ok_entry(ico_entry(o1, 1));
  let e2 = ok_entry(ico_entry(o1, 2));
  if (e0.width != 16) { return assert(false, "image 0 width"); }
  if (e0.color_count != 2) { return assert(false, "image 0 color count"); }
  if (e1.width != 256) { return assert(false, "image 1 width 256"); }
  if (e1.height != 32) { return assert(false, "image 1 height 32"); }
  if (e1.bits != 32) { return assert(false, "image 1 bits 32"); }
  if (e2.planes != 0) { return assert(false, "image 2 planes 0"); }
  if (e2.color_count != 255) { return assert(false, "image 2 color count 255"); }
  if (e0.offset != 54) { return assert(false, "image 0 offset 54"); }
  if (e1.offset != 57) { return assert(false, "image 1 offset 57"); }
  if (e2.offset != 62) { return assert(false, "image 2 offset 62"); }
  if (!vec_eq(ok_bytes(ico_image_data(o1, 0)), i0)) {
    return assert(false, "image 0 payload round-trips");
  }
  if (!vec_eq(ok_bytes(ico_image_data(o1, 1)), i1)) {
    return assert(false, "image 1 payload round-trips");
  }
  if (!vec_eq(ok_bytes(ico_image_data(o1, 2)), i2)) {
    return assert(false, "image 2 payload round-trips");
  }
  return assert(true, "three-image build parses back field-for-field");
}

fn t16() -> TestResult {
  let empty = ok_builder(ico_builder_new(1));
  if (!bytes_err_is(ico_builder_emit(empty), "ico: zero image count")) {
    return assert(false, "empty builder emit is Err");
  }
  let img = Vec[UInt8].new();
  img.push(42 as UInt8);
  let p = ok_builder(ico_builder_new(1));
  let rp = ico_builder_add(&mut p, img, 16, 16, 0, 1, 32);
  if (!rp.is_ok) { return assert(false, "tamper fixture builds"); }
  p.payload.push(0 as UInt8);
  if (!bytes_err_is(ico_builder_emit(p), "ico: builder is inconsistent")) {
    return assert(false, "payload/size mismatch is Err");
  }
  let s = ok_builder(ico_builder_new(1));
  let rs = ico_builder_add(&mut s, img, 16, 16, 0, 1, 32);
  if (!rs.is_ok) { return assert(false, "tamper fixture builds"); }
  s.sizes.push(4);
  if (!bytes_err_is(ico_builder_emit(s), "ico: builder is inconsistent")) {
    return assert(false, "parallel length mismatch is Err");
  }
  let z = ok_builder(ico_builder_new(1));
  let rz = ico_builder_add(&mut z, img, 16, 16, 0, 1, 32);
  if (!rz.is_ok) { return assert(false, "tamper fixture builds"); }
  z.sizes[0] = 0;
  if (!bytes_err_is(ico_builder_emit(z), "ico: empty image resource")) {
    return assert(false, "zero recorded size is Err");
  }
  let w = ok_builder(ico_builder_new(1));
  let rw = ico_builder_add(&mut w, img, 16, 16, 0, 1, 32);
  if (!rw.is_ok) { return assert(false, "tamper fixture builds"); }
  w.widths[0] = 0;
  if (!bytes_err_is(ico_builder_emit(w), "ico: invalid width")) {
    return assert(false, "tampered width is Err");
  }
  let cc = ok_builder(ico_builder_new(1));
  let rcc = ico_builder_add(&mut cc, img, 16, 16, 0, 1, 32);
  if (!rcc.is_ok) { return assert(false, "tamper fixture builds"); }
  cc.color_counts[0] = 999;
  if (!bytes_err_is(ico_builder_emit(cc), "ico: invalid color count")) {
    return assert(false, "tampered color count is Err");
  }
  let k = ok_builder(ico_builder_new(1));
  let rk = ico_builder_add(&mut k, img, 16, 16, 0, 1, 32);
  if (!rk.is_ok) { return assert(false, "tamper fixture builds"); }
  k.kind = 7;
  if (!bytes_err_is(ico_builder_emit(k), "ico: unknown resource type")) {
    return assert(false, "tampered kind is Err");
  }
  return assert(true, "emit rejects empty and tampered builders deterministically");
}

fn main() -> Int {
  io.println("=== xiom.ico conformance tests ===");
  var failed: Int = 0;
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
  if failed == 0 {
    io.println("xiom.ico: all tests passed");
  } else {
    io.println("xiom.ico: tests failed");
  }
  return failed;
}
