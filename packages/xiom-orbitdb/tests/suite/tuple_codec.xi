// XIOM ORBITDB -- conformance suite split: tuple_codec (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_tuple_codec

use xiom.io;
use xiom.convert;
use xiom.os.env;
use xiom.test;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.fault;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;
use xiom_db_suite_common;

fn run_row_new_and_access() -> Int {
  var data = Vec[Int].new();
  data.push(10);
  data.push(20);
  data.push(30);
  let row = Row.new(1, data);
  if row.column_count() != 3 { return 1; }
  let c0 = row.get_column(0);
  match c0 { None => return 1; Some(v) => { if v != 10 { return 1; } } }
  let c1 = row.get_column(1);
  match c1 { None => return 1; Some(v) => { if v != 20 { return 1; } } }
  let c2 = row.get_column(2);
  match c2 { None => return 1; Some(v) => { if v != 30 { return 1; } } }
  return 0;
}

fn test_row_new_and_access() -> TestResult {
  let rc = run_row_new_and_access();
  if rc == 0 { return assert(true, "tuple: Row.new + get_column access"); }
  return assert(false, "tuple: row access failed");
}

fn run_row_set_column() -> Int {
  var data = Vec[Int].new();
  data.push(10);
  let row = Row.new(1, data);
  let ok = row.set_column(0, 99);
  if !ok { return 1; }
  let v = row.get_column(0);
  match v { None => return 1; Some(val) => { if val != 99 { return 1; } } }
  return 0;
}

fn test_row_set_column() -> TestResult {
  let rc = run_row_set_column();
  if rc == 0 { return assert(true, "tuple: Row.set_column updates in place"); }
  return assert(false, "tuple: set_column failed");
}

fn run_tuple_encode_decode() -> Int {
  var data = Vec[Int].new();
  data.push(42);
  data.push(99);
  let row = Row.new(7, data);
  let enc = tuple_encode_checked(&row);
  var encoded = Vec[Int].new();
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      // C-ORBIT-01 workaround: rebind the cross-module generic Result payload
      // through an explicitly typed local (docs/repro/ok-method-receiver/).
      let bytes: Vec[Int] = buf;
      encoded = bytes;
    }
  }
  let r = tuple_decode(&encoded);
  match r {
    Err(_) => return 1,
    Ok(decoded) => {
      let d: Row = decoded;
      if d.id != 7 { return 1; }
      if d.column_count() != 2 { return 1; }
      let c0 = d.get_column(0);
      match c0 { None => return 1; Some(v) => { if v != 42 { return 1; } } }
      let c1 = d.get_column(1);
      match c1 { None => return 1; Some(v) => { if v != 99 { return 1; } } }
    }
  }
  return 0;
}

fn test_tuple_encode_decode() -> TestResult {
  let rc = run_tuple_encode_decode();
  if rc == 0 { return assert(true, "tuple: encode then decode roundtrip"); }
  return assert(false, "tuple: encode/decode failed");
}

// v1 KAT: Row(1, [1, 2]) -> exact byte sequence.
fn run_tuple_codec_kat() -> Int {
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  let row = Row.new(1, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      // 3 header bytes + 3 fields x (1 type + 8 LE)
      if bytes.len() != 30 { return 1; } // 3 + 9*3
      if bytes[0] != 0xDB { return 1; }
      if bytes[1] != 0x01 { return 1; }
      if bytes[2] != 3 { return 1; }
      // field 0 (id=1): type 0x01 then 01 00 00 00 00 00 00 00
      if bytes[3] != 0x01 { return 1; }
      if bytes[4] != 1 { return 1; }
      var k = 5;
      while k < 12 { if bytes[k] != 0 { return 1; } k = k + 1; }
      // field 1 (1)
      if bytes[12] != 0x01 { return 1; }
      if bytes[13] != 1 { return 1; }
      k = 14;
      while k < 21 { if bytes[k] != 0 { return 1; } k = k + 1; }
      // field 2 (2)
      if bytes[21] != 0x01 { return 1; }
      if bytes[22] != 2 { return 1; }
      k = 23;
      while k < 30 { if bytes[k] != 0 { return 1; } k = k + 1; }
    }
  }
  return 0;
}

fn test_tuple_codec_kat() -> TestResult {
  let rc = run_tuple_codec_kat();
  if rc == 0 { return assert(true, "tuple: codec v1 byte KAT (magic/version/LE fields)"); }
  return assert(false, "tuple: codec KAT failed");
}

// Roundtrip extremes: negatives and i64 boundaries must survive the LE codec.
fn run_tuple_codec_extremes() -> Int {
  var data = Vec[Int].new();
  data.push(-1);
  data.push(-9223372036854775807 - 1);
  data.push(9223372036854775807);
  data.push(0);
  let row = Row.new(-5, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => return 1,
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if !tuple_fits_page(&row, 4096) { return 1; }
      let r = tuple_decode(&bytes);
      match r {
        Err(_) => return 1,
        Ok(decoded) => {
          let d: Row = decoded;
          if d.id != -5 { return 1; }
          if d.column_count() != 4 { return 1; }
          let c0 = d.get_column(0);
          match c0 { None => return 1; Some(v) => { if v != -1 { return 1; } } }
          let c1 = d.get_column(1);
          match c1 { None => return 1; Some(v) => { if v != -9223372036854775807 - 1 { return 1; } } }
          let c2 = d.get_column(2);
          match c2 { None => return 1; Some(v) => { if v != 9223372036854775807 { return 1; } } }
          let c3 = d.get_column(3);
          match c3 { None => return 1; Some(v) => { if v != 0 { return 1; } } }
        }
      }
    }
  }
  return 0;
}

fn test_tuple_codec_extremes() -> TestResult {
  let rc = run_tuple_codec_extremes();
  if rc == 0 { return assert(true, "tuple: codec extremes (negatives, i64 bounds)"); }
  return assert(false, "tuple: codec extremes failed");
}

// Malformed buffers must be rejected, never partially decoded.
fn run_tuple_codec_rejects() -> Int {
  // bad magic
  var bad1 = Vec[Int].new();
  var i = 0;
  while i < 12 { bad1.push(0); i = i + 1; }
  let d1 = tuple_decode(&bad1);
  match d1 { Ok(_) => { return 1; } Err(_) => {} }
  // truncated valid header
  var bad2 = Vec[Int].new();
  bad2.push(0xDB);
  bad2.push(0x01);
  bad2.push(3);
  let d2 = tuple_decode(&bad2);
  match d2 { Ok(_) => { return 2; } Err(_) => {} }
  // trailing byte after an otherwise valid record
  var data = Vec[Int].new();
  data.push(1);
  let row = Row.new(1, data);
  let enc = tuple_encode_checked(&row);
  match enc {
    Err(_) => { return 3; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      var bad3 = Vec[Int].new();
      i = 0;
      while i < bytes.len() { bad3.push(bytes[i]); i = i + 1; }
      bad3.push(0);
      let d3 = tuple_decode(&bad3);
      match d3 { Ok(_) => { return 4; } Err(_) => {} }
    }
  }
  // empty buffer
  let empty = Vec[Int].new();
  let d4 = tuple_decode(&empty);
  match d4 { Ok(_) => { return 5; } Err(_) => {} }
  // too many fields -> checked encode refuses
  var wide = Vec[Int].new();
  i = 0;
  while i < 300 { wide.push(i); i = i + 1; }
  let wide_row = Row.new(0, wide);
  let enc2 = tuple_encode_checked(&wide_row);
  match enc2 { Ok(_) => { return 6; } Err(_) => {} }
  return 0;
}

fn test_tuple_codec_rejects() -> TestResult {
  let rc = run_tuple_codec_rejects();
  if rc == 0 { return assert(true, "tuple: codec rejects malformed/oversized buffers"); }
  return assert(false, "tuple: codec malformed rejection failed");
}

// ===========================================================================
// Tuple codec v2 (M5.1): typed values (null/int/float/text/blob). The v1
// codec above stays frozen; v2 buffers are a separate version byte.
// ===========================================================================

// KAT: TypedRow(1, [VInt(-2), VText("hi"), VFloat(1.5), VBlob([1,2]), VNull])
// in exact bytes. Offsets: 0..2 container, 3..11 id VInt, 12..20 VInt(-2),
// 21..27 VText("hi"), 28..36 VFloat(1.5), 37..43 VBlob([1,2]), 44 VNull.
fn run_tuple2_kat() -> Int {
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(-2));
  vals.push(TValue.VText("hi"));
  vals.push(TValue.VFloat(1.5));
  var bl = Vec[Int].new();
  bl.push(1);
  bl.push(2);
  vals.push(TValue.VBlob(bl));
  vals.push(TValue.VNull);

  // 3 + 9 (id) + 9 + (5+2) + 9 + (5+2) + 1 = 45
  if tuple2_encoded_len(&vals) != 45 { return 1; }
  let enc = tuple2_encode_row_checked(1, &vals);
  match enc {
    Err(_) => { return 2; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != 45 { return 3; }
      if bytes[0] != 0xDB { return 4; }
      if bytes[1] != 0x02 { return 5; }
      if bytes[2] != 6 { return 6; }        // id + 5 values
      if bytes[3] != 0x01 { return 7; }     // id tag VInt
      if bytes[4] != 1 { return 8; }
      if bytes[5] != 0 { return 9; }
      if bytes[11] != 0 { return 10; }
      if bytes[12] != 0x01 { return 11; }   // VInt(-2)
      if bytes[13] != 0xFE { return 12; }
      if bytes[14] != 0xFF { return 13; }
      if bytes[20] != 0xFF { return 14; }
      if bytes[21] != 0x03 { return 15; }   // VText("hi")
      if bytes[22] != 2 { return 16; }      // u32 len
      if bytes[23] != 0 { return 17; }
      if bytes[25] != 0 { return 18; }
      if bytes[26] != 104 { return 19; }    // 'h'
      if bytes[27] != 105 { return 20; }    // 'i'
      if bytes[28] != 0x02 { return 21; }   // VFloat(1.5)
      if bytes[29] != 0 { return 22; }
      if bytes[34] != 0 { return 23; }
      if bytes[35] != 0xF8 { return 24; }   // 1.5 = 0x3FF8...
      if bytes[36] != 0x3F { return 25; }
      if bytes[37] != 0x04 { return 26; }   // VBlob([1,2])
      if bytes[38] != 2 { return 27; }
      if bytes[41] != 0 { return 28; }
      if bytes[42] != 1 { return 29; }
      if bytes[43] != 2 { return 30; }
      if bytes[44] != 0x00 { return 31; }   // VNull
    }
  }
  return 0;
}

fn test_tuple2_kat() -> TestResult {
  let rc = run_tuple2_kat();
  if rc == 0 { return assert(true, "tuple v2: byte KAT (tags + LE payloads + text/blob lengths)"); }
  return assert(false, "tuple v2: KAT failed rc=" + int_to_str(rc));
}

// Roundtrip every kind, including i64 extremes, multibyte UTF-8, empty
// text/blob, a NaN bit pattern (handcrafted) and a bit-exact re-encode.
fn run_tuple2_roundtrip() -> Int {
  var vals = Vec[TValue].new();
  vals.push(TValue.VNull);
  vals.push(TValue.VInt(-9223372036854775807 - 1));
  vals.push(TValue.VInt(9223372036854775807));
  vals.push(TValue.VFloat(-2.25));
  vals.push(TValue.VText(""));
  vals.push(TValue.VText("h\xC3\xA9llo \xE2\x86\x92"));
  var empty_blob = Vec[Int].new();
  vals.push(TValue.VBlob(empty_blob));
  var raw = Vec[Int].new();
  raw.push(0);
  raw.push(255);
  raw.push(128);
  vals.push(TValue.VBlob(raw));

  if !tuple2_fits_page(&vals, 4096) { return 1; }
  if tuple2_fits_page(&vals, 16) { return 2; }
  let enc = tuple2_encode_row_checked(-7, &vals);
  match enc {
    Err(_) => { return 3; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != tuple2_encoded_len(&vals) { return 4; }
      let dec = tuple2_decode_row(&bytes);
      match dec {
        Err(_) => { return 5; }
        Ok(row) => {
          let r: TypedRow = row;
          if r.id != -7 { return 6; }
          if r.values.len() != 8 { return 7; }
          if !tuple2_is_null(r.values[0]) { return 8; }
          let i1 = tuple2_int_value(r.values[1]);
          match i1 { None => { return 9; } Some(x) => { if x != -9223372036854775807 - 1 { return 10; } } }
          let i2 = tuple2_int_value(r.values[2]);
          match i2 { None => { return 11; } Some(x) => { if x != 9223372036854775807 { return 12; } } }
          let f1 = tuple2_float_value(r.values[3]);
          match f1 { None => { return 13; } Some(x) => { if x != -2.25 { return 14; } } }
          let t1 = tuple2_text_value(r.values[4]);
          match t1 { None => { return 15; } Some(x) => { if x != "" { return 16; } } }
          let t2 = tuple2_text_value(r.values[5]);
          match t2 { None => { return 17; } Some(x) => { if x != "h\xC3\xA9llo \xE2\x86\x92" { return 18; } } }
          let b1 = tuple2_blob_value(r.values[6]);
          match b1 { None => { return 19; } Some(x) => { if x.len() != 0 { return 20; } } }
          let b2 = tuple2_blob_value(r.values[7]);
          match b2 {
            None => { return 21; }
            Some(x) => {
              if x.len() != 3 { return 22; }
              if x[0] != 0 { return 23; }
              if x[1] != 255 { return 24; }
              if x[2] != 128 { return 25; }
            }
          }
        }
      }
    }
  }

  // NaN bit pattern (0x7FF8000000000000 LE) must decode and re-encode
  // byte-exactly: idx 3 tag VFloat, idx 4..11 NaN bits.
  var nan_row = Vec[Int].new();
  nan_row.push(0xDB);
  nan_row.push(0x02);
  nan_row.push(0x02);
  nan_row.push(0x01);
  nan_row.push(1);
  var z = 0;
  while z < 7 { nan_row.push(0); z = z + 1; }
  nan_row.push(0x02);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0x00);
  nan_row.push(0xF8);
  nan_row.push(0x7F);
  let nd = tuple2_decode_row(&nan_row);
  match nd {
    Err(_) => { return 26; }
    Ok(row2) => {
      let r2: TypedRow = row2;
      if r2.values.len() != 1 { return 27; }
      let fv = tuple2_float_value(r2.values[0]);
      match fv {
        None => { return 28; }
        Some(f) => { if f == f { return 29; } } // NaN != NaN
      }
      // Re-encode through the typed path and compare bytes (bit-exact).
      var re = tuple2_encode_row_checked(1, &r2.values);
      match re {
        Err(_) => { return 30; }
        Ok(buf3) => {
          let b3: Vec[Int] = buf3;
          if b3.len() != nan_row.len() { return 31; }
          var k = 0;
          while k < b3.len() {
            if b3[k] != nan_row[k] { return 32; }
            k = k + 1;
          }
        }
      }
    }
  }
  return 0;
}

fn test_tuple2_roundtrip() -> TestResult {
  let rc = run_tuple2_roundtrip();
  if rc == 0 { return assert(true, "tuple v2: roundtrip all kinds (extremes, UTF-8, NaN bit-exact)"); }
  return assert(false, "tuple v2: roundtrip failed rc=" + int_to_str(rc));
}

// Corrupt / cross-version / oversized inputs must be rejected, never
// partially decoded.
fn run_tuple2_rejects() -> Int {
  // Valid v2 baseline to corrupt.
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(5));
  vals.push(TValue.VText("ab"));
  let enc = tuple2_encode_row_checked(3, &vals);
  match enc {
    Err(_) => { return 1; }
    Ok(buf) => {
      let v2: Vec[Int] = buf;

      // v1 buffer must not decode as v2 (version discriminator).
      var data1 = Vec[Int].new();
      data1.push(1);
      let row1 = Row.new(1, data1);
      let v1enc = tuple_encode_checked(&row1);
      match v1enc {
        Err(_) => { return 2; }
        Ok(v1buf) => {
          let b1: Vec[Int] = v1buf;
          let d1 = tuple2_decode_row(&b1);
          match d1 { Ok(_) => { return 3; } Err(_) => {} }
          // ... and the v2 buffer must not decode as v1.
          let d2 = tuple_decode(&v2);
          match d2 { Ok(_) => { return 4; } Err(_) => {} }
        }
      }

      // Truncated by one byte (exact-length rule).
      var trunc = Vec[Int].new();
      var i = 0;
      while i < v2.len() - 1 { trunc.push(v2[i]); i = i + 1; }
      let d3 = tuple2_decode_row(&trunc);
      match d3 { Ok(_) => { return 5; } Err(_) => {} }

      // Trailing byte.
      var trail = Vec[Int].new();
      i = 0;
      while i < v2.len() { trail.push(v2[i]); i = i + 1; }
      trail.push(0);
      let d4 = tuple2_decode_row(&trail);
      match d4 { Ok(_) => { return 6; } Err(_) => {} }

      // Wrong magic.
      var magic = Vec[Int].new();
      i = 0;
      while i < v2.len() { magic.push(v2[i]); i = i + 1; }
      magic[0] = 0x00;
      let d5 = tuple2_decode_row(&magic);
      match d5 { Ok(_) => { return 7; } Err(_) => {} }

      // Unknown tag in field 1.
      var unk = Vec[Int].new();
      i = 0;
      while i < v2.len() { unk.push(v2[i]); i = i + 1; }
      unk[12] = 0x7F;
      let d6 = tuple2_decode_row(&unk);
      match d6 { Ok(_) => { return 8; } Err(_) => {} }

      // Field 0 not VInt: flip the id tag to VText with a 1-byte body.
      var f0 = Vec[Int].new();
      f0.push(0xDB);
      f0.push(0x02);
      f0.push(0x01);
      f0.push(0x03);
      f0.push(1);
      f0.push(0);
      f0.push(0);
      f0.push(0);
      f0.push(65);
      let d7 = tuple2_decode_row(&f0);
      match d7 { Ok(_) => { return 9; } Err(_) => {} }

      // Text length field larger than the remaining buffer.
      var short = Vec[Int].new();
      short.push(0xDB);
      short.push(0x02);
      short.push(0x02);
      short.push(0x01);
      var q = 0;
      while q < 8 { short.push(0); q = q + 1; }
      short.push(0x03);
      short.push(9); // len 9, only 2 bytes below
      short.push(0);
      short.push(0);
      short.push(0);
      short.push(104);
      short.push(105);
      let d8 = tuple2_decode_row(&short);
      match d8 { Ok(_) => { return 10; } Err(_) => {} }

      // A non-byte element anywhere in the buffer (999) is corruption.
      var wide = Vec[Int].new();
      i = 0;
      while i < v2.len() { wide.push(v2[i]); i = i + 1; }
      wide[6] = 999;
      let d9 = tuple2_decode_row(&wide);
      match d9 { Ok(_) => { return 11; } Err(_) => {} }
    }
  }

  // Encode-side guards: 256 fields refuse; blob byte > 255 refuses.
  var many = Vec[TValue].new();
  var j = 0;
  while j < 255 { many.push(TValue.VNull); j = j + 1; }
  let e1 = tuple2_encode_row_checked(1, &many);
  match e1 { Ok(_) => { return 12; } Err(_) => {} }

  var bad_blob_vals = Vec[TValue].new();
  var bb = Vec[Int].new();
  bb.push(300);
  bad_blob_vals.push(TValue.VBlob(bb));
  let e2 = tuple2_encode_row_checked(1, &bad_blob_vals);
  match e2 { Ok(_) => { return 13; } Err(_) => {} }

  return 0;
}

fn test_tuple2_rejects() -> TestResult {
  let rc = run_tuple2_rejects();
  if rc == 0 { return assert(true, "tuple v2: rejects corruption + cross-version + oversized"); }
  return assert(false, "tuple v2: rejects failed rc=" + int_to_str(rc));
}

// Kinds, per-value lengths and the page budget boundary.
fn run_tuple2_budget() -> Int {
  if tuple2_kind(TValue.VNull) != 0x00 { return 1; }
  if tuple2_kind(TValue.VInt(1)) != 0x01 { return 2; }
  if tuple2_kind(TValue.VFloat(1.0)) != 0x02 { return 3; }
  if tuple2_kind(TValue.VText("a")) != 0x03 { return 4; }
  var one = Vec[Int].new();
  one.push(9);
  if tuple2_kind(TValue.VBlob(one)) != 0x04 { return 5; }

  if tuple2_value_len(TValue.VNull) != 1 { return 6; }
  if tuple2_value_len(TValue.VInt(0)) != 9 { return 7; }
  if tuple2_value_len(TValue.VFloat(0.0)) != 9 { return 8; }
  if tuple2_value_len(TValue.VText("abc")) != 8 { return 9; }
  if tuple2_value_len(TValue.VBlob(one)) != 6 { return 10; }

  // One 4000-byte text: row len = 3 + 9 + 5 + 4000 = 4017. Boundary only.
  var s = "";
  var i = 0;
  while i < 4000 { s = s + "a"; i = i + 1; }
  var vals = Vec[TValue].new();
  vals.push(TValue.VText(s));
  if tuple2_encoded_len(&vals) != 4017 { return 11; }
  if !tuple2_fits_page(&vals, 4017) { return 12; }
  if tuple2_fits_page(&vals, 4016) { return 13; }
  if tuple2_fits_page(&vals, -1) { return 14; }
  return 0;
}

fn test_tuple2_budget() -> TestResult {
  let rc = run_tuple2_budget();
  if rc == 0 { return assert(true, "tuple v2: kinds + per-value lengths + page budget boundary"); }
  return assert(false, "tuple v2: budget failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Schema-driven rows (M5.2): ColumnType <-> TValue bridge, validation, and
// the schema row codec (tuple v2 with id = pk). Pure layer; persistence +
// container decision documented in docs/TYPED-VALUES-STORAGE.md.
// ===========================================================================

fn srowt_blob(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn srowt_schema() -> Schema {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.optional("score", ColumnType.FloatType, None));
  cols.push(ColumnDef.new("ok", ColumnType.BoolType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  cols.push(ColumnDef.new("raw", ColumnType.BytesType));
  return Schema.new("t", cols, 0);
}

fn srowt_ok_row() -> Vec[TValue] {
  var vals = Vec[TValue].new();
  vals.push(TValue.VInt(42));
  vals.push(TValue.VFloat(2.5));
  vals.push(TValue.VInt(1));
  vals.push(TValue.VText("h\xC3\xA9llo"));
  vals.push(TValue.VBlob(srowt_blob(1, 2, 3)));
  return vals;
}

fn run_schema_row_kinds() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("i", ColumnType.IntType));
  cols.push(ColumnDef.new("f", ColumnType.FloatType));
  cols.push(ColumnDef.new("b", ColumnType.BoolType));
  cols.push(ColumnDef.new("s", ColumnType.StringType));
  cols.push(ColumnDef.new("y", ColumnType.BytesType));
  let c0 = cols[0];
  let c1 = cols[1];
  let c2 = cols[2];
  let c3 = cols[3];
  let c4 = cols[4];

  if !schema_row_value_ok(&c0, TValue.VInt(1)) { return 1; }
  if schema_row_value_ok(&c0, TValue.VText("x")) { return 2; }
  if schema_row_value_ok(&c0, TValue.VNull) { return 3; }
  if !schema_row_value_ok(&c1, TValue.VFloat(0.5)) { return 4; }
  if schema_row_value_ok(&c1, TValue.VInt(1)) { return 5; }
  if !schema_row_value_ok(&c2, TValue.VInt(0)) { return 6; }
  if !schema_row_value_ok(&c2, TValue.VInt(1)) { return 7; }
  if schema_row_value_ok(&c2, TValue.VInt(2)) { return 8; }
  if schema_row_value_ok(&c2, TValue.VText("1")) { return 9; }
  if !schema_row_value_ok(&c3, TValue.VText("")) { return 10; }
  if schema_row_value_ok(&c3, TValue.VBlob(srowt_blob(1, 0, 0))) { return 11; }
  if !schema_row_value_ok(&c4, TValue.VBlob(srowt_blob(1, 0, 0))) { return 12; }
  if schema_row_value_ok(&c4, TValue.VInt(1)) { return 13; }
  let nullable_col = ColumnDef.optional("n", ColumnType.StringType, None);
  if !schema_row_value_ok(&nullable_col, TValue.VNull) { return 14; }
  if !schema_row_value_ok(&nullable_col, TValue.VText("a")) { return 15; }
  if schema_row_value_ok(&nullable_col, TValue.VInt(1)) { return 16; }
  if column_type_code(ColumnType.IntType) != 1 { return 17; }
  if column_type_code(ColumnType.FloatType) != 2 { return 18; }
  if column_type_code(ColumnType.BoolType) != 3 { return 19; }
  if column_type_code(ColumnType.StringType) != 4 { return 20; }
  if column_type_code(ColumnType.BytesType) != 5 { return 21; }
  return 0;
}

fn test_schema_row_kinds() -> TestResult {
  let rc = run_schema_row_kinds();
  if rc == 0 { return assert(true, "schema_row: ColumnType<->TValue kind mapping + nullability + bool domain"); }
  return assert(false, "schema_row: kinds failed rc=" + int_to_str(rc));
}

fn run_schema_row_roundtrip() -> Int {
  let schema = srowt_schema();
  let vals = srowt_ok_row();
  match schema_row_validate(&schema, &vals) {
    Err(_) => { return 1; }
    Ok(_) => {}
  }
  match schema_row_key(&schema, &vals) {
    Err(_) => { return 2; }
    Ok(k) => { if k != 42 { return 3; } }
  }
  let enc = schema_row_encode(&schema, &vals);
  match enc {
    Err(_) => { return 4; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      if bytes.len() != tuple2_encoded_len(&vals) { return 5; }
      let dec = schema_row_decode(&schema, &bytes);
      match dec {
        Err(_) => { return 6; }
        Ok(row) => {
          let r: TypedRow = row;
          if r.id != 42 { return 7; }
          if r.values.len() != 5 { return 8; }
          match tuple2_int_value(r.values[0]) { None => { return 9; } Some(v) => { if v != 42 { return 10; } } }
          match tuple2_float_value(r.values[1]) { None => { return 11; } Some(f) => { if f != 2.5 { return 12; } } }
          match tuple2_int_value(r.values[2]) { None => { return 13; } Some(v) => { if v != 1 { return 14; } } }
          match tuple2_text_value(r.values[3]) { None => { return 15; } Some(s) => { if s != "h\xC3\xA9llo" { return 16; } } }
          match tuple2_blob_value(r.values[4]) {
            None => { return 17; }
            Some(b) => {
              if b.len() != 3 { return 18; }
              if b[0] != 1 { return 19; }
              if b[2] != 3 { return 20; }
            }
          }
          // Re-encode the decoded row: byte-identical (canonical codec).
          match schema_row_encode(&schema, &r.values) {
            Err(_) => { return 21; }
            Ok(buf2) => {
              let b2: Vec[Int] = buf2;
              if b2.len() != bytes.len() { return 22; }
              var i = 0;
              while i < b2.len() {
                if b2[i] != bytes[i] { return 23; }
                i = i + 1;
              }
            }
          }
        }
      }
      // The raw codec sees the same row (composition).
      match tuple2_decode_row(&bytes) {
        Err(_) => { return 24; }
        Ok(r2) => { if r2.id != 42 { return 25; } }
      }
    }
  }
  return 0;
}

fn test_schema_row_roundtrip() -> TestResult {
  let rc = run_schema_row_roundtrip();
  if rc == 0 { return assert(true, "schema_row: validate/key/encode/decode roundtrip + byte-identity"); }
  return assert(false, "schema_row: roundtrip failed rc=" + int_to_str(rc));
}

fn run_schema_row_rejects() -> Int {
  let schema = srowt_schema();

  // Arity: too few / too many.
  var four = Vec[TValue].new();
  four.push(TValue.VInt(1));
  four.push(TValue.VFloat(1.0));
  four.push(TValue.VInt(1));
  four.push(TValue.VText("n"));
  match schema_row_validate(&schema, &four) { Ok(_) => { return 1; } Err(e) => { if schema_row_error_code(e) != 4 { return 2; } } }
  var six = srowt_ok_row();
  six.push(TValue.VNull);
  match schema_row_validate(&schema, &six) { Ok(_) => { return 3; } Err(e) => { if schema_row_error_code(e) != 4 { return 4; } } }

  // Null on a non-nullable column.
  var nullrow = srowt_ok_row();
  nullrow[3] = TValue.VNull;
  match schema_row_validate(&schema, &nullrow) {
    Ok(_) => { return 5; }
    Err(e) => { if schema_row_error_code(e) != 3 { return 6; } }
  }

  // Null on the NULLABLE column is fine.
  var oknull = srowt_ok_row();
  oknull[1] = TValue.VNull;
  match schema_row_validate(&schema, &oknull) { Err(_) => { return 7; } Ok(_) => {} }

  // Wrong kinds per column.
  var bad = srowt_ok_row();
  bad[0] = TValue.VText("x");
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 8; } Err(e) => { if schema_row_error_code(e) != 4 { return 9; } } }
  bad = srowt_ok_row();
  bad[1] = TValue.VInt(1);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 10; } Err(e) => { if schema_row_error_code(e) != 4 { return 11; } } }
  bad = srowt_ok_row();
  bad[2] = TValue.VInt(2);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 12; } Err(e) => { if schema_row_error_code(e) != 3 { return 13; } } }
  bad = srowt_ok_row();
  bad[3] = TValue.VBlob(srowt_blob(1, 0, 0));
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 14; } Err(e) => { if schema_row_error_code(e) != 4 { return 15; } } }
  bad = srowt_ok_row();
  bad[4] = TValue.VInt(1);
  match schema_row_validate(&schema, &bad) { Ok(_) => { return 16; } Err(e) => { if schema_row_error_code(e) != 4 { return 17; } } }

  // Non-VInt pk (even when the declared type is int).
  var pkbad = srowt_ok_row();
  pkbad[0] = TValue.VText("42");
  match schema_row_key(&schema, &pkbad) { Ok(_) => { return 18; } Err(e) => { if schema_row_error_code(e) != 4 { return 19; } } }

  // Nullable pk schema + VNull pk: int-keyed storage refuses.
  var pcols = Vec[ColumnDef].new();
  pcols.push(ColumnDef.optional("id", ColumnType.IntType, None));
  let pschema = Schema.new("p", pcols, 0);
  var pvals = Vec[TValue].new();
  pvals.push(TValue.VNull);
  match schema_row_validate(&pschema, &pvals) { Ok(_) => { return 20; } Err(e) => { if schema_row_error_code(e) != 4 { return 21; } } }

  // 256 columns: valid per schema, refused by the codec (u8 field count).
  var wide_cols = Vec[ColumnDef].new();
  var wide_vals = Vec[TValue].new();
  var i = 0;
  while i < 256 {
    wide_cols.push(ColumnDef.new("c" + int_to_str(i), ColumnType.IntType));
    wide_vals.push(TValue.VInt(i));
    i = i + 1;
  }
  let wide_schema = Schema.new("w", wide_cols, 0);
  match schema_row_validate(&wide_schema, &wide_vals) { Err(_) => { return 22; } Ok(_) => {} }
  match schema_row_encode(&wide_schema, &wide_vals) { Ok(_) => { return 23; } Err(e) => { if schema_row_error_code(e) != 3 { return 24; } } }

  // Decode: v1 bytes are not schema rows.
  var v1data = Vec[Int].new();
  v1data.push(1);
  let v1row = Row.new(1, v1data);
  let v1enc = tuple_encode_checked(&v1row);
  match v1enc {
    Err(_) => { return 25; }
    Ok(v1buf) => {
      let b1: Vec[Int] = v1buf;
      match schema_row_decode(&schema, &b1) { Ok(_) => { return 26; } Err(e) => { if schema_row_error_code(e) != 6 { return 27; } } }
    }
  }

  // Decode: id/pk mismatch is corruption (encoded via the raw codec with a
  // different id).
  let vals = srowt_ok_row();
  let raw = tuple2_encode_row_checked(99, &vals);
  match raw {
    Err(_) => { return 28; }
    Ok(rawbuf) => {
      let rb: Vec[Int] = rawbuf;
      match schema_row_decode(&schema, &rb) { Ok(_) => { return 29; } Err(e) => { if schema_row_error_code(e) != 6 { return 30; } } }
    }
  }

  // Decode: schema drift (column 3 declared int instead of string).
  var drift_cols = Vec[ColumnDef].new();
  drift_cols.push(ColumnDef.new("id", ColumnType.IntType));
  drift_cols.push(ColumnDef.optional("score", ColumnType.FloatType, None));
  drift_cols.push(ColumnDef.new("ok", ColumnType.BoolType));
  drift_cols.push(ColumnDef.new("name", ColumnType.IntType));
  drift_cols.push(ColumnDef.new("raw", ColumnType.BytesType));
  let drift = Schema.new("t", drift_cols, 0);
  let enc = schema_row_encode(&schema, &vals);
  match enc {
    Err(_) => { return 31; }
    Ok(buf) => {
      let bytes: Vec[Int] = buf;
      match schema_row_decode(&drift, &bytes) { Ok(_) => { return 32; } Err(e) => { if schema_row_error_code(e) != 4 { return 33; } } }
    }
  }
  return 0;
}

fn test_schema_row_rejects() -> TestResult {
  let rc = run_schema_row_rejects();
  if rc == 0 { return assert(true, "schema_row: rejects arity/null/kind/bool/pk + corruption + schema drift"); }
  return assert(false, "schema_row: rejects failed rc=" + int_to_str(rc));
}

// Bool domain + empty text/blob round-trips through the schema layer.
fn run_schema_row_bool_and_empty() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("b", ColumnType.BoolType));
  cols.push(ColumnDef.new("s", ColumnType.StringType));
  let schema = Schema.new("be", cols, 0);

  var v0 = Vec[TValue].new();
  v0.push(TValue.VInt(1));
  v0.push(TValue.VInt(0));
  v0.push(TValue.VText(""));
  var v1 = Vec[TValue].new();
  v1.push(TValue.VInt(2));
  v1.push(TValue.VInt(1));
  var empty = Vec[Int].new();
  v1.push(TValue.VBlob(empty));

  match schema_row_encode(&schema, &v0) {
    Err(_) => { return 1; }
    Ok(b0) => {
      let bytes: Vec[Int] = b0;
      match schema_row_decode(&schema, &bytes) {
        Err(_) => { return 2; }
        Ok(r) => {
          match tuple2_int_value(r.values[1]) { None => { return 3; } Some(b) => { if b != 0 { return 4; } } }
          match tuple2_text_value(r.values[2]) { None => { return 5; } Some(s) => { if s != "" { return 6; } } }
        }
      }
    }
  }
  // Column 2 is a String column: a blob is a kind violation even when empty.
  match schema_row_encode(&schema, &v1) {
    Ok(_) => { return 7; }
    Err(e) => { if schema_row_error_code(e) != 4 { return 8; } }
  }
  return 0;
}

fn test_schema_row_bool_and_empty() -> TestResult {
  let rc = run_schema_row_bool_and_empty();
  if rc == 0 { return assert(true, "schema_row: bool 0/1 domain + empty text roundtrip + kind strictness"); }
  return assert(false, "schema_row: bool/empty failed rc=" + int_to_str(rc));
}

// ===========================================================================
// Typed rows in the engine (M5.3): payload container through put/get, WAL
// (tagged subtype 1), replay, and both snapshot containers. Contract:
// docs/TYPED-VALUES-STORAGE.md.

fn main() -> Int {
  io.println("=== XIOM DB Conformance: tuple_codec ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r90 = test_row_new_and_access();
  total = total + 1; failed = failed + report(r90.passed, r90.name);
  let r91 = test_row_set_column();
  total = total + 1; failed = failed + report(r91.passed, r91.name);
  let r92 = test_tuple_encode_decode();
  total = total + 1; failed = failed + report(r92.passed, r92.name);
  let r92b = test_tuple_codec_kat();
  total = total + 1; failed = failed + report(r92b.passed, r92b.name);
  let r92c = test_tuple_codec_extremes();
  total = total + 1; failed = failed + report(r92c.passed, r92c.name);
  let r92d = test_tuple_codec_rejects();
  total = total + 1; failed = failed + report(r92d.passed, r92d.name);
  let r111 = test_tuple2_kat();
  total = total + 1; failed = failed + report(r111.passed, r111.name);
  let r112 = test_tuple2_roundtrip();
  total = total + 1; failed = failed + report(r112.passed, r112.name);
  let r113 = test_tuple2_rejects();
  total = total + 1; failed = failed + report(r113.passed, r113.name);
  let r114 = test_tuple2_budget();
  total = total + 1; failed = failed + report(r114.passed, r114.name);
  let r115 = test_schema_row_kinds();
  total = total + 1; failed = failed + report(r115.passed, r115.name);
  let r116 = test_schema_row_roundtrip();
  total = total + 1; failed = failed + report(r116.passed, r116.name);
  let r117 = test_schema_row_rejects();
  total = total + 1; failed = failed + report(r117.passed, r117.name);
  let r118 = test_schema_row_bool_and_empty();
  total = total + 1; failed = failed + report(r118.passed, r118.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [tuple_codec]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}