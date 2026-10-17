// XIOM ORBITDB -- tuple codec v1 probe (KAT + roundtrip + rejection).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Acceptance for the byte-packed tuple codec in src/storage/tuple.xi.
// Exit: 0 green, 1+ first failing check.

module orbitdb_probe_tuple_codec

use xiom.io;
use xiom.convert;
use xiom.db.storage.tuple;

fn dump_bytes(label: Str, bytes: &Vec[Int]) {
  var s = label + " len=" + convert.int_to_string(bytes.len()) + ":";
  var i = 0;
  while i < bytes.len() {
    s = s + " " + convert.int_to_string(bytes[i]);
    i = i + 1;
  }
  io.println(s);
}

fn push8(out: &mut Vec[Int], v: Int) {
  var k = 0;
  while k < 8 {
    out.push((v >> (8 * k)) & 0xFF);
    k = k + 1;
  }
}

fn main() -> Int {
  // Helper control: the same extraction behind a &mut Vec[Int] parameter.
  var h = Vec[Int].new();
  push8(&mut h, 1);
  dump_bytes("helper", &h);
  if h.len() != 8 { io.println("helper: len FAIL"); return 30; }
  if h[0] != 1 { io.println("helper: low byte FAIL"); return 31; }

  // Inline control: the same byte-extraction loop, in this module.
  var inline = Vec[Int].new();
  var x = 1;
  var k = 0;
  while k < 8 {
    inline.push((x >> (8 * k)) & 0xFF);
    k = k + 1;
  }
  dump_bytes("inline", &inline);
  if inline.len() != 8 { io.println("inline: len FAIL"); return 20; }

  // Hand-built canonical record for Row(1,[1,2]); decode must accept it.
  var manual = Vec[Int].new();
  manual.push(0xDB);
  manual.push(0x01);
  manual.push(3);
  manual.push(0x01);
  manual.push(1);
  var z = 0;
  while z < 7 { manual.push(0); z = z + 1; }
  manual.push(0x01);
  manual.push(1);
  z = 0;
  while z < 7 { manual.push(0); z = z + 1; }
  manual.push(0x01);
  manual.push(2);
  z = 0;
  while z < 7 { manual.push(0); z = z + 1; }
  dump_bytes("manual", &manual);
  if manual.len() != 30 { io.println("manual: len FAIL"); return 21; }
  let dec0 = tuple_decode(&manual);
  match dec0 {
    Err(_) => { io.println("manual: decode ERR"); return 22; }
    Ok(decoded) => {
      let d0: Row = decoded;
      if d0.id != 1 { io.println("manual: id FAIL"); return 23; }
      let c0 = d0.get_column(0);
      match c0 { None => { return 24; } Some(v) => { if v != 1 { io.println("manual: c0 FAIL"); return 25; } } }
    }
  }

  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  let row = Row.new(1, data);
  let enc = tuple_encode_checked(&row);
  var bytes = Vec[Int].new();
  match enc {
    Err(_) => { io.println("kat: encode ERR"); return 1; }
    Ok(buf) => {
      let b: Vec[Int] = buf;
      bytes = b;
    }
  }
  dump_bytes("kat", &bytes);
  if bytes.len() != 30 { io.println("kat: len FAIL"); return 2; }
  if bytes[0] != 0xDB { io.println("kat: magic FAIL"); return 3; }
  if bytes[1] != 0x01 { io.println("kat: version FAIL"); return 4; }
  if bytes[2] != 3 { io.println("kat: count FAIL"); return 5; }
  if bytes[3] != 0x01 { io.println("kat: f0 type FAIL"); return 6; }
  if bytes[4] != 1 { io.println("kat: id byte FAIL"); return 7; }

  let dec = tuple_decode(&bytes);
  match dec {
    Err(_) => { io.println("kat: decode ERR"); return 8; }
    Ok(decoded) => {
      let d: Row = decoded;
      if d.id != 1 { io.println("kat: decoded id FAIL"); return 9; }
      if d.column_count() != 2 { io.println("kat: decoded count FAIL"); return 10; }
      let c0 = d.get_column(0);
      match c0 { None => { return 11; } Some(v) => { if v != 1 { io.println("kat: c0 FAIL"); return 12; } } }
      let c1 = d.get_column(1);
      match c1 { None => { return 13; } Some(v) => { if v != 2 { io.println("kat: c1 FAIL"); return 14; } } }
    }
  }

  // Extremes roundtrip: negatives and i64 boundaries.
  var xdata = Vec[Int].new();
  xdata.push(-1);
  xdata.push(-9223372036854775807 - 1);
  xdata.push(9223372036854775807);
  xdata.push(0);
  let xrow = Row.new(-5, xdata);
  let xenc = tuple_encode_checked(&xrow);
  match xenc {
    Err(_) => { io.println("extremes: encode ERR"); return 40; }
    Ok(buf) => {
      let xb: Vec[Int] = buf;
      if xb.len() != 3 + 9 * 5 { io.println("extremes: len FAIL"); return 41; }
      if !tuple_fits_page(&xrow, 4096) { io.println("extremes: budget FAIL"); return 42; }
      let xdec = tuple_decode(&xb);
      match xdec {
        Err(_) => { io.println("extremes: decode ERR"); return 43; }
        Ok(decoded) => {
          let d: Row = decoded;
          if d.id != -5 { io.println("extremes: id FAIL"); return 44; }
          let c1 = d.get_column(1);
          match c1 { None => { return 45; } Some(v) => { if v != -9223372036854775807 - 1 { io.println("extremes: min FAIL"); return 46; } } }
          let c2 = d.get_column(2);
          match c2 { None => { return 47; } Some(v) => { if v != 9223372036854775807 { io.println("extremes: max FAIL"); return 48; } } }
        }
      }
    }
  }

  // Rejection matrix: bad magic, truncated, trailing byte, empty.
  var bad1 = Vec[Int].new();
  var z1 = 0;
  while z1 < 12 { bad1.push(0); z1 = z1 + 1; }
  let d1 = tuple_decode(&bad1);
  match d1 { Ok(_) => { io.println("rejects: magic FAIL"); return 50; } Err(_) => {} }
  var bad2 = Vec[Int].new();
  bad2.push(0xDB);
  bad2.push(0x01);
  bad2.push(3);
  let d2 = tuple_decode(&bad2);
  match d2 { Ok(_) => { io.println("rejects: truncated FAIL"); return 51; } Err(_) => {} }
  var bad3 = Vec[Int].new();
  var z3 = 0;
  while z3 < manual.len() { bad3.push(manual[z3]); z3 = z3 + 1; }
  bad3.push(0);
  let d3 = tuple_decode(&bad3);
  match d3 { Ok(_) => { io.println("rejects: trailing FAIL"); return 52; } Err(_) => {} }
  let empty = Vec[Int].new();
  let d4 = tuple_decode(&empty);
  match d4 { Ok(_) => { io.println("rejects: empty FAIL"); return 53; } Err(_) => {} }

  // Budget: 200 columns fit a 4096 page; 255+ fields are not encodable.
  var wide = Vec[Int].new();
  var w = 0;
  while w < 200 { wide.push(w); w = w + 1; }
  let wide_row = Row.new(0, wide);
  if !tuple_fits_page(&wide_row, 4096) { io.println("budget: 200 cols FAIL"); return 60; }
  var too_wide = Vec[Int].new();
  w = 0;
  while w < 300 { too_wide.push(w); w = w + 1; }
  let tw_row = Row.new(0, too_wide);
  let tw_enc = tuple_encode_checked(&tw_row);
  match tw_enc { Ok(_) => { io.println("budget: oversize encode FAIL"); return 61; } Err(_) => {} }

  io.println("tuple-codec: OK");
  return 0;
}
