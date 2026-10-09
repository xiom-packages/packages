// XIOM -- xiom.orc: Apache ORC file metadata codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A dependency-free reader for the metadata of Apache ORC files. Only the
// container skeleton is parsed; column data is never decoded:
//
//   [3]  magic "ORC"
//   [..] stripes (index/data streams and each stripe's footer), untouched
//   [..] file footer (protobuf Footer: stripe table, schema type tree, row
//        count, statistics presence)
//   [..] file metadata (protobuf Metadata: per-stripe statistics counts)
//   [..] postscript (protobuf PostScript: footer/metadata lengths,
//        compression kind and block size, format version, writer version,
//        magic string)
//   [1]  postscript length (one byte)
//
// The postscript is never compressed; the footer, metadata and stripe
// footers are compressed when the postscript declares a compression kind
// other than NONE. This codec performs no decompression, so those regions
// are decoded only for uncompressed files: orc_parse always validates the
// magic and the postscript, and when compression is NONE it additionally
// decodes the footer, every stripe footer (stream lists) and the metadata
// (statistics presence). For compressed files orc_footer_available is
// false and every footer-derived accessor returns Err("orc: footer not
// available (compressed file)").
//
// Protobuf subset: varints; tags with wire types 0 (varint), 1 (64-bit),
// 2 (length-delimited) and 5 (32-bit); length-delimited submessages; and
// packed repeated varints (also accepted unpacked). Wire types 3/4
// (groups) are rejected; unknown fields and known fields carrying an
// unexpected wire type are skipped. Every parse failure reports the byte
// offset at which it was detected.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * field names are validated printable ASCII before they are
//     materialized with sb_to_str, which never sees a 0x00 byte.
//   * every UInt8 is widened with `(b as Int) & 0xFF` before arithmetic.
//   * every Vec[Int] element read is bound to a typed local.
//   * every push on one parallel vector is mirrored on all its siblings
//     (see the Orc type comment for the intended grouping).

module xiom.orc

use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_vec_int(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_vec_int(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Orc, Str].
fn _ok_orc(v: Orc) -> Result[Orc, Str] {
  return Ok(v);
}

// Err(m) for Result[Orc, Str].
fn _err_orc(m: Str) -> Result[Orc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed ORC file metadata.
///
/// Postscript fields (always available): `file_length`, `ps_start`/`ps_len`
/// locate the postscript, `compression` (0 NONE, 1 ZLIB, 2 SNAPPY, 3 LZ4,
/// 4 ZSTD), `block_size`, `footer_length`, `metadata_length`,
/// `writer_version` and `version` (the packed postscript version parts).
/// `footer_start`/`metadata_start` are the absolute offsets of the footer
/// and metadata regions, derived from the postscript lengths.
///
/// Footer fields (available only when `footer_available == 1`, which is
/// the case exactly when `compression == 0`): `header_length`,
/// `content_length`, `row_index_stride`, `row_count` and `stats_count`
/// (the number of footer ColumnStatistics entries).
///
/// Type tree, one entry per column in column-id order:
///   * `t_kind[i]` is the Type.Kind code (0..18, see orc_column_kind_name);
///   * `t_sub_off[i]`/`t_sub_count[i]` locate its subtype column ids in
///     `subtypes`;
///   * `t_name_off[i]`/`t_name_count[i]` locate its printable field names
///     in `field_names`;
///   * `t_max_length[i]`, `t_precision[i]`, `t_scale[i]` are the
///     maximumLength/precision/scale attributes (0 when absent).
///
/// Stripes, one entry per StripeInformation, in file order:
/// `s_offset[i]`, `s_index_len[i]`, `s_data_len[i]`, `s_footer_len[i]` and
/// `s_rows[i]`. `s_stream_off[i]`/`s_stream_count[i]` locate stripe i's
/// streams in the flattened stream arrays.
///
/// Streams (from each stripe footer, in declaration order; `st_offset` is
/// the cumulative byte offset within the stripe, synthesized because ORC
/// streams store only lengths): `st_kind`, `st_column`, `st_offset`,
/// `st_length`.
///
/// `m_col_count[i]` is the number of ColumnStatistics in stripe statistics
/// entry i of the file metadata (empty when the file has no metadata).
///
/// Fields are implementation details; use the orc_* accessors. A value is
/// only produced by orc_parse, so the invariants always hold.
pub type Orc = {
  file_length: Int;
  ps_start: Int;
  ps_len: Int;
  compression: Int;
  block_size: Int;
  footer_length: Int;
  metadata_length: Int;
  footer_start: Int;
  metadata_start: Int;
  writer_version: Int;
  version: Vec[Int];
  footer_available: Int;
  header_length: Int;
  content_length: Int;
  row_index_stride: Int;
  row_count: Int;
  stats_count: Int;
  t_kind: Vec[Int];
  t_sub_off: Vec[Int];
  t_sub_count: Vec[Int];
  t_name_off: Vec[Int];
  t_name_count: Vec[Int];
  t_max_length: Vec[Int];
  t_precision: Vec[Int];
  t_scale: Vec[Int];
  subtypes: Vec[Int];
  field_names: Vec[Str];
  s_offset: Vec[Int];
  s_index_len: Vec[Int];
  s_data_len: Vec[Int];
  s_footer_len: Vec[Int];
  s_rows: Vec[Int];
  s_stream_off: Vec[Int];
  s_stream_count: Vec[Int];
  st_kind: Vec[Int];
  st_column: Vec[Int];
  st_offset: Vec[Int];
  st_length: Vec[Int];
  m_col_count: Vec[Int];
}

// Internal protobuf cursor: a mutable window [pos, end) into the file
// buffer. Submessage parsing gives each nested message its own window.
type _Pb = {
  pos: Int;
  end: Int;
}

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// The " at offset N" suffix shared by every protobuf error message.
fn _at(pos: Int) -> Str {
  return " at offset " + convert.int_to_string(pos);
}

// `prefix` followed by the shared offset suffix.
fn _moff(prefix: Str, pos: Int) -> Str {
  return prefix + _at(pos);
}

// Byte `pos` of `buf` widened to 0..255. Callers bound-check first.
fn _byte(buf: &Vec[UInt8], pos: Int) -> Int {
  let raw: UInt8 = buf[pos];
  return (raw as Int) & 0xFF;
}

// True when `v` is exactly the three magic bytes "ORC".
fn _magic_is_orc(v: &Vec[UInt8]) -> Bool {
  if v.len() != 3 {
    return false;
  }
  let b0: UInt8 = v[0];
  let b1: UInt8 = v[1];
  let b2: UInt8 = v[2];
  if ((b0 as Int) & 0xFF) != 79 {
    return false;
  }
  if ((b1 as Int) & 0xFF) != 82 {
    return false;
  }
  if ((b2 as Int) & 0xFF) != 67 {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Protobuf wire-format core
// --------------------------------------------------

// Read one base-128 varint (at most 10 bytes). Non-minimal encodings are
// accepted; an 11th byte is rejected ("orc: varint too long") and a value
// above 2^63-1 is rejected ("orc: varint overflow"), both at the varint
// start. A window ending inside the varint is "orc: truncated varint".
fn _pb_varint(buf: &Vec[UInt8], c: &mut _Pb) -> Result[Int, Str] {
  let start = c.pos;
  var v: Int = 0;
  var place: Int = 1;
  var i = 0;
  var done = false;
  while !done {
    if c.pos >= c.end {
      return _err_int(_moff("orc: truncated varint", start));
    }
    let b = _byte(buf, c.pos);
    c.pos = c.pos + 1;
    let payload = b % 128;
    if i < 9 {
      // Byte i contributes payload * 128^i; for i <= 8 the running sum
      // cannot exceed 2^63 - 1, so no overflow check is needed here.
      v = v + payload * place;
      if i < 8 {
        place = place * 128;
      }
    } else {
      // 10th byte: a continuation bit means an 11th byte would follow; any
      // set payload bit is above bit 62, i.e. the value does not fit Int.
      if b >= 128 {
        return _err_int(_moff("orc: varint too long", start));
      }
      if payload > 0 {
        return _err_int(_moff("orc: varint overflow", start));
      }
    }
    i = i + 1;
    if b < 128 {
      done = true;
    } else {
      if i >= 10 {
        return _err_int(_moff("orc: varint too long", start));
      }
    }
  }
  return _ok_int(v);
}

// Read one tag and validate it: field numbers must be 1..2^29-1 and the
// wire type must be 0, 1, 2 or 5 (groups 3/4 and the reserved 6/7 are
// rejected). Returns the raw tag; callers split it as tag / 8 and tag % 8.
fn _pb_tag(buf: &Vec[UInt8], c: &mut _Pb) -> Result[Int, Str] {
  let start = c.pos;
  let r = _pb_varint(buf, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let tag: Int = r.value;
  let field = tag / 8;
  let wire = tag % 8;
  if field == 0 {
    return _err_int(_moff("orc: invalid field number", start));
  }
  if field > 536870911 {
    return _err_int(_moff("orc: invalid field number", start));
  }
  if wire == 3 || wire == 4 || wire > 5 {
    return _err_int("orc: invalid wire type " + convert.int_to_string(wire) + _at(start));
  }
  return _ok_int(tag);
}

// Read the length prefix of a length-delimited field. On success the
// returned value is the payload length and c.pos is at the payload start.
// The prefix position is reported on failure.
fn _pb_delim_len(buf: &Vec[UInt8], c: &mut _Pb) -> Result[Int, Str] {
  let lp = c.pos;
  let r = _pb_varint(buf, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let n: Int = r.value;
  if n > c.end - c.pos {
    return _err_int(_moff("orc: field length out of bounds", lp));
  }
  return _ok_int(n);
}

// Skip one field of the given wire type.
fn _pb_skip(buf: &Vec[UInt8], c: &mut _Pb, wire: Int) -> Result[Int, Str] {
  let start = c.pos;
  if wire == 0 {
    let r = _pb_varint(buf, c);
    if !r.is_ok {
      return _err_int(r.error);
    }
    return _ok_int(0);
  }
  if wire == 1 {
    if c.end - c.pos < 8 {
      return _err_int(_moff("orc: truncated field", start));
    }
    c.pos = c.pos + 8;
    return _ok_int(0);
  }
  if wire == 2 {
    let lr = _pb_delim_len(buf, c);
    if !lr.is_ok {
      return _err_int(lr.error);
    }
    let n: Int = lr.value;
    c.pos = c.pos + n;
    return _ok_int(0);
  }
  if wire == 5 {
    if c.end - c.pos < 4 {
      return _err_int(_moff("orc: truncated field", start));
    }
    c.pos = c.pos + 4;
    return _ok_int(0);
  }
  return _err_int("orc: invalid wire type " + convert.int_to_string(wire) + _at(start));
}

// Read a uint sequence: one varint for wire type 0, or a packed run of
// varints for wire type 2. Any other wire type yields an empty sequence
// (the caller skips it). Returns the parsed values.
fn _pb_uint_seq(buf: &Vec[UInt8], c: &mut _Pb, wire: Int) -> Result[Vec[Int], Str] {
  var out = Vec[Int].new();
  if wire == 0 {
    let r = _pb_varint(buf, c);
    if !r.is_ok {
      return _err_vec_int(r.error);
    }
    out.push(r.value);
    return _ok_vec_int(out);
  }
  if wire == 2 {
    let lr = _pb_delim_len(buf, c);
    if !lr.is_ok {
      return _err_vec_int(lr.error);
    }
    let n: Int = lr.value;
    let end = c.pos + n;
    while c.pos < end {
      let r = _pb_varint(buf, c);
      if !r.is_ok {
        return _err_vec_int(r.error);
      }
      out.push(r.value);
    }
    return _ok_vec_int(out);
  }
  return _ok_vec_int(out);
}

// Read a length-delimited payload as raw bytes.
fn _pb_bytes(buf: &Vec[UInt8], c: &mut _Pb) -> Result[Vec[UInt8], Str] {
  let lr = _pb_delim_len(buf, c);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  var out = Vec[UInt8].new();
  var k = 0;
  while k < n {
    out.push((_byte(buf, c.pos + k) as UInt8));
    k = k + 1;
  }
  c.pos = c.pos + n;
  return _ok_bytes(out);
}

// Read a length-delimited string whose bytes must all be printable ASCII
// (0x20..0x7E). The offset of the first offending byte is reported; this
// also guarantees the 0x00-free contract of sb_to_str.
fn _pb_printable_str(buf: &Vec[UInt8], c: &mut _Pb) -> Result[Str, Str] {
  let lr = _pb_delim_len(buf, c);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let n: Int = lr.value;
  let start = c.pos;
  var out = Vec[UInt8].new();
  var k = 0;
  while k < n {
    let b = _byte(buf, start + k);
    if b < 32 || b > 126 {
      return _err_str(_moff("orc: field name is not printable", start + k));
    }
    out.push((b as UInt8));
    k = k + 1;
  }
  c.pos = c.pos + n;
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Footer / stripe / type parsing
// --------------------------------------------------

// Parse one Footer.StripeInformation submessage ([start, end)); pushes the
// five parallel stripe fields.
fn _parse_stripe(o: &mut Orc, buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  var offset = 0;
  var index_len = 0;
  var data_len = 0;
  var footer_len = 0;
  var rows = 0;
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      offset = r.value;
    } else if field == 2 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      index_len = r.value;
    } else if field == 3 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      data_len = r.value;
    } else if field == 4 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      footer_len = r.value;
    } else if field == 5 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      rows = r.value;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  o.s_offset.push(offset);
  o.s_index_len.push(index_len);
  o.s_data_len.push(data_len);
  o.s_footer_len.push(footer_len);
  o.s_rows.push(rows);
  return _ok_int(0);
}

// Parse one Footer.Type submessage ([start, end)); pushes the eight
// parallel type fields and appends subtype/name payloads.
fn _parse_type(o: &mut Orc, buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  var kind = 0;
  var max_length = 0;
  var precision = 0;
  var scale = 0;
  let sub_off = o.subtypes.len();
  var sub_count = 0;
  let name_off = o.field_names.len();
  var name_count = 0;
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      kind = r.value;
    } else if field == 2 {
      let pr = _pb_uint_seq(buf, &mut c, wire);
      if !pr.is_ok {
        return _err_int(pr.error);
      }
      let vals: Vec[Int] = pr.value;
      var k = 0;
      while k < vals.len() {
        let sv: Int = vals[k];
        o.subtypes.push(sv);
        k = k + 1;
      }
      sub_count = sub_count + vals.len();
    } else if field == 3 && wire == 2 {
      let sr = _pb_printable_str(buf, &mut c);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      let name: Str = sr.value;
      o.field_names.push(name);
      name_count = name_count + 1;
    } else if field == 4 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      max_length = r.value;
    } else if field == 5 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      precision = r.value;
    } else if field == 6 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      scale = r.value;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  o.t_kind.push(kind);
  o.t_sub_off.push(sub_off);
  o.t_sub_count.push(sub_count);
  o.t_name_off.push(name_off);
  o.t_name_count.push(name_count);
  o.t_max_length.push(max_length);
  o.t_precision.push(precision);
  o.t_scale.push(scale);
  return _ok_int(0);
}

// Parse the Footer message ([start, end)).
fn _parse_footer(o: &mut Orc, buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.header_length = r.value;
    } else if field == 2 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.content_length = r.value;
    } else if field == 3 && wire == 2 {
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      let sr = _parse_stripe(o, buf, c.pos, c.pos + n);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      c.pos = c.pos + n;
    } else if field == 4 && wire == 2 {
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      let tr2 = _parse_type(o, buf, c.pos, c.pos + n);
      if !tr2.is_ok {
        return _err_int(tr2.error);
      }
      c.pos = c.pos + n;
    } else if field == 5 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.row_count = r.value;
    } else if field == 6 && wire == 2 {
      // ColumnStatistics: counted, never decoded. Skip the payload.
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      o.stats_count = o.stats_count + 1;
      c.pos = c.pos + n;
    } else if field == 7 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.row_index_stride = r.value;
    } else if field == 8 && wire == 0 {
      // Footer.writerVersion (the postscript one is exposed).
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.writer_version = r.value;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(0);
}

// Validate the type tree after the footer is parsed: every subtype must be
// a valid column id and every STRUCT must name each of its subtypes.
fn _validate_types(o: &Orc) -> Result[Int, Str] {
  var i = 0;
  while i < o.t_kind.len() {
    let offv: Vec[Int] = o.t_sub_off;
    let cntv: Vec[Int] = o.t_sub_count;
    let namev: Vec[Int] = o.t_name_count;
    let kindv: Vec[Int] = o.t_kind;
    let off: Int = offv[i];
    let cnt: Int = cntv[i];
    let names: Int = namev[i];
    let kind: Int = kindv[i];
    var j = 0;
    while j < cnt {
      let subv: Vec[Int] = o.subtypes;
      let sv: Int = subv[off + j];
      if sv >= o.t_kind.len() {
        return _err_int("orc: subtype column out of range (column=" + convert.int_to_string(i) + ")");
      }
      j = j + 1;
    }
    if kind == 12 {
      if names != cnt {
        return _err_int("orc: struct field name count mismatch (column=" + convert.int_to_string(i) + ")");
      }
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// Parse one StripeFooter.Stream submessage ([start, end)) and push its
// kind/column/offset/length; `cum` is the stream's byte offset within the
// stripe (synthesized from the running total of stream lengths). Returns
// the stream length so the caller can advance `cum`.
fn _parse_stream(o: &mut Orc, buf: &Vec[UInt8], stripe: Int, index: Int, start: Int, end: Int, cum: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  var kind = 0;
  var column = 0;
  var length = 0;
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      kind = r.value;
    } else if field == 2 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      column = r.value;
    } else if field == 3 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      length = r.value;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  if column >= o.t_kind.len() {
    return _err_int("orc: stream column out of range (stripe=" + convert.int_to_string(stripe) + ", stream=" + convert.int_to_string(index) + ")");
  }
  o.st_kind.push(kind);
  o.st_column.push(column);
  o.st_offset.push(cum);
  o.st_length.push(length);
  return _ok_int(length);
}

// Parse one StripeFooter message ([start, end)); `stripe` is the stripe
// index for diagnostics. Returns the number of streams parsed.
fn _parse_stripe_footer(o: &mut Orc, buf: &Vec[UInt8], stripe: Int, start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  var count = 0;
  var cum = 0;
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 2 {
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      let sr = _parse_stream(o, buf, stripe, count, c.pos, c.pos + n, cum);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      let len: Int = sr.value;
      cum = cum + len;
      count = count + 1;
      c.pos = c.pos + n;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(count);
}

// Parse every stripe footer referenced by the stripe table. Fails with
// "orc: stripe extends past end of buffer (stripe=N)" when a stripe's
// declared extent does not fit in the file, and pushes one
// s_stream_off/s_stream_count pair per stripe, in stripe order.
fn _parse_stripe_footers(o: &mut Orc, buf: &Vec[UInt8], total: Int) -> Result[Int, Str] {
  var s = 0;
  while s < o.s_offset.len() {
    let offv: Vec[Int] = o.s_offset;
    let ilv: Vec[Int] = o.s_index_len;
    let dlv: Vec[Int] = o.s_data_len;
    let flv: Vec[Int] = o.s_footer_len;
    let fo: Int = offv[s];
    let il: Int = ilv[s];
    let dl: Int = dlv[s];
    let fl: Int = flv[s];
    if fo > total {
      return _err_int("orc: stripe extends past end of buffer (stripe=" + convert.int_to_string(s) + ")");
    }
    if il > total - fo {
      return _err_int("orc: stripe extends past end of buffer (stripe=" + convert.int_to_string(s) + ")");
    }
    if dl > total - fo - il {
      return _err_int("orc: stripe extends past end of buffer (stripe=" + convert.int_to_string(s) + ")");
    }
    if fl > total - fo - il - dl {
      return _err_int("orc: stripe extends past end of buffer (stripe=" + convert.int_to_string(s) + ")");
    }
    let start = fo + il + dl;
    let stream_off = o.st_kind.len();
    var count = 0;
    if fl > 0 {
      let sr = _parse_stripe_footer(o, buf, s, start, start + fl);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      count = sr.value;
    }
    o.s_stream_off.push(stream_off);
    o.s_stream_count.push(count);
    s = s + 1;
  }
  return _ok_int(0);
}

// Count the ColumnStatistics entries (field 1, length-delimited) of one
// Metadata.StripeStatistics submessage window.
fn _count_stripe_stats(buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  var count = 0;
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 2 {
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      c.pos = c.pos + n;
      count = count + 1;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(count);
}

// Parse the Metadata message ([start, end)); pushes one column-statistics
// count per StripeStatistics entry, in stripe order.
fn _parse_metadata(o: &mut Orc, buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 2 {
      let lr = _pb_delim_len(buf, &mut c);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let n: Int = lr.value;
      let cr = _count_stripe_stats(buf, c.pos, c.pos + n);
      if !cr.is_ok {
        return _err_int(cr.error);
      }
      let count: Int = cr.value;
      o.m_col_count.push(count);
      c.pos = c.pos + n;
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(0);
}

// Parse the PostScript message ([start, end)). Magic (field 8000), when
// present, must be exactly "ORC".
fn _parse_postscript(o: &mut Orc, buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var c = _Pb{ pos: start; end: end; };
  while c.pos < c.end {
    let tr = _pb_tag(buf, &mut c);
    if !tr.is_ok {
      return _err_int(tr.error);
    }
    let tag: Int = tr.value;
    let field = tag / 8;
    let wire = tag % 8;
    if field == 1 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.footer_length = r.value;
    } else if field == 2 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.compression = r.value;
    } else if field == 3 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.block_size = r.value;
    } else if field == 4 {
      if wire == 0 || wire == 2 {
        let pr = _pb_uint_seq(buf, &mut c, wire);
        if !pr.is_ok {
          return _err_int(pr.error);
        }
        let vals: Vec[Int] = pr.value;
        var k = 0;
        while k < vals.len() {
          let pv: Int = vals[k];
          o.version.push(pv);
          k = k + 1;
        }
      } else {
        let sk = _pb_skip(buf, &mut c, wire);
        if !sk.is_ok {
          return _err_int(sk.error);
        }
      }
    } else if field == 5 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.metadata_length = r.value;
    } else if field == 6 && wire == 0 {
      let r = _pb_varint(buf, &mut c);
      if !r.is_ok {
        return _err_int(r.error);
      }
      o.writer_version = r.value;
    } else if field == 8000 && wire == 2 {
      let mr = _pb_bytes(buf, &mut c);
      if !mr.is_ok {
        return _err_int(mr.error);
      }
      let mb: Vec[UInt8] = mr.value;
      if !_magic_is_orc(&mb) {
        return _err_int("orc: bad postscript magic");
      }
    } else {
      let sk = _pb_skip(buf, &mut c, wire);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse the metadata of an ORC file buffer.
///
/// The buffer must hold the whole file (or at least the region from the
/// magic up to the postscript, with every referenced stripe footer
/// present for uncompressed files).
///
/// Errors (deterministic, `orc: ` prefixed; protobuf failures carry the
/// detected byte offset):
///   * "orc: file too small" / "orc: bad magic";
///   * "orc: empty postscript" / "orc: postscript length out of bounds (len=N)";
///   * "orc: truncated varint at offset N" / "orc: varint too long at
///     offset N" / "orc: varint overflow at offset N";
///   * "orc: invalid field number at offset N" / "orc: invalid wire type
///     W at offset N" / "orc: truncated field at offset N" / "orc: field
///     length out of bounds at offset N";
///   * "orc: bad postscript magic" / "orc: unsupported compression kind
///     (kind=N)";
///   * "orc: footer length out of bounds (len=N)" / "orc: metadata length
///     out of bounds (len=N)";
///   * "orc: field name is not printable at offset N";
///   * "orc: struct field name count mismatch (column=N)" / "orc: subtype
///     column out of range (column=N)";
///   * "orc: stripe extends past end of buffer (stripe=N)" / "orc: stream
///     column out of range (stripe=N, stream=N)".
pub fn orc_parse(buffer: &Vec[UInt8]) -> Result[Orc, Str]
  ensures: buffer.len() < 4 => result is Err;
{
  let total = buffer.len();
  if total < 4 {
    return _err_orc("orc: file too small");
  }
  if _byte(buffer, 0) != 79 {
    return _err_orc("orc: bad magic");
  }
  if _byte(buffer, 1) != 82 {
    return _err_orc("orc: bad magic");
  }
  if _byte(buffer, 2) != 67 {
    return _err_orc("orc: bad magic");
  }
  let ps_b = _byte(buffer, total - 1);
  if ps_b == 0 {
    return _err_orc("orc: empty postscript");
  }
  let ps_start = total - 1 - ps_b;
  if ps_start < 3 {
    return _err_orc("orc: postscript length out of bounds (len=" + convert.int_to_string(ps_b) + ")");
  }
  var o = Orc{
    file_length: total;
    ps_start: ps_start;
    ps_len: ps_b;
    compression: 0;
    block_size: 0;
    footer_length: 0;
    metadata_length: 0;
    footer_start: 0;
    metadata_start: 0;
    writer_version: 0;
    version: Vec[Int].new();
    footer_available: 0;
    header_length: 0;
    content_length: 0;
    row_index_stride: 0;
    row_count: 0;
    stats_count: 0;
    t_kind: Vec[Int].new();
    t_sub_off: Vec[Int].new();
    t_sub_count: Vec[Int].new();
    t_name_off: Vec[Int].new();
    t_name_count: Vec[Int].new();
    t_max_length: Vec[Int].new();
    t_precision: Vec[Int].new();
    t_scale: Vec[Int].new();
    subtypes: Vec[Int].new();
    field_names: Vec[Str].new();
    s_offset: Vec[Int].new();
    s_index_len: Vec[Int].new();
    s_data_len: Vec[Int].new();
    s_footer_len: Vec[Int].new();
    s_rows: Vec[Int].new();
    s_stream_off: Vec[Int].new();
    s_stream_count: Vec[Int].new();
    st_kind: Vec[Int].new();
    st_column: Vec[Int].new();
    st_offset: Vec[Int].new();
    st_length: Vec[Int].new();
    m_col_count: Vec[Int].new();
  };
  let pr = _parse_postscript(&mut o, buffer, ps_start, total - 1);
  if !pr.is_ok {
    return _err_orc(pr.error);
  }
  if o.compression > 4 {
    return _err_orc("orc: unsupported compression kind (kind=" + convert.int_to_string(o.compression) + ")");
  }
  if o.footer_length > ps_start - 3 {
    return _err_orc("orc: footer length out of bounds (len=" + convert.int_to_string(o.footer_length) + ")");
  }
  let after_footer = ps_start - o.footer_length;
  if o.metadata_length > after_footer - 3 {
    return _err_orc("orc: metadata length out of bounds (len=" + convert.int_to_string(o.metadata_length) + ")");
  }
  o.footer_start = ps_start - o.footer_length - o.metadata_length;
  o.metadata_start = o.footer_start + o.footer_length;
  if o.compression != 0 {
    // The footer, metadata and stripe footers are compressed; nothing
    // more can be decoded without a decompressor.
    return _ok_orc(o);
  }
  o.footer_available = 1;
  if o.footer_length > 0 {
    let fr = _parse_footer(&mut o, buffer, o.footer_start, o.metadata_start);
    if !fr.is_ok {
      return _err_orc(fr.error);
    }
    let vr = _validate_types(&o);
    if !vr.is_ok {
      return _err_orc(vr.error);
    }
  }
  let sr = _parse_stripe_footers(&mut o, buffer, total);
  if !sr.is_ok {
    return _err_orc(sr.error);
  }
  if o.metadata_length > 0 {
    let mr = _parse_metadata(&mut o, buffer, o.metadata_start, ps_start);
    if !mr.is_ok {
      return _err_orc(mr.error);
    }
  }
  return _ok_orc(o);
}

// --------------------------------------------------
//  Postscript accessors
// --------------------------------------------------

/// Total length in bytes of the parsed buffer.
pub fn orc_file_length(o: &Orc) -> Int
  ensures: result == o.file_length;
{
  return o.file_length;
}

/// Absolute offset of the postscript (its first byte).
pub fn orc_postscript_offset(o: &Orc) -> Int {
  return o.ps_start;
}

/// Length of the postscript in bytes (the trailing length byte).
pub fn orc_postscript_length(o: &Orc) -> Int {
  return o.ps_len;
}

/// Absolute offset of the file footer (derived from the postscript).
pub fn orc_footer_offset(o: &Orc) -> Int
  ensures: result == o.footer_start;
{
  return o.footer_start;
}

/// Compression kind code: 0 NONE, 1 ZLIB, 2 SNAPPY, 3 LZ4, 4 ZSTD.
pub fn orc_compression(o: &Orc) -> Int {
  return o.compression;
}

/// Documented name of a compression kind code ("unknown" beyond ZSTD).
pub fn orc_compression_name(c: Int) -> Str {
  if c == 0 {
    return "NONE";
  }
  if c == 1 {
    return "ZLIB";
  }
  if c == 2 {
    return "SNAPPY";
  }
  if c == 3 {
    return "LZ4";
  }
  if c == 4 {
    return "ZSTD";
  }
  return "unknown";
}

/// Compression block size declared by the postscript (0 when absent).
pub fn orc_block_size(o: &Orc) -> Int {
  return o.block_size;
}

/// Number of version parts stored in the postscript (usually 2 or 3).
pub fn orc_version_count(o: &Orc) -> Int {
  return o.version.len();
}

/// Version part `i` of the postscript version list.
/// Err("orc: version part index out of range") when out of bounds.
pub fn orc_version_part(o: &Orc, i: Int) -> Result[Int, Str]
  ensures: i < 0 || i >= o.version.len() => result is Err;
  ensures: result is Ok => i >= 0 && i < o.version.len();
{
  if i < 0 || i >= o.version.len() {
    return _err_int("orc: version part index out of range");
  }
  let v: Vec[Int] = o.version;
  let part: Int = v[i];
  return _ok_int(part);
}

/// First version part (the major version; 0 when the list is empty).
pub fn orc_version_major(o: &Orc) -> Int
  ensures: o.version.len() == 0 => result == 0;
{
  if o.version.len() == 0 {
    return 0;
  }
  let v: Vec[Int] = o.version;
  let part: Int = v[0];
  return part;
}

/// Second version part (the minor version; 0 when absent).
pub fn orc_version_minor(o: &Orc) -> Int {
  if o.version.len() < 2 {
    return 0;
  }
  let v: Vec[Int] = o.version;
  let part: Int = v[1];
  return part;
}

/// Writer version of the postscript (0 ORIGINAL .. 9 ORC_14).
pub fn orc_writer_version(o: &Orc) -> Int {
  return o.writer_version;
}

/// Documented name of a writer version code ("unknown" beyond ORC_14).
pub fn orc_writer_version_name(v: Int) -> Str {
  if v == 0 {
    return "ORIGINAL";
  }
  if v == 1 {
    return "HIVE_8732";
  }
  if v == 2 {
    return "HIVE_4243";
  }
  if v == 3 {
    return "HIVE_12055";
  }
  if v == 4 {
    return "HIVE_13083";
  }
  if v == 5 {
    return "ORC_101";
  }
  if v == 6 {
    return "ORC_135";
  }
  if v == 7 {
    return "ORC_517";
  }
  if v == 8 {
    return "ORC_203";
  }
  if v == 9 {
    return "ORC_14";
  }
  return "unknown";
}

/// Declared length of the file footer region (compressed length when the
/// file is compressed).
pub fn orc_footer_length(o: &Orc) -> Int {
  return o.footer_length;
}

/// Declared length of the file metadata region (0 when absent).
pub fn orc_metadata_length(o: &Orc) -> Int {
  return o.metadata_length;
}

/// True when the footer (and stripe footers/metadata) were decoded, which
/// happens exactly when the file is uncompressed.
pub fn orc_footer_available(o: &Orc) -> Bool
  ensures: result == (o.footer_available == 1);
{
  if o.footer_available == 1 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Footer accessors
// --------------------------------------------------

// Shared gate for footer-derived accessors.
fn _footer_ready(o: &Orc) -> Result[Int, Str] {
  if o.footer_available == 0 {
    return _err_int("orc: footer not available (compressed file)");
  }
  return _ok_int(0);
}

/// Footer.headerLength (3 for ORC files).
pub fn orc_header_length(o: &Orc) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.header_length);
}

/// Footer.contentLength: the number of bytes up to the end of the last
/// stripe.
pub fn orc_content_length(o: &Orc) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.content_length);
}

/// Footer.rowIndexStride (0 when absent).
pub fn orc_row_index_stride(o: &Orc) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.row_index_stride);
}

/// Footer.numberOfRows: the total row count of the file.
pub fn orc_rows(o: &Orc) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: o.footer_available != 0 => result is Ok;
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.row_count);
}

/// Footer.writerVersion, when the footer carried one (the postscript
/// writer version is exposed by orc_writer_version).
pub fn orc_footer_writer_version(o: &Orc) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.writer_version);
}

/// Number of StripeInformation entries (the stripe count).
pub fn orc_stripe_count(o: &Orc) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: o.footer_available != 0 => result is Ok;
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.s_offset.len());
}

// Shared bounds check for stripe indices.
fn _stripe_ready(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  if i < 0 || i >= o.s_offset.len() {
    return _err_int("orc: stripe index out of range");
  }
  return _ok_int(0);
}

/// Absolute file offset of stripe `i`.
pub fn orc_stripe_offset(o: &Orc, i: Int) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: i < 0 || i >= o.s_offset.len() => result is Err;
  ensures: result is Ok => o.footer_available != 0 && i >= 0 && i < o.s_offset.len();
{
  let r = _stripe_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_offset;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Number of index bytes of stripe `i`.
pub fn orc_stripe_index_length(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_index_len;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Number of data bytes of stripe `i`.
pub fn orc_stripe_data_length(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_data_len;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Number of stripe-footer bytes of stripe `i`.
pub fn orc_stripe_footer_length(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_footer_len;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Number of rows in stripe `i`.
pub fn orc_stripe_rows(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_rows;
  let x: Int = v[i];
  return _ok_int(x);
}

// --------------------------------------------------
//  Type tree accessors
// --------------------------------------------------

/// Number of columns (Footer.Type entries).
pub fn orc_columns(o: &Orc) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: o.footer_available != 0 => result is Ok;
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.t_kind.len());
}

// Shared bounds check for column indices.
fn _column_ready(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  if i < 0 || i >= o.t_kind.len() {
    return _err_int("orc: column index out of range");
  }
  return _ok_int(0);
}

/// Type.Kind code of column `i` (0..18, see orc_column_kind_name).
pub fn orc_column_kind(o: &Orc, i: Int) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: i < 0 || i >= o.t_kind.len() => result is Err;
  ensures: result is Ok => o.footer_available != 0 && i >= 0 && i < o.t_kind.len();
{
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_kind;
  let k: Int = v[i];
  return _ok_int(k);
}

/// Documented name of a Type.Kind code ("unknown" beyond 18).
pub fn orc_column_kind_name(k: Int) -> Str {
  if k == 0 {
    return "BOOLEAN";
  }
  if k == 1 {
    return "BYTE";
  }
  if k == 2 {
    return "SHORT";
  }
  if k == 3 {
    return "INT";
  }
  if k == 4 {
    return "LONG";
  }
  if k == 5 {
    return "FLOAT";
  }
  if k == 6 {
    return "DOUBLE";
  }
  if k == 7 {
    return "STRING";
  }
  if k == 8 {
    return "BINARY";
  }
  if k == 9 {
    return "TIMESTAMP";
  }
  if k == 10 {
    return "LIST";
  }
  if k == 11 {
    return "MAP";
  }
  if k == 12 {
    return "STRUCT";
  }
  if k == 13 {
    return "UNION";
  }
  if k == 14 {
    return "DECIMAL";
  }
  if k == 15 {
    return "DATE";
  }
  if k == 16 {
    return "VARCHAR";
  }
  if k == 17 {
    return "CHAR";
  }
  if k == 18 {
    return "TIMESTAMP_INSTANT";
  }
  return "unknown";
}

/// Number of field names declared by column `i` (struct/union field
/// names; 0 for scalar and container columns).
pub fn orc_column_field_count(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_name_count;
  let n: Int = v[i];
  return _ok_int(n);
}

/// Field name `f` of column `i`.
/// Err("orc: field name index out of range") when `f` is out of bounds.
pub fn orc_column_field_name(o: &Orc, i: Int, f: Int) -> Result[Str, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let cntv: Vec[Int] = o.t_name_count;
  let offv: Vec[Int] = o.t_name_off;
  let count: Int = cntv[i];
  if f < 0 || f >= count {
    return _err_str("orc: field name index out of range");
  }
  let off: Int = offv[i];
  let names: Vec[Str] = o.field_names;
  let s: Str = names[off + f];
  return _ok_str(s);
}

/// Number of subtypes declared by column `i` (list 1, map 2, struct/union
/// one per field, 0 for scalars).
pub fn orc_column_subtype_count(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_sub_count;
  let n: Int = v[i];
  return _ok_int(n);
}

/// Subtype `s` of column `i` (a column id).
/// Err("orc: subtype index out of range") when `s` is out of bounds.
pub fn orc_column_subtype(o: &Orc, i: Int, s: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = o.t_sub_count;
  let offv: Vec[Int] = o.t_sub_off;
  let count: Int = cntv[i];
  if s < 0 || s >= count {
    return _err_int("orc: subtype index out of range");
  }
  let off: Int = offv[i];
  let subs: Vec[Int] = o.subtypes;
  let x: Int = subs[off + s];
  return _ok_int(x);
}

/// Type.maximumLength of column `i` (VARCHAR/CHAR; 0 when absent).
pub fn orc_column_max_length(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_max_length;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Type.precision of column `i` (DECIMAL; 0 when absent).
pub fn orc_column_precision(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_precision;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Type.scale of column `i` (DECIMAL; 0 when absent).
pub fn orc_column_scale(o: &Orc, i: Int) -> Result[Int, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.t_scale;
  let x: Int = v[i];
  return _ok_int(x);
}

// --------------------------------------------------
//  Statistics accessors
// --------------------------------------------------

/// Number of footer ColumnStatistics entries (statistics are recorded in
/// column order; entry i belongs to column i when present).
pub fn orc_stats_count(o: &Orc) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: o.footer_available != 0 => result is Ok;
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.stats_count);
}

/// True when column `i` has a leading footer statistics entry (i.e. i is
/// below orc_stats_count).
pub fn orc_column_has_stats(o: &Orc, i: Int) -> Result[Bool, Str] {
  let r = _column_ready(o, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  if i < o.stats_count {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Number of StripeStatistics entries in the file metadata (0 when the
/// file has no metadata).
pub fn orc_stripe_stats_count(o: &Orc) -> Result[Int, Str] {
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.m_col_count.len());
}

/// Number of ColumnStatistics entries in stripe statistics entry `i`.
/// Err("orc: stripe stats index out of range") when out of bounds.
pub fn orc_stripe_stats_cols(o: &Orc, i: Int) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: i < 0 || i >= o.m_col_count.len() => result is Err;
  ensures: result is Ok => o.footer_available != 0 && i >= 0 && i < o.m_col_count.len();
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  if i < 0 || i >= o.m_col_count.len() {
    return _err_int("orc: stripe stats index out of range");
  }
  let v: Vec[Int] = o.m_col_count;
  let n: Int = v[i];
  return _ok_int(n);
}

// --------------------------------------------------
//  Stream accessors
// --------------------------------------------------

/// Total number of streams across every stripe footer.
pub fn orc_stream_count(o: &Orc) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: o.footer_available != 0 => result is Ok;
{
  let r = _footer_ready(o);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _ok_int(o.st_kind.len());
}

/// Number of streams in stripe `s`.
pub fn orc_stripe_stream_count(o: &Orc, s: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, s);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = o.s_stream_count;
  let n: Int = v[s];
  return _ok_int(n);
}

// Shared bounds check for stream indices.
fn _stream_ready(o: &Orc, s: Int, e: Int) -> Result[Int, Str] {
  let r = _stripe_ready(o, s);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = o.s_stream_count;
  let count: Int = cntv[s];
  if e < 0 || e >= count {
    return _err_int("orc: stream index out of range");
  }
  return _ok_int(0);
}

// Global stream index of stream `e` in stripe `s` (preconditions checked).
fn _stream_global(o: &Orc, s: Int, e: Int) -> Int {
  let offv: Vec[Int] = o.s_stream_off;
  let off: Int = offv[s];
  return off + e;
}

/// Stream.Kind code of stream `e` in stripe `s` (0..8, see
/// orc_stream_kind_name).
pub fn orc_stream_kind(o: &Orc, s: Int, e: Int) -> Result[Int, Str]
  ensures: o.footer_available == 0 => result is Err;
  ensures: s < 0 || s >= o.s_offset.len() => result is Err;
  ensures: e < 0 || e >= o.st_kind.len() => result is Err;
  ensures: result is Ok => o.footer_available != 0 && s >= 0 && s < o.s_offset.len() && e >= 0 && e < o.st_kind.len();
{
  let r = _stream_ready(o, s, e);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx = _stream_global(o, s, e);
  let v: Vec[Int] = o.st_kind;
  let k: Int = v[idx];
  return _ok_int(k);
}

/// Stream.Kind code of stream `e` in stripe `s`.
pub fn orc_stream_column(o: &Orc, s: Int, e: Int) -> Result[Int, Str] {
  let r = _stream_ready(o, s, e);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx = _stream_global(o, s, e);
  let v: Vec[Int] = o.st_column;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// Byte offset of stream `e` in stripe `s` within the stripe's data
/// region. ORC streams store only lengths, so this is synthesized as the
/// running total of the preceding streams' lengths.
pub fn orc_stream_offset(o: &Orc, s: Int, e: Int) -> Result[Int, Str] {
  let r = _stream_ready(o, s, e);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx = _stream_global(o, s, e);
  let v: Vec[Int] = o.st_offset;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// Declared byte length of stream `e` in stripe `s`.
pub fn orc_stream_length(o: &Orc, s: Int, e: Int) -> Result[Int, Str] {
  let r = _stream_ready(o, s, e);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx = _stream_global(o, s, e);
  let v: Vec[Int] = o.st_length;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// Documented name of a Stream.Kind code ("unknown" beyond 8).
pub fn orc_stream_kind_name(k: Int) -> Str {
  if k == 0 {
    return "PRESENT";
  }
  if k == 1 {
    return "DATA";
  }
  if k == 2 {
    return "LENGTH";
  }
  if k == 3 {
    return "DICTIONARY_DATA";
  }
  if k == 4 {
    return "DICTIONARY_COUNT";
  }
  if k == 5 {
    return "SECONDARY";
  }
  if k == 6 {
    return "ROW_INDEX";
  }
  if k == 7 {
    return "BLOOM_FILTER";
  }
  if k == 8 {
    return "BLOOM_FILTER_UTF8";
  }
  return "unknown";
}
