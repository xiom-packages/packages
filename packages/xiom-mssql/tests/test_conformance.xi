// XIOM -- xiom.mssql conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture is synthetic: hex strings decoded in-test, buffers assembled
// with the library's own builders, or hand-pinned hex layouts. Str values
// are compared through xiom.string.compare.str_compare (never `==`), every
// Vec element is read into a typed local first, and error strings are
// matched exactly against the documented catalog.

module mssql_tests
use xiom.io; use xiom.test;
use xiom.mssql;
use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn eat(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn concat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  return concat2(concat2(a, b), c);
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn u8v(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((v & 255) as UInt8);
  return out;
}

fn le16(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((v & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
  return out;
}

fn be16(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((v / 256) & 255) as UInt8);
  out.push((v & 255) as UInt8);
  return out;
}

fn le32(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((v & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
  out.push(((v / 65536) & 255) as UInt8);
  out.push(((v / 16777216) & 255) as UInt8);
  return out;
}

fn be32(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((v / 16777216) & 255) as UInt8);
  out.push(((v / 65536) & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
  out.push((v & 255) as UInt8);
  return out;
}

fn le64(v: Int) -> Vec[UInt8] {
  let lo: Int = v % 4294967296;
  let hi: Int = v / 4294967296;
  return concat2(le32(lo), le32(hi));
}

fn utf16(s: Str) -> Vec[UInt8] {
  return tds_utf16le_encode(s);
}

// B_VARCHAR: u8 character count + UTF-16LE characters.
fn bvarchar(s: Str) -> Vec[UInt8] {
  return concat2(u8v(s.len()), utf16(s));
}

// One LOGINACK token with progname, major, minor and build.
fn mk_loginack(prog: Str, major: Int, minor: Int, build: Int) -> Vec[UInt8] {
  let body = concat3(u8v(1), be32(TDS_VERSION_74), bvarchar(prog));
  let tail = concat3(u8v(major), u8v(minor), be16(build));
  let all = concat2(body, tail);
  return concat3(u8v(TDS_TOKEN_LOGINACK), le16(all.len()), all);
}

// One ERROR or INFO token; `line` < 0 omits the line number.
fn mk_error(token: Int, number: Int, state: Int, severity: Int, msg: Str, server: Str, proc: Str, line: Int) -> Vec[UInt8] {
  let body0 = concat3(le32(number), u8v(state), u8v(severity));
  let body1 = concat2(le16(msg.len()), utf16(msg));
  var body = concat2(concat2(body0, body1), bvarchar(server));
  body = concat2(body, bvarchar(proc));
  if line >= 0 {
    body = concat2(body, le32(line));
  }
  return concat3(u8v(token), le16(body.len()), body);
}

// One ENVCHANGE token; an empty `new_bytes`/`old_bytes` encodes a null value.
fn mk_envchange(subtype: Int, new_bytes: Vec[UInt8], old_bytes: Vec[UInt8]) -> Vec[UInt8] {
  var body = concat2(u8v(subtype), u8v(new_bytes.len()));
  body = concat2(body, new_bytes);
  body = concat2(body, u8v(old_bytes.len()));
  body = concat2(body, old_bytes);
  return concat3(u8v(TDS_TOKEN_ENVCHANGE), le16(body.len()), body);
}

// One DONE/DONEPROC/DONEINPROC token.
fn mk_done(token: Int, status: Int, curcmd: Int, rowcount: Int) -> Vec[UInt8] {
  let body = concat2(concat2(le16(status), le16(curcmd)), le64(rowcount));
  return concat2(u8v(token), body);
}

// A fully populated LOGIN7 builder input.
fn login7_spec() -> TdsLogin7 {
  let empty = Vec[UInt8].new();
  return TdsLogin7{
    total_length: 0; tds_version: TDS_VERSION_74; packet_size: 4096; client_prog_version: 65536; client_pid: 1234; connection_id: 0;
    option_flags1: 224; option_flags2: 3; type_flags: 0; option_flags3: 0;
    client_timezone: -120; client_lcid: 1033;
    hostname: utf16("host1"); username: utf16("sa"); password: hb("a5d2a5d2");
    app_name: utf16("xiom.mssql"); server_name: utf16("srv1"); extension: hb("00ff");
    library: utf16("xiom"); language: utf16("us_english"); database: utf16("master");
    client_id: hb("010203040506"); attach_db_file: empty; change_password: empty;
    sspi: empty; sspi_length: 0; next: 0;
  };
}

// --------------------------------------------------
//  t1: packet header matrix and header errors
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var types = Vec[Int].new();
  types.push(TDS_PKT_SQL_BATCH);
  types.push(TDS_PKT_RPC);
  types.push(TDS_PKT_RESPONSE);
  types.push(TDS_PKT_LOGIN7);
  types.push(TDS_PKT_SSPI);
  types.push(TDS_PKT_PRELOGIN);
  var i = 0;
  while i < types.len() {
    let t: Int = types[i];
    let br = tds_packet_build(t, TDS_STATUS_EOM, 77, 9, 4, &hb("aabb"));
    if !br.is_ok {
      ok = false;
    } else {
      let b: Vec[UInt8] = br.value;
      if b.len() != 10 {
        ok = false;
      }
      let pr = tds_packet_parse(&b, 0);
      if !pr.is_ok {
        ok = false;
      } else {
        let p: TdsPacket = pr.value;
        if p.pkt_type != t || p.status != TDS_STATUS_EOM || p.length != 10 || p.spid != 77 || p.packet_id != 9 || p.window != 4 {
          ok = false;
        }
        if p.payload_offset != 8 || p.next != 10 {
          ok = false;
        }
      }
    }
    i = i + 1;
  }
  if !tds_status_is_eom(TDS_STATUS_EOM) {
    ok = false;
  }
  if !tds_status_is_ignore(TDS_STATUS_IGNORE) {
    ok = false;
  }
  if !tds_status_is_reset(TDS_STATUS_RESETCONNECTION) {
    ok = false;
  }
  if tds_status_is_eom(0) {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(TDS_PKT_PRELOGIN), "PRELOGIN") {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(0x55), "UNKNOWN") {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(TDS_PKT_SQL_BATCH), "SQL_BATCH") {
    ok = false;
  }
  let er = tds_packet_parse(&hb(""), 0);
  if er.is_ok {
    ok = false;
  } else {
    if !str_eq(er.error, eat("mssql: truncated packet header", 0)) {
      ok = false;
    }
  }
  let er2 = tds_packet_parse(&hb("0400000000000000"), 0);
  if er2.is_ok {
    ok = false;
  } else {
    if !str_eq(er2.error, eat("mssql: bad packet length", 0)) {
      ok = false;
    }
  }
  let er3 = tds_packet_parse(&hb("04000100100000000000"), 0);
  if er3.is_ok {
    ok = false;
  } else {
    if !str_eq(er3.error, eat("mssql: truncated packet", 0)) {
      ok = false;
    }
  }
  let er4 = tds_packet_parse(&hb("04000000000000"), -3);
  if er4.is_ok {
    ok = false;
  } else {
    if !str_eq(er4.error, "mssql: negative offset") {
      ok = false;
    }
  }
  return assert(ok, "packet header: six types, BE length, status bits, builder roundtrip, header errors");
}

// --------------------------------------------------
//  t2: multi-packet message assembly
// --------------------------------------------------

fn t2() -> TestResult {
  var ok = true;
  let payload = hb("000102030405060708090a0b0c0d0e0f10111213");
  let pr = tds_message_pack(TDS_PKT_SQL_BATCH, 5, &payload, 16);
  if !pr.is_ok {
    return assert(false, "20-byte payload must pack with packet_size 16");
  }
  let packed: Vec[UInt8] = pr.value;
  if packed.len() != 44 {
    ok = false;
  }
  let mr = tds_message_parse(&packed, 0);
  if !mr.is_ok {
    return assert(false, "packed message must parse");
  }
  let m: TdsMessage = mr.value;
  if m.pkt_type != TDS_PKT_SQL_BATCH {
    ok = false;
  }
  if m.packet_count != 3 {
    ok = false;
  }
  if m.first_packet_id != 1 {
    ok = false;
  }
  if m.spid != 5 {
    ok = false;
  }
  if m.next != 44 {
    ok = false;
  }
  let mp: Vec[UInt8] = m.payload;
  if !bytes_equal(mp, payload) {
    ok = false;
  }
  let p0 = tds_packet_parse(&packed, 0);
  let p1 = tds_packet_parse(&packed, 16);
  let p2 = tds_packet_parse(&packed, 32);
  if !p0.is_ok || !p1.is_ok || !p2.is_ok {
    ok = false;
  } else {
    let q0: TdsPacket = p0.value;
    let q1: TdsPacket = p1.value;
    let q2: TdsPacket = p2.value;
    if tds_status_is_eom(q0.status) || tds_status_is_eom(q1.status) {
      ok = false;
    }
    if !tds_status_is_eom(q2.status) {
      ok = false;
    }
    if q2.length != 12 {
      ok = false;
    }
  }
  let empty = Vec[UInt8].new();
  let ep = tds_message_pack(TDS_PKT_RESPONSE, 1, &empty, 4096);
  if !ep.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = ep.value;
    if eb.len() != 8 {
      ok = false;
    } else {
      let em = tds_message_parse(&eb, 0);
      if !em.is_ok {
        ok = false;
      } else {
        let emsg: TdsMessage = em.value;
        if emsg.packet_count != 1 {
          ok = false;
        }
        let epl: Vec[UInt8] = emsg.payload;
        if epl.len() != 0 {
          ok = false;
        }
      }
    }
  }
  let br = tds_message_pack(TDS_PKT_RESPONSE, 1, &payload, 4);
  if br.is_ok {
    ok = false;
  } else {
    if !str_eq(br.error, "mssql: bad packet size") {
      ok = false;
    }
  }
  // Drop the EOM bit on the last packet: the assembly must fail closed.
  var cut = Vec[UInt8].new();
  var ci = 0;
  while ci < packed.len() {
    cut.push(packed[ci]);
    ci = ci + 1;
  }
  cut[33] = 0 as UInt8;
  let er = tds_message_parse(&cut, 0);
  if er.is_ok {
    ok = false;
  } else {
    if !str_eq(er.error, eat("mssql: message missing eom", 44)) {
      ok = false;
    }
  }
  // Change the second packet's type: the assembly must reject the mix.
  var mixed = Vec[UInt8].new();
  var mi = 0;
  while mi < packed.len() {
    mixed.push(packed[mi]);
    mi = mi + 1;
  }
  mixed[16] = 3 as UInt8;
  let er2 = tds_message_parse(&mixed, 0);
  if er2.is_ok {
    ok = false;
  } else {
    if !str_eq(er2.error, eat("mssql: packet type mismatch", 16)) {
      ok = false;
    }
  }
  return assert(ok, "multi-packet pack/assemble: 3 packets, EOM placement, missing-EOM and type-mismatch errors");
}

// --------------------------------------------------
//  t3: PRELOGIN build/parse roundtrip
// --------------------------------------------------

fn t3() -> TestResult {
  var ok = true;
  let inst = bytes_of("MSSQL");
  let br = tds_prelogin_build_basic(16, 0, 2026, 1, TDS_ENCRYPT_ON, &inst, 12345, 1, 0);
  if !br.is_ok {
    return assert(false, "prelogin builder must succeed");
  }
  let built: Vec[UInt8] = br.value;
  if built.len() != 31 + 6 + 1 + 5 + 4 + 1 + 1 {
    ok = false;
  }
  let pr = tds_prelogin_parse(&built, 0);
  if !pr.is_ok {
    return assert(false, "prelogin buffer must parse");
  }
  let p: TdsPrelogin = pr.value;
  if tds_prelogin_entry_count(&p) != 6 {
    ok = false;
  }
  if p.next != 31 {
    ok = false;
  }
  if tds_prelogin_find(&p, TDS_PRELOGIN_TRACEID) != -1 {
    ok = false;
  }
  if tds_prelogin_find(&p, TDS_PRELOGIN_VERSION) != 0 {
    ok = false;
  }
  if tds_prelogin_find(&p, TDS_PRELOGIN_FEDAUTHREQUIRED) != 5 {
    ok = false;
  }
  let ev = tds_prelogin_value(&p, TDS_PRELOGIN_INSTOPT);
  if !ev.is_ok {
    ok = false;
  } else {
    let ib: Vec[UInt8] = ev.value;
    if !bytes_equal(ib, inst) {
      ok = false;
    }
  }
  let mr = tds_prelogin_value(&p, TDS_PRELOGIN_TRACEID);
  if mr.is_ok {
    ok = false;
  } else {
    if !str_eq(mr.error, "mssql: prelogin option not found") {
      ok = false;
    }
  }
  let er = tds_prelogin_encryption_get(&p);
  if !er.is_ok {
    ok = false;
  } else {
    let e: Int = er.value;
    if e != TDS_ENCRYPT_ON {
      ok = false;
    }
  }
  if !str_eq(tds_prelogin_encryption_name(TDS_ENCRYPT_ON), "ON") {
    ok = false;
  }
  if !str_eq(tds_prelogin_encryption_name(9), "UNKNOWN") {
    ok = false;
  }
  let vr = tds_prelogin_version_get(&p);
  if !vr.is_ok {
    ok = false;
  } else {
    let v: TdsPreloginVersion = vr.value;
    if v.major != 16 || v.minor != 0 || v.build != 2026 || v.subbuild != 1 {
      ok = false;
    }
  }
  if !str_eq(tds_prelogin_encryption_name(TDS_ENCRYPT_NOT_SUP), "NOT_SUP") {
    ok = false;
  }
  return assert(ok, "PRELOGIN: build six options, offsets roundtrip, VERSION/ENCRYPTION accessors");
}

// --------------------------------------------------
//  t4: PRELOGIN pinned layout and errors
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  let v6 = concat2(u8v(16), concat2(u8v(0), concat2(be16(2026), be16(1))));
  let table = concat3(concat2(concat2(u8v(0), be16(21)), be16(6)), concat2(concat2(u8v(1), be16(27)), be16(1)), u8v(255));
  let data = concat2(repeat_byte(0, 10), concat2(v6, u8v(1)));
  let buf = concat2(table, data);
  if buf.len() != 28 {
    ok = false;
  }
  let pr = tds_prelogin_parse(&buf, 0);
  if !pr.is_ok {
    return assert(false, "hand-pinned prelogin table must parse");
  }
  let p: TdsPrelogin = pr.value;
  if p.next != 11 {
    ok = false;
  }
  if tds_prelogin_entry_count(&p) != 2 {
    ok = false;
  }
  let t0: Int = p.tokens[0];
  let o0: Int = p.offsets[0];
  let l0: Int = p.lengths[0];
  let t1: Int = p.tokens[1];
  let o1: Int = p.offsets[1];
  let l1: Int = p.lengths[1];
  if t0 != 0 || o0 != 21 || l0 != 6 {
    ok = false;
  }
  if t1 != 1 || o1 != 27 || l1 != 1 {
    ok = false;
  }
  let er = tds_prelogin_parse(&hb("00001500"), 0);
  if er.is_ok {
    ok = false;
  } else {
    if !str_eq(er.error, eat("mssql: truncated prelogin table", 0)) {
      ok = false;
    }
  }
  let er2 = tds_prelogin_parse(&hb("000000000600"), 0);
  if er2.is_ok {
    ok = false;
  } else {
    if !str_eq(er2.error, eat("mssql: truncated prelogin table", 5)) {
      ok = false;
    }
  }
  let er3 = tds_prelogin_parse(&hb("0000ff00ff"), 0);
  if er3.is_ok {
    ok = false;
  } else {
    if !str_eq(er3.error, eat("mssql: prelogin option overruns buffer", 0)) {
      ok = false;
    }
  }
  let b1 = tds_prelogin_build_basic(16, 0, 1, 1, 9, &Vec[UInt8].new(), 1, 0, 0);
  if b1.is_ok {
    ok = false;
  } else {
    if !str_eq(b1.error, "mssql: bad encryption value") {
      ok = false;
    }
  }
  let b2 = tds_prelogin_build_basic(16, 0, 1, 1, 0, &Vec[UInt8].new(), 1, 2, 0);
  if b2.is_ok {
    ok = false;
  } else {
    if !str_eq(b2.error, "mssql: bad mars value") {
      ok = false;
    }
  }
  let b3 = tds_prelogin_build_basic(16, 0, 1, 1, 0, &Vec[UInt8].new(), -1, 0, 0);
  if b3.is_ok {
    ok = false;
  } else {
    if !str_eq(b3.error, "mssql: bad threadid") {
      ok = false;
    }
  }
  let b4 = tds_prelogin_build_basic(300, 0, 1, 1, 0, &Vec[UInt8].new(), 1, 0, 0);
  if b4.is_ok {
    ok = false;
  } else {
    if !str_eq(b4.error, "mssql: bad version") {
      ok = false;
    }
  }
  return assert(ok, "PRELOGIN: pinned table bytes, offsets, truncation and overrun errors, builder validation");
}

// --------------------------------------------------
//  t5: LOGIN7 builder roundtrip
// --------------------------------------------------

fn t5() -> TestResult {
  var ok = true;
  let spec = login7_spec();
  let br = tds_login7_build(&spec);
  if !br.is_ok {
    return assert(false, "login7 builder must succeed");
  }
  let built: Vec[UInt8] = br.value;
  let pr = tds_login7_parse(&built, 0);
  if !pr.is_ok {
    return assert(false, "built login7 must parse");
  }
  let l: TdsLogin7 = pr.value;
  if l.next != built.len() {
    ok = false;
  }
  if l.total_length != built.len() {
    ok = false;
  }
  if l.tds_version != TDS_VERSION_74 {
    ok = false;
  }
  if l.packet_size != 4096 {
    ok = false;
  }
  if l.client_pid != 1234 {
    ok = false;
  }
  if l.client_timezone != -120 {
    ok = false;
  }
  if l.client_lcid != 1033 {
    ok = false;
  }
  if l.option_flags1 != 224 || l.option_flags2 != 3 {
    ok = false;
  }
  let h: Vec[UInt8] = l.hostname;
  if !bytes_equal(h, utf16("host1")) {
    ok = false;
  }
  let u: Vec[UInt8] = l.username;
  if !bytes_equal(u, utf16("sa")) {
    ok = false;
  }
  let pw: Vec[UInt8] = l.password;
  if !bytes_equal(pw, hb("a5d2a5d2")) {
    ok = false;
  }
  let ap: Vec[UInt8] = l.app_name;
  if !bytes_equal(ap, utf16("xiom.mssql")) {
    ok = false;
  }
  let db: Vec[UInt8] = l.database;
  if !bytes_equal(db, utf16("master")) {
    ok = false;
  }
  let cid: Vec[UInt8] = l.client_id;
  if !bytes_equal(cid, hb("010203040506")) {
    ok = false;
  }
  let ext: Vec[UInt8] = l.extension;
  if !bytes_equal(ext, hb("00ff")) {
    ok = false;
  }
  let sspi: Vec[UInt8] = l.sspi;
  if sspi.len() != 0 || l.sspi_length != 0 {
    ok = false;
  }
  let tr = tds_utf16le_to_str(&built, 94, 10);
  if !tr.is_ok {
    ok = false;
  } else {
    let hstr: Str = tr.value;
    if !str_eq(hstr, "host1") {
      ok = false;
    }
  }
  if !bytes_equal(utf16("abc"), hb("610062006300")) {
    ok = false;
  }
  return assert(ok, "LOGIN7: builder roundtrip, fixed fields, raw obfuscated password, client id, extension");
}

// --------------------------------------------------
//  t6: LOGIN7 SSPI long path and parser errors
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  var spec = login7_spec();
  let big: Vec[UInt8] = repeat_byte(90, 70000);
  spec.sspi = big;
  let br = tds_login7_build(&spec);
  if !br.is_ok {
    return assert(false, "login7 with 70000 SSPI bytes must build");
  }
  let built: Vec[UInt8] = br.value;
  if built.len() < 94 + 70000 {
    io.println("t6a: built.len");
    ok = false;
  }
  let pr = tds_login7_parse(&built, 0);
  if !pr.is_ok {
    return assert(false, "login7 with long SSPI must parse");
  }
  let l: TdsLogin7 = pr.value;
  if l.sspi_length != 70000 {
    io.println("t6b: sspi_length");
    ok = false;
  }
  let sp: Vec[UInt8] = l.sspi;
  if sp.len() != 70000 {
    io.println("t6c: sp.len");
    ok = false;
  }
  if !bytes_equal(sp, big) {
    io.println("t6d: bytes_equal");
    ok = false;
  }
  let cb_hi: Int = (built[80] as Int) & 0xFF;
  let cb_lo: Int = (built[81] as Int) & 0xFF;
  if cb_hi * 256 + cb_lo != 65535 {
    io.println("t6e: cbSSPI");
    ok = false;
  }
  let long_v: Int = ((built[90] as Int) & 0xFF) + (((built[91] as Int) & 0xFF) * 256) + (((built[92] as Int) & 0xFF) * 65536) + (((built[93] as Int) & 0xFF) * 16777216);
  if long_v != 70000 {
    io.println("t6f: long_v=" + int_to_string(long_v));
    ok = false;
  }
  let er = tds_login7_parse(&hb(""), 0);
  if er.is_ok {
    ok = false;
  } else {
    if !str_eq(er.error, eat("mssql: truncated login7 header", 0)) {
      io.println("t6g: truncated error");
      ok = false;
    }
  }
  let er2 = tds_login7_parse(&repeat_byte(0, 94), 0);
  if er2.is_ok {
    ok = false;
  } else {
    if !str_eq(er2.error, eat("mssql: bad login7 length", 0)) {
      io.println("t6h: bad length error");
      ok = false;
    }
  }
  var patched = Vec[UInt8].new();
  let spec2 = login7_spec();
  let br2 = tds_login7_build(&spec2);
  if !br2.is_ok {
    return assert(false, "plain login7 must build");
  }
  let plain: Vec[UInt8] = br2.value;
  var pi = 0;
  while pi < plain.len() {
    patched.push(plain[pi]);
    pi = pi + 1;
  }
  patched[36] = 255 as UInt8;
  patched[37] = 255 as UInt8;
  let er3 = tds_login7_parse(&patched, 0);
  if er3.is_ok {
    ok = false;
  } else {
    if !str_eq(er3.error, eat("mssql: login7 field overruns buffer", 36)) {
      io.println("t6i: field overrun error");
      ok = false;
    }
  }
  return assert(ok, "LOGIN7: cbSSPILong path (70000 bytes), truncated header, bad total, field overrun");
}

// --------------------------------------------------
//  t7: LOGIN7 builder validation and SSPI boundary
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = true;
  var spec = login7_spec();
  spec.hostname = bytes_of("abc");
  let b1 = tds_login7_build(&spec);
  if b1.is_ok {
    ok = false;
  } else {
    if !str_eq(b1.error, "mssql: login7 text field must be even") {
      ok = false;
    }
  }
  var spec2 = login7_spec();
  spec2.client_id = hb("0102030405");
  let b2 = tds_login7_build(&spec2);
  if b2.is_ok {
    ok = false;
  } else {
    if !str_eq(b2.error, "mssql: client id must be 6 bytes") {
      ok = false;
    }
  }
  var spec3 = login7_spec();
  let mid: Vec[UInt8] = repeat_byte(7, 65534);
  spec3.sspi = mid;
  let b3 = tds_login7_build(&spec3);
  if !b3.is_ok {
    ok = false;
  } else {
    let built: Vec[UInt8] = b3.value;
    let pr = tds_login7_parse(&built, 0);
    if !pr.is_ok {
      ok = false;
    } else {
      let l: TdsLogin7 = pr.value;
      if l.sspi_length != 65534 {
        ok = false;
      }
      let sp: Vec[UInt8] = l.sspi;
      if sp.len() != 65534 {
        ok = false;
      }
    }
  }
  return assert(ok, "LOGIN7 builder: odd text field and bad client id rejected, 65534-byte SSPI keeps cbSSPI");
}

// --------------------------------------------------
//  t8: UTF-16LE helper
// --------------------------------------------------

fn t8() -> TestResult {
  var ok = true;
  let r = tds_utf16le_to_str(&hb("610062006300"), 0, 6);
  if !r.is_ok {
    ok = false;
  } else {
    let s: Str = r.value;
    if !str_eq(s, "abc") {
      ok = false;
    }
  }
  // U+00E9, U+0000 and U+4E2D all map to '?' (no NUL can reach the builder).
  let r2 = tds_utf16le_to_str(&hb("e90000002d4e"), 0, 6);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2: Str = r2.value;
    if !str_eq(s2, "???") {
      ok = false;
    }
  }
  let r3 = tds_utf16le_to_str(&hb(""), 0, 0);
  if !r3.is_ok {
    ok = false;
  } else {
    let s3: Str = r3.value;
    if s3.len() != 0 {
      ok = false;
    }
  }
  let r4 = tds_utf16le_to_str(&hb("6100"), 0, 3);
  if r4.is_ok {
    ok = false;
  } else {
    if !str_eq(r4.error, eat("mssql: bad utf16 length", 0)) {
      ok = false;
    }
  }
  let r5 = tds_utf16le_to_str(&hb("6100"), 0, 4);
  if r5.is_ok {
    ok = false;
  } else {
    if !str_eq(r5.error, eat("mssql: truncated utf16 string", 0)) {
      ok = false;
    }
  }
  let r6 = tds_utf16le_to_str(&hb("6100"), 0, -2);
  if r6.is_ok {
    ok = false;
  } else {
    if !str_eq(r6.error, eat("mssql: negative utf16 length", 0)) {
      ok = false;
    }
  }
  if !bytes_equal(utf16("hi"), hb("68006900")) {
    ok = false;
  }
  if utf16("").len() != 0 {
    ok = false;
  }
  return assert(ok, "UTF-16LE: decode ASCII, '?' for non-ASCII/NUL, empty, odd/truncated/negative errors, encode");
}

// --------------------------------------------------
//  t9: token walk (known + unknown tokens)
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  let empty = Vec[UInt8].new();
  var stream = mk_loginack("SQL Server", 16, 0, 2000);
  stream = concat2(stream, mk_envchange(TDS_ENV_DATABASE, utf16("master"), empty));
  stream = concat2(stream, mk_done(TDS_TOKEN_DONE, 1, 0, 0));
  stream = concat2(stream, hb("77dead"));
  let wr = tds_token_walk(&stream, 0);
  if !wr.is_ok {
    return assert(false, "known tokens plus an unknown tail must walk");
  }
  let idx: TdsTokenIndex = wr.value;
  if tds_token_count(&idx) != 4 {
    ok = false;
  }
  if idx.next != stream.len() {
    ok = false;
  }
  let k0: Int = idx.kinds[0];
  let k1: Int = idx.kinds[1];
  let k2: Int = idx.kinds[2];
  let k3: Int = idx.kinds[3];
  if k0 != TDS_TOKEN_LOGINACK || k1 != TDS_TOKEN_ENVCHANGE || k2 != TDS_TOKEN_DONE || k3 != 119 {
    ok = false;
  }
  let o0: Int = idx.offsets[0];
  let o1: Int = idx.offsets[1];
  let o2: Int = idx.offsets[2];
  let o3: Int = idx.offsets[3];
  if o0 != 0 || !(o1 > o0) || !(o2 > o1) || !(o3 > o2) {
    ok = false;
  }
  let e3: Int = idx.ends[3];
  if e3 != stream.len() {
    ok = false;
  }
  let raw = tds_token_raw(&stream, &idx, 3);
  if !raw.is_ok {
    ok = false;
  } else {
    let rb: Vec[UInt8] = raw.value;
    if !bytes_equal(rb, hb("77dead")) {
      ok = false;
    }
  }
  let bad = tds_token_raw(&stream, &idx, 4);
  if bad.is_ok {
    ok = false;
  } else {
    if !str_eq(bad.error, "mssql: token index out of range") {
      ok = false;
    }
  }
  if tds_token_kind_at(&idx, -1) != -1 {
    ok = false;
  }
  if tds_token_offset_at(&idx, 4) != -1 {
    ok = false;
  }
  let rr = tds_token_walk(&hb("d100"), 0);
  if rr.is_ok {
    ok = false;
  } else {
    if !str_eq(rr.error, eat("mssql: row without colmetadata", 0)) {
      ok = false;
    }
  }
  let tr = tds_token_walk(&hb("aa0500"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  if !tds_token_known(TDS_TOKEN_ROW) || tds_token_known(0x77) {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_NBCROW), "NBCROW") {
    ok = false;
  }
  if !str_eq(tds_token_name(0x77), "UNKNOWN") {
    ok = false;
  }
  return assert(ok, "token walk: LOGINACK+ENVCHANGE+DONE indexed, unknown token preserved raw and stops the walk");
}

// --------------------------------------------------
//  t10: LOGINACK decode
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  let buf = mk_loginack("SQL Server", 16, 2, 2000);
  let r = tds_loginack_parse(&buf, 0);
  if !r.is_ok {
    return assert(false, "LOGINACK must parse");
  }
  let a: TdsLoginAck = r.value;
  if a.iface != 1 {
    ok = false;
  }
  if a.tds_version != TDS_VERSION_74 {
    ok = false;
  }
  if !str_eq(a.prog_name, "SQL Server") {
    ok = false;
  }
  if a.major != 16 || a.minor != 2 || a.build != 2000 {
    ok = false;
  }
  if a.next != buf.len() {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_LOGINACK), "LOGINACK") {
    ok = false;
  }
  let empty = Vec[UInt8].new();
  let other = mk_envchange(TDS_ENV_DATABASE, utf16("db"), empty);
  let mr = tds_loginack_parse(&other, 0);
  if mr.is_ok {
    ok = false;
  } else {
    if !str_eq(mr.error, eat("mssql: token mismatch", 0)) {
      ok = false;
    }
  }
  let cr = tds_loginack_parse(&hb("ad0500"), 0);
  if cr.is_ok {
    ok = false;
  } else {
    if !str_eq(cr.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  return assert(ok, "LOGINACK: interface, BE TDS version, progname, version triple, mismatch and truncation");
}

// --------------------------------------------------
//  t11: ERROR / INFO decode
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  let buf = mk_error(TDS_TOKEN_ERROR, 208, 1, 16, "Invalid object", "srv1", "", 42);
  let r = tds_error_parse(&buf, 0);
  if !r.is_ok {
    return assert(false, "ERROR token must parse");
  }
  let e: TdsError = r.value;
  if e.is_info != 0 {
    ok = false;
  }
  if e.number != 208 || e.state != 1 || e.severity != 16 {
    ok = false;
  }
  if !str_eq(e.message, "Invalid object") {
    ok = false;
  }
  if !str_eq(e.server_name, "srv1") {
    ok = false;
  }
  if !str_eq(e.proc_name, "") {
    ok = false;
  }
  if e.line != 42 {
    ok = false;
  }
  if e.next != buf.len() {
    ok = false;
  }
  let info = mk_error(TDS_TOKEN_INFO, 5701, 2, 10, "Changed database context", "", "", -1);
  let ir = tds_error_parse(&info, 0);
  if !ir.is_ok {
    ok = false;
  } else {
    let i: TdsError = ir.value;
    if i.is_info != 1 {
      ok = false;
    }
    if i.line != -1 {
      ok = false;
    }
    if i.number != 5701 {
      ok = false;
    }
    if !str_eq(i.message, "Changed database context") {
      ok = false;
    }
  }
  let tr = tds_error_parse(&hb("aa0100"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  let mr = tds_error_parse(&mk_done(TDS_TOKEN_DONE, 0, 0, 0), 0);
  if mr.is_ok {
    ok = false;
  } else {
    if !str_eq(mr.error, eat("mssql: token mismatch", 0)) {
      ok = false;
    }
  }
  return assert(ok, "ERROR/INFO: number, state, severity, UTF-16 message, server/proc names, optional line number");
}

// --------------------------------------------------
//  t12: ENVCHANGE decode
// --------------------------------------------------

fn t12() -> TestResult {
  var ok = true;
  let buf = mk_envchange(TDS_ENV_DATABASE, utf16("master"), utf16("db1"));
  let r = tds_envchange_parse(&buf, 0);
  if !r.is_ok {
    return assert(false, "ENVCHANGE must parse");
  }
  let e: TdsEnvChange = r.value;
  if e.subtype != TDS_ENV_DATABASE {
    ok = false;
  }
  if e.new_is_null != 0 || e.old_is_null != 0 {
    ok = false;
  }
  let nb: Vec[UInt8] = e.new_bytes;
  if !bytes_equal(nb, utf16("master")) {
    ok = false;
  }
  let ob: Vec[UInt8] = e.old_bytes;
  if !bytes_equal(ob, utf16("db1")) {
    ok = false;
  }
  if e.next != buf.len() {
    ok = false;
  }
  if !str_eq(tds_envchange_subtype_name(e.subtype), "database") {
    ok = false;
  }
  if !str_eq(tds_envchange_subtype_name(TDS_ENV_PACKET_SIZE), "packet size") {
    ok = false;
  }
  if !str_eq(tds_envchange_subtype_name(99), "unknown") {
    ok = false;
  }
  let empty = Vec[UInt8].new();
  let nul = mk_envchange(TDS_ENV_RESET_ACK, empty, empty);
  let nr = tds_envchange_parse(&nul, 0);
  if !nr.is_ok {
    ok = false;
  } else {
    let n: TdsEnvChange = nr.value;
    if n.new_is_null != 1 || n.old_is_null != 1 {
      ok = false;
    }
    let nbb: Vec[UInt8] = n.new_bytes;
    if nbb.len() != 0 {
      ok = false;
    }
  }
  let tr = tds_envchange_parse(&hb("e3010001"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  return assert(ok, "ENVCHANGE: subtype, raw new/old values, null values, subtype names, truncation");
}

// --------------------------------------------------
//  t13: DONE family
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  let buf = mk_done(TDS_TOKEN_DONE, TDS_DONE_MORE | TDS_DONE_COUNT, 1, 5);
  let r = tds_done_parse(&buf, 0);
  if !r.is_ok {
    return assert(false, "DONE must parse");
  }
  let d: TdsDone = r.value;
  if d.token != TDS_TOKEN_DONE {
    ok = false;
  }
  if d.status != 17 {
    ok = false;
  }
  if d.curcmd != 1 {
    ok = false;
  }
  if d.rowcount != 5 {
    ok = false;
  }
  if d.next != 13 {
    ok = false;
  }
  let proc = mk_done(TDS_TOKEN_DONEPROC, 0, 0, 0);
  let pr = tds_done_parse(&proc, 0);
  if !pr.is_ok {
    ok = false;
  } else {
    let p: TdsDone = pr.value;
    if p.token != TDS_TOKEN_DONEPROC || p.rowcount != 0 {
      ok = false;
    }
  }
  let big = mk_done(TDS_TOKEN_DONEINPROC, 0, 0, 1099511627776);
  let br = tds_done_parse(&big, 0);
  if !br.is_ok {
    ok = false;
  } else {
    let b: TdsDone = br.value;
    if b.rowcount != 1099511627776 {
      ok = false;
    }
  }
  let tr = tds_done_parse(&hb("fd00000000000000000000"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  let mr = tds_done_parse(&mk_loginack("x", 1, 0, 1), 0);
  if mr.is_ok {
    ok = false;
  } else {
    if !str_eq(mr.error, eat("mssql: token mismatch", 0)) {
      ok = false;
    }
  }
  return assert(ok, "DONE/DONEPROC/DONEINPROC: token byte, status bits, curcmd, 64-bit rowcount, errors");
}

// --------------------------------------------------
//  t14: COLMETADATA pinned layouts
// --------------------------------------------------

fn t14() -> TestResult {
  var ok = true;
  let c0 = hb("0000000000002604");
  let c1 = hb("0000000000006801");
  let c2 = hb("0000000000006a091202");
  let c3 = hb("00000000000038");
  let c4 = hb("0000000000002608");
  let c5 = hb("0000000000002410");
  let c6 = hb("000000000000e764000904d00000");
  let c7 = hb("000000000000a51400");
  let c8 = hb("000000000000f100");
  var ma = hb("810900");
  ma = concat2(ma, c0);
  ma = concat2(ma, c1);
  ma = concat2(ma, c2);
  ma = concat2(ma, c3);
  ma = concat2(ma, c4);
  ma = concat2(ma, c5);
  ma = concat2(ma, c6);
  ma = concat2(ma, c7);
  ma = concat2(ma, c8);
  let mr = tds_colmetadata_parse(&ma, 0);
  if !mr.is_ok {
    return assert(false, "pinned COLMETADATA must parse");
  }
  let m: TdsColMeta = mr.value;
  if m.count != 9 {
    ok = false;
  }
  if m.next != ma.len() {
    ok = false;
  }
  let t0: Int = m.type_tokens[0];
  let t1: Int = m.type_tokens[1];
  let t2: Int = m.type_tokens[2];
  let t3: Int = m.type_tokens[3];
  let t4: Int = m.type_tokens[4];
  let t5: Int = m.type_tokens[5];
  let t6: Int = m.type_tokens[6];
  let t7: Int = m.type_tokens[7];
  let t8: Int = m.type_tokens[8];
  if t0 != TDS_TYPE_INTN || t1 != TDS_TYPE_BITN || t2 != TDS_TYPE_DECIMALN {
    ok = false;
  }
  // INT4TYPE 0x38 is the canonical fixed 4-byte token (no metadata byte),
  // while a bigint travels as INTNTYPE 0x26 with a length-8 size byte.
  if t3 != TDS_TYPE_INT4 {
    ok = false;
  }
  if t4 != TDS_TYPE_INTN {
    ok = false;
  }
  if t5 != TDS_TYPE_GUIDN || t6 != TDS_TYPE_NVARCHAR || t7 != TDS_TYPE_BIGVARBIN || t8 != TDS_TYPE_XML {
    ok = false;
  }
  let s0: Int = m.type_sizes[0];
  let s3: Int = m.type_sizes[3];
  let s4: Int = m.type_sizes[4];
  let s6: Int = m.type_sizes[6];
  let p2: Int = m.precisions[2];
  let sc2: Int = m.scales[2];
  if s0 != 4 || s3 != 4 || s4 != 8 || s6 != 100 || p2 != 18 || sc2 != 2 {
    ok = false;
  }
  let coll: Int = m.collations[6];
  if !collation_lcid_check(coll) {
    ok = false;
  }
  let coff: Int = m.collation_offsets[6];
  if coff <= 0 {
    ok = false;
  }
  let s8: Int = m.type_sizes[8];
  if s8 != -1 {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT4), "INT4") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT8), "INT8") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_FLTN), "FLTN") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_NVARCHAR), "NVARCHAR") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(0x55), "UNKNOWN") {
    ok = false;
  }
  // XML schema-present + UDT + legacy TEXT/IMAGE/NTEXT.
  let x2 = hb("00000000000023e80300000904d00000");
  let x3 = hb("00000000000022d0070000");
  let x4 = hb("00000000000063b80b00000904d00000");
  var mb = hb("810500");
  mb = concat2(mb, hb("000000000000f101026400620003640062006f0003780073006300"));
  mb = concat2(mb, hb("000000000000f06400016400620003640062006f00066d0079007400790065000600610073006d00"));
  mb = concat2(mb, x2);
  mb = concat2(mb, x3);
  mb = concat2(mb, x4);
  let mr2 = tds_colmetadata_parse(&mb, 0);
  if !mr2.is_ok {
    return assert(ok, "pinned COLMETADATA with XML/UDT/legacy must parse");
  }
  let m2: TdsColMeta = mr2.value;
  if m2.count != 5 {
    ok = false;
  }
  let tt0: Int = m2.type_tokens[0];
  let tt1: Int = m2.type_tokens[1];
  let tt2: Int = m2.type_tokens[2];
  let tt4: Int = m2.type_tokens[4];
  if tt0 != TDS_TYPE_XML || tt1 != TDS_TYPE_UDT || tt2 != TDS_TYPE_TEXT || tt4 != TDS_TYPE_NTEXT {
    ok = false;
  }
  let n1o: Int = m2.name1_offsets[1];
  let n1l: Int = m2.name1_lengths[1];
  if n1o < 0 || n1l != 4 {
    ok = false;
  } else {
    let nr = tds_utf16le_to_str(&mb, n1o, n1l);
    if !nr.is_ok {
      ok = false;
    } else {
      let name: Str = nr.value;
      if !str_eq(name, "db") {
        ok = false;
      }
    }
  }
  let asm_off: Int = m2.asm_offsets[1];
  let asm_len: Int = m2.asm_lengths[1];
  if asm_off < 0 || asm_len != 6 {
    ok = false;
  } else {
    let ar = tds_utf16le_to_str(&mb, asm_off, asm_len);
    if !ar.is_ok {
      ok = false;
    } else {
      let asm: Str = ar.value;
      if !str_eq(asm, "asm") {
        ok = false;
      }
    }
  }
  let sx2: Int = m2.type_sizes[2];
  if sx2 != 1000 {
    ok = false;
  }
  let nm = tds_colmetadata_parse(&hb("81ffff"), 0);
  if !nm.is_ok {
    ok = false;
  } else {
    let n: TdsColMeta = nm.value;
    if n.count != -1 {
      ok = false;
    }
    if n.next != 3 {
      ok = false;
    }
  }
  let bad = tds_colmetadata_parse(&h134(), 0);
  if bad.is_ok {
    ok = false;
  } else {
    if !str_eq(bad.error, eat("mssql: unsupported type token", 9)) {
      ok = false;
    }
  }
  let tr = tds_colmetadata_parse(&hb("8101000000"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated colmetadata", 3)) {
      ok = false;
    }
  }
  // A crypto-metadata trailer is skipped when a column carries fEncrypted.
  let crypto = concat3(hb("8101000000000800260401"), le32(2), hb("aabb"));
  let cr = tds_colmetadata_parse(&crypto, 0);
  if !cr.is_ok {
    ok = false;
  } else {
    let cm: TdsColMeta = cr.value;
    if cm.next != crypto.len() {
      ok = false;
    }
    let cf: Int = cm.flags[0];
    if (cf & TDS_COL_FLAG_ENCRYPTED) == 0 {
      ok = false;
    }
  }
  return assert(ok, "COLMETADATA: 8 pinned columns, XML/UDT names, legacy metadata, no-metadata marker, error offsets");
}

// COLMETADATA with one column whose type token is unknown (0x55).
fn h134() -> Vec[UInt8] {
  return hb("810100000000000055");
}

// Collation check used by t14 (kept as a helper so the assertion stays a
// single Bool expression).
fn collation_lcid_check(c: Int) -> Bool {
  return tds_collation_lcid(c) == 1033;
}

// --------------------------------------------------
//  t15: ROW decode against COLMETADATA
// --------------------------------------------------

// The 9-column metadata of t14, rebuilt here for the row tests.
fn meta8() -> Vec[UInt8] {
  var ma = hb("810900");
  ma = concat2(ma, hb("0000000000002604"));
  ma = concat2(ma, hb("0000000000006801"));
  ma = concat2(ma, hb("0000000000006a091202"));
  ma = concat2(ma, hb("00000000000038"));
  ma = concat2(ma, hb("0000000000002608"));
  ma = concat2(ma, hb("0000000000002410"));
  ma = concat2(ma, hb("000000000000e764000904d00000"));
  ma = concat2(ma, hb("000000000000a51400"));
  ma = concat2(ma, hb("000000000000f100"));
  return ma;
}

fn t15() -> TestResult {
  var ok = true;
  let mb = meta8();
  let mr = tds_colmetadata_parse(&mb, 0);
  if !mr.is_ok {
    return assert(false, "meta8 must parse");
  }
  let meta: TdsColMeta = mr.value;
  var row = u8v(TDS_TOKEN_ROW);
  row = concat2(row, hb("04feffffff"));
  row = concat2(row, hb("0101"));
  row = concat2(row, hb("05012a000000"));
  row = concat2(row, hb("07000000"));
  row = concat2(row, hb("080000000001000000"));
  row = concat2(row, hb("1000112233445566778899aabbccddeeff"));
  row = concat2(row, hb("0300610062006300"));
  row = concat2(row, hb("0200dead"));
  row = concat2(row, hb("02003c00"));
  let rr = tds_row_parse(&row, 0, &meta);
  if !rr.is_ok {
    return assert(false, "9-column row must parse");
  }
  let r: TdsRow = rr.value;
  if r.count != 9 || r.next != row.len() {
    ok = false;
  }
  if r.is_nbc != 0 {
    ok = false;
  }
  let l0: Int = r.value_lengths[0];
  let l1: Int = r.value_lengths[1];
  let l2: Int = r.value_lengths[2];
  let l3: Int = r.value_lengths[3];
  let l4: Int = r.value_lengths[4];
  let l5: Int = r.value_lengths[5];
  let l6: Int = r.value_lengths[6];
  let l7: Int = r.value_lengths[7];
  let l8: Int = r.value_lengths[8];
  if l0 != 4 || l1 != 1 || l2 != 5 || l3 != 4 || l4 != 8 || l5 != 16 || l6 != 6 || l7 != 2 || l8 != 2 {
    ok = false;
  }
  let n0: Int = r.nulls[0];
  let n8: Int = r.nulls[8];
  if n0 != 0 || n8 != 0 {
    ok = false;
  }
  let i0: Int = r.value_ints[0];
  let i1: Int = r.value_ints[1];
  let i3: Int = r.value_ints[3];
  let i4: Int = r.value_ints[4];
  if i0 != -2 || i1 != 1 || i3 != 7 || i4 != 4294967296 {
    ok = false;
  }
  let vr = tds_row_value(&row, &r, 6);
  if !vr.is_ok {
    ok = false;
  } else {
    let vb: Vec[UInt8] = vr.value;
    if !bytes_equal(vb, utf16("abc")) {
      ok = false;
    }
  }
  let ir = tds_row_int(&r, 4);
  if !ir.is_ok {
    ok = false;
  } else {
    let iv: Int = ir.value;
    if iv != 4294967296 {
      ok = false;
    }
  }
  let bad = tds_row_value(&row, &r, 9);
  if bad.is_ok {
    ok = false;
  } else {
    if !str_eq(bad.error, "mssql: column index out of range") {
      ok = false;
    }
  }
  // NULLTYPE column: no value bytes at all.
  let nm = tds_colmetadata_parse(&hb("8101000000000000001f"), 0);
  if !nm.is_ok {
    return assert(false, "NULLTYPE metadata must parse");
  }
  let nmeta: TdsColMeta = nm.value;
  let nrow = hb("d1");
  let nr = tds_row_parse(&nrow, 0, &nmeta);
  if !nr.is_ok {
    ok = false;
  } else {
    let n: TdsRow = nr.value;
    let nn: Int = n.nulls[0];
    if nn != 1 {
      ok = false;
    }
    let vnr = tds_row_value(&nrow, &n, 0);
    if vnr.is_ok {
      ok = false;
    } else {
      if !str_eq(vnr.error, "mssql: value is null") {
        ok = false;
      }
    }
  }
  // Truncated value and over-long fixed value.
  let tr = tds_row_parse(&hb("d104aabb"), 0, &meta);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated row", 1)) {
      ok = false;
    }
  }
  let br = tds_row_parse(&hb("d1050100000000"), 0, &meta);
  if br.is_ok {
    ok = false;
  } else {
    if !str_eq(br.error, eat("mssql: bad value length", 1)) {
      ok = false;
    }
  }
  let xr = tds_row_parse(&hb("d200"), 0, &meta);
  if xr.is_ok {
    ok = false;
  } else {
    if !str_eq(xr.error, eat("mssql: token mismatch", 0)) {
      ok = false;
    }
  }
  return assert(ok, "ROW: 9 decoded columns, plain INT4, bigint via INTN length 8, decimal/guid spans, UTF-16 x2, NULLTYPE, errors");
}

// --------------------------------------------------
//  t16: NBCROW null bitmap
// --------------------------------------------------

fn meta10_intn() -> Vec[UInt8] {
  var ma = hb("810a00");
  var i = 0;
  while i < 10 {
    ma = concat2(ma, hb("0000000000002604"));
    i = i + 1;
  }
  return ma;
}

fn t16() -> TestResult {
  var ok = true;
  if tds_null_bitmap_len(0) != 0 || tds_null_bitmap_len(8) != 1 || tds_null_bitmap_len(9) != 2 || tds_null_bitmap_len(10) != 2 {
    ok = false;
  }
  let mb = meta10_intn();
  let mr = tds_colmetadata_parse(&mb, 0);
  if !mr.is_ok {
    return assert(false, "10-column metadata must parse");
  }
  let meta: TdsColMeta = mr.value;
  // Nulls at columns 1 and 8: byte0 bit1, byte1 bit0.
  var row = concat2(u8v(TDS_TOKEN_NBCROW), hb("0201"));
  var i = 0;
  while i < 10 {
    if i != 1 && i != 8 {
      row = concat2(row, u8v(4));
      row = concat2(row, le32(100 + i));
    }
    i = i + 1;
  }
  let rr = tds_nbcrow_parse(&row, 0, &meta);
  if !rr.is_ok {
    return assert(false, "NBCROW must parse");
  }
  let r: TdsRow = rr.value;
  if r.is_nbc != 1 || r.count != 10 {
    ok = false;
  }
  let n0: Int = r.nulls[0];
  let n1: Int = r.nulls[1];
  let n7: Int = r.nulls[7];
  let n8: Int = r.nulls[8];
  let n9: Int = r.nulls[9];
  if n0 != 0 || n1 != 1 || n7 != 0 || n8 != 1 || n9 != 0 {
    ok = false;
  }
  let i0: Int = r.value_ints[0];
  let i2: Int = r.value_ints[2];
  let i9: Int = r.value_ints[9];
  if i0 != 100 || i2 != 102 || i9 != 109 {
    ok = false;
  }
  if r.next != row.len() {
    ok = false;
  }
  let tr = tds_nbcrow_parse(&hb("d201"), 0, &meta);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated row", 1)) {
      ok = false;
    }
  }
  return assert(ok, "NBCROW: LSB-first null bitmap, values only for non-null columns, bitmap length helper");
}

// --------------------------------------------------
//  t17: RETURNSTATUS and RETURNVALUE
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  let sr = tds_returnstatus_parse(&hb("7907000000"), 0);
  if !sr.is_ok {
    ok = false;
  } else {
    let s: TdsReturnStatus = sr.value;
    if s.status != 7 || s.next != 5 {
      ok = false;
    }
  }
  var rv = u8v(TDS_TOKEN_RETURNVALUE);
  rv = concat2(rv, le16(0));
  rv = concat2(rv, u8v(0));
  rv = concat2(rv, u8v(0));
  rv = concat2(rv, le32(0));
  rv = concat2(rv, le16(0));
  rv = concat2(rv, hb("2604"));
  rv = concat2(rv, hb("042a000000"));
  let rr = tds_returnvalue_parse(&rv, 0);
  if !rr.is_ok {
    return assert(false, "RETURNVALUE INTN must parse");
  }
  let v: TdsReturnValue = rr.value;
  if v.ordinal != 0 || v.status != 0 || v.usertype != 0 || v.flags != 0 {
    ok = false;
  }
  if v.type_token != TDS_TYPE_INTN || v.type_size != 4 {
    ok = false;
  }
  if v.is_null != 0 || v.value_int != 42 {
    ok = false;
  }
  if !str_eq(v.name, "") {
    ok = false;
  }
  if v.next != rv.len() {
    ok = false;
  }
  // Named parameter and a NULL value.
  var rv2 = u8v(TDS_TOKEN_RETURNVALUE);
  rv2 = concat2(rv2, le16(3));
  rv2 = concat2(rv2, bvarchar("r"));
  rv2 = concat2(rv2, u8v(1));
  rv2 = concat2(rv2, le32(0));
  rv2 = concat2(rv2, le16(0));
  rv2 = concat2(rv2, hb("2604"));
  rv2 = concat2(rv2, u8v(0));
  let rr2 = tds_returnvalue_parse(&rv2, 0);
  if !rr2.is_ok {
    ok = false;
  } else {
    let v2: TdsReturnValue = rr2.value;
    if !str_eq(v2.name, "r") {
      ok = false;
    }
    if v2.is_null != 1 {
      ok = false;
    }
  }
  let tr = tds_returnvalue_parse(&hb("ac0000"), 0);
  if tr.is_ok {
    ok = false;
  } else {
    if !str_eq(tr.error, eat("mssql: truncated b_varchar", 3)) {
      ok = false;
    }
  }
  return assert(ok, "RETURNSTATUS and RETURNVALUE: ordinal, B_VARCHAR name, type info, decoded int, NULL value");
}

// --------------------------------------------------
//  t18: FEATUREEXTACK, ORDER and walk integration
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  let fa = hb("ae0103000000aabbccff");
  let fr = tds_featureextack_parse(&fa, 0);
  if !fr.is_ok {
    return assert(false, "FEATUREEXTACK must parse");
  }
  let f: TdsFeatureExtAck = fr.value;
  if f.ids.len() != 1 {
    ok = false;
  } else {
    let id0: Int = f.ids[0];
    let o0: Int = f.offsets[0];
    let l0: Int = f.lengths[0];
    if id0 != 1 || o0 != 6 || l0 != 3 {
      ok = false;
    }
  }
  if f.next != 10 {
    ok = false;
  }
  let fe = tds_featureextack_parse(&hb("aeff"), 0);
  if !fe.is_ok {
    ok = false;
  } else {
    let e: TdsFeatureExtAck = fe.value;
    if e.ids.len() != 0 || e.next != 2 {
      ok = false;
    }
  }
  let ft = tds_featureextack_parse(&hb("ae"), 0);
  if ft.is_ok {
    ok = false;
  } else {
    if !str_eq(ft.error, eat("mssql: truncated featureextack", 1)) {
      ok = false;
    }
  }
  let ob = concat2(concat2(u8v(TDS_TOKEN_ORDER), le16(4)), concat2(le16(0), le16(1)));
  let orr = tds_order_parse(&ob, 0);
  if !orr.is_ok {
    ok = false;
  } else {
    let o: TdsOrder = orr.value;
    if o.length != 4 || o.next != 7 {
      ok = false;
    }
    if o.ordinals.len() != 2 {
      ok = false;
    } else {
      let a0: Int = o.ordinals[0];
      let a1: Int = o.ordinals[1];
      if a0 != 0 || a1 != 1 {
        ok = false;
      }
    }
  }
  let obad = concat2(concat2(u8v(TDS_TOKEN_ORDER), le16(3)), concat2(le16(0), repeat_byte(0, 5)));
  let br = tds_order_parse(&obad, 0);
  if br.is_ok {
    ok = false;
  } else {
    if !str_eq(br.error, eat("mssql: bad order length", 0)) {
      ok = false;
    }
  }
  // End-to-end walk: COLMETADATA + ROW + DONE.
  var meta = hb("810200");
  meta = concat2(meta, hb("0000000000002604"));
  meta = concat2(meta, hb("0000000000006801"));
  var row = concat2(u8v(TDS_TOKEN_ROW), hb("04010000000101"));
  var stream = concat3(meta, row, mk_done(TDS_TOKEN_DONE, TDS_DONE_COUNT, 0, 1));
  let wr = tds_token_walk(&stream, 0);
  if !wr.is_ok {
    return assert(false, "colmetadata+row+done stream must walk");
  }
  let idx: TdsTokenIndex = wr.value;
  if tds_token_count(&idx) != 3 {
    ok = false;
  }
  let k0: Int = idx.kinds[0];
  let k1: Int = idx.kinds[1];
  let k2: Int = idx.kinds[2];
  if k0 != TDS_TOKEN_COLMETADATA || k1 != TDS_TOKEN_ROW || k2 != TDS_TOKEN_DONE {
    ok = false;
  }
  let e1: Int = idx.ends[1];
  let o2: Int = idx.offsets[2];
  if e1 != o2 || idx.next != stream.len() {
    ok = false;
  }
  return assert(ok, "FEATUREEXTACK blocks, ORDER ordinals, end-to-end walk over COLMETADATA+ROW+DONE");
}

// --------------------------------------------------
//  t19: names, constants and collation extractors
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  if !str_eq(tds_packet_type_name(TDS_PKT_RPC), "RPC") {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(TDS_PKT_RESPONSE), "RESPONSE") {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(TDS_PKT_LOGIN7), "LOGIN7") {
    ok = false;
  }
  if !str_eq(tds_packet_type_name(TDS_PKT_SSPI), "SSPI") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_ERROR), "ERROR") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_INFO), "INFO") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_RETURNVALUE), "RETURNVALUE") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_FEATUREEXTACK), "FEATUREEXTACK") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_ENVCHANGE), "ENVCHANGE") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_DONEPROC), "DONEPROC") {
    ok = false;
  }
  if !str_eq(tds_token_name(TDS_TOKEN_DONEINPROC), "DONEINPROC") {
    ok = false;
  }
  if TDS_TOKEN_DONEFINAL != TDS_TOKEN_DONEINPROC {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_DECIMALN), "DECIMALN") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_BIGVARBIN), "BIGVARBIN") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_TEXT), "TEXT") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT1), "INT1") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_BIT), "BIT") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT2), "INT2") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT4), "INT4") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_DATETIME4), "DATETIME4") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_FLT4), "FLT4") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_MONEY), "MONEY") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_DATETIME), "DATETIME") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_FLT8), "FLT8") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_INT8), "INT8") {
    ok = false;
  }
  if !str_eq(tds_type_token_name(TDS_TYPE_GUIDN), "GUIDN") {
    ok = false;
  }
  if TDS_TYPE_GUID != TDS_TYPE_GUIDN {
    ok = false;
  }
  if TDS_TYPE_INTN != 0x26 || TDS_TYPE_INT1 != 0x30 || TDS_TYPE_BIT != 0x32 || TDS_TYPE_INT2 != 0x34 {
    ok = false;
  }
  if TDS_TYPE_INT4 != 0x38 || TDS_TYPE_DATETIME4 != 0x3A || TDS_TYPE_FLT4 != 0x3B || TDS_TYPE_MONEY != 0x3C {
    ok = false;
  }
  if TDS_TYPE_DATETIME != 0x3D || TDS_TYPE_FLT8 != 0x3E || TDS_TYPE_INT8 != 0x7F || TDS_TYPE_GUIDN != 0x24 {
    ok = false;
  }
  if TDS_TYPE_BITN != 0x68 || TDS_TYPE_FLTN != 0x6D || TDS_TYPE_MONEYN != 0x6E || TDS_TYPE_DATETIMEN != 0x6F {
    ok = false;
  }
  if !str_eq(tds_envchange_subtype_name(TDS_ENV_LANGUAGE), "language") {
    ok = false;
  }
  if !str_eq(tds_envchange_subtype_name(TDS_ENV_COLLATION), "collation") {
    ok = false;
  }
  if !str_eq(tds_prelogin_encryption_name(TDS_ENCRYPT_OFF), "OFF") {
    ok = false;
  }
  if !str_eq(tds_prelogin_encryption_name(TDS_ENCRYPT_REQ), "REQ") {
    ok = false;
  }
  let packed: Int = 1033 + 64 * 1048576 + 2 * 268435456;
  if tds_collation_lcid(packed) != 1033 {
    ok = false;
  }
  if tds_collation_flags(packed) != 64 {
    ok = false;
  }
  if tds_collation_version(packed) != 2 {
    ok = false;
  }
  if tds_collation_sortid(packed) != 0 {
    ok = false;
  }
  if TDS_VERSION_74 != 1946157060 {
    ok = false;
  }
  if TDS_VERSION_72 != 1913188866 {
    ok = false;
  }
  if TDS_COL_FLAG_ENCRYPTED != 2048 {
    ok = false;
  }
  if !tds_token_known(TDS_TOKEN_RETURNSTATUS) || !tds_token_known(TDS_TOKEN_ORDER) {
    ok = false;
  }
  if !str_eq(tds_token_name(7), "UNKNOWN") {
    ok = false;
  }
  return assert(ok, "name helpers, ENCRYPTION names, collation bit extractors, version and flag constants");
}

// --------------------------------------------------
//  t20: error offsets and empty input
// --------------------------------------------------

fn t20() -> TestResult {
  var ok = true;
  let p = tds_packet_parse(&hb("040000"), 2);
  if p.is_ok {
    ok = false;
  } else {
    if !str_eq(p.error, eat("mssql: truncated packet header", 2)) {
      ok = false;
    }
  }
  let m = tds_message_parse(&hb("0400000800"), -1);
  if m.is_ok {
    ok = false;
  } else {
    if !str_eq(m.error, "mssql: negative offset") {
      ok = false;
    }
  }
  let u = tds_utf16le_to_str(&hb("6100"), 4, 2);
  if u.is_ok {
    ok = false;
  } else {
    if !str_eq(u.error, eat("mssql: truncated utf16 string", 4)) {
      ok = false;
    }
  }
  let w = tds_token_walk(&hb(""), 0);
  if w.is_ok {
    ok = false;
  } else {
    if !str_eq(w.error, eat("mssql: truncated token", 0)) {
      ok = false;
    }
  }
  let pl = tds_prelogin_parse(&hb(""), 0);
  if pl.is_ok {
    ok = false;
  } else {
    if !str_eq(pl.error, eat("mssql: truncated prelogin table", 0)) {
      ok = false;
    }
  }
  let cm = tds_colmetadata_parse(&hb("0000"), 0);
  if cm.is_ok {
    ok = false;
  } else {
    if !str_eq(cm.error, eat("mssql: token mismatch", 0)) {
      ok = false;
    }
  }
  let rv = tds_returnvalue_parse(&hb(""), 0);
  if rv.is_ok {
    ok = false;
  } else {
    if !str_eq(rv.error, eat("mssql: truncated returnvalue", 0)) {
      ok = false;
    }
  }
  if !str_eq(tds_package_version(), "0.1.0") {
    ok = false;
  }
  return assert(ok, "error catalog: offset-carrying messages for packet, message, utf16, token, prelogin, colmetadata");
}

// --------------------------------------------------
//  main
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.mssql conformance tests ===");
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
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.mssql: all tests passed");
  } else {
    io.println("xiom.mssql: tests failed");
  }
  return failed;
}
