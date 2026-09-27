// XIOM -- xiom.jpeg conformance tests (16 checks)
// Port task: prove the pure-XIOM xiom.jpeg JPEG (ITU-T T.81) marker parser.
// All fixtures are synthetic byte buffers built here; no external data files.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module jpeg_tests
use xiom.io; use xiom.test; use xiom.jpeg;
use xiom.string; use xiom.string.compare;
use xiom.convert;

// All Str equality goes through str_compare; expected messages are literals,
// parsed messages may come from concatenations.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Unsigned byte `i` of `data` equals `want` (0..255).
fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

fn ok_img(r: Result[JpegImage, JpegError]) -> JpegImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_img(); },
  }
}

fn img_err_is(r: Result[JpegImage, JpegError], base: Str, off: Int) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => {
      if (jpeg_error_offset(e) != off) { return false; }
      return streq(jpeg_error_message(e), at(base, off));
    },
  }
}

fn bad_img(r: Result[JpegImage, JpegError]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

// Expected message text: "<base> at <off>".
fn at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// The dummy image returned by ok_img when a test unexpectedly hit an error.
fn empty_img() -> JpegImage {
  return JpegImage{
    width: 0; height: 0; precision: 0; frame_marker: 0; progressive: 0;
    component_id: Vec[Int].new(); component_h: Vec[Int].new();
    component_v: Vec[Int].new(); component_quant: Vec[Int].new();
    has_jfif: 0; jfif_version_major: 0; jfif_version_minor: 0; jfif_units: 0;
    jfif_density_x: 0; jfif_density_y: 0; jfif_thumb_w: 0; jfif_thumb_h: 0;
    has_exif: 0; exif_offset: -1;
    quant_id: Vec[Int].new(); quant_precision: Vec[Int].new();
    quant_value_offset: Vec[Int].new(); quant_values: Vec[Int].new();
    dht_class: Vec[Int].new(); dht_id: Vec[Int].new(); dht_symbols: Vec[Int].new();
    dht_count_offset: Vec[Int].new(); dht_counts: Vec[Int].new();
    scan_ss: Vec[Int].new(); scan_se: Vec[Int].new();
    scan_ah: Vec[Int].new(); scan_al: Vec[Int].new();
    scan_component_count: Vec[Int].new(); scan_component_offset: Vec[Int].new();
    scan_component_id: Vec[Int].new(); scan_component_dc: Vec[Int].new();
    scan_component_ac: Vec[Int].new();
    scan_data_offset: Vec[Int].new(); scan_data_length: Vec[Int].new();
    scan_restart_count: Vec[Int].new(); scan_marker_offset: Vec[Int].new();
    app_marker: Vec[Int].new(); app_offset: Vec[Int].new();
    app_length: Vec[Int].new(); app_data_offset: Vec[Int].new();
    com_offset: Vec[Int].new(); com_length: Vec[Int].new();
    restart_interval: -1; dri_count: 0; eoi_offset: -1; total_bytes: 0;
  };
}

// --------------------------------------------------
//  Fixture builders (synthetic JPEG byte buffers)
// --------------------------------------------------

fn push_be16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while (i < v.len()) {
    out.push(v[i]);
    i = i + 1;
  }
}

fn push_ff(out: &mut Vec[UInt8], code: Int) {
  out.push(255 as UInt8);
  out.push(code as UInt8);
}

// One complete segment: FF code BE16(payload + 2) payload.
fn push_seg(out: &mut Vec[UInt8], code: Int, payload: &Vec[UInt8]) {
  push_ff(out, code);
  push_be16(out, payload.len() + 2);
  push_bytes(out, payload);
}

fn append(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_bytes(&mut v, a);
  push_bytes(&mut v, b);
  return v;
}

fn raw_bytes(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(((seed + i) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn comps1() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(1);
  return v;
}

fn zeros1() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  return v;
}

fn one_of(v: Int) -> Vec[Int] {
  var x = Vec[Int].new();
  x.push(v);
  return x;
}

fn zero16() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while (i < 16) {
    v.push(0);
    i = i + 1;
  }
  return v;
}

// JFIF APP0 payload: identifier, version, units, densities, thumbnail dims
// and the 3 * tw * th thumbnail bytes.
fn jfif_payload(major: Int, minor: Int, units: Int, dx: Int, dy: Int, tw: Int, th: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(74 as UInt8);
  v.push(70 as UInt8);
  v.push(73 as UInt8);
  v.push(70 as UInt8);
  v.push(0 as UInt8);
  v.push(major as UInt8);
  v.push(minor as UInt8);
  v.push(units as UInt8);
  push_be16(&mut v, dx);
  push_be16(&mut v, dy);
  v.push(tw as UInt8);
  v.push(th as UInt8);
  var n = tw * th * 3;
  var i = 0;
  while (i < n) {
    v.push(((i + 1) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// DQT payload for one 8-bit table: values ((seed + i) % 255) + 1 (1..255).
fn dqt8_payload(id: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(id as UInt8);
  var i = 0;
  while (i < 64) {
    v.push((((seed + i) % 255) + 1) as UInt8);
    i = i + 1;
  }
  return v;
}

// DQT payload for one 16-bit table: values ((seed + i) % 65000) + 1.
fn dqt16_payload(id: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((16 + id) as UInt8);
  var i = 0;
  while (i < 64) {
    push_be16(&mut v, ((seed + i) % 65000) + 1);
    i = i + 1;
  }
  return v;
}

// DHT payload for one table: class/id byte, 16 counts, symbol bytes.
fn dht_payload(cls: Int, id: Int, counts: &Vec[Int], symbols: &Vec[Int]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push((cls * 16 + id) as UInt8);
  var i = 0;
  while (i < 16) {
    let c: Int = counts[i];
    v.push(c as UInt8);
    i = i + 1;
  }
  i = 0;
  while (i < symbols.len()) {
    let s: Int = symbols[i];
    v.push(s as UInt8);
    i = i + 1;
  }
  return v;
}

// SOF payload: precision, height, width, Nf, one id/hv/tq triple per component.
fn sof_payload(precision: Int, w: Int, h: Int, cids: &Vec[Int], hvs: &Vec[Int], tqs: &Vec[Int]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(precision as UInt8);
  push_be16(&mut v, h);
  push_be16(&mut v, w);
  v.push(cids.len() as UInt8);
  var i = 0;
  while (i < cids.len()) {
    let c: Int = cids[i];
    let hv: Int = hvs[i];
    let tq: Int = tqs[i];
    v.push(c as UInt8);
    v.push(hv as UInt8);
    v.push(tq as UInt8);
    i = i + 1;
  }
  return v;
}

// SOS payload: Ns, per-selector id + Td/Ta, Ss, Se, Ah/Al.
fn sos_payload(ids: &Vec[Int], tds: &Vec[Int], tas: &Vec[Int], ss: Int, se: Int, ah: Int, al: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(ids.len() as UInt8);
  var i = 0;
  while (i < ids.len()) {
    let id: Int = ids[i];
    let td: Int = tds[i];
    let ta: Int = tas[i];
    v.push(id as UInt8);
    v.push((td * 16 + ta) as UInt8);
    i = i + 1;
  }
  v.push(ss as UInt8);
  v.push(se as UInt8);
  v.push((ah * 16 + al) as UInt8);
  return v;
}

// Valid gray SOF0 segment: 8-bit, 2 x 3, component id 1 (h/v 1, tq 0).
fn push_gray_sof(out: &mut Vec[UInt8]) {
  let sp = sof_payload(8, 2, 3, comps1(), one_of(17), one_of(0));
  push_seg(out, 192, sp);
}

// Valid single-component baseline SOS segment: 0 / 63 / 0 / 0.
fn push_gray_sos(out: &mut Vec[UInt8]) {
  let sp = sos_payload(comps1(), zeros1(), zeros1(), 0, 63, 0, 0);
  push_seg(out, 218, sp);
}

// SOI + SOF + SOS + one entropy byte + EOI. Offsets: SOF at 2 (payload 6,
// 13 bytes -> ends 15), SOS at 15 (payload 19, 10 bytes -> ends 25), scan at
// 25, EOI at 26, total 28.
fn mk_gray(sof_code: Int, precision: Int, w: Int, h: Int, hv: Int, tq: Int, ss: Int, se: Int, ah: Int, al: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  let sp = sof_payload(precision, w, h, comps1(), one_of(hv), one_of(tq));
  push_seg(&mut out, sof_code, sp);
  let sosp = sos_payload(comps1(), zeros1(), zeros1(), ss, se, ah, al);
  push_seg(&mut out, 218, sosp);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + SOF(code, payload) + valid gray SOS + 1 scan byte + EOI. The SOF
// payload starts at offset 6.
fn mk_sof_payload(sof_code: Int, sp: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_seg(&mut out, sof_code, sp);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + valid gray SOF + SOS(payload) + 1 scan byte + EOI. SOS is at 15 and
// its payload at 19.
fn mk_sos_payload(sp: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_gray_sof(&mut out);
  push_seg(&mut out, 218, sp);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + DQT(payload) + gray SOF + gray SOS + 1 scan byte + EOI. DQT is at 2
// and its payload at 6.
fn mk_dqt_prefix(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_seg(&mut out, 219, payload);
  push_gray_sof(&mut out);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + gray SOF + DHT(payload) + gray SOS + 1 scan byte + EOI. DHT is at 15
// and its payload at 19.
fn mk_dht_prefix(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_gray_sof(&mut out);
  push_seg(&mut out, 196, payload);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + gray SOF + DRI(payload) + gray SOS + 1 scan byte + EOI. DRI is at 15
// and its payload at 19.
fn mk_dri_prefix(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_gray_sof(&mut out);
  push_seg(&mut out, 221, payload);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// SOI + APP0(payload) + gray SOF + gray SOS + 1 scan byte + EOI. APP0 is at
// 2 and its payload at 6.
fn mk_app0_prefix(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_seg(&mut out, 224, payload);
  push_gray_sof(&mut out);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// The canonical complete baseline fixture: SOI, JFIF APP0, one 8-bit DQT,
// SOF0 (2 x 3 gray), one DC DHT, DRI 2, SOS, a 4-byte stuffed scan
// (AA FF 00 BB) and EOI. Offsets: APP0 2, DQT 20, SOF 89, DHT 102, DRI 124,
// SOS 130, scan 140 (length 4), EOI 144, total 146.
fn mk_canonical() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  let jf = jfif_payload(1, 2, 1, 300, 300, 0, 0);
  push_seg(&mut out, 224, jf);
  let dq = dqt8_payload(0, 5);
  push_seg(&mut out, 219, dq);
  push_gray_sof(&mut out);
  var cnt = zero16();
  cnt[0] = 1;
  var syms = Vec[Int].new();
  syms.push(0);
  let dh = dht_payload(0, 0, cnt, syms);
  push_seg(&mut out, 196, dh);
  var dri = Vec[UInt8].new();
  push_be16(&mut dri, 2);
  push_seg(&mut out, 221, dri);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  out.push(255 as UInt8);
  out.push(0 as UInt8);
  out.push(187 as UInt8);
  push_ff(&mut out, 217);
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let d = mk_canonical();
  if (d.len() != 146) { return assert(false, "canonical fixture is 146 bytes"); }
  if (!jpeg_is_jpeg(d)) { return assert(false, "signature classifies as JPEG"); }
  let img = ok_img(jpeg_parse(d));
  if (jpeg_width(img) != 2) { return assert(false, "width 2"); }
  if (jpeg_height(img) != 3) { return assert(false, "height 3"); }
  if (jpeg_precision(img) != 8) { return assert(false, "precision 8"); }
  if (jpeg_frame_marker(img) != 192) { return assert(false, "SOF0 frame marker"); }
  if (jpeg_is_progressive(img)) { return assert(false, "baseline is not progressive"); }
  if (jpeg_component_count(img) != 1) { return assert(false, "one component"); }
  if (jpeg_component_id(img, 0) != 1) { return assert(false, "component id 1"); }
  if (jpeg_component_h(img, 0) != 1) { return assert(false, "component h 1"); }
  if (jpeg_component_v(img, 0) != 1) { return assert(false, "component v 1"); }
  if (jpeg_component_quant(img, 0) != 0) { return assert(false, "component quant 0"); }
  if (!jpeg_has_jfif(img)) { return assert(false, "JFIF APP0 parsed"); }
  if (jpeg_jfif_version_major(img) != 1) { return assert(false, "JFIF major 1"); }
  if (jpeg_jfif_version_minor(img) != 2) { return assert(false, "JFIF minor 2"); }
  if (jpeg_jfif_units(img) != 1) { return assert(false, "JFIF units 1"); }
  if (jpeg_jfif_density_x(img) != 300) { return assert(false, "JFIF density x 300"); }
  if (jpeg_jfif_density_y(img) != 300) { return assert(false, "JFIF density y 300"); }
  if (jpeg_jfif_thumb_w(img) != 0) { return assert(false, "JFIF thumbnail width 0"); }
  if (jpeg_jfif_thumb_h(img) != 0) { return assert(false, "JFIF thumbnail height 0"); }
  if (jpeg_has_exif(img)) { return assert(false, "no EXIF in the canonical fixture"); }
  if (jpeg_exif_offset(img) != -1) { return assert(false, "EXIF offset sentinel"); }
  if (jpeg_quant_table_count(img) != 1) { return assert(false, "one quant table"); }
  if (jpeg_quant_id(img, 0) != 0) { return assert(false, "quant id 0"); }
  if (jpeg_quant_precision(img, 0) != 0) { return assert(false, "quant precision 0"); }
  if (jpeg_quant_value_offset(img, 0) != 0) { return assert(false, "quant value offset 0"); }
  if (jpeg_quant_value(img, 0, 0) != 6) { return assert(false, "quant value 0 is 6"); }
  if (jpeg_quant_value(img, 0, 63) != 69) { return assert(false, "quant value 63 is 69"); }
  if (jpeg_dht_table_count(img) != 1) { return assert(false, "one DHT table"); }
  if (jpeg_dht_class(img, 0) != 0) { return assert(false, "DHT class 0"); }
  if (jpeg_dht_id(img, 0) != 0) { return assert(false, "DHT id 0"); }
  if (jpeg_dht_symbol_count(img, 0) != 1) { return assert(false, "DHT symbol count 1"); }
  if (jpeg_dht_count(img, 0, 0) != 1) { return assert(false, "DHT count 0 is 1"); }
  if (jpeg_dht_count(img, 0, 1) != 0) { return assert(false, "DHT count 1 is 0"); }
  if (jpeg_restart_interval(img) != 2) { return assert(false, "restart interval 2"); }
  if (!jpeg_has_dri(img)) { return assert(false, "DRI present"); }
  if (jpeg_dri_count(img) != 1) { return assert(false, "one DRI"); }
  if (jpeg_scan_count(img) != 1) { return assert(false, "one scan"); }
  if (jpeg_scan_ss(img, 0) != 0) { return assert(false, "scan Ss 0"); }
  if (jpeg_scan_se(img, 0) != 63) { return assert(false, "scan Se 63"); }
  if (jpeg_scan_ah(img, 0) != 0) { return assert(false, "scan Ah 0"); }
  if (jpeg_scan_al(img, 0) != 0) { return assert(false, "scan Al 0"); }
  if (jpeg_scan_component_count(img, 0) != 1) { return assert(false, "one scan component"); }
  if (jpeg_scan_component_id(img, 0, 0) != 1) { return assert(false, "scan selector id 1"); }
  if (jpeg_scan_component_dc(img, 0, 0) != 0) { return assert(false, "scan DC selector 0"); }
  if (jpeg_scan_component_ac(img, 0, 0) != 0) { return assert(false, "scan AC selector 0"); }
  if (jpeg_scan_data_offset(img, 0) != 140) { return assert(false, "scan data at 140"); }
  if (jpeg_scan_data_length(img, 0) != 4) { return assert(false, "scan data length 4"); }
  if (jpeg_scan_restart_count(img, 0) != 0) { return assert(false, "no restarts"); }
  if (jpeg_scan_marker_offset(img, 0) != 144) { return assert(false, "scan ends at 144"); }
  if (jpeg_app_segment_count(img) != 1) { return assert(false, "one APP segment"); }
  if (jpeg_app_marker(img, 0) != 224) { return assert(false, "APP0 marker code"); }
  if (jpeg_app_offset(img, 0) != 2) { return assert(false, "APP0 at 2"); }
  if (jpeg_app_length(img, 0) != 16) { return assert(false, "APP0 length 16"); }
  if (jpeg_app_data_offset(img, 0) != 6) { return assert(false, "APP0 data at 6"); }
  if (jpeg_comment_count(img) != 0) { return assert(false, "no comments"); }
  if (jpeg_eoi_offset(img) != 144) { return assert(false, "EOI at 144"); }
  if (jpeg_total_bytes(img) != 146) { return assert(false, "total 146"); }
  if (jpeg_trailing_bytes(img) != 0) { return assert(false, "no trailing bytes"); }
  return assert(true, "canonical baseline image decodes every field exactly");
}

fn t2() -> TestResult {
  var empty = Vec[UInt8].new();
  if (!img_err_is(jpeg_parse(empty), "jpeg: missing SOI", 0)) {
    return assert(false, "empty buffer is missing SOI");
  }
  var one = Vec[UInt8].new();
  one.push(255 as UInt8);
  if (!img_err_is(jpeg_parse(one), "jpeg: missing SOI", 0)) {
    return assert(false, "one byte is missing SOI");
  }
  var wrong = Vec[UInt8].new();
  wrong.push(137 as UInt8);
  wrong.push(80 as UInt8);
  if (!img_err_is(jpeg_parse(wrong), "jpeg: missing SOI", 0)) {
    return assert(false, "PNG signature is missing SOI");
  }
  if (jpeg_is_jpeg(empty)) { return assert(false, "empty is not a JPEG"); }
  if (jpeg_is_jpeg(wrong)) { return assert(false, "PNG is not a JPEG"); }
  var soi_only = Vec[UInt8].new();
  push_ff(&mut soi_only, 216);
  if (!jpeg_is_jpeg(soi_only)) { return assert(false, "FFD8 classifies as JPEG"); }
  if (!img_err_is(jpeg_parse(soi_only), "jpeg: missing SOF", 2)) {
    return assert(false, "SOI alone is missing SOF at end of buffer");
  }
  return assert(true, "SOI validation and classification sentinels hold");
}

fn t3() -> TestResult {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  var exif = Vec[UInt8].new();
  exif.push(69 as UInt8);
  exif.push(120 as UInt8);
  exif.push(105 as UInt8);
  exif.push(102 as UInt8);
  exif.push(0 as UInt8);
  exif.push(0 as UInt8);
  push_seg(&mut out, 225, exif);
  let jf = jfif_payload(1, 2, 2, 150, 100, 1, 1);
  push_seg(&mut out, 224, jf);
  let app2 = raw_bytes(5, 40);
  push_seg(&mut out, 226, app2);
  let app13 = raw_bytes(3, 60);
  push_seg(&mut out, 237, app13);
  push_gray_sof(&mut out);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  let img = ok_img(jpeg_parse(out));
  if (jpeg_app_segment_count(img) != 4) { return assert(false, "four APP segments indexed"); }
  if (jpeg_app_marker(img, 0) != 225) { return assert(false, "first APP is APP1"); }
  if (jpeg_app_marker(img, 1) != 224) { return assert(false, "second APP is APP0"); }
  if (jpeg_app_marker(img, 2) != 226) { return assert(false, "third APP is APP2"); }
  if (jpeg_app_marker(img, 3) != 237) { return assert(false, "fourth APP is APP13"); }
  if (jpeg_app_offset(img, 0) != 2) { return assert(false, "APP1 at 2"); }
  if (jpeg_app_offset(img, 1) != 12) { return assert(false, "APP0 at 12"); }
  if (jpeg_app_offset(img, 2) != 33) { return assert(false, "APP2 at 33"); }
  if (jpeg_app_offset(img, 3) != 42) { return assert(false, "APP13 at 42"); }
  if (jpeg_app_length(img, 0) != 8) { return assert(false, "APP1 length 8"); }
  if (jpeg_app_length(img, 1) != 19) { return assert(false, "APP0 length 19"); }
  if (jpeg_app_data_offset(img, 0) != 6) { return assert(false, "APP1 data at 6"); }
  if (jpeg_app_data_offset(img, 1) != 16) { return assert(false, "APP0 data at 16"); }
  if (!jpeg_has_exif(img)) { return assert(false, "EXIF header detected"); }
  if (jpeg_exif_offset(img) != 2) { return assert(false, "EXIF at 2"); }
  if (!jpeg_has_jfif(img)) { return assert(false, "JFIF detected after EXIF"); }
  if (jpeg_jfif_units(img) != 2) { return assert(false, "JFIF units 2"); }
  if (jpeg_jfif_density_x(img) != 150) { return assert(false, "JFIF density x 150"); }
  if (jpeg_jfif_density_y(img) != 100) { return assert(false, "JFIF density y 100"); }
  if (jpeg_jfif_thumb_w(img) != 1) { return assert(false, "JFIF thumbnail width 1"); }
  if (jpeg_jfif_thumb_h(img) != 1) { return assert(false, "JFIF thumbnail height 1"); }
  // Malformed JFIF variants.
  let bad_units = jfif_payload(1, 2, 3, 1, 1, 0, 0);
  if (!img_err_is(jpeg_parse(mk_app0_prefix(bad_units)), "jpeg: invalid JFIF units", 13)) {
    return assert(false, "units 3 is rejected");
  }
  let bad_density = jfif_payload(1, 2, 1, 0, 1, 0, 0);
  if (!img_err_is(jpeg_parse(mk_app0_prefix(bad_density)), "jpeg: invalid JFIF density", 14)) {
    return assert(false, "zero density is rejected");
  }
  var short_jfif = Vec[UInt8].new();
  short_jfif.push(74 as UInt8);
  short_jfif.push(70 as UInt8);
  short_jfif.push(73 as UInt8);
  short_jfif.push(70 as UInt8);
  short_jfif.push(0 as UInt8);
  short_jfif.push(1 as UInt8);
  short_jfif.push(2 as UInt8);
  short_jfif.push(1 as UInt8);
  push_be16(&mut short_jfif, 1);
  push_be16(&mut short_jfif, 1);
  short_jfif.push(1 as UInt8);
  short_jfif.push(1 as UInt8);
  if (!img_err_is(jpeg_parse(mk_app0_prefix(short_jfif)), "jpeg: invalid JFIF segment", 2)) {
    return assert(false, "thumbnail bytes missing is rejected");
  }
  var dup = Vec[UInt8].new();
  push_ff(&mut dup, 216);
  let jf1 = jfif_payload(1, 2, 1, 1, 1, 0, 0);
  push_seg(&mut dup, 224, jf1);
  let jf2 = jfif_payload(1, 2, 1, 1, 1, 0, 0);
  push_seg(&mut dup, 224, jf2);
  push_gray_sof(&mut dup);
  push_gray_sos(&mut dup);
  dup.push(170 as UInt8);
  push_ff(&mut dup, 217);
  if (!img_err_is(jpeg_parse(dup), "jpeg: duplicate JFIF", 20)) {
    return assert(false, "a second JFIF APP0 is rejected");
  }
  var not_jfif = Vec[UInt8].new();
  not_jfif.push(74 as UInt8);
  not_jfif.push(70 as UInt8);
  not_jfif.push(88 as UInt8);
  not_jfif.push(88 as UInt8);
  not_jfif.push(0 as UInt8);
  not_jfif.push(9 as UInt8);
  not_jfif.push(9 as UInt8);
  let img2 = ok_img(jpeg_parse(mk_app0_prefix(not_jfif)));
  if (jpeg_has_jfif(img2)) { return assert(false, "JFXX APP0 is not JFIF"); }
  if (jpeg_app_segment_count(img2) != 1) { return assert(false, "JFXX APP0 is still indexed"); }
  if (jpeg_app_marker(img2, 0) != 224) { return assert(false, "JFXX APP0 marker code"); }
  return assert(true, "APP index, JFIF decode and EXIF presence are exact");
}

fn t4() -> TestResult {
  let t0 = dqt8_payload(0, 5);
  let t1 = dqt8_payload(2, 100);
  let two = append(t0, t1);
  let img = ok_img(jpeg_parse(mk_dqt_prefix(two)));
  if (jpeg_quant_table_count(img) != 2) { return assert(false, "two quant tables in one segment"); }
  if (jpeg_quant_id(img, 0) != 0) { return assert(false, "first table id 0"); }
  if (jpeg_quant_id(img, 1) != 2) { return assert(false, "second table id 2"); }
  if (jpeg_quant_precision(img, 0) != 0) { return assert(false, "first table 8-bit"); }
  if (jpeg_quant_precision(img, 1) != 0) { return assert(false, "second table 8-bit"); }
  if (jpeg_quant_value_offset(img, 0) != 0) { return assert(false, "first value offset 0"); }
  if (jpeg_quant_value_offset(img, 1) != 64) { return assert(false, "second value offset 64"); }
  if (jpeg_quant_value(img, 0, 0) != 6) { return assert(false, "table 0 value 0 is 6"); }
  if (jpeg_quant_value(img, 1, 0) != 101) { return assert(false, "table 1 value 0 is 101"); }
  if (jpeg_quant_value(img, 1, 63) != 164) { return assert(false, "table 1 value 63 is 164"); }
  let wide = dqt16_payload(3, 300);
  let img2 = ok_img(jpeg_parse(mk_dqt_prefix(wide)));
  if (jpeg_quant_precision(img2, 0) != 1) { return assert(false, "16-bit precision 1"); }
  if (jpeg_quant_id(img2, 0) != 3) { return assert(false, "16-bit table id 3"); }
  if (jpeg_quant_value(img2, 0, 0) != 301) { return assert(false, "16-bit value 0 is 301"); }
  if (jpeg_quant_value(img2, 0, 63) != 364) { return assert(false, "16-bit value 63 is 364"); }
  if (jpeg_quant_value(img2, 0, 64) != -1) { return assert(false, "value index 64 is out of range"); }
  if (jpeg_quant_value(img2, 1, 0) != -1) { return assert(false, "table index 1 is out of range"); }
  // Malformed DQT segments.
  var empty = Vec[UInt8].new();
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(empty)), "jpeg: empty DQT", 2)) {
    return assert(false, "empty DQT payload is rejected");
  }
  var bad_prec = Vec[UInt8].new();
  bad_prec.push(32 as UInt8);
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(bad_prec)), "jpeg: invalid DQT precision", 6)) {
    return assert(false, "precision 2 is rejected");
  }
  var bad_id = Vec[UInt8].new();
  bad_id.push(4 as UInt8);
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(bad_id)), "jpeg: invalid DQT table id", 6)) {
    return assert(false, "table id 4 is rejected");
  }
  var short_tbl = raw_bytes(10, 3);
  short_tbl[0] = 0 as UInt8;
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(short_tbl)), "jpeg: truncated DQT table", 6)) {
    return assert(false, "a truncated 8-bit table is rejected");
  }
  var zero_val = dqt8_payload(0, 5);
  zero_val[1] = 0 as UInt8;
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(zero_val)), "jpeg: zero quant value", 7)) {
    return assert(false, "a zero quant value is rejected");
  }
  var short16 = raw_bytes(70, 3);
  short16[0] = 16 as UInt8;
  if (!img_err_is(jpeg_parse(mk_dqt_prefix(short16)), "jpeg: truncated DQT table", 6)) {
    return assert(false, "a truncated 16-bit table is rejected");
  }
  return assert(true, "DQT table index, values and malformed payloads are exact");
}

fn t5() -> TestResult {
  let img = ok_img(jpeg_parse(mk_gray(192, 8, 7, 5, 17, 0, 0, 63, 0, 0)));
  if (jpeg_width(img) != 7) { return assert(false, "width 7"); }
  if (jpeg_height(img) != 5) { return assert(false, "height 5"); }
  if (jpeg_frame_marker(img) != 192) { return assert(false, "SOF0 accepted"); }
  let ext = ok_img(jpeg_parse(mk_gray(193, 12, 1, 1, 17, 0, 0, 63, 0, 0)));
  if (jpeg_frame_marker(ext) != 193) { return assert(false, "SOF1 accepted"); }
  if (jpeg_precision(ext) != 12) { return assert(false, "extended precision 12"); }
  if (jpeg_is_progressive(ext)) { return assert(false, "SOF1 is not progressive"); }
  let prog = ok_img(jpeg_parse(mk_gray(194, 8, 1, 1, 34, 0, 0, 0, 0, 0)));
  if (jpeg_frame_marker(prog) != 194) { return assert(false, "SOF2 accepted"); }
  if (!jpeg_is_progressive(prog)) { return assert(false, "SOF2 sets progressive"); }
  if (jpeg_component_h(prog, 0) != 2) { return assert(false, "progressive sampling h 2"); }
  if (jpeg_component_v(prog, 0) != 2) { return assert(false, "progressive sampling v 2"); }
  // Malformed SOF payloads.
  let base = sof_payload(8, 1, 1, comps1(), one_of(17), one_of(0));
  let bad_len = append(base, raw_bytes(3, 1));
  if (!img_err_is(jpeg_parse(mk_sof_payload(192, bad_len)), "jpeg: invalid SOF length", 2)) {
    return assert(false, "Nf/3*Nf length mismatch is rejected");
  }
  var zero_nf = sof_payload(8, 1, 1, comps1(), one_of(17), one_of(0));
  zero_nf[5] = 0 as UInt8;
  if (!img_err_is(jpeg_parse(mk_sof_payload(192, zero_nf)), "jpeg: invalid component count", 11)) {
    return assert(false, "Nf 0 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 12, 1, 1, 17, 0, 0, 63, 0, 0)), "jpeg: invalid precision", 6)) {
    return assert(false, "SOF0 precision 12 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(193, 10, 1, 1, 17, 0, 0, 63, 0, 0)), "jpeg: invalid precision", 6)) {
    return assert(false, "SOF1 precision 10 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 0, 1, 17, 0, 0, 63, 0, 0)), "jpeg: zero frame dimension", 9)) {
    return assert(false, "width 0 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 0, 17, 0, 0, 63, 0, 0)), "jpeg: zero frame dimension", 7)) {
    return assert(false, "height 0 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 1, 0, 0, 63, 0, 0)), "jpeg: invalid sampling factor", 13)) {
    return assert(false, "horizontal sampling 0 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 81, 0, 0, 63, 0, 0)), "jpeg: invalid sampling factor", 13)) {
    return assert(false, "horizontal sampling 5 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 16, 0, 0, 63, 0, 0)), "jpeg: invalid sampling factor", 13)) {
    return assert(false, "vertical sampling 0 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 17, 4, 0, 63, 0, 0)), "jpeg: invalid quant table id", 14)) {
    return assert(false, "quant table id 4 is rejected");
  }
  let cids2 = Vec[Int].new();
  cids2.push(1);
  cids2.push(1);
  let hvs2 = Vec[Int].new();
  hvs2.push(17);
  hvs2.push(17);
  let tqs2 = Vec[Int].new();
  tqs2.push(0);
  tqs2.push(0);
  let dup_comp = sof_payload(8, 1, 1, cids2, hvs2, tqs2);
  if (!img_err_is(jpeg_parse(mk_sof_payload(192, dup_comp)), "jpeg: duplicate component id", 15)) {
    return assert(false, "duplicate component id is rejected");
  }
  var sof3 = Vec[UInt8].new();
  push_ff(&mut sof3, 216);
  let none = Vec[UInt8].new();
  push_seg(&mut sof3, 195, none);
  if (!img_err_is(jpeg_parse(sof3), "jpeg: unsupported frame type", 2)) {
    return assert(false, "SOF3 is an unsupported frame type");
  }
  var dup_sof = Vec[UInt8].new();
  push_ff(&mut dup_sof, 216);
  push_gray_sof(&mut dup_sof);
  push_gray_sof(&mut dup_sof);
  if (!img_err_is(jpeg_parse(dup_sof), "jpeg: duplicate SOF", 15)) {
    return assert(false, "a second SOF is rejected");
  }
  return assert(true, "SOF0/SOF1/SOF2 decode and every SOF rule rejects correctly");
}

fn t6() -> TestResult {
  var sos_first = Vec[UInt8].new();
  push_ff(&mut sos_first, 216);
  push_gray_sos(&mut sos_first);
  sos_first.push(170 as UInt8);
  push_ff(&mut sos_first, 217);
  if (!img_err_is(jpeg_parse(sos_first), "jpeg: SOS before SOF", 2)) {
    return assert(false, "SOS before SOF is rejected");
  }
  let good = sos_payload(comps1(), zeros1(), zeros1(), 0, 63, 0, 0);
  let img = ok_img(jpeg_parse(mk_sos_payload(good)));
  if (jpeg_scan_count(img) != 1) { return assert(false, "valid SOS parses"); }
  var short_len = sos_payload(comps1(), zeros1(), zeros1(), 0, 63, 0, 0);
  short_len[0] = 2 as UInt8;
  if (!img_err_is(jpeg_parse(mk_sos_payload(short_len)), "jpeg: invalid SOS length", 15)) {
    return assert(false, "Ns/length mismatch is rejected");
  }
  var zero_ns = Vec[UInt8].new();
  zero_ns.push(0 as UInt8);
  zero_ns.push(0 as UInt8);
  zero_ns.push(63 as UInt8);
  zero_ns.push(0 as UInt8);
  if (!img_err_is(jpeg_parse(mk_sos_payload(zero_ns)), "jpeg: invalid scan component count", 19)) {
    return assert(false, "Ns 0 is rejected");
  }
  var five_ids = Vec[Int].new();
  var five_tds = Vec[Int].new();
  var five_tas = Vec[Int].new();
  var z = 0;
  while (z < 5) {
    five_ids.push(1);
    five_tds.push(0);
    five_tas.push(0);
    z = z + 1;
  }
  let many = sos_payload(five_ids, five_tds, five_tas, 0, 63, 0, 0);
  if (!img_err_is(jpeg_parse(mk_sos_payload(many)), "jpeg: invalid scan component count", 19)) {
    return assert(false, "Ns 5 is rejected");
  }
  let unknown = sos_payload(one_of(2), zeros1(), zeros1(), 0, 63, 0, 0);
  if (!img_err_is(jpeg_parse(mk_sos_payload(unknown)), "jpeg: unknown scan component", 20)) {
    return assert(false, "an unknown selector is rejected");
  }
  let dup = sos_payload(one_of(1), zeros1(), zeros1(), 0, 63, 0, 0);
  if (bad_img(jpeg_parse(mk_sos_payload(dup)))) { return assert(false, "single selector parses"); }
  var dup_ids = Vec[Int].new();
  dup_ids.push(1);
  dup_ids.push(1);
  var dup_tds = Vec[Int].new();
  dup_tds.push(0);
  dup_tds.push(0);
  var dup_tas = Vec[Int].new();
  dup_tas.push(0);
  dup_tas.push(0);
  let dup2 = sos_payload(dup_ids, dup_tds, dup_tas, 0, 63, 0, 0);
  if (!img_err_is(jpeg_parse(mk_sos_payload(dup2)), "jpeg: duplicate scan component", 22)) {
    return assert(false, "a repeated selector is rejected");
  }
  // Baseline, one selector: the DC/Ta byte is at payload offset 2 (abs 21).
  let dc4 = sos_payload(comps1(), one_of(4), zeros1(), 0, 63, 0, 0);
  if (!img_err_is(jpeg_parse(mk_sos_payload(dc4)), "jpeg: invalid DC table selector", 21)) {
    return assert(false, "DC selector 4 is rejected");
  }
  let ac4 = sos_payload(comps1(), zeros1(), one_of(4), 0, 63, 0, 0);
  if (!img_err_is(jpeg_parse(mk_sos_payload(ac4)), "jpeg: invalid AC table selector", 21)) {
    return assert(false, "AC selector 4 is rejected");
  }
  // Baseline must be 0 / 63 / 0 / 0; Ss is at abs 22, Se 23, Ah/Al 24.
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 17, 0, 1, 63, 0, 0)), "jpeg: invalid spectral selection", 22)) {
    return assert(false, "baseline Ss 1 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 17, 0, 0, 62, 0, 0)), "jpeg: invalid spectral selection", 23)) {
    return assert(false, "baseline Se 62 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(192, 8, 1, 1, 17, 0, 0, 63, 1, 0)), "jpeg: invalid successive approximation", 24)) {
    return assert(false, "baseline Ah 1 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(194, 8, 1, 1, 17, 0, 5, 0, 0, 0)), "jpeg: invalid spectral selection", 22)) {
    return assert(false, "progressive DC scan with Se 5 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(194, 8, 1, 1, 17, 0, 0, 63, 14, 0)), "jpeg: invalid successive approximation", 24)) {
    return assert(false, "progressive Ah 14 is rejected");
  }
  if (!img_err_is(jpeg_parse(mk_gray(194, 8, 1, 1, 17, 0, 1, 63, 3, 1)), "jpeg: invalid successive approximation", 24)) {
    return assert(false, "progressive Ah not Al+1 is rejected");
  }
  // A valid progressive refinement scan: Ss=1, Se=63, Ah=1, Al=0.
  let ref = ok_img(jpeg_parse(mk_gray(194, 8, 1, 1, 17, 0, 1, 63, 1, 0)));
  if (jpeg_scan_ah(ref, 0) != 1) { return assert(false, "refinement Ah 1 accepted"); }
  if (jpeg_scan_al(ref, 0) != 0) { return assert(false, "refinement Al 0 accepted"); }
  return assert(true, "SOS selection, approximation and ordering rules are exact");
}

fn t7() -> TestResult {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  let sp2 = sof_payload(8, 2, 3, comps1(), one_of(17), one_of(0));
  push_seg(&mut out, 194, sp2);
  let sos1 = sos_payload(comps1(), zeros1(), zeros1(), 0, 0, 0, 0);
  push_seg(&mut out, 218, sos1);
  // Scan 1: 13 raw bytes, three restarts, one stuffed FF00.
  out.push(17 as UInt8);
  out.push(255 as UInt8);
  out.push(0 as UInt8);
  out.push(34 as UInt8);
  push_ff(&mut out, 208);
  out.push(51 as UInt8);
  push_ff(&mut out, 209);
  out.push(68 as UInt8);
  push_ff(&mut out, 210);
  out.push(85 as UInt8);
  var cnt = zero16();
  cnt[0] = 1;
  var syms = Vec[Int].new();
  syms.push(0);
  let dh = dht_payload(0, 0, cnt, syms);
  push_seg(&mut out, 196, dh);
  let sos2 = sos_payload(comps1(), zeros1(), zeros1(), 1, 63, 0, 0);
  push_seg(&mut out, 218, sos2);
  out.push(102 as UInt8);
  push_ff(&mut out, 211);
  out.push(119 as UInt8);
  push_ff(&mut out, 217);
  if (out.len() != 76) { return assert(false, "two-scan fixture is 76 bytes"); }
  let img = ok_img(jpeg_parse(out));
  if (jpeg_scan_count(img) != 2) { return assert(false, "two scans recorded"); }
  if (jpeg_scan_ss(img, 0) != 0) { return assert(false, "scan 0 is a DC scan"); }
  if (jpeg_scan_se(img, 0) != 0) { return assert(false, "scan 0 Se 0"); }
  if (jpeg_scan_data_offset(img, 0) != 25) { return assert(false, "scan 0 data at 25"); }
  if (jpeg_scan_data_length(img, 0) != 13) { return assert(false, "scan 0 raw length 13"); }
  if (jpeg_scan_restart_count(img, 0) != 3) { return assert(false, "scan 0 has 3 restarts"); }
  if (jpeg_scan_marker_offset(img, 0) != 38) { return assert(false, "scan 0 ends at DHT"); }
  if (jpeg_scan_ss(img, 1) != 1) { return assert(false, "scan 1 Ss 1"); }
  if (jpeg_scan_se(img, 1) != 63) { return assert(false, "scan 1 Se 63"); }
  if (jpeg_scan_data_offset(img, 1) != 70) { return assert(false, "scan 1 data at 70"); }
  if (jpeg_scan_data_length(img, 1) != 4) { return assert(false, "scan 1 raw length 4"); }
  if (jpeg_scan_restart_count(img, 1) != 1) { return assert(false, "scan 1 has 1 restart"); }
  if (jpeg_scan_marker_offset(img, 1) != 74) { return assert(false, "scan 1 ends at EOI"); }
  if (jpeg_dht_table_count(img) != 1) { return assert(false, "DHT between scans recorded"); }
  if (jpeg_eoi_offset(img) != 74) { return assert(false, "EOI at 74"); }
  if (jpeg_total_bytes(img) != 76) { return assert(false, "total 76"); }
  return assert(true, "stuffing, restart markers and a between-scan DHT decode exactly");
}

fn dst_soi_tail(tail: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_bytes(&mut out, tail);
  return out;
}

fn t8() -> TestResult {
  var ff00 = Vec[UInt8].new();
  ff00.push(255 as UInt8);
  ff00.push(0 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(ff00)), "jpeg: invalid marker", 2)) {
    return assert(false, "FF00 outside a scan is invalid");
  }
  var soi2 = Vec[UInt8].new();
  soi2.push(255 as UInt8);
  soi2.push(216 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(soi2)), "jpeg: unexpected SOI", 2)) {
    return assert(false, "a second SOI is rejected");
  }
  var rst = Vec[UInt8].new();
  rst.push(255 as UInt8);
  rst.push(208 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(rst)), "jpeg: unexpected restart marker", 2)) {
    return assert(false, "RST outside a scan is rejected");
  }
  var sof3 = Vec[UInt8].new();
  sof3.push(255 as UInt8);
  sof3.push(195 as UInt8);
  sof3.push(0 as UInt8);
  sof3.push(2 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(sof3)), "jpeg: unsupported frame type", 2)) {
    return assert(false, "SOF3 is rejected before the length field");
  }
  var dac = Vec[UInt8].new();
  dac.push(255 as UInt8);
  dac.push(204 as UInt8);
  dac.push(0 as UInt8);
  dac.push(2 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(dac)), "jpeg: unsupported marker", 2)) {
    return assert(false, "DAC is an unsupported marker");
  }
  var tem = Vec[UInt8].new();
  tem.push(255 as UInt8);
  tem.push(1 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(tem)), "jpeg: unsupported marker", 2)) {
    return assert(false, "TEM is an unsupported marker");
  }
  var garbage = Vec[UInt8].new();
  garbage.push(0 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(garbage)), "jpeg: invalid marker", 2)) {
    return assert(false, "a non-FF byte starts no marker");
  }
  var lone_ff = Vec[UInt8].new();
  lone_ff.push(255 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(lone_ff)), "jpeg: truncated marker", 2)) {
    return assert(false, "a lone FF is a truncated marker");
  }
  var ff_run = Vec[UInt8].new();
  ff_run.push(255 as UInt8);
  ff_run.push(255 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(ff_run)), "jpeg: truncated marker", 2)) {
    return assert(false, "an FF run at EOF is a truncated marker");
  }
  var short_len = Vec[UInt8].new();
  short_len.push(255 as UInt8);
  short_len.push(224 as UInt8);
  short_len.push(0 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(short_len)), "jpeg: truncated segment", 2)) {
    return assert(false, "a missing length byte is truncation");
  }
  var len0 = Vec[UInt8].new();
  len0.push(255 as UInt8);
  len0.push(224 as UInt8);
  len0.push(0 as UInt8);
  len0.push(0 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(len0)), "jpeg: invalid segment length", 2)) {
    return assert(false, "length 0 is rejected");
  }
  var len1 = Vec[UInt8].new();
  len1.push(255 as UInt8);
  len1.push(224 as UInt8);
  len1.push(0 as UInt8);
  len1.push(1 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(len1)), "jpeg: invalid segment length", 2)) {
    return assert(false, "length 1 is rejected");
  }
  var oob = Vec[UInt8].new();
  oob.push(255 as UInt8);
  oob.push(224 as UInt8);
  oob.push(0 as UInt8);
  oob.push(16 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(oob)), "jpeg: segment length out of bounds", 2)) {
    return assert(false, "a length past the buffer is rejected");
  }
  var empty_app = Vec[UInt8].new();
  empty_app.push(255 as UInt8);
  empty_app.push(224 as UInt8);
  empty_app.push(0 as UInt8);
  empty_app.push(2 as UInt8);
  if (!img_err_is(jpeg_parse(dst_soi_tail(empty_app)), "jpeg: missing SOF", 6)) {
    return assert(false, "an empty APP0 segment is structurally legal");
  }
  // Fill bytes before the SOF marker: FF FF C0.
  var fill = Vec[UInt8].new();
  push_ff(&mut fill, 216);
  fill.push(255 as UInt8);
  push_gray_sof(&mut fill);
  push_gray_sos(&mut fill);
  fill.push(170 as UInt8);
  push_ff(&mut fill, 217);
  if (fill.len() != 29) { return assert(false, "fill fixture is 29 bytes"); }
  let img = ok_img(jpeg_parse(fill));
  if (jpeg_width(img) != 2) { return assert(false, "fill before SOF still parses"); }
  if (jpeg_scan_data_offset(img, 0) != 26) { return assert(false, "scan data shifts by the fill byte"); }
  if (jpeg_eoi_offset(img) != 27) { return assert(false, "EOI at 27"); }
  if (jpeg_total_bytes(img) != 29) { return assert(false, "total 29"); }
  return assert(true, "marker grammar, segment bounds and fill bytes behave exactly");
}

fn t9() -> TestResult {
  let d = mk_canonical();
  var with_tail = Vec[UInt8].new();
  push_bytes(&mut with_tail, d);
  with_tail.push(222 as UInt8);
  with_tail.push(173 as UInt8);
  let img = ok_img(jpeg_parse(with_tail));
  if (jpeg_trailing_bytes(img) != 2) { return assert(false, "two trailing bytes after EOI"); }
  if (jpeg_eoi_offset(img) != 144) { return assert(false, "EOI stays at 144"); }
  if (jpeg_total_bytes(img) != 148) { return assert(false, "total 148 with trailing bytes"); }
  // SOI + SOF only: EOF before EOI.
  var no_eoi = Vec[UInt8].new();
  push_ff(&mut no_eoi, 216);
  push_gray_sof(&mut no_eoi);
  if (!img_err_is(jpeg_parse(no_eoi), "jpeg: missing EOI", 15)) {
    return assert(false, "EOF after a segment is a missing EOI");
  }
  // SOI + SOF + EOI: no scan.
  var no_sos = Vec[UInt8].new();
  push_ff(&mut no_sos, 216);
  push_gray_sof(&mut no_sos);
  push_ff(&mut no_sos, 217);
  if (!img_err_is(jpeg_parse(no_sos), "jpeg: missing SOS", 15)) {
    return assert(false, "EOI without a scan is rejected");
  }
  var only_eoi = Vec[UInt8].new();
  push_ff(&mut only_eoi, 216);
  push_ff(&mut only_eoi, 217);
  if (!img_err_is(jpeg_parse(only_eoi), "jpeg: missing SOF", 2)) {
    return assert(false, "SOI + EOI is missing SOF");
  }
  var app_then_eoi = Vec[UInt8].new();
  push_ff(&mut app_then_eoi, 216);
  let none = Vec[UInt8].new();
  push_seg(&mut app_then_eoi, 224, none);
  push_ff(&mut app_then_eoi, 217);
  if (!img_err_is(jpeg_parse(app_then_eoi), "jpeg: missing SOF", 6)) {
    return assert(false, "EOI before SOF reports missing SOF");
  }
  return assert(true, "EOI presence, trailing bytes and missing-SOF/SOS precedence hold");
}

fn t10() -> TestResult {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  let c1 = raw_bytes(5, 11);
  push_seg(&mut out, 254, c1);
  let none = Vec[UInt8].new();
  push_seg(&mut out, 254, none);
  push_gray_sof(&mut out);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  if (out.len() != 41) { return assert(false, "COM fixture is 41 bytes"); }
  let img = ok_img(jpeg_parse(out));
  if (jpeg_comment_count(img) != 2) { return assert(false, "two comments indexed"); }
  if (jpeg_comment_offset(img, 0) != 2) { return assert(false, "first comment at 2"); }
  if (jpeg_comment_length(img, 0) != 7) { return assert(false, "first comment length 7"); }
  if (jpeg_comment_offset(img, 1) != 11) { return assert(false, "second comment at 11"); }
  if (jpeg_comment_length(img, 1) != 2) { return assert(false, "empty comment length 2"); }
  if (jpeg_comment_offset(img, 2) != -1) { return assert(false, "comment offset sentinel"); }
  if (jpeg_comment_length(img, 9) != -1) { return assert(false, "comment length sentinel"); }
  if (jpeg_app_segment_count(img) != 0) { return assert(false, "comments are not APP segments"); }
  return assert(true, "COM segments are indexed without being interpreted");
}

fn t11() -> TestResult {
  var p4 = Vec[UInt8].new();
  push_be16(&mut p4, 4);
  let img = ok_img(jpeg_parse(mk_dri_prefix(p4)));
  if (jpeg_restart_interval(img) != 4) { return assert(false, "interval 4"); }
  if (!jpeg_has_dri(img)) { return assert(false, "DRI presence"); }
  if (jpeg_dri_count(img) != 1) { return assert(false, "one DRI segment"); }
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_gray_sof(&mut out);
  var d2 = Vec[UInt8].new();
  push_be16(&mut d2, 2);
  push_seg(&mut out, 221, d2);
  var d8 = Vec[UInt8].new();
  push_be16(&mut d8, 8);
  push_seg(&mut out, 221, d8);
  push_gray_sos(&mut out);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  let img2 = ok_img(jpeg_parse(out));
  if (jpeg_restart_interval(img2) != 8) { return assert(false, "a later DRI replaces the interval"); }
  if (jpeg_dri_count(img2) != 2) { return assert(false, "two DRI segments"); }
  let bad = raw_bytes(3, 1);
  if (!img_err_is(jpeg_parse(mk_dri_prefix(bad)), "jpeg: invalid DRI length", 15)) {
    return assert(false, "a DRI payload other than 4 bytes is rejected");
  }
  var p0 = Vec[UInt8].new();
  push_be16(&mut p0, 0);
  let img0 = ok_img(jpeg_parse(mk_dri_prefix(p0)));
  if (jpeg_restart_interval(img0) != 0) { return assert(false, "interval 0 is legal"); }
  if (!jpeg_has_dri(img0)) { return assert(false, "DRI 0 is still a DRI"); }
  return assert(true, "DRI interval, replacement and length rules are exact");
}

fn t12() -> TestResult {
  var cnt_a = zero16();
  cnt_a[0] = 2;
  cnt_a[1] = 1;
  var sym_a = Vec[Int].new();
  sym_a.push(0);
  sym_a.push(1);
  sym_a.push(2);
  var cnt_b = zero16();
  cnt_b[0] = 1;
  var sym_b = Vec[Int].new();
  sym_b.push(5);
  let ta = dht_payload(0, 0, cnt_a, sym_a);
  let tb = dht_payload(1, 3, cnt_b, sym_b);
  let both = append(ta, tb);
  let img = ok_img(jpeg_parse(mk_dht_prefix(both)));
  if (jpeg_dht_table_count(img) != 2) { return assert(false, "two DHT tables in one segment"); }
  if (jpeg_dht_class(img, 0) != 0) { return assert(false, "first table DC"); }
  if (jpeg_dht_id(img, 0) != 0) { return assert(false, "first table id 0"); }
  if (jpeg_dht_symbol_count(img, 0) != 3) { return assert(false, "first table has 3 symbols"); }
  if (jpeg_dht_class(img, 1) != 1) { return assert(false, "second table AC"); }
  if (jpeg_dht_id(img, 1) != 3) { return assert(false, "second table id 3"); }
  if (jpeg_dht_symbol_count(img, 1) != 1) { return assert(false, "second table has 1 symbol"); }
  if (jpeg_dht_count_offset(img, 0) != 0) { return assert(false, "first count offset 0"); }
  if (jpeg_dht_count_offset(img, 1) != 16) { return assert(false, "second count offset 16"); }
  if (jpeg_dht_count(img, 0, 0) != 2) { return assert(false, "count 0 is 2"); }
  if (jpeg_dht_count(img, 0, 1) != 1) { return assert(false, "count 1 is 1"); }
  if (jpeg_dht_count(img, 0, 15) != 0) { return assert(false, "count 15 is 0"); }
  if (jpeg_dht_count(img, 1, 0) != 1) { return assert(false, "second count 0 is 1"); }
  if (jpeg_dht_count(img, 0, 16) != -1) { return assert(false, "count index 16 is out of range"); }
  if (jpeg_dht_count(img, 2, 0) != -1) { return assert(false, "table index 2 is out of range"); }
  // Overflow: 255 + 2 = 257 > 256.
  var cnt_of = zero16();
  cnt_of[0] = 255;
  cnt_of[1] = 2;
  let sym_of = raw_bytes(0, 0);
  let overflow = dht_payload(0, 0, cnt_of, sym_of);
  if (!img_err_is(jpeg_parse(mk_dht_prefix(overflow)), "jpeg: DHT symbol count overflow", 19)) {
    return assert(false, "a symbol count above 256 is rejected");
  }
  // Truncated symbol list: 5 declared, 2 present.
  var cnt_tr = zero16();
  cnt_tr[0] = 5;
  let sym_tr = raw_bytes(2, 9);
  let trunc = dht_payload(0, 0, cnt_tr, sym_tr);
  if (!img_err_is(jpeg_parse(mk_dht_prefix(trunc)), "jpeg: truncated DHT", 19)) {
    return assert(false, "a truncated symbol list is rejected");
  }
  let bad_class = dht_payload(2, 0, zero16(), raw_bytes(0, 0));
  if (!img_err_is(jpeg_parse(mk_dht_prefix(bad_class)), "jpeg: invalid DHT class", 19)) {
    return assert(false, "DHT class 2 is rejected");
  }
  var cnt_1 = zero16();
  cnt_1[0] = 1;
  var sym_1 = Vec[Int].new();
  sym_1.push(0);
  let bad_id = dht_payload(0, 4, cnt_1, sym_1);
  if (!img_err_is(jpeg_parse(mk_dht_prefix(bad_id)), "jpeg: invalid DHT table id", 19)) {
    return assert(false, "DHT id 4 is rejected");
  }
  var empty = Vec[UInt8].new();
  if (!img_err_is(jpeg_parse(mk_dht_prefix(empty)), "jpeg: empty DHT", 15)) {
    return assert(false, "an empty DHT payload is rejected");
  }
  let partial = append(ta, raw_bytes(10, 7));
  if (!img_err_is(jpeg_parse(mk_dht_prefix(partial)), "jpeg: truncated DHT", 39)) {
    return assert(false, "a partial second table is truncation at its start");
  }
  return assert(true, "DHT counts, symbol sums and malformed payloads are exact");
}

fn t13() -> TestResult {
  if (jpeg_soi() != 216) { return assert(false, "SOI constant"); }
  if (jpeg_eoi() != 217) { return assert(false, "EOI constant"); }
  if (jpeg_sos() != 218) { return assert(false, "SOS constant"); }
  if (jpeg_frame_baseline() != 192) { return assert(false, "SOF0 constant"); }
  if (jpeg_frame_extended() != 193) { return assert(false, "SOF1 constant"); }
  if (jpeg_frame_progressive() != 194) { return assert(false, "SOF2 constant"); }
  if (jpeg_restart_first() != 208) { return assert(false, "RST0 constant"); }
  if (jpeg_restart_last() != 215) { return assert(false, "RST7 constant"); }
  if (jpeg_min_segment_length() != 2) { return assert(false, "min segment length constant"); }
  if (jpeg_no_offset() != -1) { return assert(false, "no-offset constant"); }
  let e = empty_img();
  if (jpeg_component_id(e, 0) != -1) { return assert(false, "component accessor sentinel"); }
  if (jpeg_component_h(e, 0) != -1) { return assert(false, "component h sentinel"); }
  if (jpeg_component_v(e, 0) != -1) { return assert(false, "component v sentinel"); }
  if (jpeg_component_quant(e, 0) != -1) { return assert(false, "component quant sentinel"); }
  if (jpeg_quant_id(e, 0) != -1) { return assert(false, "quant id sentinel"); }
  if (jpeg_quant_precision(e, 0) != -1) { return assert(false, "quant precision sentinel"); }
  if (jpeg_quant_value_offset(e, 0) != -1) { return assert(false, "quant offset sentinel"); }
  if (jpeg_dht_class(e, 0) != -1) { return assert(false, "DHT class sentinel"); }
  if (jpeg_dht_id(e, 0) != -1) { return assert(false, "DHT id sentinel"); }
  if (jpeg_dht_symbol_count(e, 0) != -1) { return assert(false, "DHT symbol count sentinel"); }
  if (jpeg_dht_count_offset(e, 0) != -1) { return assert(false, "DHT count offset sentinel"); }
  if (jpeg_scan_ss(e, 0) != -1) { return assert(false, "scan Ss sentinel"); }
  if (jpeg_scan_se(e, 0) != -1) { return assert(false, "scan Se sentinel"); }
  if (jpeg_scan_ah(e, 0) != -1) { return assert(false, "scan Ah sentinel"); }
  if (jpeg_scan_al(e, 0) != -1) { return assert(false, "scan Al sentinel"); }
  if (jpeg_scan_component_count(e, 0) != -1) { return assert(false, "scan comp count sentinel"); }
  if (jpeg_scan_component_offset(e, 0) != -1) { return assert(false, "scan comp offset sentinel"); }
  if (jpeg_scan_component_id(e, 0, 0) != -1) { return assert(false, "scan comp id sentinel"); }
  if (jpeg_scan_component_dc(e, 0, 0) != -1) { return assert(false, "scan comp DC sentinel"); }
  if (jpeg_scan_component_ac(e, 0, 0) != -1) { return assert(false, "scan comp AC sentinel"); }
  if (jpeg_scan_data_offset(e, 0) != -1) { return assert(false, "scan data offset sentinel"); }
  if (jpeg_scan_data_length(e, 0) != -1) { return assert(false, "scan data length sentinel"); }
  if (jpeg_scan_restart_count(e, 0) != -1) { return assert(false, "scan restart sentinel"); }
  if (jpeg_scan_marker_offset(e, 0) != -1) { return assert(false, "scan marker sentinel"); }
  if (jpeg_app_marker(e, 0) != -1) { return assert(false, "APP marker sentinel"); }
  if (jpeg_app_offset(e, 0) != -1) { return assert(false, "APP offset sentinel"); }
  if (jpeg_app_length(e, 0) != -1) { return assert(false, "APP length sentinel"); }
  if (jpeg_app_data_offset(e, 0) != -1) { return assert(false, "APP data sentinel"); }
  if (jpeg_restart_interval(e) != -1) { return assert(false, "restart interval sentinel"); }
  if (jpeg_has_dri(e)) { return assert(false, "empty image has no DRI"); }
  if (jpeg_has_jfif(e)) { return assert(false, "empty image has no JFIF"); }
  if (jpeg_has_exif(e)) { return assert(false, "empty image has no EXIF"); }
  if (jpeg_exif_offset(e) != -1) { return assert(false, "EXIF offset sentinel"); }
  if (jpeg_component_count(e) != 0) { return assert(false, "empty component count"); }
  if (jpeg_quant_table_count(e) != 0) { return assert(false, "empty quant table count"); }
  if (jpeg_dht_table_count(e) != 0) { return assert(false, "empty DHT table count"); }
  if (jpeg_scan_count(e) != 0) { return assert(false, "empty scan count"); }
  if (jpeg_app_segment_count(e) != 0) { return assert(false, "empty APP count"); }
  if (jpeg_comment_count(e) != 0) { return assert(false, "empty comment count"); }
  var bad = Vec[UInt8].new();
  push_ff(&mut bad, 216);
  let r = jpeg_parse(bad);
  match r {
    Ok(v) => { return assert(false, "SOI alone must fail"); },
    Err(err) => {
      let m: Str = jpeg_error_message(err);
      if (string.str_len(m) == 0) { return assert(false, "error message is non-empty"); }
      if (jpeg_error_offset(err) != 2) { return assert(false, "error offset is 2"); }
    },
  }
  return assert(true, "constants, accessor sentinels and error accessors hold");
}

fn t14() -> TestResult {
  var comps = Vec[Int].new();
  comps.push(1);
  comps.push(2);
  comps.push(3);
  var hvs = Vec[Int].new();
  hvs.push(34);
  hvs.push(17);
  hvs.push(17);
  var tqs = Vec[Int].new();
  tqs.push(0);
  tqs.push(1);
  tqs.push(1);
  var ids = Vec[Int].new();
  ids.push(1);
  ids.push(2);
  ids.push(3);
  var tds = Vec[Int].new();
  tds.push(0);
  tds.push(0);
  tds.push(0);
  var tas = Vec[Int].new();
  tas.push(0);
  tas.push(1);
  tas.push(1);
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  let sp = sof_payload(8, 16, 16, comps, hvs, tqs);
  push_seg(&mut out, 192, sp);
  let sosp = sos_payload(ids, tds, tas, 0, 63, 0, 0);
  push_seg(&mut out, 218, sosp);
  out.push(170 as UInt8);
  push_ff(&mut out, 217);
  if (out.len() != 38) { return assert(false, "4:2:0 fixture is 38 bytes"); }
  let img = ok_img(jpeg_parse(out));
  if (jpeg_component_count(img) != 3) { return assert(false, "three frame components"); }
  if (jpeg_component_id(img, 0) != 1) { return assert(false, "Y id 1"); }
  if (jpeg_component_id(img, 1) != 2) { return assert(false, "Cb id 2"); }
  if (jpeg_component_id(img, 2) != 3) { return assert(false, "Cr id 3"); }
  if (jpeg_component_h(img, 0) != 2) { return assert(false, "Y h 2"); }
  if (jpeg_component_v(img, 0) != 2) { return assert(false, "Y v 2"); }
  if (jpeg_component_h(img, 1) != 1) { return assert(false, "Cb h 1"); }
  if (jpeg_component_v(img, 1) != 1) { return assert(false, "Cb v 1"); }
  if (jpeg_component_quant(img, 0) != 0) { return assert(false, "Y quant 0"); }
  if (jpeg_component_quant(img, 1) != 1) { return assert(false, "Cb quant 1"); }
  if (jpeg_component_quant(img, 2) != 1) { return assert(false, "Cr quant 1"); }
  if (jpeg_scan_component_count(img, 0) != 3) { return assert(false, "three scan selectors"); }
  if (jpeg_scan_component_id(img, 0, 0) != 1) { return assert(false, "selector 0 id 1"); }
  if (jpeg_scan_component_id(img, 0, 1) != 2) { return assert(false, "selector 1 id 2"); }
  if (jpeg_scan_component_id(img, 0, 2) != 3) { return assert(false, "selector 2 id 3"); }
  if (jpeg_scan_component_dc(img, 0, 2) != 0) { return assert(false, "selector 2 DC 0"); }
  if (jpeg_scan_component_ac(img, 0, 1) != 1) { return assert(false, "selector 1 AC 1"); }
  if (jpeg_scan_component_ac(img, 0, 2) != 1) { return assert(false, "selector 2 AC 1"); }
  if (jpeg_scan_component_id(img, 0, 3) != -1) { return assert(false, "selector 3 is out of range"); }
  if (jpeg_scan_data_offset(img, 0) != 35) { return assert(false, "scan data at 35"); }
  // An unknown fourth selector is rejected at its own byte.
  var bad_ids = Vec[Int].new();
  bad_ids.push(1);
  bad_ids.push(2);
  bad_ids.push(4);
  var bad = Vec[UInt8].new();
  push_ff(&mut bad, 216);
  let sp2 = sof_payload(8, 16, 16, comps, hvs, tqs);
  push_seg(&mut bad, 192, sp2);
  let bad_sos = sos_payload(bad_ids, tds, tas, 0, 63, 0, 0);
  push_seg(&mut bad, 218, bad_sos);
  bad.push(170 as UInt8);
  push_ff(&mut bad, 217);
  if (!img_err_is(jpeg_parse(bad), "jpeg: unknown scan component", 30)) {
    return assert(false, "unknown selector in a 3-component scan is at offset 30");
  }
  return assert(true, "a 4:2:0 frame and its scan selectors decode exactly");
}

fn t15() -> TestResult {
  // A scan with zero entropy bytes is structurally legal.
  var z = Vec[UInt8].new();
  push_ff(&mut z, 216);
  push_gray_sof(&mut z);
  push_gray_sos(&mut z);
  push_ff(&mut z, 217);
  if (z.len() != 27) { return assert(false, "zero-scan fixture is 27 bytes"); }
  let img = ok_img(jpeg_parse(z));
  if (jpeg_scan_data_offset(img, 0) != 25) { return assert(false, "empty scan starts at 25"); }
  if (jpeg_scan_data_length(img, 0) != 0) { return assert(false, "empty scan has length 0"); }
  if (jpeg_scan_restart_count(img, 0) != 0) { return assert(false, "empty scan has no restarts"); }
  if (jpeg_scan_marker_offset(img, 0) != 25) { return assert(false, "empty scan ends at 25"); }
  if (jpeg_eoi_offset(img) != 25) { return assert(false, "EOI at 25"); }
  if (jpeg_total_bytes(img) != 27) { return assert(false, "total 27"); }
  // EOF inside scan data.
  var eof = Vec[UInt8].new();
  push_ff(&mut eof, 216);
  push_gray_sof(&mut eof);
  push_gray_sos(&mut eof);
  eof.push(17 as UInt8);
  eof.push(34 as UInt8);
  if (!img_err_is(jpeg_parse(eof), "jpeg: missing EOI", 27)) {
    return assert(false, "EOF in scan data is a missing EOI");
  }
  // A lone FF at EOF inside scan data.
  var lone = Vec[UInt8].new();
  push_ff(&mut lone, 216);
  push_gray_sof(&mut lone);
  push_gray_sos(&mut lone);
  lone.push(17 as UInt8);
  lone.push(255 as UInt8);
  if (!img_err_is(jpeg_parse(lone), "jpeg: truncated marker", 26)) {
    return assert(false, "a lone FF at EOF in a scan is truncated");
  }
  var run = Vec[UInt8].new();
  push_ff(&mut run, 216);
  push_gray_sof(&mut run);
  push_gray_sos(&mut run);
  run.push(255 as UInt8);
  run.push(255 as UInt8);
  if (!img_err_is(jpeg_parse(run), "jpeg: truncated marker", 26)) {
    return assert(false, "an FF fill run at EOF in a scan is truncated");
  }
  return assert(true, "scan spans, zero-length scans and in-scan EOF are exact");
}

fn t16() -> TestResult {
  var out = Vec[UInt8].new();
  push_ff(&mut out, 216);
  push_gray_sof(&mut out);
  push_gray_sos(&mut out);
  out.push(1 as UInt8);
  out.push(255 as UInt8);
  out.push(0 as UInt8);
  out.push(2 as UInt8);
  push_ff(&mut out, 208);
  out.push(3 as UInt8);
  push_ff(&mut out, 209);
  out.push(4 as UInt8);
  push_ff(&mut out, 210);
  out.push(5 as UInt8);
  push_ff(&mut out, 211);
  out.push(6 as UInt8);
  push_ff(&mut out, 212);
  out.push(7 as UInt8);
  push_ff(&mut out, 213);
  out.push(8 as UInt8);
  push_ff(&mut out, 214);
  out.push(9 as UInt8);
  push_ff(&mut out, 215);
  out.push(10 as UInt8);
  out.push(255 as UInt8);
  out.push(255 as UInt8);
  out.push(11 as UInt8);
  push_ff(&mut out, 217);
  if (out.len() != 58) { return assert(false, "stress fixture is 58 bytes"); }
  if (!byte_is(out, 25, 1)) { return assert(false, "scan data starts at 25"); }
  if (!byte_is(out, 26, 255)) { return assert(false, "stuffed FF is at 26"); }
  if (!byte_is(out, 27, 0)) { return assert(false, "stuffing byte is at 27"); }
  let img = ok_img(jpeg_parse(out));
  if (jpeg_scan_data_length(img, 0) != 31) { return assert(false, "raw span is 31 bytes"); }
  if (jpeg_scan_restart_count(img, 0) != 8) { return assert(false, "all eight RST markers counted"); }
  if (jpeg_scan_marker_offset(img, 0) != 56) { return assert(false, "terminating marker at 56"); }
  if (jpeg_eoi_offset(img) != 56) { return assert(false, "EOI at 56"); }
  if (jpeg_total_bytes(img) != 58) { return assert(false, "total 58"); }
  if (jpeg_trailing_bytes(img) != 0) { return assert(false, "no trailing bytes"); }
  return assert(true, "stuffing, fill bytes and all RST0..RST7 markers are consumed exactly");
}

fn check(r: TestResult) -> Int {
  if (r.passed) {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name + " -- " + r.message);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.jpeg conformance tests ===");
  var failed: Int = 0;
  failed = failed + check(t1());
  failed = failed + check(t2());
  failed = failed + check(t3());
  failed = failed + check(t4());
  failed = failed + check(t5());
  failed = failed + check(t6());
  failed = failed + check(t7());
  failed = failed + check(t8());
  failed = failed + check(t9());
  failed = failed + check(t10());
  failed = failed + check(t11());
  failed = failed + check(t12());
  failed = failed + check(t13());
  failed = failed + check(t14());
  failed = failed + check(t15());
  failed = failed + check(t16());
  if failed == 0 {
    io.println("xiom.jpeg: all tests passed");
  } else {
    io.println("xiom.jpeg: tests failed");
  }
  return failed;
}

